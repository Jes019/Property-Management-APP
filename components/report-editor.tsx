"use client";

import { useEffect, useState } from "react";

import { getEvidenceSignedUrl, listInspectionMedia } from "@/lib/data/media";
import { createDraftReport, publishReport, updateDraftReport } from "@/lib/data/reports";
import { createClient } from "@/lib/supabase/client";
import type { Inspection, MediaAsset, ReportVersion } from "@/lib/types";

interface MediaOption {
  asset: MediaAsset;
  url: string | null;
}

export function ReportEditor({
  inspection,
  initialReports,
}: {
  inspection: Inspection;
  initialReports: ReportVersion[];
}) {
  const [reports, setReports] = useState(initialReports);
  const [mediaOptions, setMediaOptions] = useState<MediaOption[]>([]);
  const [creating, setCreating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [publishedMessage, setPublishedMessage] = useState<string | null>(null);

  const draft = reports.find((report) => report.status === "DRAFT") ?? null;
  const currentFinal = reports.find((report) => report.status === "FINAL") ?? null;

  const [title, setTitle] = useState(draft?.title ?? "Inspection Report");
  const [summary, setSummary] = useState(draft?.summary ?? "");
  const [selectedMedia, setSelectedMedia] = useState<Set<string>>(
    new Set(draft?.content?.media ?? []),
  );

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const supabase = createClient();
      const assets = await listInspectionMedia(supabase, inspection.id);
      const withUrls = await Promise.all(
        assets.map(async (asset) => ({
          asset,
          url: await getEvidenceSignedUrl(supabase, asset.storage_path).catch(() => null),
        })),
      );
      if (!cancelled) setMediaOptions(withUrls);
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [inspection.id]);

  async function handleCreateDraft() {
    setCreating(true);
    setError(null);
    try {
      const supabase = createClient();
      const created = await createDraftReport(supabase, {
        companyId: inspection.company_id,
        propertyId: inspection.property_id,
        inspectionId: inspection.id,
        title,
      });
      setReports((current) => [created, ...current]);
    } catch {
      setError("Could not create a draft report.");
    } finally {
      setCreating(false);
    }
  }

  async function handleSaveDraft() {
    if (!draft) return;
    setSaving(true);
    setError(null);
    try {
      const supabase = createClient();
      const updated = await updateDraftReport(supabase, draft.id, {
        title,
        summary: summary || null,
        content: { summary, media: Array.from(selectedMedia) },
      });
      setReports((current) => current.map((report) => (report.id === updated.id ? updated : report)));
    } catch {
      setError("Could not save the draft report.");
    } finally {
      setSaving(false);
    }
  }

  async function handlePublish() {
    if (!draft) return;
    setPublishing(true);
    setError(null);
    setPublishedMessage(null);
    try {
      const supabase = createClient();
      await handleSaveDraft();
      const published = await publishReport(supabase, draft.id);
      setReports((current) => [
        published,
        ...current.filter((report) => report.id !== published.id).map((report) =>
          report.status === "FINAL" ? { ...report, status: "SUPERSEDED" as const } : report,
        ),
      ]);
      setPublishedMessage(`Report v${published.version_number} published.`);
    } catch {
      setError("Could not publish this report. Confirm the inspection is completed and try again.");
    } finally {
      setPublishing(false);
    }
  }

  function toggleMedia(assetId: string) {
    setSelectedMedia((current) => {
      const next = new Set(current);
      if (next.has(assetId)) {
        next.delete(assetId);
      } else {
        next.add(assetId);
      }
      return next;
    });
  }

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold tracking-tight">Report</h2>

      {currentFinal ? (
        <p className="rounded-xl border border-good/30 bg-good-bg p-4 text-sm text-good">
          Current published version: v{currentFinal.version_number}
        </p>
      ) : null}

      {!draft ? (
        <button
          type="button"
          onClick={handleCreateDraft}
          disabled={creating}
          className="min-h-[48px] w-full rounded-xl bg-navy text-sm font-bold uppercase tracking-widest text-white disabled:opacity-50"
        >
          {creating ? "Creating…" : "Create Draft Report"}
        </button>
      ) : (
        <div className="space-y-4">
          <div>
            <label htmlFor="report-title" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Title
            </label>
            <input
              id="report-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="report-summary" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Summary
            </label>
            <textarea
              id="report-summary"
              value={summary}
              onChange={(event) => setSummary(event.target.value)}
              rows={4}
              className="w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm"
            />
          </div>

          <fieldset>
            <legend className="mb-2 text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Owner-Visible Media
            </legend>
            <p className="mb-2 text-xs text-navy/50">
              Only the evidence selected here will be visible to the property owner.
            </p>
            <div className="grid grid-cols-3 gap-2">
              {mediaOptions.map(({ asset }) => (
                <label key={asset.id} className="relative flex aspect-square items-center justify-center rounded-lg border border-border bg-white text-xs">
                  <input
                    type="checkbox"
                    checked={selectedMedia.has(asset.id)}
                    onChange={() => toggleMedia(asset.id)}
                    className="absolute right-1 top-1 h-5 w-5"
                    aria-label={`Include evidence ${asset.id.slice(0, 8)} for the owner`}
                  />
                  <span className="px-1 text-center text-navy/50">{asset.id.slice(0, 8)}</span>
                </label>
              ))}
              {mediaOptions.length === 0 ? (
                <p className="col-span-3 text-sm text-navy/50">No evidence available for this inspection.</p>
              ) : null}
            </div>
          </fieldset>

          <div className="flex gap-3">
            <button
              type="button"
              onClick={handleSaveDraft}
              disabled={saving}
              className="min-h-[44px] flex-1 rounded-lg border border-border text-sm font-bold text-navy disabled:opacity-50"
            >
              {saving ? "Saving…" : "Save Draft"}
            </button>
            <button
              type="button"
              onClick={handlePublish}
              disabled={publishing}
              className="min-h-[44px] flex-1 rounded-lg bg-navy text-sm font-bold uppercase tracking-widest text-white disabled:opacity-50"
            >
              {publishing ? "Publishing…" : "Publish FINAL"}
            </button>
          </div>
        </div>
      )}

      {publishedMessage ? (
        <p role="status" className="text-sm font-semibold text-good">
          {publishedMessage}
        </p>
      ) : null}
      {error ? (
        <p role="alert" className="text-sm font-semibold text-urgent">
          {error}
        </p>
      ) : null}
    </div>
  );
}
