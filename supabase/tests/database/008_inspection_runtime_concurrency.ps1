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

$fixtureProfileId = '8c000000-0000-0000-0000-000000000001'
$fixtureCompanyId = '8c000000-0000-0000-0000-000000000002'
$fixturePropertyId = '8c000000-0000-0000-0000-000000000003'
$fixtureTemplateId = '8c000000-0000-0000-0000-000000000004'
$fixtureVersionId = '8c000000-0000-0000-0000-000000000005'
$fixtureSectionId = '8c000000-0000-0000-0000-000000000006'
$fixtureItemId = '8c000000-0000-0000-0000-000000000007'
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
DELETE FROM public.inspection_changes
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.inspection_results
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.meter_readings
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.inspections
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.inspection_template_items
WHERE section_id = '$fixtureSectionId';
DELETE FROM public.inspection_template_sections
WHERE version_id = '$fixtureVersionId';
DELETE FROM public.inspection_template_versions
WHERE template_id = '$fixtureTemplateId';
DELETE FROM public.inspection_templates
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.property_staff_assignments
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.company_property_settings
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.property_company_relationships
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.property_owners
WHERE property_id = '$fixturePropertyId';
DELETE FROM public.company_memberships
WHERE company_id = '$fixtureCompanyId';
DELETE FROM public.companies
WHERE id = '$fixtureCompanyId';
DELETE FROM public.properties
WHERE id = '$fixturePropertyId';
DELETE FROM public.profiles
WHERE id = '$fixtureProfileId';
DELETE FROM auth.users
WHERE id = '$fixtureProfileId';
SET session_replication_role = origin;
"@

  $cleanupResult = Invoke-Psql -Sql $cleanupSql
  if ($cleanupResult.ExitCode -ne 0) {
    throw 'Task 9 concurrency fixture cleanup failed.'
  }
}

function Start-PsqlJob {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Sql
  )

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
    [Parameter(Mandatory = $true)]
    [object]$Job,

    [Parameter(Mandatory = $true)]
    [string]$FailureMessage
  )

  $completedJob = Wait-Job -Job $Job -Timeout ($HoldSeconds + 20)
  if ($null -eq $completedJob) {
    Stop-Job -Job $Job -ErrorAction SilentlyContinue
    throw $FailureMessage
  }

  $received = @(Receive-Job -Job $Job)
  if ($received.Count -eq 0) {
    throw $FailureMessage
  }

  return $received[-1]
}

function Wait-ForCompletionHold {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationName
  )

  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ([DateTime]::UtcNow -lt $deadline) {
    $escapedName = $ApplicationName.Replace("'", "''")
    $probe = Invoke-Psql -Sql @"
SELECT count(*)
FROM pg_stat_activity
WHERE application_name = '$escapedName'
  AND state = 'active'
  AND wait_event = 'PgSleep';
"@

    if ($probe.ExitCode -eq 0 -and $probe.Output.Trim() -eq '1') {
      return
    }

    Start-Sleep -Milliseconds 100
  }

  throw 'Completion session did not reach its bounded hold point.'
}

function Test-Race {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$InspectionId,

    [Parameter(Mandatory = $true)]
    [string]$ChildSql,

    [Parameter(Mandatory = $true)]
    [string]$PostconditionSql,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPostcondition
  )

  $applicationName = 'jtc_task9_' + $Name
  $completionSql = @"
