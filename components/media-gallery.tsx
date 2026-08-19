"use client";

import Image from "next/image";
import { useEffect, useState } from "react";

import { IconCamera } from "@/components/icons";
import { getEvidenceSignedUrl, listInspectionMedia, registerAndUploadEvidence } from "@/lib/data/media";
import { createClient } from "@/lib/supabase/client";
import type { MediaAsset } from "@/lib/types";

interface DisplayedMedia {
  asset: MediaAsset;
  url: string | null;
}

export function MediaGallery({
  inspectionId,
  companyId,
  propertyId,
  readOnly,
}: {
  inspectionId: string;
  companyId: string;
  propertyId: string;
  readOnly: boolean;
}) {
  const [media, setMedia] = useState<DisplayedMedia[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const supabase = createClient();
      try {
        const assets = await listInspectionMedia(supabase, inspectionId);
        const withUrls = await Promise.all(
          assets.map(async (asset) => ({
            asset,
            url: await getEvidenceSignedUrl(supabase, asset.storage_path).catch(() => null),
          })),
        );
        if (!cancelled) setMedia(withUrls);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [inspectionId]);

  async function handleFileSelected(file: File) {
    setError(null);
    setUploading(true);
    try {
      const supabase = createClient();
      const asset = await registerAndUploadEvidence(supabase, {
        companyId,
        propertyId,
        inspectionId,
        file,
      });
      const url = await getEvidenceSignedUrl(supabase, asset.storage_path).catch(() => null);
      setMedia((current) => [{ asset, url }, ...current]);
    } catch {
      setError("Could not upload this photo. Try again.");
    } finally {
      setUploading(false);
    }
  }

  return (
    <section className="space-y-3">
      <h2 className="text-lg font-bold">Evidence</h2>

      {loading ? <p className="text-sm text-navy/50">Loading evidence…</p> : null}

      <div className="grid grid-cols-3 gap-2">
        {media.map(({ asset, url }) =>
          url ? (
            <div key={asset.id} className="relative aspect-square overflow-hidden rounded-lg border border-border">
              <Image src={url} alt="Inspection evidence" fill sizes="120px" className="object-cover" unoptimized />
            </div>
          ) : (
            <div
              key={asset.id}
              className="flex aspect-square items-center justify-center rounded-lg border border-border bg-border/20 text-xs text-navy/50"
            >
              Unavailable
            </div>
          ),
        )}
      </div>

      {!readOnly ? (
        <label className="flex min-h-[48px] w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-border bg-white text-sm font-semibold text-navy">
          <IconCamera className="h-5 w-5" />
          {uploading ? "Uploading…" : "Add Photo"}
          <input
            type="file"
            accept="image/*"
            className="sr-only"
            disabled={uploading}
            onChange={(event) => {
              const file = event.target.files?.[0];
              event.target.value = "";
              if (file) void handleFileSelected(file);
            }}
          />
        </label>
      ) : null}

      {error ? (
        <p role="alert" className="text-xs font-semibold text-urgent">
          {error}
        </p>
      ) : null}
    </section>
  );
}
