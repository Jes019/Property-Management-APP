import type { InspectionSeverity } from "@/lib/types";

const OPTIONS: { value: InspectionSeverity; label: string; toneClass: string }[] = [
  { value: "PASS", label: "Pass", toneClass: "data-[selected=true]:bg-good data-[selected=true]:text-white" },
  {
    value: "ATTENTION",
    label: "Attention",
    toneClass: "data-[selected=true]:bg-attention-dot data-[selected=true]:text-white",
  },
  { value: "URGENT", label: "Urgent", toneClass: "data-[selected=true]:bg-urgent data-[selected=true]:text-white" },
];

export function SeveritySelector({
  value,
  onChange,
  disabled,
}: {
  value: InspectionSeverity | null;
  onChange: (value: InspectionSeverity) => void;
  disabled?: boolean;
}) {
  return (
    <fieldset>
      <legend className="mb-1 text-[10px] font-bold uppercase tracking-widest text-navy/50">
        Severity
      </legend>
      <div role="radiogroup" aria-label="Severity" className="flex gap-2">
        {OPTIONS.map((option) => (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={value === option.value}
            data-selected={value === option.value}
            disabled={disabled}
            onClick={() => onChange(option.value)}
            className={`min-h-[44px] flex-1 rounded-lg border border-border px-3 py-2 text-sm font-semibold text-navy disabled:opacity-50 ${option.toneClass}`}
          >
            {option.label}
          </button>
        ))}
      </div>
    </fieldset>
  );
}