BEGIN;
SET LOCAL application_name = '$applicationName';
SET LOCAL request.jwt.claim.sub = '$fixtureProfileId';
SET LOCAL lock_timeout = '10s';
UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = '$InspectionId';
SELECT pg_sleep($HoldSeconds);
COMMIT;
"@

  $completionJob = $null
  $childJob = $null
  try {
    $completionJob = Start-PsqlJob -Sql $completionSql
    Wait-ForCompletionHold -ApplicationName $applicationName

    $childStatement = @"
SET request.jwt.claim.sub = '$fixtureProfileId';
SET lock_timeout = '10s';
$ChildSql
"@
    $childJob = Start-PsqlJob -Sql $childStatement

    $childResult = Receive-BoundedJob `
      -Job $childJob `
      -FailureMessage "$Name child session did not finish in time."
    $completionResult = Receive-BoundedJob `
      -Job $completionJob `
      -FailureMessage "$Name completion session did not finish in time."

    if ($completionResult.ExitCode -ne 0) {
      $raceFailures.Add("$Name completion failed unexpectedly.")
      return
    }

    if ($childResult.ExitCode -eq 0) {
      $raceFailures.Add("$Name child mutation committed unexpectedly.")
      return
    }

    if ($childResult.Output -notmatch 'ERROR:\s+55000:') {
      $raceFailures.Add("$Name child mutation did not return SQLSTATE 55000.")
      return
    }

    $postcondition = Invoke-RequiredSql `
      -Sql $PostconditionSql `
      -FailureMessage "$Name postcondition query failed."
    if ($postcondition.Trim() -ne $ExpectedPostcondition) {
      $raceFailures.Add("$Name final snapshot did not match.")
      return
    }

    Write-Output "$Name passed"
  }
  catch {
    $raceFailures.Add("$Name failed: $($_.Exception.Message)")
  }
  finally {
    foreach ($job in @($childJob, $completionJob)) {
      if ($null -ne $job) {
        if ($job.State -eq 'Running') {
          Stop-Job -Job $job -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        [void]$activeJobs.Remove($job)
      }
    }
  }
}

$inspectionIds = @(
  '8d000000-0000-0000-0000-000000000001',
  '8d000000-0000-0000-0000-000000000002',
  '8d000000-0000-0000-0000-000000000003',
  '8d000000-0000-0000-0000-000000000004',
  '8d000000-0000-0000-0000-000000000005',
  '8d000000-0000-0000-0000-000000000006'
)

