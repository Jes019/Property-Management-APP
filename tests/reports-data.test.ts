import { describe, expect, it, vi } from "vitest";

import { listOwnerReportMedia, listVisibleReports, publishReport } from "@/lib/data/reports";

function makeSelectQuery(result: { data: unknown[]; error: null }) {
  const query: Record<string, unknown> = {};
  query.select = vi.fn(() => query);
  query.order = vi.fn(() => Promise.resolve(result));
  return query;
}

describe("owner-facing report data access", () => {
  it("listOwnerReportMedia calls the Task 12 owner_report_media RPC, never a raw media_assets select", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    const supabase = { rpc, from: vi.fn() } as never;

    await listOwnerReportMedia(supabase, "report-1");

    expect(rpc).toHaveBeenCalledWith("owner_report_media", { p_report_version_id: "report-1" });
    expect((supabase as { from: ReturnType<typeof vi.fn> }).from).not.toHaveBeenCalled();
  });

  it("listVisibleReports adds no status/company filter of its own — RLS alone decides what comes back", async () => {
    const query = makeSelectQuery({ data: [], error: null });
    const from = vi.fn(() => query);
    const supabase = { from } as never;

    await listVisibleReports(supabase);

    expect(from).toHaveBeenCalledWith("inspection_report_versions");
    expect(query.select).toHaveBeenCalledWith(expect.stringContaining("status"));
    // No .eq() call exists on this stub at all — if the implementation added
    // a client-side status/company filter it would call a method this stub
    // doesn't provide, and the test would throw instead of resolving.
  });

  it("publishReport invokes the controlled RPC rather than updating the table directly", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { id: "report-1", status: "FINAL" }, error: null });
    const from = vi.fn();
    const supabase = { rpc, from } as never;

    await publishReport(supabase, "report-1");

    expect(rpc).toHaveBeenCalledWith("publish_inspection_report", { p_report_id: "report-1" });
    expect(from).not.toHaveBeenCalled();
  });
});
