import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { ReportEditor } from "@/components/report-editor";
import { requireUser } from "@/lib/auth";
import { getInspection } from "@/lib/data/inspections";
import { listInspectionReports } from "@/lib/data/reports";
import { createClient } from "@/lib/supabase/server";

export default async function InspectionReportPage({
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

  const reports = await listInspectionReports(supabase, inspectionId);

  return (
    <AppShell title="JTC Property Services" variant="company" activeHref="/properties">
      <ReportEditor inspection={inspection} initialReports={reports} />
    </AppShell>
  );
}
