# JTC First Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the secured JTC inspection-to-published-report workflow in which a JTC administrator completes an inspection and Andrea can read only the final owner-visible report and permitted media.

**Architecture:** Build a Next.js App Router application over a locally reproducible Supabase project. PostgreSQL RLS and narrowly controlled transactional functions are the authorization boundary; server-side application code calls those contracts without service-role credentials in the browser. Database tests establish every permission before UI routes consume it.

**Tech Stack:** Next.js, React, TypeScript, Tailwind CSS, Supabase PostgreSQL/Auth/Storage, PostgreSQL RLS, pgTAP via Supabase CLI, Vitest, Playwright, Vercel

## Global Constraints

- The approved design is `docs/superpowers/specs/2026-08-09-rls-architecture-v1-design.md` and is authoritative.
- The visual design is frozen; supplied Stitch HTML is a visual reference only and must never be copied in as production code.
- JTC Property Services is seed data, never a hard-coded authorization exception.
- Authorization is default-deny and identifiers never confer access.
- `OWNER` is not a company role.
- Operational records include `company_id` and `property_id` when required by the approved design.
- Owner visibility is enforced in PostgreSQL and Storage policies, not frontend filtering.
- Service-role or privileged credentials must never enter `NEXT_PUBLIC_*`, client components, browser bundles, logs, or fixtures.
- `FINAL` and `SUPERSEDED` reports, shared/historical quote versions, approval snapshots/events, and audit records use layered immutability controls.
- Do not implement quotes, approvals, maintenance jobs, billing, automation, or other later product workflows in this slice.
- The locked requirement that an `ADMIN` cannot modify `approval_snapshots` remains mandatory, but its executable adversarial test is deferred until the future approvals slice creates the approvals schema and migration. Migrations `001`–`012` must not create approval tables or invent approval workflow behavior.
- No package installation may occur until Jesmond approves the exact install command, per repository instructions.
- UI implementation that depends on the frozen visual treatment must wait until the final Stitch HTML references are supplied; security, data, route, and test work does not depend on them.

## File Map

### Project and test harness

- `package.json` — scripts and JavaScript dependencies.
- `next.config.ts`, `tsconfig.json`, `postcss.config.mjs`, `eslint.config.mjs` — application toolchain.
- `vitest.config.ts`, `playwright.config.ts` — unit and browser test configuration.
- `.env.example` — public local Supabase variable names only.
- `src/lib/supabase/browser.ts` — browser client using publishable/anon credentials.
- `src/lib/supabase/server.ts` — request-scoped server client using cookies.
- `src/lib/supabase/database.types.ts` — generated database types; never hand-edited.
- `src/lib/auth/require-profile.ts` — authenticated profile lookup for server routes.
- `tests/unit/security/no-service-role-in-client.test.ts` — browser credential regression test.
- `tests/e2e/jtc-inspection-report.spec.ts` — administrator-to-owner acceptance flow.

### Database migrations

- `supabase/migrations/001_extensions_enums.sql`
- `supabase/migrations/002_profiles_identity.sql`
- `supabase/migrations/003_companies_branding_memberships.sql`
- `supabase/migrations/004_security_schema_helpers.sql`
- `supabase/migrations/005_property_core.sql`
- `supabase/migrations/006_property_rls.sql`
- `supabase/migrations/007_inspection_template_system.sql`
- `supabase/migrations/008_inspection_runtime_meter_readings.sql`
- `supabase/migrations/009_media_storage_rls.sql`
- `supabase/migrations/010_report_versioning_publish.sql`
- `supabase/migrations/011_owner_portal_read_policies.sql`
- `supabase/migrations/012_audit_foundation.sql`

Each migration owns only the responsibility named above. Later migrations may add policies or audit hooks to earlier tables but must not weaken an earlier invariant.

### Database tests and fixtures

- `supabase/tests/000_test_helpers.sql` — authenticated-role switching, JWT claims, and denial assertions.
- `supabase/tests/001_identity_company_test.sql`
- `supabase/tests/002_property_rls_test.sql`
- `supabase/tests/003_inspection_rls_test.sql`
- `supabase/tests/004_storage_rls_test.sql`
- `supabase/tests/005_report_publish_test.sql`
- `supabase/tests/006_owner_portal_test.sql`
- `supabase/tests/007_immutability_audit_test.sql`
- `supabase/seed.sql` — deterministic local identities and the JTC/Pender Gardens acceptance dataset.

### Application boundaries

