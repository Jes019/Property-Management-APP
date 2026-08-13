CREATE TABLE public.media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  inspection_id uuid REFERENCES public.inspections (id),
  inspection_result_id uuid REFERENCES public.inspection_results (id),
  meter_reading_id uuid REFERENCES public.meter_readings (id),
  storage_bucket text NOT NULL,
  storage_path text NOT NULL,
  mime_type text,
  file_size_bytes bigint,
  created_by uuid NOT NULL REFERENCES public.profiles (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_assets_one_evidence_parent_check CHECK (
    num_nonnulls(inspection_id, inspection_result_id, meter_reading_id) = 1
  ),
  CONSTRAINT media_assets_private_bucket_check CHECK (
    storage_bucket = 'inspection-media'
  ),
  CONSTRAINT media_assets_file_size_check CHECK (
    file_size_bytes IS NULL OR file_size_bytes >= 0
  ),
  CONSTRAINT media_assets_image_mime_check CHECK (
    mime_type IS NULL OR mime_type = ANY (ARRAY[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    ]::text[])
  ),
  UNIQUE (storage_bucket, storage_path)
);

CREATE INDEX media_assets_company_id_property_id_idx
  ON public.media_assets (company_id, property_id);

CREATE INDEX media_assets_inspection_id_idx
  ON public.media_assets (inspection_id);

CREATE INDEX media_assets_inspection_result_id_idx
  ON public.media_assets (inspection_result_id);

CREATE INDEX media_assets_meter_reading_id_idx
  ON public.media_assets (meter_reading_id);

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.protect_media_asset()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  asset_company_id uuid;
  asset_property_id uuid;
  asset_inspection_id uuid;
  asset_parent_id uuid;
  asset_parent_type text;
  parent_company_id uuid;
  parent_property_id uuid;
  parent_status public.inspection_lifecycle_status;
  actor_id uuid;
  expected_prefix text;
  filename text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    asset_company_id := OLD.company_id;
    asset_property_id := OLD.property_id;

    IF OLD.inspection_id IS NOT NULL THEN
      asset_inspection_id := OLD.inspection_id;
      asset_parent_id := OLD.inspection_id;
      asset_parent_type := 'inspection';
    ELSIF OLD.inspection_result_id IS NOT NULL THEN
      SELECT result_state.inspection_id
      INTO asset_inspection_id
      FROM public.inspection_results AS result_state
      WHERE result_state.id = OLD.inspection_result_id;
      asset_parent_id := OLD.inspection_result_id;
      asset_parent_type := 'result';
    ELSE
      SELECT meter_state.inspection_id
      INTO asset_inspection_id
      FROM public.meter_readings AS meter_state
      WHERE meter_state.id = OLD.meter_reading_id;
      asset_parent_id := OLD.meter_reading_id;
      asset_parent_type := 'meter';
    END IF;
  ELSE
    asset_company_id := NEW.company_id;
    asset_property_id := NEW.property_id;

    IF NEW.inspection_id IS NOT NULL THEN
      asset_inspection_id := NEW.inspection_id;
      asset_parent_id := NEW.inspection_id;
      asset_parent_type := 'inspection';
    ELSIF NEW.inspection_result_id IS NOT NULL THEN
      SELECT result_state.inspection_id
      INTO asset_inspection_id
      FROM public.inspection_results AS result_state
      WHERE result_state.id = NEW.inspection_result_id;
      asset_parent_id := NEW.inspection_result_id;
      asset_parent_type := 'result';
    ELSE
      SELECT meter_state.inspection_id
      INTO asset_inspection_id
      FROM public.meter_readings AS meter_state
      WHERE meter_state.id = NEW.meter_reading_id;
      asset_parent_id := NEW.meter_reading_id;
      asset_parent_type := 'meter';
    END IF;
  END IF;

  SELECT
    inspection_state.company_id,
    inspection_state.property_id,
    inspection_state.status
  INTO parent_company_id, parent_property_id, parent_status
  FROM public.inspections AS inspection_state
  WHERE inspection_state.id = asset_inspection_id
  FOR SHARE OF inspection_state;

  IF parent_company_id IS NULL THEN
    RAISE EXCEPTION 'media asset requires an existing evidence parent'
      USING ERRCODE = '55000';
  END IF;

  IF asset_company_id <> parent_company_id
    OR asset_property_id <> parent_property_id
  THEN
    RAISE EXCEPTION 'media asset tenant identity must match its evidence parent'
      USING ERRCODE = '55000';
  END IF;

  IF parent_status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'media evidence can change only while its inspection is in progress'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'INSERT' THEN
    actor_id := security.current_profile_id();
    IF actor_id IS NULL THEN
      RAISE EXCEPTION 'media registration requires an authenticated profile'
        USING ERRCODE = '42501';
    END IF;

    NEW.created_by := actor_id;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id
      OR NEW.property_id IS DISTINCT FROM OLD.property_id
      OR NEW.inspection_id IS DISTINCT FROM OLD.inspection_id
      OR NEW.inspection_result_id IS DISTINCT FROM OLD.inspection_result_id
      OR NEW.meter_reading_id IS DISTINCT FROM OLD.meter_reading_id
      OR NEW.storage_bucket IS DISTINCT FROM OLD.storage_bucket
      OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
      OR NEW.created_by IS DISTINCT FROM OLD.created_by
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
      RAISE EXCEPTION 'media asset identity is immutable'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  expected_prefix :=
    NEW.company_id::text || '/' ||
    NEW.property_id::text || '/' ||
    asset_parent_type || '/' ||
    asset_parent_id::text || '/' ||
    NEW.id::text || '/';
  filename := substr(NEW.storage_path, length(expected_prefix) + 1);

  IF left(NEW.storage_path, length(expected_prefix)) <> expected_prefix
    OR filename = ''
    OR filename IN ('.', '..')
    OR position('/' IN filename) > 0
  THEN
    RAISE EXCEPTION 'media storage path must exactly match its registered parent and asset'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION security.protect_media_asset()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER media_assets_protect_runtime
