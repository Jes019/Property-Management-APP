import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { PropertyList } from "@/components/property-list";
import type { Property } from "@/lib/types";

function makeProperty(overrides: Partial<Property>): Property {
  return {
    id: "prop-1",
    name: "Villa Azure",
    address_line_1: null,
    address_line_2: null,
    locality: "Monaco",
    postcode: null,
    country: "Monaco",
    created_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

describe("PropertyList", () => {
  it("renders exactly the authorized properties it is given, nothing more", () => {
    const properties = [makeProperty({ id: "a", name: "Villa Azure" }), makeProperty({ id: "b", name: "Marina Heights" })];

    render(
      <PropertyList properties={properties} hrefBuilder={(id) => `/properties/${id}`} emptyMessage="none" />,
    );

    expect(screen.getByText("Villa Azure")).toBeInTheDocument();
    expect(screen.getByText("Marina Heights")).toBeInTheDocument();
    expect(screen.getAllByRole("link")).toHaveLength(2);
  });

  it("links each property to the caller-provided route, not a hardcoded one", () => {
    const properties = [makeProperty({ id: "owned-1" })];

    render(
      <PropertyList
        properties={properties}
        hrefBuilder={(id) => `/owner/properties/${id}`}
        emptyMessage="none"
      />,
    );

    expect(screen.getByRole("link")).toHaveAttribute("href", "/owner/properties/owned-1");
  });

  it("shows the empty state instead of fabricating properties when none are authorized", () => {
    render(<PropertyList properties={[]} hrefBuilder={(id) => id} emptyMessage="No properties yet." />);

    expect(screen.getByText("No properties yet.")).toBeInTheDocument();
    expect(screen.queryAllByRole("link")).toHaveLength(0);
  });
});
