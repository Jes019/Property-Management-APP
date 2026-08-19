import type { SupabaseClient } from "@supabase/supabase-js";

import type { Inspection } from "@/lib/types";

const INSPECTION_COLUMNS =
  "id, company_id, property_id, template_version_id, status, scheduled_at, started_at, completed_at, created_by, created_at, updated_at";

export async function listPropertyInspections(
  supabase: SupabaseClient,
  propertyId: string,
): Promise<Inspection[]> {
  const { data, error } = await supabase
    .from("inspections")
    .select(INSPECTION_COLUMNS)
    .eq("property_id", propertyId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []) as Inspection[];
}

/** RLS already scopes this to inspections the current company user can see. */
export async function listRecentInspections(
  supabase: SupabaseClient,
  limit = 5,
): Promise<Inspection[]> {
  const { data, error } = await supabase
    .from("inspections")
    .select(INSPECTION_COLUMNS)
    .order("updated_at", { ascending: false })
    .limit(limit);

  if (error) throw error;
  return (data ?? []) as Inspection[];
}

export async function getInspection(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<Inspection | null> {
  const { data, error } = await supabase
    .from("inspections")
    .select(INSPECTION_COLUMNS)
    .eq("id", inspectionId)
    .maybeSingle();

  if (error) throw error;
  return data as Inspection | null;
}

export async function createInspection(
  supabase: SupabaseClient,
  params: { companyId: string; propertyId: string; templateVersionId: string },
): Promise<Inspection> {
  const { data, error } = await supabase
    .from("inspections")
    .insert({
      company_id: params.companyId,
      property_id: params.propertyId,
      template_version_id: params.templateVersionId,
    })
    .select(INSPECTION_COLUMNS)
    .single();

  if (error) throw error;
  return data as Inspection;
}

export async function startInspection(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<Inspection> {
  const { data, error } = await supabase
    .from("inspections")
    .update({ status: "IN_PROGRESS" })
    .eq("id", inspectionId)
    .select(INSPECTION_COLUMNS)
    .single();

  if (error) throw error;
  return data as Inspection;
}

/**
 * Freezes results, meters, and evidence and writes the completion audit
 * event (Task 13 trigger) — this is the single authoritative completion
 * action, there is no separate "edit completed inspection" path.
 */
export async function completeInspection(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<Inspection> {
  const { data, error } = await supabase
    .from("inspections")
    .update({ status: "COMPLETED" })
    .eq("id", inspectionId)
    .select(INSPECTION_COLUMNS)
    .single();

  if (error) throw error;
  return data as Inspection;
}