BEFORE INSERT OR UPDATE OR DELETE ON public.media_assets
FOR EACH ROW
EXECUTE FUNCTION security.protect_media_asset();

CREATE FUNCTION security.can_read_inspection_media_object(
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
    WHERE asset.storage_bucket = p_bucket_id
      AND asset.storage_path = p_name
      AND p_bucket_id = 'inspection-media'
      AND security.company_has_property_scope(
        asset.company_id,
        asset.property_id,
        ARRAY[
          'FULL_MANAGEMENT',
          'INSPECTION_SERVICE'
        ]::public.property_company_relationship_scope[]
      )
      AND (
        security.has_company_role(
          asset.company_id,
          ARRAY[
            'ADMIN',
            'MANAGER',
            'COORDINATOR',
            'READ_ONLY'
          ]::public.company_role[]
        )
        OR (
          security.has_company_role(
            asset.company_id,
            ARRAY['INSPECTOR']::public.company_role[]
          )
          AND security.is_assigned_to_property(
            asset.company_id,
            asset.property_id
          )
        )
      )
  );
$$;

CREATE FUNCTION security.can_mutate_inspection_media_object(
  p_bucket_id text,
  p_name text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  asset_state record;
  parent_status public.inspection_lifecycle_status;
BEGIN
  SELECT
    asset.company_id,
    asset.property_id,
    COALESCE(
      asset.inspection_id,
      result_state.inspection_id,
      meter_state.inspection_id
    ) AS inspection_id
  INTO asset_state
    FROM public.media_assets AS asset
    LEFT JOIN public.inspection_results AS result_state
      ON result_state.id = asset.inspection_result_id
    LEFT JOIN public.meter_readings AS meter_state
      ON meter_state.id = asset.meter_reading_id
    WHERE asset.storage_bucket = p_bucket_id
      AND asset.storage_path = p_name
      AND p_bucket_id = 'inspection-media';

  IF asset_state.inspection_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT inspection_state.status
  INTO parent_status
  FROM public.inspections AS inspection_state
  WHERE inspection_state.id = asset_state.inspection_id
  FOR SHARE OF inspection_state;

  RETURN parent_status = 'IN_PROGRESS'
    AND security.company_has_property_scope(
      asset_state.company_id,
      asset_state.property_id,
      ARRAY[
        'FULL_MANAGEMENT',
        'INSPECTION_SERVICE'
      ]::public.property_company_relationship_scope[]
    )
    AND (
      security.has_company_role(
        asset_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
      OR (
        security.has_company_role(
          asset_state.company_id,
          ARRAY['INSPECTOR']::public.company_role[]
        )
        AND security.is_assigned_to_property(
          asset_state.company_id,
          asset_state.property_id
        )
      )
    );
END;
$$;

REVOKE ALL ON FUNCTION security.can_read_inspection_media_object(text, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION security.can_mutate_inspection_media_object(text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION security.can_read_inspection_media_object(text, text)
  TO authenticated;
GRANT EXECUTE
  ON FUNCTION security.can_mutate_inspection_media_object(text, text)
  TO authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.media_assets
  FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, DELETE
  ON TABLE public.media_assets
  TO authenticated;

CREATE POLICY media_assets_company_select
ON public.media_assets
FOR SELECT
TO authenticated
USING (
  security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND (
    security.has_company_role(
      company_id,
      ARRAY[
        'ADMIN',
        'MANAGER',
        'COORDINATOR',
        'READ_ONLY'
      ]::public.company_role[]
    )
    OR (
      security.has_company_role(
        company_id,
        ARRAY['INSPECTOR']::public.company_role[]
      )
      AND security.is_assigned_to_property(company_id, property_id)
    )
  )
);

CREATE POLICY media_assets_operational_insert
ON public.media_assets
FOR INSERT
TO authenticated
WITH CHECK (
  security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND (
    security.has_company_role(
      company_id,
      ARRAY['ADMIN', 'MANAGER']::public.company_role[]
    )
    OR (
      security.has_company_role(
        company_id,
        ARRAY['INSPECTOR']::public.company_role[]
      )
      AND security.is_assigned_to_property(company_id, property_id)
    )
  )
);

CREATE POLICY media_assets_operational_delete
ON public.media_assets
FOR DELETE
TO authenticated
USING (
  security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND (
    security.has_company_role(
      company_id,
      ARRAY['ADMIN', 'MANAGER']::public.company_role[]
    )
    OR (
      security.has_company_role(
        company_id,
        ARRAY['INSPECTOR']::public.company_role[]
      )
      AND security.is_assigned_to_property(company_id, property_id)
    )
  )
);

INSERT INTO storage.buckets (id, name, public, allowed_mime_types)
VALUES (
  'inspection-media',
  'inspection-media',
  false,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
);

CREATE POLICY inspection_media_objects_select
ON storage.objects
FOR SELECT
TO authenticated
USING (
  security.can_read_inspection_media_object(bucket_id, name)
);

CREATE POLICY inspection_media_objects_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  security.can_mutate_inspection_media_object(bucket_id, name)
);

CREATE POLICY inspection_media_objects_update
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  security.can_mutate_inspection_media_object(bucket_id, name)
)
WITH CHECK (
  security.can_mutate_inspection_media_object(bucket_id, name)
);

CREATE POLICY inspection_media_objects_delete
ON storage.objects
FOR DELETE
TO authenticated
USING (
  security.can_mutate_inspection_media_object(bucket_id, name)
);
