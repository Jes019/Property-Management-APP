import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth";
import { getEvidenceSignedUrl } from "@/lib/data/media";
import { getReport, listOwnerReportMedia } from "@/lib/data/reports";
import { createClient } from "@/lib/supabase/server";

export default async function OwnerReportPage({
  params,
}: {
  params: Promise<{ reportId: string }>;
}) {
  await requireUser();
  const { reportId } = await params;
  const supabase = await createClient();

  // getReport reads the same RLS-scoped table the owner policy already
  // limits to their own current FINAL rows — a report that isn't theirs,
  // isn't FINAL, or is a DRAFT/SUPERSEDED simply doesn't come back.
  const report = await getReport(supabase, reportId);
  if (!report) {
    notFound();
  }

  // Media never comes from raw media_assets for an owner — only through
  // this Task 12 projection, which re-derives visibility from the same
  // FINAL report and its content->'media' selection.
  const media = await listOwnerReportMedia(supabase, reportId);
  const mediaWithUrls = await Promise.all(
    media.map(async (item) => ({
      item,
      url: await getEvidenceSignedUrl(supabase, item.storage_path).catch(() => null),
    })),
  );

  return (
    <AppShell title="Owner Portal" variant="owner" activeHref="/owner">
      <div>
        <Link href="/owner" className="mb-4 inline-block text-sm font-semibold text-navy/60">
          ← Portfolio
        </Link>
        <h2 className="text-2xl font-bold tracking-tight">{report.title ?? "Inspection Report"}</h2>
        <p className="text-sm text-navy/50">
          Published {report.published_at ? new Date(report.published_at).toLocaleDateString() : ""}
        </p>
      </div>

      {report.summary ? <p className="text-sm text-navy/80">{report.summary}</p> : null}

      <section>
        <h3 className="mb-3 text-lg font-bold">Evidence</h3>
        {mediaWithUrls.length === 0 ? (
          <p className="text-sm text-navy/50">No photos were included with this report.</p>
        ) : (
          <div className="grid grid-cols-3 gap-2">
            {mediaWithUrls.map(({ item, url }) =>
              url ? (
                <div key={item.media_id} className="relative aspect-square overflow-hidden rounded-lg border border-border">
                  <Image src={url} alt="Report evidence" fill sizes="120px" className="object-cover" unoptimized />
                </div>
              ) : null,
            )}
          </div>
        )}
      </section>
    </AppShell>
  );
}
