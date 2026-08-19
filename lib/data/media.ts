import type { SupabaseClient } from "@supabase/supabase-js";

import type { MediaAsset } from "@/lib/types";

const MEDIA_COLUMNS =
  "id, company_id, property_id, inspection_id, inspection_result_id, meter_reading_id, storage_bucket, storage_path, mime_type, file_size_bytes, created_at";

const BUCKET = "inspection-media";

/** Matches the exact path shape Task 10's protect_media_asset trigger requires. */
function buildEvidencePath(
  companyId: string,
  propertyId: string,
  inspectionId: string,
  assetId: string,
  filename: string,
): string {
  return `${companyId}/${propertyId}/inspection/${inspectionId}/${assetId}/${filename}`;
}

export async function listInspectionMedia(
  supabase: SupabaseClient,
  inspectionId: string,
): Promise<MediaAsset[]> {
  const { data, error } = await supabase
    .from("media_assets")
    .select(MEDIA_COLUMNS)
    .eq("inspection_id", inspectionId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []) as MediaAsset[];
}

/**
 * Registers the media_assets row first, then uploads to the exact path it
 * declares — the order Task 10's RLS requires (storage upload is only
 * authorized once a matching row already exists).
 */
export async function registerAndUploadEvidence(
  supabase: SupabaseClient,
  params: {
    companyId: string;
    propertyId: string;
    inspectionId: string;
    file: File;
  },
): Promise<MediaAsset> {
  const assetId = crypto.randomUUID();
  const storagePath = buildEvidencePath(
    params.companyId,
    params.propertyId,
    params.inspectionId,
    assetId,
    params.file.name,
  );

  const { data: asset, error: insertError } = await supabase
    .from("media_assets")
    .insert({
      id: assetId,
      company_id: params.companyId,
      property_id: params.propertyId,
      inspection_id: params.inspectionId,
      storage_bucket: BUCKET,
      storage_path: storagePath,
      mime_type: params.file.type || null,
      file_size_bytes: params.file.size,
    })
    .select(MEDIA_COLUMNS)
    .single();

  if (insertError) throw insertError;

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(storagePath, params.file, { contentType: params.file.type || undefined });

  if (uploadError) {
    // Registration succeeded but the file never landed — remove the orphan
    // row while the inspection is still in progress (RLS permits it then).
    await supabase.from("media_assets").delete().eq("id", assetId);
    throw uploadError;
  }

  return asset as MediaAsset;
}

export async function getEvidenceSignedUrl(
  supabase: SupabaseClient,
  storagePath: string,
): Promise<string> {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(storagePath, 60 * 10);

  if (error) throw error;
  return data.signedUrl;
}
