/**
 * Task 14 real end-to-end proof, run against the disposable Supabase
 * Postgres database. This is NOT a browser E2E test — no NEXT_PUBLIC
 * Supabase project credentials exist in this environment to run the Next.js
 * app or authenticate a real browser session (see the Task 14 completion
 * report for that limitation). This script instead issues the exact SQL
 * shapes the app's lib/data/* functions issue, under the same role/RLS
 * emulation technique used by the pgTAP suite (SET ROLE authenticated +
 * request.jwt.claim.sub), proving the full first-slice workflow end to end
 * against the real database and real security policies — company workflow,
 * publish, and owner visibility — without a browser.
 *
 * Usage: JTC_TEST_DATABASE_URL must be set. Run with:
 *   npx tsx scripts/e2e-first-slice.ts
 */
import { Client } from "pg";

const DATABASE_URL = process.env.JTC_TEST_DATABASE_URL;
if (!DATABASE_URL) {
  console.error("JTC_TEST_DATABASE_URL is not set.");
  process.exit(1);
}

const ids = {
  adminA: "e1000000-0000-0000-0000-000000000001",
  andrea: "e1000000-0000-0000-0000-000000000002",
  unrelated: "e1000000-0000-0000-0000-000000000003",
  companyA: "e2000000-0000-0000-0000-000000000001",
  companyUnrelated: "e2000000-0000-0000-0000-000000000002",
  propertyA: "e3000000-0000-0000-0000-000000000001",
  template: "e4000000-0000-0000-0000-000000000001",
  templateVersion: "e5000000-0000-0000-0000-000000000001",
  section: "e6000000-0000-0000-0000-000000000001",
  itemPass: "e7000000-0000-0000-0000-000000000001",
  itemAttention: "e7000000-0000-0000-0000-000000000002",
  itemUrgent: "e7000000-0000-0000-0000-000000000003",
  inspection: "e8000000-0000-0000-0000-000000000001",
  media1: "e9000000-0000-0000-0000-000000000001",
  media2: "e9000000-0000-0000-0000-000000000002",
  reportDraft: "ea000000-0000-0000-0000-000000000001",
};

let step = 0;
function log(message: string) {
  step += 1;
  console.log(`${String(step).padStart(2, "0")}. ${message}`);
}