- `src/app/(auth)/login/page.tsx`, `src/app/auth/callback/route.ts` — Supabase Auth entry and callback.
- `src/app/(company)/properties/page.tsx` — company-authorized property list.
- `src/app/(company)/properties/[propertyId]/page.tsx` — property summary.
- `src/app/(company)/properties/[propertyId]/inspections/new/page.tsx` — inspection creation.
- `src/app/(company)/inspections/[inspectionId]/page.tsx` — results, readings, and evidence workflow.
- `src/app/(company)/inspections/[inspectionId]/report/page.tsx` — draft review and publish action.
- `src/app/(owner)/owner/reports/page.tsx` — owner-visible final report list.
- `src/app/(owner)/owner/reports/[reportVersionId]/page.tsx` — owner-facing report and permitted media.
- `src/app/actions/inspections.ts`, `src/app/actions/reports.ts` — typed server actions calling RLS-protected tables/RPCs.
- `src/features/inspections/schemas.ts`, `src/features/reports/schemas.ts` — input validation.
- `src/features/inspections/components/*`, `src/features/reports/components/*` — production React components recreated from supplied visual references.

---

### Task 1: Reproducible Next.js and Supabase Baseline

**Files:**
- Create: `package.json`
- Create: `next.config.ts`
- Create: `tsconfig.json`
- Create: `postcss.config.mjs`
- Create: `eslint.config.mjs`
- Create: `vitest.config.ts`
- Create: `playwright.config.ts`
- Create: `.gitignore`
- Create: `.env.example`
- Create: `src/app/layout.tsx`
- Create: `src/app/page.tsx`
- Create: `src/app/globals.css`
- Create: `src/lib/supabase/browser.ts`
- Create: `src/lib/supabase/server.ts`
- Create: `tests/unit/security/no-service-role-in-client.test.ts`
- Create: `supabase/config.toml`

**Interfaces:**
- Produces: `createBrowserSupabaseClient(): SupabaseClient<Database>` and `createServerSupabaseClient(): Promise<SupabaseClient<Database>>`.
- Produces: scripts `lint`, `typecheck`, `test:unit`, `test:db`, `test:e2e`, and `build`.

- [ ] **Step 1: Record and approve the scaffold/install command**

Run only after Jesmond approves package installation:

```powershell
npx create-next-app@latest . --ts --tailwind --eslint --app --src-dir --import-alias "@/*" --use-npm
npm install @supabase/ssr @supabase/supabase-js zod
npm install --save-dev vitest @vitejs/plugin-react jsdom @testing-library/react @testing-library/jest-dom @playwright/test
```

Expected: a Next.js App Router scaffold with a lockfile; no second application directory.

- [ ] **Step 2: Write the failing client-secret test**

```ts
// tests/unit/security/no-service-role-in-client.test.ts
import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { extname, join } from "node:path";

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return sourceFiles(path);
    return [".ts", ".tsx"].includes(extname(path)) ? [path] : [];
  });
}

describe("client credential boundary", () => {
  it("does not reference privileged Supabase variables in browser code", () => {
    const files = sourceFiles("src");
    const clientFiles = files.filter((file) =>
      readFileSync(file, "utf8").includes('"use client"'),
    );
    for (const file of clientFiles) {
      expect(readFileSync(file, "utf8")).not.toMatch(/SERVICE_ROLE|SUPABASE_SECRET/i);
    }
  });
});
```

- [ ] **Step 3: Run the focused test and confirm red**

Run: `npm run test:unit -- tests/unit/security/no-service-role-in-client.test.ts`

Expected: FAIL until the Vitest script/config and source boundary exist.

- [ ] **Step 4: Configure the minimal clients and scripts**

`.env.example` contains only:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

The browser client reads only these names. The server client uses `@supabase/ssr` with request cookies; it does not use service role.

- [ ] **Step 5: Verify baseline**

Run:

```powershell
npm run test:unit -- tests/unit/security/no-service-role-in-client.test.ts
npm run lint
npm run typecheck
npm run build
supabase start
supabase status
```

Expected: all npm checks pass and local Supabase reports healthy services.

- [ ] **Step 6: Commit baseline**

```powershell
git add package.json package-lock.json next.config.ts tsconfig.json postcss.config.mjs eslint.config.mjs vitest.config.ts playwright.config.ts .gitignore .env.example src tests/unit/security/no-service-role-in-client.test.ts supabase/config.toml
git commit -m "chore: scaffold application and local Supabase"
```

### Task 2: Extensions, Enums, Profiles, and Company Memberships

