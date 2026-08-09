# RLS Architecture V1 Design

**Status:** Approved and locked
**Date:** 2026-08-09
**Product:** Multi-tenant white-label property management platform
**First tenant:** JTC Property Services

## 1. Purpose

This specification defines the approved version 1.0 authorization architecture for the property management platform. It is the security contract for database schema design, PostgreSQL Row Level Security (RLS), controlled database operations, Supabase Storage access, and the first production vertical slice.

The visual design is complete and frozen. Future Google Stitch HTML files are visual references only and are not production code. This specification does not redesign the product, add features, or authorize broad implementation.

## 2. Locked Technology Stack

- Next.js
- React
- TypeScript
- Tailwind CSS
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- PostgreSQL Row Level Security
- Vercel

Supabase service-role and other privileged credentials must never be exposed to browser or client code.

## 3. Core Authorization Model

Authorization follows this chain:

```text
GLOBAL PROFILE
-> COMPANY / TENANT
-> PROPERTY RELATIONSHIP
-> OPERATIONAL RECORD
-> RLS PERMISSION
```

The platform is multi-tenant and white-label from its first release. JTC Property Services is the first tenant, not a special-case security boundary.

All access is default-deny. A caller must prove the required relationship and permission through database records evaluated by RLS or a narrowly controlled transactional database function. Possession of a `company_id`, `property_id`, `owner_id`, record identifier, or any other UUID never grants access.

## 4. Identity and Tenant Boundaries

### 4.1 Global profiles and owners

`profiles` represents global platform identities associated with Supabase Auth identities. Owners are global platform users; they are not records owned by a company.

An owner account may be related to properties managed by different companies. Owner access derives from `property_owners`, scoped to the particular property. A company must never discover an owner's unrelated properties, relationships, or portfolio history through that owner identity.

`OWNER` is not a company role and must not be added to company role enums or membership logic.

### 4.2 Companies and memberships

Company authorization derives from an active `company_memberships` relationship and, when the operation concerns a property, an authorized `property_company_relationships` relationship. Role or assignment checks are added when the operation requires them.

The locked company roles are:

- `ADMIN`
- `MANAGER`
- `INSPECTOR`
- `COORDINATOR`
- `READ_ONLY`

Role membership alone does not grant access to every property or every operational record. Property relationship, service scope, record responsibility, and assignment requirements remain independently enforceable.

### 4.3 Property-company relationships

Each property has exactly one active primary management company. This invariant must be enforced in the database, including under concurrent writes.

Secondary or service companies receive only explicitly granted bounded scopes:

- `FULL_MANAGEMENT`
- `INSPECTION_SERVICE`
- `MAINTENANCE_SERVICE`
- `COORDINATION_SERVICE`

A relationship to the same property does not grant a company access to records belonging to another company. On an operational record, `company_id` identifies the company responsible for that record. Operational tables normally store both `company_id` and `property_id` explicitly so policies can enforce both boundaries without indirect or ambiguous inference.

## 5. Domain Rules Enforced by Authorization

### 5.1 Inspections

Inspection severity values are:

- `PASS`
- `ATTENTION`
- `URGENT`

Inspection operational action is a separate dimension with these values:

- `MONITOR`
- `INCLUDED_IN_SERVICE`
- `OWNER_APPROVAL_REQUIRED`

Severity and operational action must remain separate columns or values. One must not be inferred from or collapsed into the other.

Inspectors receive only assignment-bounded access. An inspector may access an inspection only when the applicable property and inspection assignment rules succeed. A property assignment must not silently grant access to unrelated inspections where an inspection-specific assignment is required.

### 5.2 Reports

Inspection report versions use these states:

- `DRAFT`
- `FINAL`
- `SUPERSEDED`

Published reports are immutable. `FINAL` and `SUPERSEDED` report versions cannot be modified or deleted by ordinary company users, including administrators. Publishing is a controlled transaction that validates authority, creates or transitions the final version consistently, supersedes the applicable prior final version when required, and records an audit event.

Owners may see only published owner-facing report versions for properties they own and only media explicitly permitted for owner viewing. Owners cannot see draft reports, internal fields, or company-only records.

### 5.3 Quotes, approvals, and maintenance

Quotes are versioned. Historical quote versions and quote versions shared with an owner are immutable.

Owner approval is an immutable snapshot containing, at minimum, the selected contractor, scope, amount, and quote version. Any contractor change, amount increase, quote-version change, or material scope change invalidates reuse of the existing approval and requires fresh owner approval.

