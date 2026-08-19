import Link from "next/link";

import { IconLocation } from "@/components/icons";
import type { Property } from "@/lib/types";

function formatAddress(property: Property): string {
  return [property.locality, property.country].filter(Boolean).join(", ");
}

export function PropertyCard({ property, href }: { property: Property; href: string }) {
  const address = formatAddress(property);

  return (
    <Link
      href={href}
      className="block overflow-hidden rounded-2xl border border-border bg-white p-5 shadow-sm transition-transform active:scale-[0.98]"
    >
      <h3 className="mb-1 text-xl font-bold tracking-tight">{property.name}</h3>
      {address ? (
        <div className="mb-2 flex items-center gap-1 text-sm text-navy/60">
          <IconLocation className="h-4 w-4" />
          <span>{address}</span>
        </div>
      ) : null}
    </Link>
  );
}
