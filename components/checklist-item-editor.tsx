"use client";

import { useState } from "react";

import { OperationalActionSelector } from "@/components/operational-action-selector";
import { SeveritySelector } from "@/components/severity-selector";
import type { InspectionResult, InspectionSeverity, InspectionTemplateItem, OperationalAction } from "@/lib/types";

export interface ChecklistItemValues {
  severity: InspectionSeverity;
  operationalAction: OperationalAction;
  comment: string | null;
}

export function ChecklistItemEditor({
  item,
  result,
  readOnly,
  onSave,
}: {
  item: InspectionTemplateItem;
  result: InspectionResult | null;
  readOnly: boolean;
  onSave: (values: ChecklistItemValues) => Promise<void>;
}) {
  const [severity, setSeverity] = useState<InspectionSeverity | null>(result?.severity ?? null);
  const [operationalAction, setOperationalAction] = useState<OperationalAction | null>(
    result?.operational_action ?? null,
  );
  const [comment, setComment] = useState(result?.comment ?? "");
  const [status, setStatus] = useState<"idle" | "saving" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function persist(next: Partial<ChecklistItemValues>) {
    const nextSeverity = next.severity ?? severity;
    const nextAction = next.operationalAction ?? operationalAction;
    if (!nextSeverity || !nextAction) return;

    setStatus("saving");
    setErrorMessage(null);
    try {
      await onSave({
        severity: nextSeverity,
        operationalAction: nextAction,
        comment: next.comment !== undefined ? next.comment : comment || null,
      });
      setStatus("idle");
    } catch (error) {
      setStatus("error");
      setErrorMessage(
        error instanceof Error ? "Could not save this result." : "Could not save this result.",
      );
    }
  }

  return (
    <div className="rounded-xl border border-border bg-white p-4 shadow-sm">
      <p className="mb-3 text-sm font-bold">{item.label}</p>

      <div className="mb-3">
        <SeveritySelector
          value={severity}
          disabled={readOnly}
          onChange={(value) => {
            setSeverity(value);
            void persist({ severity: value });
          }}
        />
      </div>

      <div className="mb-3">
        <OperationalActionSelector
          value={operationalAction}
          disabled={readOnly}
          onChange={(value) => {
            setOperationalAction(value);
            void persist({ operationalAction: value });
          }}
        />
      </div>

      <div>
        <label
          htmlFor={`comment-${item.id}`}
          className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50"
        >
          Comment
        </label>
        <textarea
          id={`comment-${item.id}`}
          value={comment}
          disabled={readOnly}
          onChange={(event) => setComment(event.target.value)}
          onBlur={() => void persist({ comment: comment || null })}
          rows={2}
          className="w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm focus:border-navy focus:outline-none disabled:opacity-50"
        />
      </div>

      {status === "saving" ? <p className="mt-2 text-xs text-navy/50">Saving…</p> : null}
      {status === "error" ? (
        <p role="alert" className="mt-2 text-xs font-semibold text-urgent">
          {errorMessage}
        </p>
      ) : null}
    </div>
  );
}
