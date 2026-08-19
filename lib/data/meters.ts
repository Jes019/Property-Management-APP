import type { SupabaseClient } from "@supabase/supabase-js";

import type { MeterReading, MeterType } from "@/lib/types";

const METER_COLUMNS = "id, inspection_id, meter_type, reading_value, unit, recorded_at";

export async function listMeterReadings(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<MeterReading[]> {
  const { data, error } = await supabase
    .from("meter_readings")
    .select(METER_COLUMNS)
    .eq("inspection_id", inspectionId)
    .order("recorded_at", { ascending: true });

  if (error) throw error;
  return (data ?? []) as MeterReading[];
}

/** One property may carry more than one reading per meter type over time — this always appends. */
export async function addMeterReading(
  supabase: SupabaseClient,
  params: {
    companyId: string;
    propertyId: string;
    inspectionId: string;
    meterType: MeterType;
    readingValue: number;
    unit: string;
  },
): Promise<MeterReading> {
  const { data, error } = await supabase
    .from("meter_readings")
    .insert({
      company_id: params.companyId,
      property_id: params.propertyId,
      inspection_id: params.inspectionId,
      meter_type: params.meterType,
      reading_value: params.readingValue,
      unit: params.unit,
    })
    .select(METER_COLUMNS)
    .single();

  if (error) throw error;
  return data as MeterReading;
}
