import type { SupabaseClient } from "@supabase/supabase-js";

import type { InspectionResult, InspectionSeverity, OperationalAction } from "@/lib/types";

const RESULT_COLUMNS =
  "id, inspection_id, template_item_id, severity, operational_action, comment";

export async function listInspectionResults(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<InspectionResult[]> {
  const { data, error } = await supabase
    .from("inspection_results")
    .select(RESULT_COLUMNS)
    .eq("inspection_id", inspectionId);

  if (error) throw error;
  return (data ?? []) as InspectionResult[];
}

/**
 * Creates or updates the result for one checklist item. The database
 * rejects this once the inspection is completed (immutability trigger) —
 * callers should surface that failure as a read-only state, not retry.
 */
export async function saveInspectionResult(
  supabase: SupabaseClient,
  params: {
    companyId: string;
    propertyId: string;
    inspectionId: string;
    templateItemId: string;
    severity: InspectionSeverity;
    operationalAction: OperationalAction;
    comment: string | null;
  },
): Promise<InspectionResult> {
  const { data, error } = await supabase
    .from("inspection_results")
    .upsert(
      {
        company_id: params.companyId,
        property_id: params.propertyId,
        inspection_id: params.inspectionId,
        template_item_id: params.templateItemId,
        severity: params.severity,
        operational_action: params.operationalAction,
        comment: params.comment,
      },
      { onConflict: "inspection_id,template_item_id" },
    )
    .select(RESULT_COLUMNS)
    .single();

  if (error) throw error;
  return data as InspectionResult;
}
