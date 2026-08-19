import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ChecklistItemEditor } from "@/components/checklist-item-editor";
import type { InspectionTemplateItem } from "@/lib/types";

const item: InspectionTemplateItem = { id: "item-1", section_id: "section-1", label: "Roof", sort_order: 1 };

describe("ChecklistItemEditor", () => {
  it("keeps severity and operational action as separate controls that don't affect each other", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);

    render(<ChecklistItemEditor item={item} result={null} readOnly={false} onSave={onSave} />);

    await user.click(screen.getByRole("radio", { name: "Urgent" }));
    await user.selectOptions(screen.getByLabelText("Operational Action"), "OWNER_APPROVAL_REQUIRED");

    // Selecting severity must not have silently picked an operational action, and vice versa.
    expect(onSave).toHaveBeenLastCalledWith({
      severity: "URGENT",
      operationalAction: "OWNER_APPROVAL_REQUIRED",
      comment: null,
    });
    expect(screen.getByRole("radio", { name: "Urgent" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("radio", { name: "Pass" })).toHaveAttribute("aria-checked", "false");
  });

  it("does not save until both severity and operational action are chosen", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);

    render(<ChecklistItemEditor item={item} result={null} readOnly={false} onSave={onSave} />);

    await user.click(screen.getByRole("radio", { name: "Pass" }));

    expect(onSave).not.toHaveBeenCalled();
  });

  it("surfaces a save failure instead of silently succeeding (fails closed)", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockRejectedValue(new Error("permission denied"));

    render(<ChecklistItemEditor item={item} result={null} readOnly={false} onSave={onSave} />);

    await user.click(screen.getByRole("radio", { name: "Pass" }));
    await user.selectOptions(screen.getByLabelText("Operational Action"), "MONITOR");

    expect(await screen.findByRole("alert")).toHaveTextContent("Could not save this result.");
  });

  it("disables all controls in read-only mode (completed inspection)", () => {
    render(
      <ChecklistItemEditor
        item={item}
        result={{ id: "r1", inspection_id: "insp-1", template_item_id: "item-1", severity: "PASS", operational_action: "MONITOR", comment: null }}
        readOnly
        onSave={vi.fn()}
      />,
    );

    expect(screen.getByRole("radio", { name: "Pass" })).toBeDisabled();
    expect(screen.getByLabelText("Operational Action")).toBeDisabled();
    expect(screen.getByLabelText("Comment")).toBeDisabled();
  });
});