`approval_snapshots` and `approval_events` are immutable. Maintenance jobs may be created only after validation of a current, applicable approval snapshot. Sensitive approval and job-creation operations must use controlled server/database transactions rather than unrestricted browser inserts or updates.

### 5.4 Owner-facing and private information

Owners receive simplified statuses and only records expressly marked or derived as owner-visible under database policy. Frontend hiding is not an authorization mechanism.

The following remain private from owners and unrelated companies:

- internal notes
- internal quote comparisons
- contractor internals
- supplier internals
- drafts and internal report content
- operational records owned by another responsible company

### 5.5 Auditability

Every important decision and action must be audited. `audit_log` is append-only. Audit writes for sensitive state transitions occur within the same controlled transaction as the protected operation so the business change and its audit record cannot diverge.

## 6. Data Model Scope

The approved main database architecture comprises:

- `profiles`
- `companies`
- `company_branding`
- `company_memberships`
- `company_host_settings`
- `properties`
- `property_owners`
- `property_company_relationships`
- `company_property_settings`
- `property_staff_assignments`
- `inspection_templates`
- `inspection_template_sections`
- `inspection_template_items`
- `inspection_item_snapshots`
- `inspections`
- `inspection_results`
- `inspection_result_changes`
- `media_assets`
- `meter_readings`
- `inspection_report_versions`
- `issues`
- `owner_requests`
- `vendors`
- `vendor_capabilities`
- `contractor_profiles`
- `vendor_documents`
- `quotes`
- `quote_versions`
- `quote_owner_shares`
- `approval_requests`
- `approval_snapshots`
- `approval_events`
- `approval_comment_reviews`
- `maintenance_jobs`
- `job_reschedule_requests`
- `job_cancellation_requests`
- `assets`
- `preventive_maintenance_rules`
- `preventive_maintenance_occurrences`
- `documents`
- `document_versions`
- `property_emergency_limit_versions`
- `emergency_actions`
- `job_feedback`
- `notifications`
- `audit_log`
- `plans`
- `subscriptions`

This list fixes the architectural domain boundaries; it does not require every table to be implemented in the first vertical slice.

## 7. Security Schema and Helper Functions

Create a non-exposed `security` schema for authorization helpers. It must not be exposed through the client-facing API schemas. The initial helper interface is:

```sql
security.current_profile_id()
security.is_company_member(company_id)
security.company_role(company_id)
security.has_company_role(company_id, allowed_roles[])
security.is_property_owner(property_id)
security.company_has_property_access(company_id, property_id)
security.company_has_property_scope(company_id, property_id, required_scope)
security.is_assigned_to_property(company_id, property_id)
security.is_assigned_to_inspection(inspection_id)
security.can_view_operational_record(company_id, property_id)
security.can_manage_operational_record(company_id, property_id)
security.owner_can_view_report(report_version_id)
security.owner_can_view_quote_version(quote_version_id)
security.owner_can_view_document(document_id)
```

Exact PostgreSQL parameter types and return types are defined in migrations, using UUID identifiers, the relevant enum types, and boolean results except for role lookup. Helpers must return false or null when identity or relationships are absent; they must not broaden access on missing data.

Use `SECURITY DEFINER` only where required to evaluate authorization without RLS recursion or to perform a controlled privileged transition. Every security-definer function must:

- have a tightly controlled, explicit `search_path`
- schema-qualify referenced objects
- validate the caller and all identifiers inside the function
- expose `EXECUTE` only to the minimum required roles
- revoke default/public execution where applicable
- avoid accepting caller-supplied facts that can be derived securely from the database

Helper functions centralize predicates but do not replace table-specific policies. Policies must still distinguish read, create, update, delete, assignment, owner visibility, immutable state, and responsible-company boundaries.

## 8. RLS and Database Enforcement

RLS is enabled and forced where appropriate from the beginning, not added after feature implementation. Every client-accessible table receives explicit policies; absence of an applicable policy means denial.

Protection of immutable and sensitive records combines:

- RLS `USING` and `WITH CHECK` predicates
- table and column privileges
- constraints and triggers for invariants and immutability
- controlled transactional functions for sensitive state changes

RLS alone is not the only control for published reports, historical/shared quote versions, approval records, or audit records. Database constraints and triggers must protect invariants even from application defects or privileged application paths, while narrowly controlled administrative/database maintenance remains an explicit operational concern.

`READ_ONLY` cannot mutate. `COORDINATOR` cannot publish a final report. Administrators remain subject to immutability and cross-tenant boundaries.

## 9. Storage Authorization

Operational files use private Supabase Storage buckets with RLS on `storage.objects`. Likely buckets are:

