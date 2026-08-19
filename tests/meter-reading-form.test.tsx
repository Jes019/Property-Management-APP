import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { MeterReadingForm } from "@/components/meter-reading-form";

describe("MeterReadingForm", () => {
  it("supports both ELECTRICITY and WATER meter types", () => {
    render(<MeterReadingForm readings={[]} readOnly={false} onAdd={vi.fn()} />);

    const options = screen.getAllByRole("option").map((option) => option.textContent);
    expect(options).toEqual(["Electricity", "Water"]);
  });

  it("submits a real numeric reading for the selected meter type", async () => {
    const user = userEvent.setup();
    const onAdd = vi.fn().mockResolvedValue(undefined);

    render(<MeterReadingForm readings={[]} readOnly={false} onAdd={onAdd} />);

    await user.selectOptions(screen.getByLabelText(/Meter$/), "WATER");
    await user.type(screen.getByLabelText(/Reading/), "42.5");
    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(onAdd).toHaveBeenCalledWith("WATER", 42.5);
  });

  it("rejects a non-numeric reading client-side without calling onAdd", async () => {
    const user = userEvent.setup();
    const onAdd = vi.fn();

    render(<MeterReadingForm readings={[]} readOnly={false} onAdd={onAdd} />);

    await user.type(screen.getByLabelText(/Reading/), "not-a-number");
    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(onAdd).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent("Enter a valid numeric reading.");
  });

  it("hides the add form once the inspection is read-only", () => {
    render(<MeterReadingForm readings={[]} readOnly onAdd={vi.fn()} />);

    expect(screen.queryByRole("button", { name: "Add" })).not.toBeInTheDocument();
  });

  it("lists existing readings", () => {
    render(
      <MeterReadingForm
        readings={[
          { id: "m1", inspection_id: "i1", meter_type: "ELECTRICITY", reading_value: 100, unit: "kWh", recorded_at: "2026-01-01T00:00:00Z" },
        ]}
        readOnly
        onAdd={vi.fn()}
      />,
    );

    expect(screen.getByText("ELECTRICITY")).toBeInTheDocument();
    expect(screen.getByText("100 kWh")).toBeInTheDocument();
  });
});
