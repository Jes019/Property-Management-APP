import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { IconLocation } from "@/components/icons";
import { requireUser } from "@/lib/auth";
import { getProperty } from "@/lib/data/properties";
import { listVisibleReportsForProperty } from "@/lib/data/reports";
import { createClient } from "@/lib/supabase/server";

export default async function OwnerPropertyPage({
  params,
}: {
  params: Promise<{ propertyId: string }>;
}) {
  await requireUser();
  const { propertyId } = await params;
  const supabase = await createClient();

  const property = await getProperty(supabase, propertyId);
  if (!property) {
    notFound();
  }

  const reports = await listVisibleReportsForProperty(supabase, propertyId);

  return (
    <AppShell title="Owner Portal" variant="owner" activeHref="/owner">
      <div>
        <Link href="/owner" className="mb-4 inline-block text-sm font-semibold text-navy/60">
          ← Portfolio
        </Link>
        <h2 className="text-3xl font-bold tracking-tight">{property.name}</h2>
        {property.locality || property.country ? (
          <div className="mt-1 flex items-center gap-1 text-sm text-navy/60">
            <IconLocation className="h-4 w-4" />
            <span>{[property.locality, property.country].filter(Boolean).join(", ")}</span>
          </div>
        ) : null}
      </div>

      <section>
        <h2 className="mb-3 text-lg font-bold">Published Reports</h2>
        {reports.length === 0 ? (
          <p className="text-sm text-navy/50">No published reports yet for this property.</p>
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
