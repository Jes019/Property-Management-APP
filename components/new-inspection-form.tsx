"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { createInspection } from "@/lib/data/inspections";
import { getCurrentFrozenVersion, type InspectionTemplate } from "@/lib/data/templates";
import { createClient } from "@/lib/supabase/client";

/**
 * Client-side validation here is just "a template is selected" — the
 * database is what actually decides whether the template version is
 * frozen, whether the company has an inspection-capable relationship to
 * this property, and whether the caller's role permits creating an
 * inspection at all.
 */
export function NewInspectionForm({
  propertyId,
  companyId,
  templates,
}: {
  propertyId: string;
  companyId: string;
  templates: InspectionTemplate[];
}) {
  const router = useRouter();
  const [templateId, setTemplateId] = useState(templates[0]?.id ?? "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleCreate() {
    if (!templateId) {
      setError("Choose a template first.");
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const supabase = createClient();
      const version = await getCurrentFrozenVersion(supabase, templateId);
      if (!version) {
        setError("This template has no frozen current version to inspect against.");
        return;
      }

      const inspection = await createInspection(supabase, {
        companyId,
        propertyId,
        templateVersionId: version.id,
      });

      router.push(`/inspections/${inspection.id}`);
    } catch {
      setError("Could not create the inspection.");
    } finally {
      setSubmitting(false);
    }
  }

  if (templates.length === 0) {
    return <p className="text-sm text-navy/50">No inspection templates are available for this company yet.</p>;
  }

  return (
    <div className="flex items-end gap-3 rounded-2xl border border-border bg-white p-4 shadow-sm">
      <div className="flex-1">
        <label htmlFor="template" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
          Template
        </label>
        <select
          id="template"
          value={templateId}
          onChange={(event) => setTemplateId(event.target.value)}
          className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm"
        >
          {templates.map((template) => (
            <option key={template.id} value={template.id}>
              {template.name}
            </option>
          ))}
        </select>
      </div>
      <button
        type="button"
        onClick={handleCreate}
        disabled={submitting}
        className="min-h-[44px] rounded-lg bg-navy px-4 py-2 text-sm font-bold uppercase tracking-widest text-white disabled:opacity-50"
      >
        {submitting ? "Creating…" : "New Inspection"}
      </button>
      {error ? (
        <p role="alert" className="text-xs font-semibold text-urgent">
          {error}
        </p>
      ) : null}
    </div>
  );
}
