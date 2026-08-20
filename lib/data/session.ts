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
/**
 * Whether the current authenticated user owns at least one property.
 * property_owners is SELECT-granted with RLS scoped to the caller's own
 * rows (Task 6), so a non-empty result here already proves ownership
 * without ever touching company_memberships. Used only to decide where a
 * freshly-logged-in user lands (/owner vs /dashboard) — a routing
 * convenience, not an authorization decision; every destination page
 * enforces its own access independently regardless of this choice.
 */
export async function isOwner(supabase: SupabaseClient): Promise<boolean> {
  const { data, error } = await supabase.from("property_owners").select("property_id").limit(1);

  if (error) throw error;
  return (data?.length ?? 0) > 0;
}

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