**Files:**
- Create: `supabase/migrations/001_extensions_enums.sql`
- Create: `supabase/migrations/002_profiles_identity.sql`
- Create: `supabase/migrations/003_companies_branding_memberships.sql`
- Create: `supabase/tests/000_test_helpers.sql`
- Create: `supabase/tests/001_identity_company_test.sql`

**Interfaces:**
- Produces enums `company_role`, `property_company_relationship_type`, `property_service_scope`, `inspection_severity`, `inspection_action`, `inspection_status`, `report_status`, and `media_visibility` with exactly the locked values needed by this slice.
- Produces tables `public.profiles`, `public.companies`, `public.company_branding`, `public.company_memberships`.
- Produces test helpers `tests.authenticate_as(profile_id uuid)` and `tests.clear_authentication()` that set transaction-local request claims and role.

- [ ] **Step 1: Write failing identity and tenant tests**

The pgTAP file must assert:

```sql
select has_table('public', 'profiles');
select has_table('public', 'companies');
select has_table('public', 'company_memberships');
select col_is_unique('public', 'profiles', 'auth_user_id');
select throws_ok(
  $$ insert into public.company_memberships (company_id, profile_id, role)
     values (tests.uuid('jtc'), tests.uuid('jesmond'), 'OWNER') $$,
  '22P02'
);
```

Also assert that a duplicate active membership is rejected and enum values match the approved specification.

- [ ] **Step 2: Run the database test and confirm red**

Run: `supabase db reset; supabase test db supabase/tests/001_identity_company_test.sql`

Expected: FAIL because migrations `001`–`003` do not exist.

- [ ] **Step 3: Implement minimal schemas and constraints**

Use `gen_random_uuid()` identifiers, `timestamptz` audit timestamps, foreign keys to `auth.users` through `profiles.auth_user_id`, and a partial unique index for one active membership per company/profile. Do not create owner-as-company membership logic.

- [ ] **Step 4: Verify migrations from empty state**

Run: `supabase db reset; supabase test db supabase/tests/001_identity_company_test.sql`

Expected: PASS.

- [ ] **Step 5: Commit identity and company foundation**

```powershell
git add supabase/migrations/001_extensions_enums.sql supabase/migrations/002_profiles_identity.sql supabase/migrations/003_companies_branding_memberships.sql supabase/tests/000_test_helpers.sql supabase/tests/001_identity_company_test.sql
git commit -m "feat(db): add identity and company membership foundation"
```

### Task 3: Security Schema Helper Contract

**Files:**
- Create: `supabase/migrations/004_security_schema_helpers.sql`
- Modify: `supabase/tests/001_identity_company_test.sql`

**Interfaces:**
- Produces the exact `security.*` helper names listed in the approved specification.
- `security.current_profile_id()` returns `uuid`; `security.company_role(uuid)` returns `company_role`; predicate helpers return `boolean` and coalesce absence to `false`.

- [ ] **Step 1: Add failing helper tests**

```sql
select has_function('security', 'current_profile_id', array[]::text[]);
select has_function('security', 'is_company_member', array['uuid']);
select has_function('security', 'has_company_role', array['uuid', 'company_role[]']);
select tests.authenticate_as(tests.uuid('jesmond'));
select is(security.current_profile_id(), tests.uuid('jesmond'));
select ok(security.is_company_member(tests.uuid('jtc')));
select tests.clear_authentication();
select is(security.is_company_member(tests.uuid('jtc')), false);
```

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/001_identity_company_test.sql`

Expected: FAIL with missing `security` functions.

- [ ] **Step 3: Implement non-exposed helpers**

Create `security`, revoke schema access from `public` and `anon`, grant only required usage/execute to `authenticated`, revoke public function execution, schema-qualify every relation, and set each security-definer function to `search_path = pg_catalog, public, security`.

Property/report/document helpers whose tables arrive later must be introduced as signatures in their owning later migration, not as broken forward references in `004`; `004` owns identity/company helpers.

- [ ] **Step 4: Verify helper behavior and privileges**

Run: `supabase db reset; supabase test db supabase/tests/001_identity_company_test.sql`

Expected: PASS, including unauthenticated false/null behavior.

- [ ] **Step 5: Commit security helpers**

```powershell
git add supabase/migrations/004_security_schema_helpers.sql supabase/tests/001_identity_company_test.sql
git commit -m "feat(db): add security authorization helpers"
```

### Task 4: Property Core, Relationships, and Adversarial RLS

**Files:**
- Create: `supabase/migrations/005_property_core.sql`
- Create: `supabase/migrations/006_property_rls.sql`
- Create: `supabase/tests/002_property_rls_test.sql`

**Interfaces:**
- Produces `properties`, `property_owners`, `property_company_relationships`, `company_property_settings`, and `property_staff_assignments`.
- Produces `security.is_property_owner(uuid)`, `security.company_has_property_access(uuid, uuid)`, `security.company_has_property_scope(uuid, uuid, property_service_scope)`, `security.is_assigned_to_property(uuid, uuid)`, `security.can_view_operational_record(uuid, uuid)`, and `security.can_manage_operational_record(uuid, uuid)`.

- [ ] **Step 1: Write failing adversarial property tests**

Seed two companies, three properties, Jesmond as JTC `ADMIN`, Andrea as owner of Pender Gardens 1042 plus a property managed by the unrelated company, a second owner, a secondary inspection company, a `READ_ONLY` member, and assigned/unassigned inspectors. Assert with authenticated `SELECT`/`INSERT` statements:

```sql
select results_eq(
  $$ select id from public.properties order by id $$,
  $$ values (tests.uuid('pender-1042')) $$,
  'JTC admin sees only the JTC property, not Andrea unrelated property'
);
select throws_ok(
  $$ update public.properties set display_name = 'attack'
     where id = tests.uuid('other-company-property') $$,
  '42501'
);
```

Include owner-own/owner-other, known-owner portfolio non-discovery, one-active-primary concurrency-safe unique constraint, secondary scope, `READ_ONLY` mutation denial, and malicious company/property UUID substitution cases.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/002_property_rls_test.sql`

