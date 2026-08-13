param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$DatabaseUrl,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$PsqlPath,

  [ValidateRange(2, 30)]
  [int]$HoldSeconds = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) {
  throw 'The supplied psql executable does not exist.'
}

$fixtureCompanyId = '7a000000-0000-0000-0000-000000000001'
$tempDirectory = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  ('jtc-task8-concurrency-' + [guid]::NewGuid().ToString('N'))
$activeJobs = [System.Collections.Generic.List[object]]::new()
$raceFailures = [System.Collections.Generic.List[string]]::new()

function Invoke-Psql {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Sql
  )

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $commandOutput = & $PsqlPath $DatabaseUrl `
      -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt -P pager=off -c $Sql 2>&1
    $commandExitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
  }

  [pscustomobject]@{
    ExitCode = $commandExitCode
    Output = ($commandOutput | Out-String).Trim()
  }
}

function Invoke-RequiredSql {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Sql,

    [Parameter(Mandatory = $true)]
    [string]$FailureMessage
  )

  $result = Invoke-Psql -Sql $Sql
  if ($result.ExitCode -ne 0) {
    throw $FailureMessage
  }

  return $result.Output
}

function Remove-Fixtures {
  $cleanupSql = @"
SET session_replication_role = replica;
DELETE FROM public.inspection_template_items
WHERE section_id IN (
  SELECT id
  FROM public.inspection_template_sections
  WHERE version_id IN (
    SELECT id
    FROM public.inspection_template_versions
    WHERE template_id IN (
      SELECT id
      FROM public.inspection_templates
      WHERE company_id = '$fixtureCompanyId'
    )
  )
);
DELETE FROM public.inspection_template_sections
WHERE version_id IN (
  SELECT id
  FROM public.inspection_template_versions
  WHERE template_id IN (
    SELECT id
    FROM public.inspection_templates
    WHERE company_id = '$fixtureCompanyId'
  )
);
DELETE FROM public.inspection_template_versions
WHERE template_id IN (
  SELECT id
  FROM public.inspection_templates
  WHERE company_id = '$fixtureCompanyId'
);
DELETE FROM public.inspection_templates
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.companies
WHERE id = '$fixtureCompanyId';
SET session_replication_role = origin;
"@

  $cleanupResult = Invoke-Psql -Sql $cleanupSql
  if ($cleanupResult.ExitCode -ne 0) {
    throw 'Concurrency test fixture cleanup failed.'
  }
}

function Wait-ForSessionHold {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationName
  )

  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  do {
    $pollSql = @"
SELECT count(*)
FROM pg_catalog.pg_stat_activity
WHERE application_name = '$ApplicationName'
  AND wait_event_type = 'Timeout'
  AND wait_event = 'PgSleep';
"@
    $pollResult = Invoke-Psql -Sql $pollSql
    if ($pollResult.ExitCode -ne 0) {
      throw 'Could not observe the held session.'
    }
    if ($pollResult.Output -eq '1') {
      return
    }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)

  throw 'Session did not reach its deterministic hold point.'
}

function Get-SqlState {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Result
  )

  if ($Result.ExitCode -eq 0) {
    return '00000'
  }

  $match = [regex]::Match($Result.Output, 'ERROR:\s+([0-9A-Z]{5}):')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return 'UNKNOWN'
}

function Invoke-FreezeRace {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$VersionId,

    [Parameter(Mandatory = $true)]
    [string]$ChildSql,

    [Parameter(Mandatory = $true)]
    [string]$ChildPostconditionSql
  )

  $applicationName = 'jtc_task8_' + $Name
  $freezeFile = Join-Path $tempDirectory ($Name + '-freeze.sql')
  $freezeSql = @"
\set ON_ERROR_STOP on
SET application_name = '$applicationName';
BEGIN;
UPDATE public.inspection_template_versions
SET is_current = false,
    frozen_at = clock_timestamp()
WHERE id = '$VersionId';
SELECT pg_sleep($HoldSeconds);
COMMIT;
"@
  [System.IO.File]::WriteAllText($freezeFile, $freezeSql)

  $freezeJob = Start-Job -ScriptBlock {
    param($Executable, $Target, $SqlFile)
    $sessionOutput = & $Executable $Target `
      -X -v ON_ERROR_STOP=1 -qAt -P pager=off -f $SqlFile 2>&1
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($sessionOutput | Out-String).Trim()
    }
  } -ArgumentList $PsqlPath, $DatabaseUrl, $freezeFile
  $activeJobs.Add($freezeJob)

  Wait-ForSessionHold -ApplicationName $applicationName

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $childResult = Invoke-Psql -Sql $ChildSql
  $stopwatch.Stop()

  $completedJob = Wait-Job -Job $freezeJob -Timeout ($HoldSeconds + 15)
  if ($null -eq $completedJob) {
    Stop-Job -Job $freezeJob
    throw "$Name freeze session did not finish."
  }
  $freezeResult = Receive-Job -Job $freezeJob
  Remove-Job -Job $freezeJob
  [void]$activeJobs.Remove($freezeJob)

  if ($freezeResult.ExitCode -ne 0) {
    throw "$Name freeze session failed."
  }
  if ($childResult.ExitCode -eq 0) {
    throw "$Name child mutation committed during an uncommitted freeze."
  }
  if ($childResult.Output -notmatch '55000') {
    throw "$Name child mutation failed without the frozen-history SQLSTATE."
  }
  if ($stopwatch.Elapsed.TotalSeconds -lt ($HoldSeconds - 1)) {
    throw "$Name child mutation did not wait on the ancestor freeze lock."
  }

  $postconditionSql = @"
