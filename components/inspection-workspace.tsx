"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { ChecklistSection } from "@/components/checklist-section";
import { MediaGallery } from "@/components/media-gallery";
import { MeterReadingForm } from "@/components/meter-reading-form";
import { StatusPill } from "@/components/status-pill";
import { completeInspection, startInspection } from "@/lib/data/inspections";
import { addMeterReading } from "@/lib/data/meters";
import { saveInspectionResult } from "@/lib/data/results";
import { createClient } from "@/lib/supabase/client";
import type {
  Inspection,
  InspectionResult,
  InspectionTemplateSection,
  MeterReading,
  MeterType,
} from "@/lib/types";

const STATUS_LABEL: Record<Inspection["status"], string> = {
  SCHEDULED: "Scheduled",
  IN_PROGRESS: "In Progress",
  COMPLETED: "Completed",
};

export function InspectionWorkspace({
  inspection,
  sections,
  initialResults,
  initialMeterReadings,
}: {
  inspection: Inspection;
  sections: InspectionTemplateSection[];
  initialResults: InspectionResult[];
  initialMeterReadings: MeterReading[];
}) {
  const router = useRouter();
  const [status, setStatus] = useState(inspection.status);
  const [results, setResults] = useState(initialResults);
  const [meterReadings, setMeterReadings] = useState(initialMeterReadings);
  const [transitioning, setTransitioning] = useState(false);
  const [transitionError, setTransitionError] = useState<string | null>(null);
  const [confirmingCompletion, setConfirmingCompletion] = useState(false);

  const readOnly = status === "COMPLETED";

  async function handleStart() {
    setTransitioning(true);
    setTransitionError(null);
    try {
      const supabase = createClient();
      const updated = await startInspection(supabase, inspection.id);
      setStatus(updated.status);
    } catch {
      setTransitionError("Could not start this inspection.");
    } finally {
      setTransitioning(false);
    }
  }

  async function handleComplete() {
    setTransitioning(true);
    setTransitionError(null);
    try {
      const supabase = createClient();
      const updated = await completeInspection(supabase, inspection.id);
      setStatus(updated.status);
      setConfirmingCompletion(false);
      router.refresh();
    } catch {
      setTransitionError("Could not complete this inspection — evidence may be incomplete.");
    } finally {
      setTransitioning(false);
    }
  }

  async function handleSaveItem(
    templateItemId: string,
    values: { severity: InspectionResult["severity"]; operationalAction: InspectionResult["operational_action"]; comment: string | null },
  ) {
    const supabase = createClient();
    const saved = await saveInspectionResult(supabase, {
      companyId: inspection.company_id,
      propertyId: inspection.property_id,
      inspectionId: inspection.id,
      templateItemId,
      severity: values.severity,
      operationalAction: values.operationalAction,
      comment: values.comment,
    });
    setResults((current) => [...current.filter((result) => result.template_item_id !== templateItemId), saved]);
  }

  async function handleAddMeterReading(meterType: MeterType, value: number) {
    const supabase = createClient();
    const unit = meterType === "ELECTRICITY" ? "kWh" : "m3";
    const saved = await addMeterReading(supabase, {
      companyId: inspection.company_id,
      propertyId: inspection.property_id,
      inspectionId: inspection.id,
      meterType,
      readingValue: value,
      unit,
    });
    setMeterReadings((current) => [...current, saved]);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold tracking-tight">Inspection {inspection.id.slice(0, 8)}</h2>
        <StatusPill label={STATUS_LABEL[status]} tone={status === "COMPLETED" ? "good" : "neutral"} />
      </div>

      {status === "SCHEDULED" ? (
        <button
          type="button"
          onClick={handleStart}
          disabled={transitioning}
          className="min-h-[48px] w-full rounded-xl bg-navy text-sm font-bold uppercase tracking-widest text-white disabled:opacity-50"
        >
          {transitioning ? "Starting…" : "Start Inspection"}
        </button>
      ) : null}

      {readOnly ? (
        <p className="rounded-xl border border-border bg-white p-4 text-sm text-navy/70">
          This inspection is complete. Results, meter readings, and evidence are now immutable.
        </p>
      ) : null}

      {status !== "SCHEDULED" ? (
        <>
          <div className="space-y-6">
            {sections.map((section) => (
              <ChecklistSection
                key={section.id}
                section={section}
                results={results}
                readOnly={readOnly}
                onSaveItem={handleSaveItem}
              />
            ))}
          </div>

          <MeterReadingForm readings={meterReadings} readOnly={readOnly} onAdd={handleAddMeterReading} />

          <MediaGallery
            inspectionId={inspection.id}
            companyId={inspection.company_id}
            propertyId={inspection.property_id}
            readOnly={readOnly}
          />
        </>
      ) : null}

      {transitionError ? (
        <p role="alert" className="text-sm font-semibold text-urgent">
          {transitionError}
        </p>
      ) : null}

      {status === "IN_PROGRESS" ? (
        confirmingCompletion ? (
          <div className="space-y-3 rounded-xl border border-urgent/30 bg-urgent-bg p-4">
            <p className="text-sm font-semibold text-urgent">
              Completing this inspection freezes all results, meter readings, and evidence. This cannot be undone.
            </p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={handleComplete}
                disabled={transitioning}
                className="min-h-[44px] flex-1 rounded-lg bg-urgent text-sm font-bold text-white disabled:opacity-50"
              >
                {transitioning ? "Completing…" : "Confirm Completion"}
              </button>
              <button
                type="button"
                onClick={() => setConfirmingCompletion(false)}
                className="min-h-[44px] flex-1 rounded-lg border border-border text-sm font-semibold text-navy"
              >
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setConfirmingCompletion(true)}
            className="min-h-[48px] w-full rounded-xl bg-navy text-sm font-bold uppercase tracking-widest text-white"
          >
            Complete Inspection
          </button>
        )
      ) : null}

      {readOnly ? (
        <div className="flex gap-3">
          <Link
            href={`/inspections/${inspection.id}/review`}
            className="min-h-[48px] flex-1 rounded-xl border border-border bg-white text-center text-sm font-bold uppercase tracking-widest leading-[48px] text-navy"
          >
            Review
          </Link>
          <Link
            href={`/inspections/${inspection.id}/report`}
            className="min-h-[48px] flex-1 rounded-xl bg-navy text-center text-sm font-bold uppercase tracking-widest leading-[48px] text-white"
          >
            Draft Report
          </Link>
        </div>
      ) : null}
    </div>
  );
}