Expected: FAIL with missing property tables.

- [ ] **Step 3: Implement property constraints and RLS**

Use a partial unique index on `property_company_relationships(property_id) where relationship_type = 'PRIMARY' and ended_at is null`. Policies require active membership plus active property relationship and scope; owner policies join only the current profile to `property_owners` for the target property. Force RLS on the client-facing tables.

- [ ] **Step 4: Verify all property attacks**

Run: `supabase db reset; supabase test db supabase/tests/002_property_rls_test.sql`

Expected: PASS with every positive assertion paired to cross-tenant denial.

- [ ] **Step 5: Commit property boundary**

```powershell
git add supabase/migrations/005_property_core.sql supabase/migrations/006_property_rls.sql supabase/tests/002_property_rls_test.sql
git commit -m "feat(db): enforce property tenant boundaries"
```

### Task 5: Inspection Template Snapshots

**Files:**
- Create: `supabase/migrations/007_inspection_template_system.sql`
- Create: `supabase/tests/003_inspection_rls_test.sql`

**Interfaces:**
- Produces `inspection_templates`, `inspection_template_sections`, `inspection_template_items`, and immutable `inspection_item_snapshots`.
- Template records are responsible-company scoped; snapshot content is copied into an inspection transaction and is not changed by later template edits.

- [ ] **Step 1: Write failing template isolation tests**

Test JTC template visibility, unrelated-company denial, secondary inspection-scope read behavior, and snapshot immutability after creation.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/003_inspection_rls_test.sql`

Expected: FAIL with missing inspection template relations.

- [ ] **Step 3: Implement template schema, copy function, and RLS**

Create `public.create_inspection_from_template(company_id uuid, property_id uuid, template_id uuid)` as a controlled function that validates management access and copies ordered item labels/instructions into snapshots. Revoke public execute and grant authenticated execute only.

- [ ] **Step 4: Verify**

Run: `supabase db reset; supabase test db supabase/tests/003_inspection_rls_test.sql`

Expected: template/snapshot assertions PASS.

- [ ] **Step 5: Commit templates**

```powershell
git add supabase/migrations/007_inspection_template_system.sql supabase/tests/003_inspection_rls_test.sql
git commit -m "feat(db): add tenant-scoped inspection templates"
```

### Task 6: Inspection Runtime, Results, Changes, and Meter Readings

**Files:**
- Create: `supabase/migrations/008_inspection_runtime_meter_readings.sql`
- Modify: `supabase/tests/003_inspection_rls_test.sql`

**Interfaces:**
- Produces `inspections`, `inspection_results`, `inspection_result_changes`, and `meter_readings` with explicit `company_id` and `property_id`.
- Produces `security.is_assigned_to_inspection(uuid)` and controlled functions `complete_inspection(uuid)` and `record_inspection_result(...)`.

- [ ] **Step 1: Add failing runtime authorization tests**

Assert that `inspection_severity` and `inspection_action` are separate required values; JTC admin can create/complete; assigned inspector can read and record only the assigned inspection; unassigned inspector cannot discover it; coordinator and read-only users cannot complete it; UUID substitution across company/property/inspection fails; change rows preserve before/after values.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/003_inspection_rls_test.sql`

