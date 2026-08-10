# JTC First Vertical Slice Implementation Plan

Status: APPROVED
Execution style: TDD, small commits, stop on genuine blockers.
Stack: Next.js, React, TypeScript, Tailwind CSS, Supabase PostgreSQL/Auth/Storage, PostgreSQL RLS, Vercel.

## Scope

Implement only:

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

Do not implement unrelated later modules unless required as a minimal dependency.

Primary frozen Stitch references:
- `docs/stitch-reference/home-dashboard.html`
- `docs/stitch-reference/properties-list.html`
- `docs/stitch-reference/property-detail.html`
- `docs/stitch-reference/inspection-checklist.html`
- `docs/stitch-reference/inspection-review.html`
- `docs/stitch-reference/owner-portal.html`

Stitch controls visuals only.
RLS/spec controls security and permissions.
Database architecture controls data structure/workflow.

## Development rules

- Do not work directly on `main`.
- Use isolated worktree/feature branch when git metadata is available.
- Use TDD.
- Keep commits small.
- Run relevant tests before each commit.
- Do not commit secrets or `.env`.
- Do not expose Supabase service role to browser code.
- Do not weaken tests to pass.
- Stop and ask if implementation requires a new business rule.
- Do not redesign frozen Stitch UI.
- Demo records in Stitch are not production data.

## Test layers

- pgTAP for database and RLS behavior
- Vitest for application/domain logic
- Playwright for end-to-end workflow where specified

## Migration sequence

1. `001_extensions_enums.sql`
2. `002_profiles_identity.sql`
3. `003_companies_branding_memberships.sql`
4. `004_security_helpers.sql`
5. `005_property_core.sql`
6. `006_property_rls.sql`
7. `007_inspection_template_system.sql`
8. `008_inspection_runtime_meters.sql`
9. `009_media_storage_rls.sql`
10. `010_report_versioning_publish.sql`
11. `011_owner_portal_read.sql`
12. `012_audit_foundation.sql`

Do not create approvals tables in this slice.
The approval-snapshot immutability test is deferred to the future approvals slice.

# Tasks

## Task 1 - Repository and application scaffold

Create the production application scaffold required by the approved stack.

Expected areas:
- Next.js App Router
- TypeScript
- Tailwind CSS
- Supabase client/server helpers
- test configuration
- environment variable example without secrets

Tests:
- basic Vitest smoke test
- lint/typecheck/build commands established

Commit boundary:
`chore: scaffold JTC property platform`

## Task 2 - Extensions and enums

Create migration `001_extensions_enums.sql`.

Include only enums/types needed by the first slice and approved architecture, including:
- company role
- company/property relationship status/type/scope as required
- inspection severity PASS/ATTENTION/URGENT
- operational action MONITOR/INCLUDED_IN_SERVICE/OWNER_APPROVAL_REQUIRED
- inspection lifecycle statuses required by first slice
- report status DRAFT/FINAL/SUPERSEDED

Write pgTAP tests proving enum presence/allowed values.

Commit boundary:
`feat(db): add core extensions and enums`

## Task 3 - Global profiles identity

Create migration `002_profiles_identity.sql`.

Implement global `profiles` identity linked to Supabase Auth.

Rules:
- profile is global
- not company-owned
- suitable for both staff and owners

Tests:
- profile creation/access invariants
- no tenant ownership column that makes owner company-scoped

Commit boundary:
`feat(db): add global profile identity`

## Task 4 - Companies, branding, memberships

Create migration `003_companies_branding_memberships.sql`.

Implement:
- companies
- company_branding
- company_memberships

Membership supports:
- ADMIN
- MANAGER
- INSPECTOR
- COORDINATOR
- READ_ONLY
- active/inactive lifecycle

Tests:
- active membership lookup behavior
- duplicate/invalid membership constraints

Commit boundary:
`feat(db): add companies and memberships`

## Task 5 - Security helper foundation

Create migration `004_security_helpers.sql`.

Implement reusable security helpers for:
- current profile
- active membership
- role checks
- property ownership
- company/property access
- assignment checks as required

Requirements:
- least privilege
- SECURITY DEFINER only where necessary
- fixed search_path
- controlled EXECUTE

Write pgTAP tests for helper behavior.

Commit boundary:
`feat(security): add RLS helper functions`

## Task 6 - Property core and ownership relationships

Create migration `005_property_core.sql`.

Implement at minimum:
- properties
- property_owners
- property_company_relationships
- company_property_settings as required
- property_staff_assignments if required by inspector bounding

Rules:
- owner is global
- one ACTIVE PRIMARY management company per property
- service relationships are bounded by explicit scope
- company cannot discover owner's unrelated properties

Tests:
- primary uniqueness
- owner relationship behavior
- service-scope constraints

Commit boundary:
`feat(db): add property ownership and management relationships`

## Task 7 - Property RLS and adversarial tests

Create migration `006_property_rls.sql`.

Implement default-deny RLS for first-slice property tables.

Mandatory pgTAP/adversarial tests:
- tenant A cannot read tenant B property
- company cannot discover unrelated owner properties
- owner can read own property
- owner cannot read another owner's property
- READ_ONLY cannot mutate
- hostile UUID substitution fails
- service relationship access does not broaden beyond scope

Commit boundary:
`feat(security): enforce property tenant isolation`

