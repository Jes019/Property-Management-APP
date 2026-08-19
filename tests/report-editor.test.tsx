import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({}) }));

const { mediaAssets, updateDraftReport, publishReport } = vi.hoisted(() => {
  const mediaAssets = [
    {
      id: "media-1",
      company_id: "company-1",
      property_id: "property-1",
      inspection_id: "insp-1",
      inspection_result_id: null,
      meter_reading_id: null,
      storage_bucket: "inspection-media",
      storage_path: "path/media-1.jpg",
      mime_type: "image/jpeg",
      file_size_bytes: 100,
      created_at: "2026-01-01T00:00:00Z",
    },
  ];

  const updateDraftReport = vi.fn().mockImplementation(
    (_supabase: unknown, id: string, params: { title: string; summary: string | null; content: { media: string[] } }) =>
      Promise.resolve({
        id,
        company_id: "company-1",
        property_id: "property-1",
        inspection_id: "insp-1",
        version_number: 1,
        status: "DRAFT",
        title: params.title,
        summary: params.summary,
        content: params.content,
        created_by: "profile-1",
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-01T00:00:00Z",
        published_at: null,
        published_by: null,
      }),
  );

  const publishReport = vi.fn().mockResolvedValue({
    id: "report-1",
    company_id: "company-1",
    property_id: "property-1",
    inspection_id: "insp-1",
    version_number: 1,
    status: "FINAL",
    title: "Inspection Report",
    summary: null,
    content: { media: ["media-1"] },
    created_by: "profile-1",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    published_at: "2026-01-02T00:00:00Z",
    published_by: "profile-1",
  });

  return { mediaAssets, updateDraftReport, publishReport };
});

vi.mock("@/lib/data/media", () => ({
  listInspectionMedia: vi.fn().mockResolvedValue(mediaAssets),
  getEvidenceSignedUrl: vi.fn().mockResolvedValue("https://example.test/media-1.jpg"),
}));

vi.mock("@/lib/data/reports", () => ({
  createDraftReport: vi.fn(),
  updateDraftReport,
  publishReport,
}));

import { ReportEditor } from "@/components/report-editor";
import type { Inspection, ReportVersion } from "@/lib/types";

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

const draftReport: ReportVersion = {
  id: "report-1",
  company_id: "company-1",
  property_id: "property-1",
  inspection_id: "insp-1",
  version_number: 1,
  status: "DRAFT",
  title: "Inspection Report",
  summary: null,
  content: { media: [] },
  created_by: "profile-1",
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
  published_at: null,
  published_by: null,
};

describe("ReportEditor", () => {
  it("builds content.media from explicit checkbox selection, not automatically from all evidence", async () => {
    const user = userEvent.setup();
    render(<ReportEditor inspection={inspection} initialReports={[draftReport]} />);

    await screen.findByLabelText(/Include evidence media-1/);
    await user.click(screen.getByLabelText(/Include evidence media-1/));
    await user.click(screen.getByRole("button", { name: "Save Draft" }));

    await waitFor(() =>
      expect(updateDraftReport).toHaveBeenCalledWith(
        {},
        "report-1",
        expect.objectContaining({ content: expect.objectContaining({ media: ["media-1"] }) }),
      ),
    );
  });

  it("never selects media automatically — an untouched draft saves with an empty media list", async () => {
    const user = userEvent.setup();
    render(<ReportEditor inspection={inspection} initialReports={[draftReport]} />);

    await screen.findByLabelText(/Include evidence media-1/);
    await user.click(screen.getByRole("button", { name: "Save Draft" }));

    await waitFor(() =>
      expect(updateDraftReport).toHaveBeenCalledWith(
        {},
        "report-1",
        expect.objectContaining({ content: expect.objectContaining({ media: [] }) }),
      ),
    );
  });

  it("publishing calls the controlled publish_inspection_report RPC wrapper with the report id", async () => {
    const user = userEvent.setup();
    render(<ReportEditor inspection={inspection} initialReports={[draftReport]} />);

    await screen.findByLabelText(/Include evidence media-1/);
    await user.click(screen.getByRole("button", { name: "Publish FINAL" }));

    await waitFor(() => expect(publishReport).toHaveBeenCalledWith({}, "report-1"));
    expect(await screen.findByRole("status")).toHaveTextContent("Report v1 published.");
  });

  it("shows a clear failure state when publish is rejected, not a false success", async () => {
    publishReport.mockRejectedValueOnce(new Error("inspection must be completed"));
    const user = userEvent.setup();
    render(<ReportEditor inspection={inspection} initialReports={[draftReport]} />);

    await screen.findByLabelText(/Include evidence media-1/);
    await user.click(screen.getByRole("button", { name: "Publish FINAL" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Could not publish this report");
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });
});