Expected: FAIL with missing runtime tables/functions.

- [ ] **Step 3: Implement minimal runtime and controlled transitions**

All child rows must carry foreign keys that prove their `company_id` and `property_id` match the parent inspection. Result writes append `inspection_result_changes`; completion rejects missing required results or readings and stamps `completed_at` atomically.

- [ ] **Step 4: Verify runtime attacks**

Run: `supabase db reset; supabase test db supabase/tests/003_inspection_rls_test.sql`

Expected: PASS.

- [ ] **Step 5: Commit runtime**

```powershell
git add supabase/migrations/008_inspection_runtime_meter_readings.sql supabase/tests/003_inspection_rls_test.sql
git commit -m "feat(db): add secured inspection runtime"
```

### Task 7: Private Inspection Media and Storage RLS

**Files:**
- Create: `supabase/migrations/009_media_storage_rls.sql`
- Create: `supabase/tests/004_storage_rls_test.sql`

**Interfaces:**
- Produces `media_assets` and private bucket `inspection-media`.
- Object names follow `{company_id}/{property_id}/inspection/{inspection_id}/{filename}`; `media_assets.owner_visible` remains authoritative.

- [ ] **Step 1: Write failing storage attacks**

Insert `storage.objects` as each representative user and assert: authorized admin/assigned inspector upload succeeds; unrelated company, unassigned inspector, owner upload, and substituted path UUIDs fail; owner reads only a linked object whose media row is owner-visible and whose report is final.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/004_storage_rls_test.sql`

Expected: FAIL because bucket, metadata, and policies are absent.

- [ ] **Step 3: Implement metadata constraints and object policies**

Policies parse path segments only to locate authoritative rows, then validate `media_assets`, its parent inspection, responsible company, property relationship, assignment, and owner-visible final-report link. Filename/path equality alone never returns true.

- [ ] **Step 4: Verify database-backed storage authorization**

Run: `supabase db reset; supabase test db supabase/tests/004_storage_rls_test.sql`

Expected: PASS.

- [ ] **Step 5: Commit storage security**

```powershell
git add supabase/migrations/009_media_storage_rls.sql supabase/tests/004_storage_rls_test.sql
git commit -m "feat(db): secure inspection media storage"
```

### Task 8: Versioned Reports and Controlled Publish Transaction

**Files:**
- Create: `supabase/migrations/010_report_versioning_publish.sql`
- Create: `supabase/tests/005_report_publish_test.sql`

**Interfaces:**
- Produces `inspection_report_versions` with `DRAFT`, `FINAL`, `SUPERSEDED` states and monotonically increasing per-inspection version numbers.
- Produces `public.create_draft_inspection_report(inspection_id uuid)` and `public.publish_inspection_report(report_version_id uuid)`.
- Publish returns the final report-version UUID and writes no partial state on failure.

- [ ] **Step 1: Write failing report state-machine tests**

Assert admin draft creation; owner draft denial; coordinator publish denial; read-only denial; final publish success; prior final superseded on republish; admin update/delete of final and superseded rows denied; direct browser-role insertion of `FINAL` denied; company/property substitution denied; failed publish leaves no partial transition.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/005_report_publish_test.sql`

Expected: FAIL with missing report relation/functions.

- [ ] **Step 3: Implement report versioning and immutability**

Use a uniqueness constraint on `(inspection_id, version_number)`, a trigger rejecting update/delete of final or superseded versions, restricted table privileges, and a security-definer publish function with explicit search path. Lock the inspection/report rows during publication, revalidate caller role and responsible-company/property access, set owner-facing content, and transition any previous final to superseded in one transaction.

- [ ] **Step 4: Verify publish transaction**

Run: `supabase db reset; supabase test db supabase/tests/005_report_publish_test.sql`

Expected: PASS.

- [ ] **Step 5: Commit reports**

```powershell
git add supabase/migrations/010_report_versioning_publish.sql supabase/tests/005_report_publish_test.sql
git commit -m "feat(db): add immutable report publication"
```

### Task 9: Owner Portal Read Policies

**Files:**
- Create: `supabase/migrations/011_owner_portal_read_policies.sql`
- Create: `supabase/tests/006_owner_portal_test.sql`

