import { describe, expect, it, vi } from "vitest";

import { isOwner } from "@/lib/data/session";

describe("isOwner", () => {
  it("is true when property_owners returns at least one row for the caller (RLS-scoped)", async () => {
    const query: Record<string, unknown> = {};
    query.select = vi.fn(() => query);
    query.limit = vi.fn(() => Promise.resolve({ data: [{ property_id: "p1" }], error: null }));
    const supabase = { from: vi.fn(() => query) } as never;

    await expect(isOwner(supabase)).resolves.toBe(true);
    expect(query.select).toHaveBeenCalledWith("property_id");
  });

  it("is false when property_owners returns no rows — never touches company_memberships", async () => {
    const query: Record<string, unknown> = {};
    query.select = vi.fn(() => query);
    query.limit = vi.fn(() => Promise.resolve({ data: [], error: null }));
    const from = vi.fn(() => query);
    const supabase = { from } as never;

    await expect(isOwner(supabase)).resolves.toBe(false);
    expect(from).toHaveBeenCalledWith("property_owners");
    expect(from).not.toHaveBeenCalledWith("company_memberships");
  });
});
