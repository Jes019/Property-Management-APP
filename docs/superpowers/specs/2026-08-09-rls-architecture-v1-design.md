# RLS Architecture v1.0 - JTC Property Services

Status: APPROVED
Purpose: Authoritative security and tenancy specification for implementation.

## Core model

GLOBAL PROFILE -> COMPANY / TENANT -> PROPERTY RELATIONSHIP -> OPERATIONAL RECORD -> RLS PERMISSION

### Identity
- `profiles` is global identity.
- Owners are global platform users, not company-owned users.
- One owner account may own properties managed by different companies.
- Owner identity must never grant a company discovery of unrelated owner properties or portfolio history.

### Company membership
Company roles:
- ADMIN
- MANAGER
- INSPECTOR
- COORDINATOR
- READ_ONLY

A company user requires an active `company_membership`.

### Property management relationship
- One ACTIVE PRIMARY management company per property.
- Additional bounded service relationships may exist with explicit scope:
  - FULL_MANAGEMENT
  - INSPECTION_SERVICE
  - MAINTENANCE_SERVICE
  - COORDINATION_SERVICE
- A company relationship to a property never grants access to records owned by another company unless an approved cross-company rule explicitly allows it.

### Operational record ownership
Operational tables normally store explicit:
- `company_id`
- `property_id`

`company_id` means the company responsible for / owning that operational record.

## Owner authorization path

Owner access is derived separately from company access through `property_owners`.

Owners:
- may access only properties they own;
- may access only explicitly owner-visible records;
- may not access company-internal data;
- may not access unrelated properties belonging to the same owner identity through company-side discovery.

The owner authorization path must remain separate from the company membership authorization path.

## Inspection rules

Inspection severity values:
- PASS
- ATTENTION
- URGENT

Operational action is separate:
- MONITOR
- INCLUDED_IN_SERVICE
- OWNER_APPROVAL_REQUIRED

Never merge severity and operational action.

Inspector access should be assignment-bounded where the workflow uses staff assignment.

## Reports

Report states:
- DRAFT
- FINAL
- SUPERSEDED

Rules:
- DRAFT is editable only by authorized company users.
- FINAL is published and immutable.
- SUPERSEDED is immutable history.
- Owners may see only published FINAL owner-visible reports.
- Owners must never see DRAFT reports.

Published report immutability must be enforced below the UI layer.

## Quotes and approvals

Quotes are versioned.

Once a quote version is shared with an owner or used for approval, that version is immutable.

Owner approval must capture an immutable snapshot of:
- contractor/vendor
- scope
- amount
- quote version

A fresh approval is required when there is:
- contractor change
- amount increase
- material scope change

Approval snapshots/events are immutable, including to tenant ADMIN.

Owner approval should be performed through a controlled transaction/RPC.

Maintenance jobs are created only from valid approval through a controlled operation such as `create_job_from_approval`.

Do not permit unrestricted browser insert paths that bypass approval.

NOTE FOR FIRST VERTICAL SLICE:
Approval tables are not part of migrations 001-012.
The required future adversarial test "ADMIN cannot modify approval snapshot" remains locked but executable coverage is deferred to the approvals slice. Do not create premature approval tables just to satisfy that future test.

## Internal vs owner-visible data

Owners must not see:
- internal notes
- quote comparison internals
- contractor/supplier internal records
- internal recommendation logic
- draft reports
- unrelated company records

Owner visibility must be explicit in database/storage policy, not implemented only by UI hiding.

## Storage

Storage buckets are private.

Suggested buckets:
- inspection-media
- reports
- documents
- vendor-documents
- job-media
- company-branding

Suggested object path:
`/{company_id}/{property_id}/{record_type}/{record_id}/{filename}`

Path structure alone is not authorization.

Storage object RLS must validate the database parent record and the same tenant/property/owner visibility rules.

## Service role

Supabase service role:
- server-side only
- never browser/client
- never `NEXT_PUBLIC_*`

Ordinary application access should run under authenticated user context and RLS.

## Security helper functions

Use a dedicated security schema for reusable helpers such as:
- `current_profile_id()`
- `is_company_member(company_id)`
- `company_role(company_id)`
- `has_company_role(company_id, roles[])`
- `is_property_owner(property_id)`
- `company_has_property_access(company_id, property_id)`
- `company_has_property_scope(company_id, property_id, scope)`
- `is_assigned_to_property(profile_id, property_id)`
- `is_assigned_to_inspection(profile_id, inspection_id)`
- `can_view_operational_record(...)`
- `can_manage_operational_record(...)`
- `owner_can_view_report(report_version_id)`
- `owner_can_view_quote_version(quote_version_id)`
- `owner_can_view_document(document_version_id)`

Use SECURITY DEFINER only where required.
For SECURITY DEFINER:
- fixed `search_path`
- minimal privilege
- controlled EXECUTE grants

## Immutability enforcement

Immutability is not a UI concern.

Use the correct combination of:
- RLS
- table privileges
- constraints
- triggers
- controlled functions / RPC
- server actions where appropriate

## Audit

Important actions and decisions are audited.

`audit_log` is append-only.

Normal users:
- no UPDATE
- no DELETE
- no unrestricted INSERT

Audit entries should be created by controlled triggers/functions/server-side trust-boundary operations.

## RLS defaults

- Default deny.
- Every tenant-facing table gets explicit policies.
- Never rely on client filtering.
- Hostile UUID substitution must fail.

## Performance indexes

Index the columns used by authorization predicates, including:
- company membership lookups
- property owner lookups
- property-company relationship lookups
- property/staff assignment lookups
- operational `company_id`
- operational `property_id`
- report publication/visibility lookups

## Mandatory adversarial tests

As applicable to implemented slices:
- tenant A cannot read tenant B data
- owner can read own property only
- owner cannot discover unrelated properties
- owner can see FINAL report
- owner cannot see DRAFT report
- owner sees only explicitly shared quote versions
- inspector sees assigned scope only
- coordinator cannot publish where not authorized
- READ_ONLY cannot mutate
- ADMIN cannot mutate immutable FINAL records
- secondary/service company sees only bounded scope
- hostile UUID substitution denied

Future approvals slice:
- ADMIN cannot modify approval snapshot

## First vertical slice security target

JTC ADMIN -> Property -> Owner -> Inspection -> Results / Photos / Meter Readings -> Draft Report -> FINAL Published Report -> Owner Portal

Success scenario:
- JTC admin opens Pender Gardens Apartment 1042.
- Creates and completes an inspection.
- Records electricity/water readings.
- Adds photos.
- Produces a DRAFT report.
- Publishes FINAL.
- Andrea logs in and sees only the published owner-facing report and owner-visible photos.
- Andrea cannot see drafts, internal notes, or unrelated property/company data.