**Interfaces:**
- Produces `security.owner_can_view_report(uuid)` and final owner read policies over properties, report versions, readings included in owner-facing report content, and permitted media.
- Owners receive no company-internal columns through a broad table read; expose a security-invoker view or RPC with an explicit owner-facing projection where column privacy requires it.

- [ ] **Step 1: Write failing owner projection tests**

Authenticate as Andrea and assert exactly one Pender Gardens final report, permitted photo IDs, and simplified status. Assert zero draft rows, zero internal result-change rows, zero internal notes, zero other-owner rows, and zero unrelated Andrea portfolio rows when querying through the JTC context. Attempt direct base-table reads and known-UUID substitutions.

- [ ] **Step 2: Confirm red**

Run: `supabase test db supabase/tests/006_owner_portal_test.sql`

Expected: FAIL because owner-final policies/projection are absent.

- [ ] **Step 3: Implement owner helpers, policies, and projection**

The helper must join current profile -> property owner -> target report property and require report state `FINAL`. Media access additionally requires `owner_visible = true` and linkage to that report/inspection. Do not use company membership for owner authorization.

- [ ] **Step 4: Verify owner isolation**

Run: `supabase db reset; supabase test db supabase/tests/006_owner_portal_test.sql`

Expected: PASS.

- [ ] **Step 5: Commit owner policies**

```powershell
git add supabase/migrations/011_owner_portal_read_policies.sql supabase/tests/006_owner_portal_test.sql
git commit -m "feat(db): add owner final report access"
```

### Task 10: Append-Only Audit Foundation and Locked-Record Regression

**Files:**
- Create: `supabase/migrations/012_audit_foundation.sql`
- Create: `supabase/tests/007_immutability_audit_test.sql`
- Modify: `supabase/migrations/010_report_versioning_publish.sql`

**Interfaces:**
- Produces append-only `audit_log` and internal `security.write_audit_event(...)` callable only from controlled functions.
- Report publication, inspection completion, and material result changes write audit events transactionally.

- [ ] **Step 1: Write failing audit and immutability tests**

Assert one audit row per protected success, zero audit row on rolled-back failure, and authenticated denial for direct insert/update/delete of `audit_log`. Retain report immutability regression coverage from Task 8. Do not add an `approval_snapshots` assertion because no approvals relation exists in this slice.

- [ ] **Step 2: Preserve the narrow approval-snapshot deferral**

The platform requirement that an `ADMIN` cannot modify `approval_snapshots` remains locked. Defer only its executable adversarial test until the future approvals slice introduces the approvals schema and migration. Do not create approval tables in migrations `001`–`012`, add an approval shell to `012_audit_foundation.sql`, or invent any approval workflow behavior.

- [ ] **Step 3: Confirm red**

Run: `supabase test db supabase/tests/007_immutability_audit_test.sql`

Expected: FAIL with missing audit foundation.

- [ ] **Step 4: Implement append-only audit controls**

Revoke authenticated mutation privileges, add update/delete rejection triggers, and call the internal writer from the same transactions as protected operations. The actor is derived from `security.current_profile_id()`, never accepted as a trusted caller parameter.

- [ ] **Step 5: Verify full database suite**

Run:

```powershell
supabase db reset
supabase test db
```

Expected: all identity, property, inspection, storage, report, owner, in-slice immutability, and audit tests PASS. The test output does not claim coverage of `approval_snapshots`; that locked adversarial test remains deferred to the future approvals slice.

- [ ] **Step 6: Commit audit foundation**

```powershell
git add supabase/migrations/010_report_versioning_publish.sql supabase/migrations/012_audit_foundation.sql supabase/tests/007_immutability_audit_test.sql
git commit -m "feat(db): add append-only audit foundation"
```

### Task 11: Deterministic JTC Acceptance Seed and Generated Types

**Files:**
- Create: `supabase/seed.sql`
- Create: `src/lib/supabase/database.types.ts`
- Modify: `package.json`

**Interfaces:**
- Produces deterministic local accounts for Jesmond, Andrea, unrelated company admin/owner, assigned/unassigned inspectors, coordinator, and read-only user.
- Produces JTC, Pender Gardens Apartment 1042, its owner/company relationships, template, and permitted/non-permitted media metadata.

- [ ] **Step 1: Add a failing seed smoke assertion**

Append a transaction to `supabase/tests/001_identity_company_test.sql` that asserts the canonical JTC and Pender records exist after reset and that every test identity maps to one profile.

- [ ] **Step 2: Confirm red on a fresh reset**

Run: `supabase db reset; supabase test db supabase/tests/001_identity_company_test.sql`

Expected: FAIL because seed records are absent.