- `inspection-media`
- `reports`
- `documents`
- `vendor-documents`
- `job-media`
- `company-branding`

The standard operational object-key shape is:

```text
/{company_id}/{property_id}/{record_type}/{record_id}/{filename}
```

The path is organizational metadata, not authorization. Storage policies must parse and validate expected path components and join them to authoritative database records. A caller must satisfy the same tenant, property, responsible-company, assignment, state, and owner-visibility rules that govern the associated database row.

Uploads and mutations must verify that the target record exists and is manageable by the caller. Owner reads must be limited to objects linked through `media_assets` or the relevant document/report record and explicitly permitted for owner viewing. Guessing or substituting path UUIDs must fail. Company branding is tenant-scoped and must not provide a route to operational property data.

## 10. First Production Vertical Slice

The first real vertical slice is limited to:

```text
JTC ADMIN
-> Property
-> Owner
-> Inspection
-> Inspection Results
-> Photos
-> Meter Readings
-> Draft Report
-> FINAL Published Report
-> Owner Portal
```

The success case is:

1. Jesmond signs in as a JTC `ADMIN`.
2. He opens Pender Gardens Apartment 1042.
3. He creates and completes an inspection.
4. He records electricity and water readings.
5. He uploads inspection photos or evidence.
6. He generates and reviews a `DRAFT` report.
7. He publishes a `FINAL` report through the controlled publish transaction.
8. Andrea signs in as the owner.
9. Andrea sees the published owner-facing report and permitted photos only.
10. Andrea cannot see drafts, internal fields, or company-only records.

The slice establishes a production security foundation but does not implement quotes, approvals, maintenance jobs, subscriptions, automation, or the remaining domain tables beyond what is necessary to establish referenced types or security contracts.

## 11. Migration Sequence

The first migrations are ordered as follows:

1. `001` extensions and enums
2. `002` profiles and identity
3. `003` companies, branding, and memberships
4. `004` security schema and helper functions
5. `005` property core
6. `006` property RLS and adversarial tests
7. `007` inspection template system
8. `008` inspection runtime and meter readings
9. `009` media and Storage RLS
10. `010` report versioning and publish transaction
11. `011` owner portal read policies
12. `012` audit foundation

Dependencies may be introduced only in the earliest migration that genuinely needs them. Migration numbering and responsibility must remain stable; later migrations must not silently redefine earlier security boundaries.

## 12. Mandatory Adversarial Verification

Automated database tests must prove at least the following cases:

- JTC `ADMIN` sees a JTC property.
- JTC `ADMIN` cannot see an unrelated company's property.
- JTC `ADMIN` cannot discover unrelated properties through a known owner.
- An owner sees their own property.
- An owner cannot see another owner's property.
- An owner sees a published `FINAL` report.
- An owner cannot see a `DRAFT` report.
- An inspector sees only an assigned inspection.
- A coordinator cannot publish a `FINAL` report.
- `READ_ONLY` cannot mutate.
- An `ADMIN` cannot modify a `FINAL` report.
- An `ADMIN` cannot modify an approval snapshot.
- A secondary company accesses only its authorized service scope.
- A secondary company cannot see the primary company's internal records.
- Malicious property or company UUID substitution fails.

Tests must execute as representative authenticated users, not solely as a database owner or service role. Positive tests are insufficient without paired denial and cross-tenant substitution tests. Storage policies require equivalent database-backed access tests.

## 13. Security Acceptance Criteria

RLS Architecture V1 is correctly implemented only when:

- all client-accessible data and private storage objects are default-deny
- company access requires membership plus the applicable property relationship, scope, role, responsibility, and assignment checks
- owner access is derived only from `property_owners` and explicit owner-visible state
- cross-company and cross-owner enumeration is prevented
- one active primary management company per property is database-enforced
- operational records preserve responsible-company and property boundaries
- published reports and other locked historical records are immutable through layered controls
- sensitive transitions are transactional and audited
- privileged credentials remain server-only
- all mandatory adversarial tests pass
- the vertical-slice owner can see only the final owner-facing result and permitted media

## 14. Explicit Non-Goals

This specification does not:

- redesign the frozen visual product
- treat Stitch HTML as production code
- add product features or automation
- authorize implementation beyond the first vertical slice
- define UI micro-interactions, copy, or styling
- grant access based on identifiers, URL paths, or frontend visibility
- make JTC-specific shortcuts part of the shared architecture
- expose the `security` schema or service-role credentials to clients

Build the first secured workflow before adding automation. Any product micro-decision not required to implement this security contract remains outside scope and requires separate approval.
