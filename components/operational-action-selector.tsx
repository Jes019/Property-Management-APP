import type { OperationalAction } from "@/lib/types";

const OPTIONS: { value: OperationalAction; label: string }[] = [
  { value: "MONITOR", label: "Monitor" },
  { value: "INCLUDED_IN_SERVICE", label: "Included in Service" },
  { value: "OWNER_APPROVAL_REQUIRED", label: "Owner Approval Required" },
];

/**
 * Deliberately a separate control from SeveritySelector — severity (what was
 * found) and operational action (what happens next) are distinct
 * classifications and must never collapse into one field.
 */
export function OperationalActionSelector({
  value,
  onChange,
  disabled,
}: {
  value: OperationalAction | null;
  onChange: (value: OperationalAction) => void;
  disabled?: boolean;
}) {
  const selectId = "operational-action";

  return (
    <div>
      <label htmlFor={selectId} className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
        Operational Action
      </label>
      <select
        id={selectId}
        value={value ?? ""}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value as OperationalAction)}
        className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm font-medium text-navy focus:border-navy focus:outline-none disabled:opacity-50"
      >
        <option value="" disabled>
          Select an action
        </option>
        {OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}