async function main() {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();

  try {
    await client.query("BEGIN");

    await client.query(
      `DELETE FROM public.inspection_report_versions WHERE inspection_id = $1`,
      [ids.inspection],
    );
    await client.query(`DELETE FROM public.media_assets WHERE inspection_id = $1`, [ids.inspection]);
    await client.query(`DELETE FROM public.meter_readings WHERE inspection_id = $1`, [ids.inspection]);
    await client.query(`DELETE FROM public.inspection_results WHERE inspection_id = $1`, [ids.inspection]);
    await client.query(`DELETE FROM public.inspection_changes WHERE inspection_id = $1`, [ids.inspection]);
    await client.query(`DELETE FROM public.audit_log WHERE entity_id = $1`, [ids.inspection]);
    await client.query(`DELETE FROM public.inspections WHERE id = $1`, [ids.inspection]);

    await client.query(`DELETE FROM public.inspection_template_items WHERE id = ANY($1)`, [
      [ids.itemPass, ids.itemAttention, ids.itemUrgent],
    ]);
    await client.query(`DELETE FROM public.inspection_template_sections WHERE id = $1`, [ids.section]);
    await client.query(`DELETE FROM public.inspection_template_versions WHERE id = $1`, [ids.templateVersion]);
    await client.query(`DELETE FROM public.inspection_templates WHERE id = $1`, [ids.template]);
    await client.query(`DELETE FROM public.property_owners WHERE property_id = $1`, [ids.propertyA]);
    await client.query(`DELETE FROM public.property_company_relationships WHERE property_id = $1`, [ids.propertyA]);
    await client.query(`DELETE FROM public.properties WHERE id = $1`, [ids.propertyA]);
    await client.query(`DELETE FROM public.company_memberships WHERE company_id IN ($1, $2)`, [
      ids.companyA,
      ids.companyUnrelated,
    ]);
    await client.query(`DELETE FROM public.companies WHERE id IN ($1, $2)`, [ids.companyA, ids.companyUnrelated]);
    await client.query(`DELETE FROM public.profiles WHERE id = ANY($1)`, [[ids.adminA, ids.andrea, ids.unrelated]]);
    await client.query(`DELETE FROM auth.users WHERE id = ANY($1)`, [[ids.adminA, ids.andrea, ids.unrelated]]);

    log("Create Company A ADMIN, owner Andrea, and an unrelated profile");
    await client.query(`INSERT INTO auth.users (id) VALUES ($1), ($2), ($3)`, [ids.adminA, ids.andrea, ids.unrelated]);
    await client.query(`INSERT INTO public.profiles (id) VALUES ($1), ($2), ($3)`, [ids.adminA, ids.andrea, ids.unrelated]);
    await client.query(`INSERT INTO public.companies (id, name) VALUES ($1, 'E2E Company A'), ($2, 'E2E Unrelated Co')`, [
      ids.companyA,
      ids.companyUnrelated,
    ]);
    await client.query(`INSERT INTO public.company_memberships (company_id, profile_id, role, is_active) VALUES ($1, $2, 'ADMIN', true)`, [
      ids.companyA,
      ids.adminA,
    ]);

    log("Create Property A owned by Andrea");
    await client.query(`INSERT INTO public.properties (id, name, locality, country) VALUES ($1, 'E2E Property A', 'Malta', 'Malta')`, [
      ids.propertyA,
    ]);
    await client.query(`INSERT INTO public.property_owners (property_id, profile_id) VALUES ($1, $2)`, [
      ids.propertyA,
      ids.andrea,
    ]);

    log("Give Company A a FULL_MANAGEMENT relationship to Property A");
    await client.query(
      `INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope)
       VALUES ($1, $2, 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT')`,
      [ids.propertyA, ids.companyA],
    );

    log("Create and freeze an inspection template version");
    await client.query(`INSERT INTO public.inspection_templates (id, company_id, name) VALUES ($1, $2, 'E2E Template')`, [
      ids.template,
      ids.companyA,
    ]);
    await client.query(
      `INSERT INTO public.inspection_template_versions (id, template_id, version_number, is_current) VALUES ($1, $2, 1, false)`,
      [ids.templateVersion, ids.template],
    );
    await client.query(`INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order) VALUES ($1, $2, 'General', 1)`, [
      ids.section,
      ids.templateVersion,
    ]);
    await client.query(
      `INSERT INTO public.inspection_template_items (id, section_id, label, sort_order) VALUES
         ($1, $4, 'Smoke detectors', 1), ($2, $4, 'AC unit', 2), ($3, $4, 'Balcony railing', 3)`,
      [ids.itemPass, ids.itemAttention, ids.itemUrgent, ids.section],
    );
    await client.query(`UPDATE public.inspection_template_versions SET frozen_at = now() WHERE id = $1`, [ids.templateVersion]);

    // From here on, act as Company A's authenticated ADMIN under RLS —
    // exactly the session context the app would run under.
    await client.query(`SET LOCAL ROLE authenticated`);
    await client.query(`SET LOCAL request.jwt.claim.sub = '${ids.adminA}'`);

    log("Create inspection (as the app's createInspection() call would)");
    await client.query(
      `INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ($1, $2, $3, $4)`,
      [ids.inspection, ids.companyA, ids.propertyA, ids.templateVersion],
    );

    log("Start inspection");
    await client.query(`UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = $1`, [ids.inspection]);

    log("Enter checklist results — PASS/ATTENTION/URGENT with distinct operational actions");
    await client.query(
      `INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action, comment)
       VALUES
         ($1, $2, $3, $4, 'PASS', 'MONITOR', 'Working correctly'),
         ($1, $2, $3, $5, 'ATTENTION', 'INCLUDED_IN_SERVICE', 'Needs servicing'),
         ($1, $2, $3, $6, 'URGENT', 'OWNER_APPROVAL_REQUIRED', 'Safety risk, needs owner sign-off')`,
      [ids.companyA, ids.propertyA, ids.inspection, ids.itemPass, ids.itemAttention, ids.itemUrgent],
    );

    log("Add ELECTRICITY reading");
    await client.query(
      `INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ($1, $2, $3, 'ELECTRICITY', 4820, 'kWh')`,
      [ids.companyA, ids.propertyA, ids.inspection],
    );

    log("Add WATER reading");
    await client.query(
      `INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ($1, $2, $3, 'WATER', 310.5, 'm3')`,
      [ids.companyA, ids.propertyA, ids.inspection],
    );

    log("Register and 'upload' two evidence photos (media_assets + storage.objects)");
    const path1 = `${ids.companyA}/${ids.propertyA}/inspection/${ids.inspection}/${ids.media1}/balcony.jpg`;
    const path2 = `${ids.companyA}/${ids.propertyA}/inspection/${ids.inspection}/${ids.media2}/ac-unit.jpg`;
    await client.query(
      `INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type) VALUES
         ($1, $3, $4, $5, 'inspection-media', $6, 'image/jpeg'),
         ($2, $3, $4, $5, 'inspection-media', $7, 'image/jpeg')`,
      [ids.media1, ids.media2, ids.companyA, ids.propertyA, ids.inspection, path1, path2],
    );
    await client.query(`INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', $1), ('inspection-media', $2)`, [
      path1,
      path2,
    ]);

    log("Complete inspection");
    await client.query(`UPDATE public.inspections SET status = 'COMPLETED' WHERE id = $1`, [ids.inspection]);

    const completedCheck = await client.query(`SELECT status FROM public.inspections WHERE id = $1`, [ids.inspection]);
    if (completedCheck.rows[0]?.status !== "COMPLETED") throw new Error("Inspection did not complete");

    log("Confirm completed state is immutable (further result edits are rejected)");
    let immutabilityHeld = false;
    await client.query("SAVEPOINT immutability_check");
    try {
      await client.query(
        `UPDATE public.inspection_results SET severity = 'PASS' WHERE inspection_id = $1 AND template_item_id = $2`,
        [ids.inspection, ids.itemUrgent],
      );
    } catch {
      immutabilityHeld = true;
      await client.query("ROLLBACK TO SAVEPOINT immutability_check");
    }
    if (!immutabilityHeld) throw new Error("Completed inspection results were NOT immutable");

    log("Create DRAFT report");
    await client.query(
      `INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content) VALUES ($1, $2, $3, $4, 'E2E Inspection Report', $5)`,
      [ids.reportDraft, ids.companyA, ids.propertyA, ids.inspection, JSON.stringify({ media: [] })],
    );

    log("Select only balcony.jpg for owner visibility (not both photos)");
    await client.query(`UPDATE public.inspection_report_versions SET content = $1 WHERE id = $2`, [
      JSON.stringify({ summary: "Routine inspection complete.", media: [ids.media1] }),
      ids.reportDraft,
    ]);

    log("Publish report through the controlled publish_inspection_report() function");
    const published = await client.query(`SELECT * FROM public.publish_inspection_report($1)`, [ids.reportDraft]);
    if (published.rows[0]?.status !== "FINAL") throw new Error("Publish did not produce a FINAL report");

    log("Confirm publication audit event exists");
    const audit = await client.query(
      `SELECT action FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = $1 AND action = 'REPORT_PUBLISHED'`,
      [ids.reportDraft],
    );
    if (audit.rows.length !== 1) throw new Error("REPORT_PUBLISHED audit event missing");

    log("Log in as Andrea (owner) and confirm what she can see");
    await client.query(`SET LOCAL request.jwt.claim.sub = '${ids.andrea}'`);

    const ownerProperty = await client.query(`SELECT id FROM public.properties WHERE id = $1`, [ids.propertyA]);
    if (ownerProperty.rows.length !== 1) throw new Error("Andrea cannot see her owned property");

    const ownerReport = await client.query(`SELECT id, status FROM public.inspection_report_versions WHERE id = $1`, [ids.reportDraft]);
    if (ownerReport.rows.length !== 1 || ownerReport.rows[0].status !== "FINAL") {
      throw new Error("Andrea cannot see the published FINAL report");
    }

    const ownerMedia = await client.query(`SELECT media_id FROM public.owner_report_media($1)`, [ids.reportDraft]);
    if (ownerMedia.rows.length !== 1 || ownerMedia.rows[0].media_id !== ids.media1) {
      throw new Error("Andrea's owner-visible media set is wrong");
    }

    log("Confirm Andrea CANNOT see raw inspection/results/meters/unselected media/audit_log");
    const denials: Array<[string, string]> = [
      ["public.inspections", `SELECT * FROM public.inspections WHERE id = '${ids.inspection}'`],
      ["public.inspection_results", `SELECT * FROM public.inspection_results WHERE inspection_id = '${ids.inspection}'`],
      ["public.meter_readings", `SELECT * FROM public.meter_readings WHERE inspection_id = '${ids.inspection}'`],
      ["public.media_assets", `SELECT * FROM public.media_assets WHERE inspection_id = '${ids.inspection}'`],
      ["public.audit_log", `SELECT * FROM public.audit_log`],
    ];
    for (const [label, sql] of denials) {
      const result = await client.query(sql).catch(() => ({ rows: [] }));
      if (result.rows.length !== 0) throw new Error(`Andrea unexpectedly saw rows in ${label}`);
    }
    const unselectedMedia = await client.query(
      `SELECT * FROM storage.objects WHERE name = '${path2}'`,
    );
    if (unselectedMedia.rows.length !== 0) throw new Error("Andrea saw the unselected evidence photo");

    log("Confirm the unrelated company/user cannot see Property A, its report, or its media");
    await client.query(`SET LOCAL request.jwt.claim.sub = '${ids.unrelated}'`);
    const unrelatedProperty = await client.query(`SELECT * FROM public.properties WHERE id = $1`, [ids.propertyA]);
    const unrelatedReport = await client.query(`SELECT * FROM public.inspection_report_versions WHERE id = $1`, [ids.reportDraft]);
    const unrelatedMedia = await client.query(`SELECT * FROM storage.objects WHERE name = '${path1}'`);
    if (unrelatedProperty.rows.length !== 0 || unrelatedReport.rows.length !== 0 || unrelatedMedia.rows.length !== 0) {
      throw new Error("Unrelated user saw Property A data");
    }

    await client.query("ROLLBACK");
    console.log("\nFirst-slice DB-level end-to-end workflow: PASSED (transaction rolled back, no residue).");
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("\nFirst-slice end-to-end workflow FAILED:", error);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
}

void main();
