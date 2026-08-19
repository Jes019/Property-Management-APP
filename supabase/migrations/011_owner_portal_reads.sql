CREATE FUNCTION security.report_media_id_texts(p_content jsonb)
RETURNS SETOF text
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
  SELECT lower(media_ref.media_id_text)
  FROM jsonb_array_elements_text(
    CASE
      WHEN jsonb_typeof(p_content -> 'media') = 'array'
        THEN p_content -> 'media'
      ELSE '[]'::jsonb
    END
  ) AS media_ref(media_id_text);
$$;

REVOKE ALL ON FUNCTION security.report_media_id_texts(jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE FUNCTION security.owner_can_view_report(p_report_version_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.inspection_report_versions AS report
    WHERE report.id = p_report_version_id
      AND report.status = 'FINAL'
      AND security.is_property_owner(report.property_id)
  );
$$;

CREATE FUNCTION security.owner_can_view_media(
  p_bucket_id text,
  p_name text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.media_assets AS asset
    LEFT JOIN public.inspection_results AS result_state
      ON result_state.id = asset.inspection_result_id
    LEFT JOIN public.meter_readings AS meter_state
      ON meter_state.id = asset.meter_reading_id
    JOIN public.inspection_report_versions AS report
      ON report.property_id = asset.property_id
     AND report.inspection_id = COALESCE(
           asset.inspection_id,
           result_state.inspection_id,
           meter_state.inspection_id
         )
     AND report.status = 'FINAL'
    WHERE asset.storage_bucket = p_bucket_id
      AND asset.storage_path = p_name
      AND p_bucket_id = 'inspection-media'
      AND security.is_property_owner(asset.property_id)
      AND lower(asset.id::text) IN (
        SELECT security.report_media_id_texts(report.content)
      )
  );
$$;

REVOKE ALL ON FUNCTION security.owner_can_view_report(uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION security.owner_can_view_media(text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION security.owner_can_view_report(uuid)
  TO authenticated;
GRANT EXECUTE
  ON FUNCTION security.owner_can_view_media(text, text)
  TO authenticated;

CREATE POLICY inspection_report_versions_owner_select
ON public.inspection_report_versions
FOR SELECT
TO authenticated
USING (
  security.owner_can_view_report(id)
);

CREATE POLICY inspection_media_objects_owner_select
ON storage.objects
FOR SELECT
TO authenticated
USING (
  security.owner_can_view_media(bucket_id, name)
);

CREATE FUNCTION public.owner_report_media(p_report_version_id uuid)
RETURNS TABLE (
  media_id uuid,
  storage_bucket text,
  storage_path text,
  mime_type text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT
    asset.id,
    asset.storage_bucket,
    asset.storage_path,
    asset.mime_type
  FROM public.inspection_report_versions AS report
  JOIN public.media_assets AS asset
    ON lower(asset.id::text) IN (
      SELECT security.report_media_id_texts(report.content)
    )
   AND asset.property_id = report.property_id
  WHERE report.id = p_report_version_id
    AND report.status = 'FINAL'
    AND security.is_property_owner(report.property_id);
$$;

REVOKE ALL ON FUNCTION public.owner_report_media(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.owner_report_media(uuid)
  TO authenticated;
