import { describe, expect, it, vi } from "vitest";

import { getLatestFrozenVersion, getTemplateSections } from "@/lib/data/templates";

/** Minimal chainable query-builder stub matching the calls getTemplateSections makes. */
function makeQuery(result: { data: unknown[]; error: null }) {
  const query: Record<string, unknown> = {};
  query.select = vi.fn(() => query);
  query.eq = vi.fn(() => query);
  query.in = vi.fn(() => query);
  query.order = vi.fn(() => Promise.resolve(result));
  return query;
}

describe("getLatestFrozenVersion", () => {
  it("never filters on is_current — Task 7's own trigger forbids a version being both current and frozen", async () => {
    const query: Record<string, unknown> = {};
    query.select = vi.fn(() => query);
    query.eq = vi.fn(() => query);
    query.not = vi.fn(() => query);
    query.order = vi.fn(() => query);
    query.limit = vi.fn(() => query);
    query.maybeSingle = vi.fn(() =>
      Promise.resolve({
        data: { id: "v1", template_id: "t1", version_number: 2, frozen_at: "2026-01-01T00:00:00Z" },
        error: null,
      }),
    );

    const from = vi.fn(() => query);
    const supabase = { from } as never;

    const version = await getLatestFrozenVersion(supabase, "t1");

    expect(query.eq).not.toHaveBeenCalledWith("is_current", true);
    expect(query.not).toHaveBeenCalledWith("frozen_at", "is", null);
    expect(version).toEqual({ id: "v1", template_id: "t1", version_number: 2, frozen_at: "2026-01-01T00:00:00Z" });
  });
});

describe("getTemplateSections", () => {
  it("requests sections and items ordered by sort_order, the source of truth for display order", async () => {
    const sectionsQuery = makeQuery({
      data: [{ id: "s1", version_id: "v1", title: "Exterior", sort_order: 1 }],
      error: null,
    });
    const itemsQuery = makeQuery({
      data: [{ id: "i1", section_id: "s1", label: "Facade", sort_order: 1 }],
      error: null,
    });

    const from = vi.fn((table: string) =>
      table === "inspection_template_sections" ? sectionsQuery : itemsQuery,
    );

    const supabase = { from } as never;

    const sections = await getTemplateSections(supabase, "v1");

    expect(sectionsQuery.order).toHaveBeenCalledWith("sort_order", { ascending: true });
    expect(itemsQuery.order).toHaveBeenCalledWith("sort_order", { ascending: true });
    expect(sections).toEqual([
      { id: "s1", version_id: "v1", title: "Exterior", sort_order: 1, items: [{ id: "i1", section_id: "s1", label: "Facade", sort_order: 1 }] },
    ]);
  });
});