SELECT (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions
    WHERE id = '$VersionId'
      AND NOT is_current
      AND frozen_at IS NOT NULL
  )
  AND ($ChildPostconditionSql)
)::integer;
"@
  $postcondition = Invoke-RequiredSql `
    -Sql $postconditionSql `
    -FailureMessage "$Name postcondition query failed."
  if ($postcondition -ne '1') {
    throw "$Name left an incoherent frozen graph."
  }

  Write-Output "ok - $Name serialized against freeze and was rejected"
}

function Invoke-DeleteRetryRace {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$ParentLockSql,

    [Parameter(Mandatory = $true)]
    [string]$ParentDeleteSql,

    [Parameter(Mandatory = $true)]
    [string]$ChildMutationSql,

    [Parameter(Mandatory = $true)]
    [string]$PostconditionSql,

    [Parameter(Mandatory = $true)]
    [string]$RetryPostconditionSql
  )

  $applicationName = 'jtc_task8_' + $Name
  $parentSql = @"
SET application_name = '$applicationName';
SET deadlock_timeout = '500ms';
SET lock_timeout = '10s';
BEGIN;
$ParentLockSql
SELECT pg_sleep($HoldSeconds);
$ParentDeleteSql
COMMIT;
"@

  $parentJob = Start-Job -ScriptBlock {
    param($Executable, $Target, $Sql)
    $sessionOutput = & $Executable $Target `
      -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt -P pager=off -c $Sql 2>&1
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($sessionOutput | Out-String).Trim()
    }
  } -ArgumentList $PsqlPath, $DatabaseUrl, $parentSql
  $activeJobs.Add($parentJob)

  Wait-ForSessionHold -ApplicationName $applicationName

  $childSql = @"
SET application_name = 'jtc_task8_child_$Name';
SET deadlock_timeout = '500ms';
SET lock_timeout = '10s';
$ChildMutationSql
"@
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $childResult = Invoke-Psql -Sql $childSql
  $stopwatch.Stop()

  $completedJob = Wait-Job -Job $parentJob -Timeout ($HoldSeconds + 15)
  if ($null -eq $completedJob) {
    Stop-Job -Job $parentJob
    throw "$Name parent delete session did not finish."
  }
  $parentResult = Receive-Job -Job $parentJob
  Remove-Job -Job $parentJob
  [void]$activeJobs.Remove($parentJob)

  $parentSqlState = Get-SqlState -Result $parentResult
  $childSqlState = Get-SqlState -Result $childResult
  if ($parentSqlState -ne '40P01') {
    throw "$Name parent delete did not fail safely with deadlock_detected (got $parentSqlState)."
  }
  if ($childSqlState -ne '00000') {
    throw "$Name child mutation failed (SQLSTATE $childSqlState)."
  }
  if ($stopwatch.Elapsed.TotalSeconds -lt ($HoldSeconds - 1)) {
    throw "$Name child mutation did not wait behind the held ancestor lock."
  }
  if ($stopwatch.Elapsed.TotalSeconds -gt ($HoldSeconds + 3)) {
    throw "$Name exceeded the fail-fast timing bound."
  }

  $postcondition = Invoke-RequiredSql `
    -Sql $PostconditionSql `
    -FailureMessage "$Name postcondition query failed."
  if ($postcondition -ne '1') {
    throw "$Name did not preserve the parent and commit the child mutation."
  }

  $retryResult = Invoke-Psql -Sql $ParentDeleteSql
  $retrySqlState = Get-SqlState -Result $retryResult
  if ($retrySqlState -ne '00000') {
    throw "$Name parent delete retry failed (SQLSTATE $retrySqlState)."
  }

  $retryPostcondition = Invoke-RequiredSql `
    -Sql $RetryPostconditionSql `
    -FailureMessage "$Name retry postcondition query failed."
  if ($retryPostcondition -ne '1') {
    throw "$Name retry did not leave the expected graph state."
  }

  $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
  Write-Output (
    "ok - $Name failed safe and retried " +
    "(parent=40P01, child=00000, retry=00000, " +
    "child_elapsed_seconds=$elapsed, pre_retry=1, post_retry=1)"
  )
}

try {
  New-Item -ItemType Directory -Path $tempDirectory -ErrorAction Stop | Out-Null
  Remove-Fixtures

  $setupSql = @"
INSERT INTO public.companies (id, name)
VALUES ('$fixtureCompanyId', 'Task 8 concurrency fixture');

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  (
    '7b000000-0000-0000-0000-000000000101',
    '$fixtureCompanyId',
    'Section race'
  ),
  (
    '7b000000-0000-0000-0000-000000000102',
    '$fixtureCompanyId',
    'Item race'
  );

INSERT INTO public.inspection_template_versions (id, template_id, version_number)
VALUES
  (
    '7c000000-0000-0000-0000-000000000101',
    '7b000000-0000-0000-0000-000000000101',
    1
  ),
  (
    '7c000000-0000-0000-0000-000000000102',
    '7b000000-0000-0000-0000-000000000102',
    1
  );

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES (
  '7d000000-0000-0000-0000-000000000102',
  '7c000000-0000-0000-0000-000000000102',
  'Existing item parent',
  10
);
"@
  [void](Invoke-RequiredSql `
    -Sql $setupSql `
    -FailureMessage 'Concurrency test fixture setup failed.')

  try {
    Invoke-FreezeRace `
      -Name 'section_insert' `
      -VersionId '7c000000-0000-0000-0000-000000000101' `
      -ChildSql @"
INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES (
  '7d000000-0000-0000-0000-000000000101',
  '7c000000-0000-0000-0000-000000000101',
  'Concurrent section',
  10
);
"@ `
      -ChildPostconditionSql @"
NOT EXISTS (
  SELECT 1
  FROM public.inspection_template_sections
  WHERE id = '7d000000-0000-0000-0000-000000000101'
)
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  try {
    Invoke-FreezeRace `
      -Name 'item_insert' `
      -VersionId '7c000000-0000-0000-0000-000000000102' `
      -ChildSql @"
INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES (
  '7e000000-0000-0000-0000-000000000102',
  '7d000000-0000-0000-0000-000000000102',
  'Concurrent item',
  10
);
"@ `
      -ChildPostconditionSql @"
NOT EXISTS (
  SELECT 1
  FROM public.inspection_template_items
  WHERE id = '7e000000-0000-0000-0000-000000000102'
)
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  $deleteRaceSetupSql = @"
INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  (
    '7b000000-0000-0000-0000-000000000201',
    '$fixtureCompanyId',
    'Section versus version delete'
  ),
  (
    '7b000000-0000-0000-0000-000000000202',
    '$fixtureCompanyId',
    'Item versus section delete'
  ),
  (
    '7b000000-0000-0000-0000-000000000203',
    '$fixtureCompanyId',
    'Item versus version delete'
  ),
  (
    '7b000000-0000-0000-0000-000000000204',
    '$fixtureCompanyId',
    'Version old template'
  ),
  (
    '7b000000-0000-0000-0000-000000000205',
    '$fixtureCompanyId',
    'Version new template'
  );

INSERT INTO public.inspection_template_versions (id, template_id, version_number)
VALUES
  (
    '7c000000-0000-0000-0000-000000000201',
    '7b000000-0000-0000-0000-000000000201',
    1
  ),
  (
    '7c000000-0000-0000-0000-000000000202',
    '7b000000-0000-0000-0000-000000000202',
    1
  ),
  (
    '7c000000-0000-0000-0000-000000000203',
    '7b000000-0000-0000-0000-000000000203',
    1
  ),
  (
    '7c000000-0000-0000-0000-000000000204',
    '7b000000-0000-0000-0000-000000000204',
    1
  );

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES
  (
    '7d000000-0000-0000-0000-000000000201',
    '7c000000-0000-0000-0000-000000000201',
    'Section update',
    10
  ),
  (
    '7d000000-0000-0000-0000-000000000202',
    '7c000000-0000-0000-0000-000000000202',
    'Section delete',
    10
  ),
  (
    '7d000000-0000-0000-0000-000000000203',
    '7c000000-0000-0000-0000-000000000203',
    'Version delete',
    10
  );

INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES
  (
    '7e000000-0000-0000-0000-000000000202',
    '7d000000-0000-0000-0000-000000000202',
    'Item update',
    10
  ),
  (
    '7e000000-0000-0000-0000-000000000203',
    '7d000000-0000-0000-0000-000000000203',
    'Item update',
    10
  );
"@
  [void](Invoke-RequiredSql `
    -Sql $deleteRaceSetupSql `
    -FailureMessage 'Delete-race fixture setup failed.')

  try {
    Invoke-DeleteRetryRace `
      -Name 'section_update_vs_version_delete' `
      -ParentLockSql @"
SELECT id
FROM public.inspection_template_versions
WHERE id = '7c000000-0000-0000-0000-000000000201'
FOR UPDATE;
"@ `
      -ParentDeleteSql @"
DELETE FROM public.inspection_template_versions
WHERE id = '7c000000-0000-0000-0000-000000000201';
"@ `
      -ChildMutationSql @"
UPDATE public.inspection_template_sections
SET title = 'Section updated'
WHERE id = '7d000000-0000-0000-0000-000000000201';
"@ `
      -PostconditionSql @"
SELECT (
  EXISTS (
    SELECT 1 FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000201'
  )
  AND (
    SELECT title = 'Section updated'
    FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000201'
  )
)::integer;
"@ `
      -RetryPostconditionSql @"
SELECT (
  NOT EXISTS (
    SELECT 1 FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000201'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000201'
  )
)::integer;
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  try {
    Invoke-DeleteRetryRace `
      -Name 'item_update_vs_section_delete' `
      -ParentLockSql @"
SELECT id
FROM public.inspection_template_sections
WHERE id = '7d000000-0000-0000-0000-000000000202'
FOR UPDATE;
"@ `
      -ParentDeleteSql @"
DELETE FROM public.inspection_template_sections
WHERE id = '7d000000-0000-0000-0000-000000000202';
"@ `
      -ChildMutationSql @"
UPDATE public.inspection_template_items
SET label = 'Item updated'
WHERE id = '7e000000-0000-0000-0000-000000000202';
"@ `
      -PostconditionSql @"
SELECT (
  EXISTS (
    SELECT 1 FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000202'
  )
  AND (
    SELECT label = 'Item updated'
    FROM public.inspection_template_items
    WHERE id = '7e000000-0000-0000-0000-000000000202'
  )
)::integer;
"@ `
      -RetryPostconditionSql @"
SELECT (
  NOT EXISTS (
    SELECT 1 FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000202'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.inspection_template_items
    WHERE id = '7e000000-0000-0000-0000-000000000202'
  )
)::integer;
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  try {
    Invoke-DeleteRetryRace `
      -Name 'item_update_vs_version_delete' `
      -ParentLockSql @"
SELECT id
FROM public.inspection_template_versions
WHERE id = '7c000000-0000-0000-0000-000000000203'
FOR UPDATE;
"@ `
      -ParentDeleteSql @"
DELETE FROM public.inspection_template_versions
WHERE id = '7c000000-0000-0000-0000-000000000203';
"@ `
      -ChildMutationSql @"
UPDATE public.inspection_template_items
SET label = 'Item updated'
WHERE id = '7e000000-0000-0000-0000-000000000203';
"@ `
      -PostconditionSql @"
SELECT (
  EXISTS (
    SELECT 1 FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000203'
  )
  AND EXISTS (
    SELECT 1 FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000203'
  )
  AND (
    SELECT label = 'Item updated'
    FROM public.inspection_template_items
    WHERE id = '7e000000-0000-0000-0000-000000000203'
  )
)::integer;
"@ `
      -RetryPostconditionSql @"
SELECT (
  NOT EXISTS (
    SELECT 1 FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000203'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.inspection_template_sections
    WHERE id = '7d000000-0000-0000-0000-000000000203'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.inspection_template_items
    WHERE id = '7e000000-0000-0000-0000-000000000203'
  )
)::integer;
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  try {
    Invoke-DeleteRetryRace `
      -Name 'version_reparent_vs_template_delete' `
      -ParentLockSql @"
SELECT id
FROM public.inspection_templates
WHERE id = '7b000000-0000-0000-0000-000000000204'
FOR UPDATE;
"@ `
      -ParentDeleteSql @"
DELETE FROM public.inspection_templates
WHERE id = '7b000000-0000-0000-0000-000000000204';
"@ `
      -ChildMutationSql @"
UPDATE public.inspection_template_versions
SET template_id = '7b000000-0000-0000-0000-000000000205'
WHERE id = '7c000000-0000-0000-0000-000000000204';
"@ `
      -PostconditionSql @"
SELECT (
  EXISTS (
    SELECT 1 FROM public.inspection_templates
    WHERE id = '7b000000-0000-0000-0000-000000000204'
  )
  AND (
    SELECT template_id = '7b000000-0000-0000-0000-000000000205'
    FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000204'
  )
)::integer;
"@ `
      -RetryPostconditionSql @"
SELECT (
  NOT EXISTS (
    SELECT 1 FROM public.inspection_templates
    WHERE id = '7b000000-0000-0000-0000-000000000204'
  )
  AND (
    SELECT template_id = '7b000000-0000-0000-0000-000000000205'
    FROM public.inspection_template_versions
    WHERE id = '7c000000-0000-0000-0000-000000000204'
  )
)::integer;
"@
  }
  catch {
    $raceFailures.Add($_.Exception.Message)
    Write-Output "not ok - $($_.Exception.Message)"
  }

  if ($raceFailures.Count -ne 0) {
    throw "$($raceFailures.Count)/6 concurrency races failed."
  }

  Write-Output '6/6 concurrency races passed'
}
finally {
  foreach ($job in @($activeJobs)) {
    if ($job.State -eq 'Running') {
      Stop-Job -Job $job
    }
    Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  }

  try {
    Remove-Fixtures
  }
  finally {
    if (Test-Path -LiteralPath $tempDirectory) {
      Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
  }
}