try {
  Remove-Fixtures

  $inspectionValues = ($inspectionIds | ForEach-Object {
    "('$_', '$fixtureCompanyId', '$fixturePropertyId', '$fixtureVersionId')"
  }) -join ",`n  "

  $setupSql = @"
INSERT INTO auth.users (id) VALUES ('$fixtureProfileId');
INSERT INTO public.profiles (id) VALUES ('$fixtureProfileId');
INSERT INTO public.companies (id, name)
VALUES ('$fixtureCompanyId', 'Task 9 concurrency fixture');
INSERT INTO public.company_memberships (
  company_id,
  profile_id,
  role,
  is_active
)
VALUES ('$fixtureCompanyId', '$fixtureProfileId', 'ADMIN', true);
INSERT INTO public.properties (id, name)
VALUES ('$fixturePropertyId', 'Task 9 concurrency property');
INSERT INTO public.property_company_relationships (
  id,
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES (
  '8c000000-0000-0000-0000-000000000008',
  '$fixturePropertyId',
  '$fixtureCompanyId',
  'PRIMARY',
  'ACTIVE',
  'FULL_MANAGEMENT'
);
INSERT INTO public.inspection_templates (id, company_id, name)
VALUES ('$fixtureTemplateId', '$fixtureCompanyId', 'Task 9 concurrency template');
INSERT INTO public.inspection_template_versions (
  id,
  template_id,
  version_number,
  is_current
)
VALUES ('$fixtureVersionId', '$fixtureTemplateId', 1, false);
INSERT INTO public.inspection_template_sections (
  id,
  version_id,
  title,
  sort_order
)
VALUES ('$fixtureSectionId', '$fixtureVersionId', 'Concurrency', 1);
INSERT INTO public.inspection_template_items (
  id,
  section_id,
  label,
  sort_order
)
VALUES ('$fixtureItemId', '$fixtureSectionId', 'Concurrency item', 1);
UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id = '$fixtureVersionId';
SET request.jwt.claim.sub = '$fixtureProfileId';
INSERT INTO public.inspections (
  id,
  company_id,
  property_id,
  template_version_id
)
VALUES
  $inspectionValues;
UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE company_id = '$fixtureCompanyId';
INSERT INTO public.inspection_results (
  id,
  company_id,
  property_id,
  inspection_id,
  template_item_id,
  severity,
  operational_action,
  comment
)
VALUES
  ('8e000000-0000-0000-0000-000000000002', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000002', '$fixtureItemId', 'PASS', 'MONITOR', 'original update'),
  ('8e000000-0000-0000-0000-000000000003', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000003', '$fixtureItemId', 'PASS', 'MONITOR', 'original delete');
INSERT INTO public.meter_readings (
  id,
  company_id,
  property_id,
  inspection_id,
  meter_type,
  reading_value,
  unit
)
VALUES
  ('8f000000-0000-0000-0000-000000000005', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000005', 'WATER', 15.5, 'm3'),
  ('8f000000-0000-0000-0000-000000000006', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000006', 'ELECTRICITY', 16.5, 'kWh');
"@

  [void](Invoke-RequiredSql `
    -Sql $setupSql `
    -FailureMessage 'Task 9 concurrency fixture setup failed.')

  Test-Race `
    -Name 'result_insert' `
    -InspectionId '8d000000-0000-0000-0000-000000000001' `
    -ChildSql "INSERT INTO public.inspection_results (id, company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('8e000000-0000-0000-0000-000000000001', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000001', '$fixtureItemId', 'PASS', 'MONITOR');" `
    -PostconditionSql "SELECT status || '|' || (SELECT count(*) FROM public.inspection_results WHERE inspection_id = '8d000000-0000-0000-0000-000000000001') || '|' || (SELECT count(*) FROM public.inspection_changes WHERE inspection_id = '8d000000-0000-0000-0000-000000000001' AND change_type = 'RESULT_CHANGED') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000001';" `
    -ExpectedPostcondition 'COMPLETED|0|0'

  Test-Race `
    -Name 'result_update' `
    -InspectionId '8d000000-0000-0000-0000-000000000002' `
    -ChildSql "UPDATE public.inspection_results SET comment = 'hostile update' WHERE id = '8e000000-0000-0000-0000-000000000002';" `
    -PostconditionSql "SELECT status || '|' || (SELECT comment FROM public.inspection_results WHERE id = '8e000000-0000-0000-0000-000000000002') || '|' || (SELECT count(*) FROM public.inspection_changes WHERE inspection_id = '8d000000-0000-0000-0000-000000000002' AND change_type = 'RESULT_CHANGED') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000002';" `
    -ExpectedPostcondition 'COMPLETED|original update|1'

  Test-Race `
    -Name 'result_delete' `
    -InspectionId '8d000000-0000-0000-0000-000000000003' `
    -ChildSql "DELETE FROM public.inspection_results WHERE id = '8e000000-0000-0000-0000-000000000003';" `
    -PostconditionSql "SELECT status || '|' || (SELECT count(*) FROM public.inspection_results WHERE id = '8e000000-0000-0000-0000-000000000003') || '|' || (SELECT count(*) FROM public.inspection_changes WHERE inspection_id = '8d000000-0000-0000-0000-000000000003' AND change_type = 'RESULT_CHANGED') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000003';" `
    -ExpectedPostcondition 'COMPLETED|1|1'

  Test-Race `
    -Name 'meter_insert' `
    -InspectionId '8d000000-0000-0000-0000-000000000004' `
    -ChildSql "INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('8f000000-0000-0000-0000-000000000004', '$fixtureCompanyId', '$fixturePropertyId', '8d000000-0000-0000-0000-000000000004', 'WATER', 14.5, 'm3');" `
    -PostconditionSql "SELECT status || '|' || (SELECT count(*) FROM public.meter_readings WHERE inspection_id = '8d000000-0000-0000-0000-000000000004') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000004';" `
    -ExpectedPostcondition 'COMPLETED|0'

  Test-Race `
    -Name 'meter_update' `
    -InspectionId '8d000000-0000-0000-0000-000000000005' `
    -ChildSql "UPDATE public.meter_readings SET reading_value = 999 WHERE id = '8f000000-0000-0000-0000-000000000005';" `
    -PostconditionSql "SELECT status || '|' || (SELECT reading_value FROM public.meter_readings WHERE id = '8f000000-0000-0000-0000-000000000005') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000005';" `
    -ExpectedPostcondition 'COMPLETED|15.5'

  Test-Race `
    -Name 'meter_delete' `
    -InspectionId '8d000000-0000-0000-0000-000000000006' `
    -ChildSql "DELETE FROM public.meter_readings WHERE id = '8f000000-0000-0000-0000-000000000006';" `
    -PostconditionSql "SELECT status || '|' || (SELECT count(*) FROM public.meter_readings WHERE id = '8f000000-0000-0000-0000-000000000006') FROM public.inspections WHERE id = '8d000000-0000-0000-0000-000000000006';" `
    -ExpectedPostcondition 'COMPLETED|1'

  if ($raceFailures.Count -gt 0) {
    foreach ($failure in $raceFailures) {
      Write-Error $failure
    }
    throw "$($raceFailures.Count)/6 concurrency races failed."
  }

  Write-Output '6/6 completion-versus-evidence races passed'
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