- [ ] **Step 3: Create idempotent local-only seed data**

Use fixed UUIDs consistently referenced by `tests.uuid(...)`. Never place real passwords, API keys, production personal data, or service-role secrets in the repository. Label identities as local acceptance fixtures.

- [ ] **Step 4: Generate types and verify no manual drift**

Run:

```powershell
supabase db reset
supabase gen types typescript --local --schema public > src/lib/supabase/database.types.ts
npm run typecheck
supabase test db
```

Expected: generated types compile and all database tests PASS.

- [ ] **Step 5: Commit fixtures and types**

```powershell
git add supabase/seed.sql supabase/tests/001_identity_company_test.sql src/lib/supabase/database.types.ts package.json
git commit -m "test: add JTC vertical slice fixtures"
```

### Task 12: Authentication and Server Authorization Adapters

**Files:**
- Create: `src/app/(auth)/login/page.tsx`
- Create: `src/app/auth/callback/route.ts`
- Create: `src/lib/auth/require-profile.ts`
- Create: `src/app/actions/inspections.ts`
- Create: `src/app/actions/reports.ts`
- Create: `src/features/inspections/schemas.ts`
- Create: `src/features/reports/schemas.ts`
- Create: `tests/unit/actions/inspections.test.ts`
- Create: `tests/unit/actions/reports.test.ts`

**Interfaces:**
- Produces `requireProfile(): Promise<{ id: string }>`.
- Produces server actions `createInspection(input)`, `saveInspectionResult(input)`, `saveMeterReading(input)`, `completeInspection(input)`, `createDraftReport(input)`, and `publishReport(input)`.
- Actions accept only record identifiers and user-entered values; company/profile authority is derived by PostgreSQL.

- [ ] **Step 1: Write failing action contract tests**

Mock the request-scoped Supabase client, assert Zod rejects malformed UUIDs/enum values, assert RPC/database errors are returned as typed action failures, and assert no action accepts `actorId`, `role`, `isAdmin`, or trusted owner-visibility flags.

- [ ] **Step 2: Confirm red**

Run: `npm run test:unit -- tests/unit/actions`

Expected: FAIL because adapters do not exist.

- [ ] **Step 3: Implement thin server adapters**

Each action validates shape, requires an authenticated profile, calls the RLS-protected table/RPC using the user's session, and returns `{ ok: true, data } | { ok: false, code, message }`. Do not use a service-role client to bypass RLS.

- [ ] **Step 4: Verify adapters and credential boundary**

Run:

```powershell
npm run test:unit -- tests/unit/actions tests/unit/security/no-service-role-in-client.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit adapters**

```powershell
git add src/app/\(auth\) src/app/auth src/app/actions src/lib/auth src/features/inspections/schemas.ts src/features/reports/schemas.ts tests/unit/actions
git commit -m "feat: add authenticated inspection server actions"
```

### Task 13: Company Inspection Workflow UI

**Precondition:** Final Stitch HTML reference files for these screens are present in the agreed reference location and have been inspected. If they are not supplied, stop this task without blocking Tasks 1–12.

**Files:**
- Create: `src/app/(company)/properties/page.tsx`
- Create: `src/app/(company)/properties/[propertyId]/page.tsx`
- Create: `src/app/(company)/properties/[propertyId]/inspections/new/page.tsx`
- Create: `src/app/(company)/inspections/[inspectionId]/page.tsx`
- Create: `src/app/(company)/inspections/[inspectionId]/report/page.tsx`
- Create: `src/features/inspections/components/inspection-form.tsx`
- Create: `src/features/inspections/components/meter-readings-form.tsx`
- Create: `src/features/inspections/components/media-uploader.tsx`
- Create: `src/features/reports/components/draft-report-review.tsx`
- Create: `tests/e2e/jtc-inspection-report.spec.ts`

**Interfaces:**
- Pages query only rows returned by the signed-in user's RLS session.
- Components call Task 12 actions and show explicit pending, validation, authorization-denied, and retry states.

- [ ] **Step 1: Write the failing administrator Playwright path**

Test login as local Jesmond, open Pender Gardens Apartment 1042, create an inspection, record distinct severity/action values, add electricity and water readings, upload an allowed test image, complete, create draft, verify draft is not owner-visible, and publish final.

- [ ] **Step 2: Confirm red**

Run: `npm run test:e2e -- tests/e2e/jtc-inspection-report.spec.ts --grep "JTC admin publishes"`

Expected: FAIL because company pages do not exist.

- [ ] **Step 3: Recreate the frozen references as production React**

Implement semantic, accessible React components using the existing Tailwind setup and visual values observed in the supplied references. Do not paste Stitch HTML, add screens, change navigation, or invent interactions. Preserve visible loading/error/disabled states required by real server actions.

- [ ] **Step 4: Verify company workflow**

Run:

```powershell
npm run test:e2e -- tests/e2e/jtc-inspection-report.spec.ts --grep "JTC admin publishes"
npm run lint
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit company workflow**

