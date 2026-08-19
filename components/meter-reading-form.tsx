"use client";

import { useState, type FormEvent } from "react";

import type { MeterReading, MeterType } from "@/lib/types";

const METER_UNITS: Record<MeterType, string> = {
  ELECTRICITY: "kWh",
  WATER: "m3",
};

export function MeterReadingForm({
  readings,
  readOnly,
  onAdd,
}: {
  readings: MeterReading[];
  readOnly: boolean;
  onAdd: (meterType: MeterType, value: number) => Promise<void>;
}) {
  const [meterType, setMeterType] = useState<MeterType>("ELECTRICITY");
  const [rawValue, setRawValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    const parsed = Number(rawValue);
    if (rawValue.trim() === "" || Number.isNaN(parsed)) {
      setError("Enter a valid numeric reading.");
      return;
    }

    setSubmitting(true);
    try {
      await onAdd(meterType, parsed);
      setRawValue("");
    } catch {
      setError("Could not save this reading.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="space-y-3">
      <h2 className="text-lg font-bold">Meter Readings</h2>

      <ul className="space-y-2">
        {readings.map((reading) => (
          <li
            key={reading.id}
            className="flex items-center justify-between rounded-xl border border-border bg-white px-4 py-3 text-sm"
          >
            <span className="font-semibold">{reading.meter_type}</span>
            <span>
              {reading.reading_value} {reading.unit}
            </span>
          </li>
        ))}
        {readings.length === 0 ? <li className="text-sm text-navy/50">No meter readings yet.</li> : null}
      </ul>

      {!readOnly ? (
        <form onSubmit={handleSubmit} className="flex items-end gap-3 rounded-xl border border-border bg-white p-4">
          <div>
            <label htmlFor="meter-type" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Meter
            </label>
            <select
              id="meter-type"
              value={meterType}
              onChange={(event) => setMeterType(event.target.value as MeterType)}
              className="min-h-[44px] rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm"
            >
              <option value="ELECTRICITY">Electricity</option>
              <option value="WATER">Water</option>
            </select>
          </div>
          <div className="flex-1">
            <label htmlFor="meter-value" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Reading ({METER_UNITS[meterType]})
            </label>
            <input
              id="meter-value"
              type="text"
              inputMode="decimal"
              value={rawValue}
              onChange={(event) => setRawValue(event.target.value)}
              className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm"
            />
          </div>
          <button
            type="submit"
            disabled={submitting}
            className="min-h-[44px] rounded-lg bg-navy px-4 py-2 text-sm font-bold text-white disabled:opacity-50"
          >
            Add
          </button>
        </form>
      ) : null}
      {error ? (
        <p role="alert" className="text-xs font-semibold text-urgent">
          {error}
        </p>
      ) : null}
    </section>
  );
}
