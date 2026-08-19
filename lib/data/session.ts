import type { SupabaseClient } from "@supabase/supabase-js";

export interface PropertyCompanyContext {
  companyId: string;
}

/**
 * The company (if any) managing a property the caller can already see.
 * property_company_relationships is SELECT-granted and RLS-scoped to
 * company members, so a returned row already proves company membership —
 * company_memberships itself has no direct grant at all (Task 4/13
 * contract) and security.* helpers live outside PostgREST's default
 * public-schema exposure, so this is the RLS-safe way to establish
 * "is the current user a company user for this property" without either.
 *
 * This does not resolve to a specific role (ADMIN vs MANAGER vs ...): the
 * UI only needs "show the operational controls" vs "don't" here — the
 * database is what actually enforces which mutations succeed. UI hiding
 * is not security.
 */
export async function getPropertyCompanyContext(
  supabase: SupabaseClient,
  propertyId: string,
): Promise<PropertyCompanyContext | null> {
  const { data, error } = await supabase
    .from("property_company_relationships")
    .select("company_id")
    .eq("property_id", propertyId)
    .eq("status", "ACTIVE")
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  return { companyId: data.company_id as string };
}
