import type { InspectionSeverity } from "@/lib/types";

const SEVERITY_STYLE: Record<InspectionSeverity, string> = {
  PASS: "bg-good-bg text-good",
  ATTENTION: "bg-attention-bg text-attention",
  URGENT: "bg-urgent-bg text-urgent",
};

const SEVERITY_LABEL: Record<InspectionSeverity, string> = {
  PASS: "Pass",
  ATTENTION: "Attention Required",
  URGENT: "Urgent",
};

/** Text label is the status carrier — color is decoration only, never the sole signal. */
export function SeverityPill({ severity }: { severity: InspectionSeverity }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-wider ${SEVERITY_STYLE[severity]}`}
    >
      {SEVERITY_LABEL[severity]}
    </span>
  );
}

export function StatusPill({ label, tone }: { label: string; tone: "good" | "attention" | "urgent" | "neutral" }) {
  const toneClass =
    tone === "good"
      ? "bg-good-bg text-good"
      : tone === "attention"
        ? "bg-attention-bg text-attention"
        : tone === "urgent"
          ? "bg-urgent-bg text-urgent"
          : "bg-border/40 text-navy";

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-wider ${toneClass}`}
    >
      {label}
    </span>
  );
}
