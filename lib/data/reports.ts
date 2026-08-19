import type { SupabaseClient } from "@supabase/supabase-js";

import type { OwnerVisibleMedia, ReportContent, ReportVersion } from "@/lib/types";

const REPORT_COLUMNS =
  "id, company_id, property_id, inspection_id, version_number, status, title, summary, content, created_by, created_at, updated_at, published_at, published_by";

/**
 * All report versions the current session can see, with no extra filter —
 * RLS alone decides the result: a company user gets their company's rows,
 * an owner gets only their own properties' current FINAL rows. Used for
 * the owner portal's "my reports" list.
 */
export async function listVisibleReports(supabase: SupabaseClient): Promise<ReportVersion[]> {
  const { data, error } = await supabase
    .from("inspection_report_versions")
    .select(REPORT_COLUMNS)
    .order("published_at", { ascending: false, nullsFirst: false });

  if (error) throw error;
  return (data ?? []) as ReportVersion[];
}

export async function listVisibleReportsForProperty(
  supabase: SupabaseClient,
  propertyId: string,
): Promise<ReportVersion[]> {
  const { data, error } = await supabase
    .from("inspection_report_versions")
    .select(REPORT_COLUMNS)
    .eq("property_id", propertyId)
    .order("published_at", { ascending: false, nullsFirst: false });

  if (error) throw error;
  return (data ?? []) as ReportVersion[];
}

export async function listInspectionReports(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<ReportVersion[]> {
  const { data, error } = await supabase
    .from("inspection_report_versions")
    .select(REPORT_COLUMNS)
    .eq("inspection_id", inspectionId)
    .order("version_number", { ascending: false });

  if (error) throw error;
  return (data ?? []) as ReportVersion[];
}

/** Works for both a company reader and an owner: RLS decides what's visible, this just reads by id. */
export async function getReport(
  supabase: SupabaseClient,
  reportId: string,
): Promise<ReportVersion | null> {
  const { data, error } = await supabase
    .from("inspection_report_versions")
    .select(REPORT_COLUMNS)
    .eq("id", reportId)
    .maybeSingle();

  if (error) throw error;
  return data as ReportVersion | null;
}

export async function createDraftReport(
  supabase: SupabaseClient,
  params: { companyId: string; propertyId: string; inspectionId: string; title: string },
): Promise<ReportVersion> {
  const emptyContent: ReportContent = { media: [] };

  const { data, error } = await supabase
    .from("inspection_report_versions")
    .insert({
      company_id: params.companyId,
      property_id: params.propertyId,
      inspection_id: params.inspectionId,
      title: params.title,
      content: emptyContent,
    })
    .select(REPORT_COLUMNS)
    .single();

  if (error) throw error;
  return data as ReportVersion;
}

export async function updateDraftReport(
  supabase: SupabaseClient,
  reportId: string,
  params: { title: string; summary: string | null; content: ReportContent },
): Promise<ReportVersion> {
  const { data, error } = await supabase
    .from("inspection_report_versions")
    .update({
      title: params.title,
      summary: params.summary,
      content: params.content,
    })
    .eq("id", reportId)
    .select(REPORT_COLUMNS)
    .single();

  if (error) throw error;
  return data as ReportVersion;
}

/**
 * The only path to FINAL — invokes the Task 11 controlled RPC, which
 * validates lifecycle/scope/actor, handles supersession and locking, and
 * writes the Task 13 audit event, all inside its own transaction.
 */
export async function publishReport(
  supabase: SupabaseClient,
  reportId: string,
): Promise<ReportVersion> {
  const { data, error } = await supabase.rpc("publish_inspection_report", {
    p_report_id: reportId,
  });

  if (error) throw error;
  return data as ReportVersion;
}

/** Owner-safe media projection (Task 12) — never reads raw media_assets. */
export async function listOwnerReportMedia(
  supabase: SupabaseClient,
  reportId: string,
): Promise<OwnerVisibleMedia[]> {
  const { data, error } = await supabase.rpc("owner_report_media", {
    p_report_version_id: reportId,
  });

  if (error) throw error;
  return (data ?? []) as OwnerVisibleMedia[];
}