## Task 8 - Inspection template system

Create migration `007_inspection_template_system.sql`.

Implement:
- inspection_templates
- inspection_template_sections
- inspection_template_items
- inspection template snapshot/version behavior required to make completed inspections historically stable

Use the approved checklist structure without hard-coding Stitch demo data into schema.

Tests:
- template ordering
- section/item ownership
- snapshot immutability/stability where applicable

Commit boundary:
`feat(db): add inspection template system`

## Task 9 - Inspection runtime, results and meters

Create migration `008_inspection_runtime_meters.sql`.

Implement:
- inspections
- inspection_results
- inspection_changes as required
- meter_readings

Rules:
- result severity PASS/ATTENTION/URGENT
- operational action remains separate
- inspector assignment-bounded access where used
- meter readings linked to correct property/inspection/company
- company_id + property_id explicit on operational records where appropriate

Tests:
- authorized create/update
- cross-tenant denial
- assignment denial
- invalid severity denied
- hostile IDs denied

Commit boundary:
`feat(db): add inspection runtime and meter readings`

## Task 10 - Media and storage RLS

Create migration `009_media_storage_rls.sql`.

Implement:
- media_assets metadata
- private inspection media bucket/policies
- owner visibility semantics required by published report

Suggested path:
`/{company_id}/{property_id}/{record_type}/{record_id}/{filename}`

Rules:
- path is not authorization
- DB parent governs authorization
- draft/internal inspection media not automatically owner-visible
- service role remains server-only

Tests:
- tenant isolation
- owner cannot access non-owner-visible media
- owner can access media exposed by published owner-facing report
- hostile object path/UUID attempts fail

Commit boundary:
`feat(storage): secure inspection media`

## Task 11 - Report versioning and publish transaction

Create migration `010_report_versioning_publish.sql`.

Implement:
- inspection_report_versions
- DRAFT / FINAL / SUPERSEDED
- controlled publish function/RPC

Rules:
- DRAFT editable by authorized manager/admin
- FINAL immutable
- publishing supersedes prior FINAL where approved behavior requires it
- publication is transactional
- owner sees FINAL only
- publication records audit-relevant metadata

Tests:
- draft editable
- final cannot be updated/deleted by normal tenant users
- owner cannot see draft
- owner can see final
- cross-tenant final inaccessible
- hostile UUID fails

Commit boundary:
`feat(reports): add immutable report publishing`

## Task 12 - Owner portal read model/RLS

Create migration `011_owner_portal_read.sql` and application read queries.

Implement owner-facing read path for:
- owned properties
- FINAL published inspection reports
- explicitly owner-visible report media

Do not expose:
- internal notes
- company-internal records
- drafts
- unrelated properties
- unrelated companies

Tests:
- owner own property only
- owner final only
- owner-visible media only
- no portfolio leakage

Commit boundary:
`feat(owner): add secure owner portal reads`

## Task 13 - Audit foundation

Create migration `012_audit_foundation.sql`.

Implement append-only `audit_log`.

Audit important first-slice actions such as:
- inspection lifecycle changes
- report publication
- other trust-boundary actions required by the slice

Rules:
- normal users cannot UPDATE/DELETE
- no unrestricted client INSERT
- use controlled trigger/function/server operation

Tests:
- append succeeds through controlled path
- normal mutation denied

Commit boundary:
`feat(audit): add append-only audit foundation`

## Task 14 - First-slice UI and end-to-end workflow

Translate the frozen Stitch references into reusable Next.js/React/Tailwind components.

Implement primarily:
- home dashboard
- properties list
- property detail
- inspection checklist
- inspection review
- owner portal

Do not paste static Stitch HTML as production application pages.

Bind UI to Supabase-backed data.

Target scenario:
1. JTC admin signs in.
2. Opens Pender Gardens Apartment 1042.
3. Sees Andrea as owner.
4. Starts inspection.
5. Records checklist results.
6. Records water/electricity meter readings.
7. Adds photos.
8. Saves draft.
9. Reviews internally.
10. Publishes FINAL report.
11. Andrea signs in.
12. Andrea sees her property and FINAL report/photos only.
13. Andrea cannot access draft/internal/unrelated data.

Playwright tests:
- happy path above
- owner draft denial
- unrelated property denial
- hostile URL/UUID attempt denial

Visual implementation:
- faithfully follow frozen Stitch
- preserve navy `#1F3461`
- preserve gold `#C9A84C`
- preserve layout, spacing, hierarchy, cards, status treatments, mobile-first navigation/actions
- use real data, not demo records

Commit boundaries may be split into small UI/domain commits rather than one large commit.

# Completion verification

Before declaring the slice complete:
- run database tests
- run Vitest
- run Playwright
- run typecheck
- run lint
- run production build
- inspect git diff/status
- verify no secrets
- verify Stitch references remain unchanged
- verify final report immutability
- verify owner cannot see draft or unrelated data
- verify tenant isolation adversarial tests pass

Then use the Superpowers finishing-development-branch workflow.

# Explicitly deferred

Do not implement in this slice:
- quote comparison workflow
- owner approval workflow
- approval snapshots
- maintenance-job creation/execution
- preventive maintenance
- asset lifecycle
- document version management
- staff management UI
- white-label settings UI
- subscription/billing
- automation
- AI functionality
