import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { InspectionReview } from "@/components/inspection-review";
import { requireUser } from "@/lib/auth";
import { getInspection } from "@/lib/data/inspections";
import { listMeterReadings } from "@/lib/data/meters";
import { listInspectionResults } from "@/lib/data/results";
import { getTemplateSections } from "@/lib/data/templates";
import { createClient } from "@/lib/supabase/server";

export default async function InspectionReviewPage({
  params,
}: {
  params: Promise<{ inspectionId: string }>;
}) {
  await requireUser();
  const { inspectionId } = await params;
  const supabase = await createClient();

  const inspection = await getInspection(supabase, inspectionId);
  if (!inspection) {
    notFound();
  }

  const [sections, results, meterReadings] = await Promise.all([
    getTemplateSections(supabase, inspection.template_version_id),
    listInspectionResults(supabase, inspectionId),
    listMeterReadings(supabase, inspectionId),
  ]);

  return (
    <AppShell title="JTC Property Services" variant="company" activeHref="/properties">
      <InspectionReview
        inspection={inspection}
        sections={sections}
        results={results}
        meterReadings={meterReadings}
      />
    </AppShell>
  );
}
