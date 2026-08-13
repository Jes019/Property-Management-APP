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

function Wait-ForFreezeHold {
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
      throw 'Could not observe the freeze session.'
    }
    if ($pollResult.Output -eq '1') {
      return
    }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)

  throw 'Freeze session did not reach its deterministic hold point.'
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

  Wait-ForFreezeHold -ApplicationName $applicationName

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

  if ($raceFailures.Count -ne 0) {
    throw "$($raceFailures.Count)/2 concurrency races failed."
  }

  Write-Output '2/2 concurrency races passed'
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
