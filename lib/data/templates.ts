import type { SupabaseClient } from "@supabase/supabase-js";

import type { InspectionTemplateSection } from "@/lib/types";

export interface InspectionTemplate {
  id: string;
  company_id: string;
  name: string;
}

export interface FrozenTemplateVersion {
  id: string;
  template_id: string;
  version_number: number;
  frozen_at: string;
}

/** Templates a company can start an inspection from, i.e. that have a frozen current version. */
export async function listCompanyTemplates(
  supabase: SupabaseClient,
  companyId: string,
): Promise<InspectionTemplate[]> {
  const { data, error } = await supabase
    .from("inspection_templates")
    .select("id, company_id, name")
    .eq("company_id", companyId)
    .order("name", { ascending: true });

  if (error) throw error;
  return (data ?? []) as InspectionTemplate[];
}

/**
 * The version to start a new inspection against. Task 7's own trigger
 * (security.protect_inspection_template_version) forbids a version being
 * both frozen and is_current at the same time — is_current tracks the
 * mutable draft being edited, frozen_at marks an immutable, inspectable
 * snapshot, and a version becomes one or the other, never both. So the
 * right lookup is simply the most recently frozen version, not "the
 * current one that's also frozen" (which can never exist).
 */
export async function getLatestFrozenVersion(
  supabase: SupabaseClient,
  templateId: string,
): Promise<FrozenTemplateVersion | null> {
  const { data, error } = await supabase
    .from("inspection_template_versions")
    .select("id, template_id, version_number, frozen_at")
    .eq("template_id", templateId)
    .not("frozen_at", "is", null)
    .order("frozen_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return data as FrozenTemplateVersion | null;
}

/** Sections with their items, in display order, for a single frozen template version. */
export async function getTemplateSections(
  supabase: SupabaseClient,
  versionId: string,
): Promise<InspectionTemplateSection[]> {
  const { data: sections, error: sectionsError } = await supabase
    .from("inspection_template_sections")
    .select("id, version_id, title, sort_order")
    .eq("version_id", versionId)
    .order("sort_order", { ascending: true });

  if (sectionsError) throw sectionsError;

  const sectionIds = (sections ?? []).map((section) => section.id as string);
  if (sectionIds.length === 0) return [];

  const { data: items, error: itemsError } = await supabase
    .from("inspection_template_items")
    .select("id, section_id, label, sort_order")
    .in("section_id", sectionIds)
    .order("sort_order", { ascending: true });

  if (itemsError) throw itemsError;

  return (sections ?? []).map((section) => ({
    id: section.id,
    version_id: section.version_id,
    title: section.title,
    sort_order: section.sort_order,
    items: (items ?? []).filter((item) => item.section_id === section.id),
  })) as InspectionTemplateSection[];
}
