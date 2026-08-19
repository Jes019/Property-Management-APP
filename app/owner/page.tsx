import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { PropertyList } from "@/components/property-list";
import { requireUser } from "@/lib/auth";
import { listAccessibleProperties } from "@/lib/data/properties";
import { listVisibleReports } from "@/lib/data/reports";
import { createClient } from "@/lib/supabase/server";

export default async function OwnerPortalPage() {
  await requireUser();
  const supabase = await createClient();

  // Same query as the company properties page — RLS alone decides the
  // result set here, via the owner path (property_owners), never the
  // company path. Ownership is global: properties under different
  // management companies can both appear, with no cross-company leakage.
  const [properties, reports] = await Promise.all([
    listAccessibleProperties(supabase),
    listVisibleReports(supabase),
  ]);

  return (
    <AppShell title="Owner Portal" variant="owner" activeHref="/owner">
      <section>
        <p className="mb-1 text-xs font-bold uppercase tracking-[0.2em] text-gold">Portfolio Summary</p>
        <h2 className="text-3xl font-bold tracking-tight">Your Properties</h2>
      </section>

      <PropertyList
        properties={properties}
        hrefBuilder={(propertyId) => `/owner/properties/${propertyId}`}
        emptyMessage="No properties are linked to your account yet."
      />

      <section>
        <h2 className="mb-3 text-lg font-bold">Published Reports</h2>
        {reports.length === 0 ? (
          <p className="text-sm text-navy/50">No published reports yet.</p>
        ) : (
          <ul className="space-y-3">
            {reports.map((report) => (
              <li key={report.id}>
                <Link
                  href={`/owner/reports/${report.id}`}
                  className="flex items-center justify-between rounded-xl border border-border bg-white p-4 shadow-sm"
                >
                  <span className="text-sm font-semibold">{report.title ?? "Inspection Report"}</span>
                  <span className="text-xs text-navy/50">v{report.version_number}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </AppShell>
  );
}
