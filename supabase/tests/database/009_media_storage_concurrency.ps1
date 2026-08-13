param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$DatabaseUrl,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$PsqlPath,

  [ValidateRange(2, 20)]
  [int]$HoldSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) {
  throw 'The supplied psql executable does not exist.'
}

$profileId = '9c000000-0000-0000-0000-000000000001'
$companyId = '9c000000-0000-0000-0000-000000000002'
$propertyId = '9c000000-0000-0000-0000-000000000003'
$templateId = '9c000000-0000-0000-0000-000000000004'
$versionId = '9c000000-0000-0000-0000-000000000005'
$sectionId = '9c000000-0000-0000-0000-000000000006'
$itemId = '9c000000-0000-0000-0000-000000000007'
$inspectionId = '9d000000-0000-0000-0000-000000000001'
$assetId = '9e000000-0000-0000-0000-000000000001'
$objectPath = "$companyId/$propertyId/inspection/$inspectionId/$assetId/race.jpg"
$activeJobs = [System.Collections.Generic.List[object]]::new()

function Invoke-Psql {
  param([Parameter(Mandatory = $true)][string]$Sql)

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $commandOutput = & $PsqlPath $DatabaseUrl `
      -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt -P pager=off `
      -c $Sql 2>&1
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
    [Parameter(Mandatory = $true)][string]$Sql,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )

  $result = Invoke-Psql -Sql $Sql
  if ($result.ExitCode -ne 0) {
    throw $FailureMessage
  }
  return $result.Output
}

function Start-PsqlJob {
  param([Parameter(Mandatory = $true)][string]$Sql)

  $job = Start-Job -ScriptBlock {
    param($Executable, $Target, $Statement)
    $jobOutput = & $Executable $Target `
      -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt -P pager=off `
      -c $Statement 2>&1
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($jobOutput | Out-String).Trim()
    }
  } -ArgumentList $PsqlPath, $DatabaseUrl, $Sql

  $activeJobs.Add($job)
  return $job
}

function Receive-BoundedJob {
  param(
    [Parameter(Mandatory = $true)][object]$Job,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )

  $completed = Wait-Job -Job $Job -Timeout ($HoldSeconds + 20)
  if ($null -eq $completed) {
    Stop-Job -Job $Job -ErrorAction SilentlyContinue
    throw $FailureMessage
  }
  $received = @(Receive-Job -Job $Job)
  if ($received.Count -eq 0) {
    throw $FailureMessage
  }
  return $received[-1]
}

function Wait-ForSessionState {
  param(
    [Parameter(Mandatory = $true)][string]$ProbeSql,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )

  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ([DateTime]::UtcNow -lt $deadline) {
    $probe = Invoke-Psql -Sql $ProbeSql
    if ($probe.ExitCode -eq 0 -and $probe.Output.Trim()) {
      return $probe.Output.Trim()
    }
    Start-Sleep -Milliseconds 100
  }
  throw $FailureMessage
}

function Remove-Fixtures {
  $cleanupSql = @"
SET session_replication_role = replica;
SET storage.allow_delete_query = 'true';
DELETE FROM storage.objects
WHERE bucket_id = 'inspection-media'
  AND name = '$objectPath';
DELETE FROM public.media_assets WHERE id = '$assetId';
DELETE FROM public.inspection_changes WHERE company_id = '$companyId';
DELETE FROM public.inspections WHERE id = '$inspectionId';
DELETE FROM public.inspection_template_items WHERE id = '$itemId';
DELETE FROM public.inspection_template_sections WHERE id = '$sectionId';
DELETE FROM public.inspection_template_versions WHERE id = '$versionId';
DELETE FROM public.inspection_templates WHERE id = '$templateId';
DELETE FROM public.property_company_relationships WHERE company_id = '$companyId';
DELETE FROM public.company_memberships WHERE company_id = '$companyId';
DELETE FROM public.companies WHERE id = '$companyId';
DELETE FROM public.properties WHERE id = '$propertyId';
DELETE FROM public.profiles WHERE id = '$profileId';
DELETE FROM auth.users WHERE id = '$profileId';
SET session_replication_role = origin;
"@
  $result = Invoke-Psql -Sql $cleanupSql
  if ($result.ExitCode -ne 0) {
    throw 'Task 10 concurrency fixture cleanup failed.'
  }
}

