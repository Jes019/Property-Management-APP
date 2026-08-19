import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ChecklistSection } from "@/components/checklist-section";
import type { InspectionTemplateSection } from "@/lib/types";

const section: InspectionTemplateSection = {
  id: "section-1",
  version_id: "version-1",
  title: "Exterior",
  sort_order: 1,
  items: [
    { id: "item-1", section_id: "section-1", label: "Facade", sort_order: 1 },
    { id: "item-2", section_id: "section-1", label: "Garden", sort_order: 2 },
    { id: "item-3", section_id: "section-1", label: "Roof", sort_order: 3 },
  ],
};

describe("ChecklistSection", () => {
  it("preserves the given (already versioned/sort_order-fetched) item order when rendering", () => {
    render(
      <ChecklistSection
        section={section}
        results={[]}
        readOnly={false}
        onSaveItem={async () => {}}
      />,
    );

    const labels = screen.getAllByText(/Facade|Garden|Roof/).map((element) => element.textContent);
    expect(labels).toEqual(["Facade", "Garden", "Roof"]);
  });

  it("renders the section title", () => {
    render(
      <ChecklistSection section={section} results={[]} readOnly={false} onSaveItem={async () => {}} />,
    );

    expect(screen.getByRole("heading", { name: "Exterior" })).toBeInTheDocument();
  });
});
