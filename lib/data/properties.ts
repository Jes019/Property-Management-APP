import type { SupabaseClient } from "@supabase/supabase-js";

import type { Property } from "@/lib/types";

const PROPERTY_COLUMNS =
  "id, name, address_line_1, address_line_2, locality, postcode, country, created_at";

/**
 * Properties visible to the current authenticated user under RLS. For a
 * company user this is scoped by property_company_relationships; for an
 * owner this is scoped by property_owners. The same query serves both —
 * the database, not this function, decides what rows come back.
 */
export async function listAccessibleProperties(
  supabase: SupabaseClient,
): Promise<Property[]> {
  const { data, error } = await supabase
    .from("properties")
    .select(PROPERTY_COLUMNS)
    .order("name", { ascending: true });

  if (error) throw error;
  return (data ?? []) as Property[];
}

export async function getProperty(
  supabase: SupabaseClient,
  propertyId: string,
): Promise<Property | null> {
  const { data, error } = await supabase
    .from("properties")
    .select(PROPERTY_COLUMNS)
    .eq("id", propertyId)
    .maybeSingle();

  if (error) throw error;
  return data as Property | null;
}
