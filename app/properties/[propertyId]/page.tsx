import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { IconLocation } from "@/components/icons";
import { NewInspectionForm } from "@/components/new-inspection-form";
import { StatusPill } from "@/components/status-pill";
import { requireUser } from "@/lib/auth";
import { listPropertyInspections } from "@/lib/data/inspections";
import { getProperty } from "@/lib/data/properties";
import { getPropertyCompanyContext } from "@/lib/data/session";
import { listCompanyTemplates } from "@/lib/data/templates";
import { createClient } from "@/lib/supabase/server";
import type { InspectionStatus } from "@/lib/types";

const STATUS_LABEL: Record<InspectionStatus, string> = {
  SCHEDULED: "Scheduled",
  IN_PROGRESS: "In Progress",
  COMPLETED: "Completed",
};

export default async function PropertyDetailPage({
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

  const [inspections, companyContext] = await Promise.all([
    listPropertyInspections(supabase, propertyId),
    getPropertyCompanyContext(supabase, propertyId),
  ]);

  const templates = companyContext
    ? await listCompanyTemplates(supabase, companyContext.companyId)
    : [];

  return (
    <AppShell title="JTC Property Services" variant="company" activeHref="/properties">
      <div>
        <Link href="/properties" className="mb-4 inline-block text-sm font-semibold text-navy/60">
          ← Properties
        </Link>
        <h2 className="text-3xl font-bold tracking-tight">{property.name}</h2>
        {property.locality || property.country ? (
          <div className="mt-1 flex items-center gap-1 text-sm text-navy/60">
            <IconLocation className="h-4 w-4" />
            <span>{[property.locality, property.country].filter(Boolean).join(", ")}</span>
          </div>
        ) : null}
      </div>

      {companyContext ? (
        <NewInspectionForm propertyId={property.id} companyId={companyContext.companyId} templates={templates} />
      ) : null}

      <section>
        <h2 className="mb-3 text-lg font-bold">Inspections</h2>
        {inspections.length === 0 ? (
          <p className="text-sm text-navy/50">No inspections yet for this property.</p>
        ) : (
          <ul className="space-y-3">
            {inspections.map((inspection) => (
              <li key={inspection.id}>
                <Link
                  href={`/inspections/${inspection.id}`}
                  className="flex items-center justify-between rounded-xl border border-border bg-white p-4 shadow-sm"
                >
                  <span className="text-sm font-semibold">Inspection {inspection.id.slice(0, 8)}</span>
                  <StatusPill
                    label={STATUS_LABEL[inspection.status]}
                    tone={inspection.status === "COMPLETED" ? "good" : "neutral"}
                  />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </AppShell>
  );
}
