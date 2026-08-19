import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({}) }));
vi.mock("@/lib/data/media", () => ({
  listInspectionMedia: vi.fn().mockResolvedValue([]),
  getEvidenceSignedUrl: vi.fn().mockResolvedValue(null),
  registerAndUploadEvidence: vi.fn(),
}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }) }));

import { InspectionWorkspace } from "@/components/inspection-workspace";
import type { Inspection, InspectionTemplateSection } from "@/lib/types";

const inspection: Inspection = {
  id: "insp-1",
  company_id: "company-1",
  property_id: "property-1",
  template_version_id: "version-1",
  status: "COMPLETED",
  scheduled_at: null,
  started_at: "2026-01-01T00:00:00Z",
  completed_at: "2026-01-02T00:00:00Z",
  created_by: "profile-1",
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-02T00:00:00Z",
};

const sections: InspectionTemplateSection[] = [
  {
    id: "section-1",
    version_id: "version-1",
    title: "Exterior",
    sort_order: 1,
    items: [{ id: "item-1", section_id: "section-1", label: "Roof", sort_order: 1 }],
  },
];

describe("InspectionWorkspace — completed inspection", () => {
  it("renders read-only: no Start/Complete controls, no editable severity, an immutability notice", () => {
    render(
      <InspectionWorkspace
        inspection={inspection}
        sections={sections}
        initialResults={[
          {
            id: "r1",
            inspection_id: "insp-1",
            template_item_id: "item-1",
            severity: "PASS",
            operational_action: "MONITOR",
            comment: null,
          },
        ]}
        initialMeterReadings={[]}
      />,
    );

    expect(screen.getByText(/now immutable/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Start Inspection" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Complete Inspection" })).not.toBeInTheDocument();
    expect(screen.getByRole("radio", { name: "Pass" })).toBeDisabled();
    expect(screen.getByRole("link", { name: "Review" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Draft Report" })).toBeInTheDocument();
  });

  it("does not offer an 'edit completed inspection' control anywhere", () => {
    render(
      <InspectionWorkspace inspection={inspection} sections={sections} initialResults={[]} initialMeterReadings={[]} />,
    );

    expect(screen.queryByRole("button", { name: /edit/i })).not.toBeInTheDocument();
  });
});