try {
  Remove-Fixtures

  [void](Invoke-RequiredSql -FailureMessage 'Task 10 race fixture setup failed.' -Sql @"
INSERT INTO auth.users (id) VALUES ('$profileId');
INSERT INTO public.profiles (id) VALUES ('$profileId');
INSERT INTO public.companies (id, name)
VALUES ('$companyId', 'Task 10 race company');
INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES ('$companyId', '$profileId', 'ADMIN', true);
INSERT INTO public.properties (id, name)
VALUES ('$propertyId', 'Task 10 race property');
INSERT INTO public.property_company_relationships (
  id, property_id, company_id, relationship_type, status, scope
) VALUES (
  '9c000000-0000-0000-0000-000000000008',
  '$propertyId', '$companyId', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'
);
INSERT INTO public.inspection_templates (id, company_id, name)
VALUES ('$templateId', '$companyId', 'Task 10 race template');
INSERT INTO public.inspection_template_versions (
  id, template_id, version_number, is_current
) VALUES ('$versionId', '$templateId', 1, false);
INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES ('$sectionId', '$versionId', 'Race', 1);
INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES ('$itemId', '$sectionId', 'Race item', 1);
UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id = '$versionId';
SET request.jwt.claim.sub = '$profileId';
INSERT INTO public.inspections (
  id, company_id, property_id, template_version_id
) VALUES ('$inspectionId', '$companyId', '$propertyId', '$versionId');
UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = '$inspectionId';
INSERT INTO public.media_assets (
  id, company_id, property_id, inspection_id,
  storage_bucket, storage_path, mime_type
) VALUES (
  '$assetId', '$companyId', '$propertyId', '$inspectionId',
  'inspection-media', '$objectPath', 'image/jpeg'
);
"@)

  $gateName = 'jtc_task10_storage_gate'
  $parentName = 'jtc_task10_storage_parent'
  $childName = 'jtc_task10_storage_child'

  $gateJob = Start-PsqlJob -Sql @"
SET application_name = '$gateName';
SELECT pg_advisory_lock(9010, 1);
SELECT pg_sleep($($HoldSeconds + 20));
"@
  [void](Wait-ForSessionState -FailureMessage 'Task 10 advisory gate was not held.' -ProbeSql @"
SELECT 'gate_held'
FROM pg_stat_activity
WHERE application_name = '$gateName'
  AND state = 'active'
  AND wait_event = 'PgSleep';
"@)

  $parentJob = Start-PsqlJob -Sql @"
BEGIN;
SET LOCAL application_name = '$parentName';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '$profileId';
SET LOCAL lock_timeout = '20s';
UPDATE public.inspections SET status = 'COMPLETED' WHERE id = '$inspectionId';
SELECT pg_advisory_lock(9010, 1);
COMMIT;
"@
  [void](Wait-ForSessionState -FailureMessage 'Completion did not acquire the row before gating.' -ProbeSql @"
SELECT 'parent_gated'
FROM pg_stat_activity AS parent_state
WHERE parent_state.application_name = '$parentName'
  AND parent_state.wait_event_type = 'Lock'
  AND parent_state.wait_event = 'advisory'
  AND EXISTS (
    SELECT 1 FROM pg_stat_activity AS gate_state
    WHERE gate_state.application_name = '$gateName'
      AND gate_state.pid = ANY (pg_blocking_pids(parent_state.pid))
  );
"@)

  $childJob = Start-PsqlJob -Sql @"
SET application_name = '$childName';
SET ROLE authenticated;
SET request.jwt.claim.sub = '$profileId';
SET lock_timeout = '10s';
INSERT INTO storage.objects (bucket_id, name)
VALUES ('inspection-media', '$objectPath');
"@

  [void](Wait-ForSessionState -FailureMessage 'Storage upload was not observed blocked by completion.' -ProbeSql @"
SELECT child_state.wait_event
FROM pg_stat_activity AS child_state
JOIN pg_stat_activity AS parent_state
  ON parent_state.application_name = '$parentName'
WHERE child_state.application_name = '$childName'
  AND child_state.state = 'active'
  AND child_state.wait_event_type = 'Lock'
  AND child_state.wait_event IN ('transactionid', 'tuple')
  AND parent_state.pid = ANY (pg_blocking_pids(child_state.pid));
"@)

  $released = Invoke-RequiredSql -FailureMessage 'Task 10 gate release failed.' -Sql @"
SELECT COALESCE(bool_and(pg_terminate_backend(pid)), false)::text
FROM pg_stat_activity
WHERE application_name = '$gateName';
"@
  if ($released.Trim() -ne 'true') {
    throw 'Task 10 gate backend was not released.'
  }

  $parentResult = Receive-BoundedJob -Job $parentJob -FailureMessage 'Completion session timed out.'
  $childResult = Receive-BoundedJob -Job $childJob -FailureMessage 'Storage child session timed out.'
  if ($parentResult.ExitCode -ne 0) {
    throw 'Completion session failed unexpectedly.'
  }
  if ($childResult.ExitCode -eq 0 -or $childResult.Output -notmatch 'ERROR:\s+42501:') {
    throw 'The post-wait storage upload did not fail with SQLSTATE 42501.'
  }

  $finalState = Invoke-RequiredSql -FailureMessage 'Task 10 final race state query failed.' -Sql @"
SELECT (
  (SELECT status = 'COMPLETED' FROM public.inspections WHERE id = '$inspectionId')
  AND NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'inspection-media' AND name = '$objectPath'
  )
)::text;
"@
  if ($finalState.Trim() -ne 'true') {
    throw 'Task 10 completion/upload race left an invalid final state.'
  }

  Write-Output '1/1 completion-versus-storage-upload race passed'
}
finally {
  foreach ($job in @($activeJobs)) {
    if ($job.State -eq 'Running') {
      Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  }
  Remove-Fixtures
}
