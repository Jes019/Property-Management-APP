import { PropertyCard } from "@/components/property-card";
import type { Property } from "@/lib/types";

/**
 * Renders exactly the properties it is given — authorization happens
 * entirely upstream, at the RLS-scoped query that produced this list. This
 * component never fetches, so it can't itself widen or narrow access.
 */
export function PropertyList({
  properties,
  hrefBuilder,
  emptyMessage,
}: {
  properties: Property[];
  hrefBuilder: (propertyId: string) => string;
  emptyMessage: string;
}) {
  if (properties.length === 0) {
    return <p className="text-sm text-navy/50">{emptyMessage}</p>;
  }

  return (
    <div className="space-y-6">
      {properties.map((property) => (
        <PropertyCard key={property.id} property={property} href={hrefBuilder(property.id)} />
      ))}
    </div>
  );
}
