import { AppShell } from "@/components/app-shell";
import { PropertyList } from "@/components/property-list";
import { requireUser } from "@/lib/auth";
import { listAccessibleProperties } from "@/lib/data/properties";
import { createClient } from "@/lib/supabase/server";

export default async function PropertiesPage() {
  await requireUser();
  const supabase = await createClient();
  const properties = await listAccessibleProperties(supabase);

  return (
    <AppShell title="JTC Property Services" variant="company" activeHref="/properties">
      <section>
        <h2 className="mb-2 text-3xl font-bold tracking-tight">Properties</h2>
        <p className="text-navy/70">Manage your property portfolio and inspections.</p>
      </section>

      <PropertyList
        properties={properties}
        hrefBuilder={(propertyId) => `/properties/${propertyId}`}
        emptyMessage="No properties are accessible to your account yet."
      />
    </AppShell>
  );
}