```powershell
git add src/app/\(company\) src/features/inspections/components src/features/reports/components tests/e2e/jtc-inspection-report.spec.ts
git commit -m "feat: add JTC inspection publication workflow"
```

### Task 14: Owner Final-Report Portal UI

**Precondition:** Final Stitch HTML references for owner report screens are supplied and inspected.

**Files:**
- Create: `src/app/(owner)/owner/reports/page.tsx`
- Create: `src/app/(owner)/owner/reports/[reportVersionId]/page.tsx`
- Create: `src/features/reports/components/owner-report.tsx`
- Modify: `tests/e2e/jtc-inspection-report.spec.ts`

**Interfaces:**
- Owner pages consume only the owner-facing projection from Task 9.
- Owner media uses signed access obtained under the owner's RLS session; it never exposes bucket-wide or company-internal object access.

- [ ] **Step 1: Add failing owner and malicious-navigation cases**

After the Task 13 publish, log in as Andrea and assert the final report plus permitted photo is visible. Assert draft text, internal change history, non-owner-visible photo, another owner's report UUID, and an unrelated Andrea property in the JTC route are absent/inaccessible.

- [ ] **Step 2: Confirm red**

Run: `npm run test:e2e -- tests/e2e/jtc-inspection-report.spec.ts --grep "Andrea"`

Expected: FAIL because owner routes do not exist.

- [ ] **Step 3: Implement owner pages from frozen references**

Render only the database owner projection. Treat authorization-denied and not-found uniformly enough to avoid record discovery. Recreate supplied visuals without importing Stitch code.

- [ ] **Step 4: Run the complete vertical-slice gate**

Run:

```powershell
supabase db reset
supabase test db
npm run test:unit
npm run lint
npm run typecheck
npm run build
npm run test:e2e -- tests/e2e/jtc-inspection-report.spec.ts
git diff --check
```

Expected: every command PASS; Jesmond completes the workflow and Andrea sees only the published permitted result.

- [ ] **Step 5: Commit owner portal**

```powershell
git add src/app/\(owner\) src/features/reports/components/owner-report.tsx tests/e2e/jtc-inspection-report.spec.ts
git commit -m "feat: add owner published report portal"
```

## Final Review Gate

- [ ] Map each section of the approved RLS specification to a migration/test above; record later-slice domains as explicit non-goals, not false passes.
- [ ] Search for `TBD`, `TODO`, `FIXME`, placeholder behavior, broad exception handling, hard-coded JTC authorization, and client-side privileged variables; resolve every occurrence.
- [ ] Confirm generated types match function and enum names used by server actions.
- [ ] Confirm all twelve migrations apply from an empty local database in numeric order.
- [ ] Confirm every mandatory adversarial case within this slice passes as an authenticated representative user.
- [ ] Confirm migrations `001`–`012` contain no approval tables or approval workflow behavior, while the locked `ADMIN`-cannot-modify-`approval_snapshots` requirement and its explicit future-approvals-slice test deferral remain documented.
- [ ] Confirm Stitch files remain references only and are not staged as application source unless Jesmond separately asks to retain them.
- [ ] Run `git status --short --branch` and `git log --oneline --decorate -15`; do not claim completion with an unexplained dirty tree or failed check.

## Commit Boundary Summary

1. `chore: scaffold application and local Supabase`
2. `feat(db): add identity and company membership foundation`
3. `feat(db): add security authorization helpers`
4. `feat(db): enforce property tenant boundaries`
5. `feat(db): add tenant-scoped inspection templates`
6. `feat(db): add secured inspection runtime`
7. `feat(db): secure inspection media storage`
8. `feat(db): add immutable report publication`
9. `feat(db): add owner final report access`
10. `feat(db): add append-only audit foundation`
11. `test: add JTC vertical slice fixtures`
12. `feat: add authenticated inspection server actions`
13. `feat: add JTC inspection publication workflow`
14. `feat: add owner published report portal`

Each boundary must be reviewed and green before the next task begins. Do not squash security boundaries during implementation review; their focused history is useful for auditing.
