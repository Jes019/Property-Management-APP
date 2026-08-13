CREATE TYPE public.meter_type AS ENUM (
  'ELECTRICITY',
  'WATER'
);

CREATE TABLE public.inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  template_version_id uuid NOT NULL
    REFERENCES public.inspection_template_versions (id),
  status public.inspection_lifecycle_status NOT NULL DEFAULT 'SCHEDULED',
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid NOT NULL REFERENCES public.profiles (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.inspection_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  inspection_id uuid NOT NULL
    REFERENCES public.inspections (id) ON DELETE CASCADE,
  template_item_id uuid NOT NULL
    REFERENCES public.inspection_template_items (id),
  severity public.inspection_severity NOT NULL,
  operational_action public.operational_action NOT NULL,
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (inspection_id, template_item_id)
);

CREATE TABLE public.inspection_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id uuid NOT NULL REFERENCES public.inspections (id),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  changed_by uuid NOT NULL REFERENCES public.profiles (id),
  change_type text NOT NULL CHECK (
    change_type IN ('STARTED', 'RESULT_CHANGED', 'COMPLETED')
  ),
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.meter_readings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  inspection_id uuid NOT NULL REFERENCES public.inspections (id),
  meter_type public.meter_type NOT NULL,
  reading_value numeric NOT NULL,
  unit text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorded_by uuid NOT NULL REFERENCES public.profiles (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meter_readings_finite_value_check CHECK (
    reading_value NOT IN (
      'NaN'::numeric,
      'Infinity'::numeric,
      '-Infinity'::numeric
    )
  )
);

CREATE INDEX inspections_company_id_property_id_status_idx
  ON public.inspections (company_id, property_id, status);

CREATE INDEX inspections_property_id_scheduled_at_idx
  ON public.inspections (property_id, scheduled_at);

CREATE INDEX inspection_results_company_id_property_id_idx
  ON public.inspection_results (company_id, property_id);

CREATE INDEX meter_readings_inspection_id_meter_type_idx
  ON public.meter_readings (inspection_id, meter_type);

CREATE INDEX meter_readings_company_id_property_id_idx
  ON public.meter_readings (company_id, property_id);

CREATE INDEX inspection_changes_inspection_id_created_at_idx
  ON public.inspection_changes (inspection_id, created_at);

ALTER TABLE public.inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_readings ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.protect_inspection_runtime()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  qualifying_relationship_id uuid;
  template_company_id uuid;
  template_frozen_at timestamptz;
BEGIN
  IF TG_OP = 'INSERT' THEN
    actor_id := security.current_profile_id();
    IF actor_id IS NULL THEN
      RAISE EXCEPTION 'inspection creation requires an authenticated profile'
        USING ERRCODE = '42501';
    END IF;

    NEW.created_by := actor_id;

    IF NEW.status <> 'SCHEDULED' THEN
      RAISE EXCEPTION 'inspections must be created as scheduled'
        USING ERRCODE = '55000';
    END IF;

    NEW.started_at := NULL;
    NEW.completed_at := NULL;
  ELSE
    IF OLD.status = 'COMPLETED' THEN
      RAISE EXCEPTION 'completed inspections are immutable'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.company_id IS DISTINCT FROM OLD.company_id
      OR NEW.property_id IS DISTINCT FROM OLD.property_id
      OR NEW.created_by IS DISTINCT FROM OLD.created_by
    THEN
      RAISE EXCEPTION 'inspection company, property, and creator are immutable'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.template_version_id IS DISTINCT FROM OLD.template_version_id THEN
      IF OLD.status <> 'SCHEDULED' OR NEW.status <> 'SCHEDULED' THEN
        RAISE EXCEPTION 'template version can change only while scheduled'
          USING ERRCODE = '55000';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.inspection_results AS result_state
        WHERE result_state.inspection_id = OLD.id
      ) OR EXISTS (
        SELECT 1
        FROM public.meter_readings AS meter_state
        WHERE meter_state.inspection_id = OLD.id
      ) THEN
        RAISE EXCEPTION 'template version cannot change after evidence exists'
          USING ERRCODE = '55000';
      END IF;
    END IF;

    IF NEW.status = OLD.status THEN
      NEW.started_at := OLD.started_at;
      NEW.completed_at := OLD.completed_at;
    ELSIF OLD.status = 'SCHEDULED' AND NEW.status = 'IN_PROGRESS' THEN
      NEW.started_at := clock_timestamp();
      NEW.completed_at := NULL;
    ELSIF OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED' THEN
      NEW.started_at := OLD.started_at;
      NEW.completed_at := clock_timestamp();
    ELSE
      RAISE EXCEPTION 'invalid inspection lifecycle transition'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  SELECT relationship.id
  INTO qualifying_relationship_id
  FROM public.property_company_relationships AS relationship
  WHERE relationship.company_id = NEW.company_id
    AND relationship.property_id = NEW.property_id
    AND relationship.status = 'ACTIVE'
    AND relationship.scope IN ('FULL_MANAGEMENT', 'INSPECTION_SERVICE')
  ORDER BY relationship.id
  LIMIT 1
  FOR SHARE OF relationship;

  IF qualifying_relationship_id IS NULL THEN
    RAISE EXCEPTION 'inspection requires an active inspection-capable property relationship'
      USING ERRCODE = '55000';
  END IF;

  SELECT template_state.company_id, version_state.frozen_at
  INTO template_company_id, template_frozen_at
  FROM public.inspection_template_versions AS version_state
  JOIN public.inspection_templates AS template_state
    ON template_state.id = version_state.template_id
  WHERE version_state.id = NEW.template_version_id
  FOR SHARE OF version_state, template_state;

  IF template_company_id IS NULL
    OR template_company_id <> NEW.company_id
    OR template_frozen_at IS NULL
  THEN
    RAISE EXCEPTION 'inspection requires a frozen template version from its company'
      USING ERRCODE = '55000';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE FUNCTION security.protect_inspection_result()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  parent_inspection_id uuid;
  parent_company_id uuid;
  parent_property_id uuid;
  parent_template_version_id uuid;
  parent_status public.inspection_lifecycle_status;
  item_template_version_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    parent_inspection_id := OLD.inspection_id;
  ELSE
    parent_inspection_id := NEW.inspection_id;
  END IF;

  IF TG_OP = 'UPDATE'
    AND (
      NEW.company_id IS DISTINCT FROM OLD.company_id
      OR NEW.property_id IS DISTINCT FROM OLD.property_id
      OR NEW.inspection_id IS DISTINCT FROM OLD.inspection_id
      OR NEW.template_item_id IS DISTINCT FROM OLD.template_item_id
    )
  THEN
    RAISE EXCEPTION 'inspection result identity is immutable'
      USING ERRCODE = '55000';
  END IF;

  SELECT
    inspection_state.company_id,
    inspection_state.property_id,
    inspection_state.template_version_id,
    inspection_state.status
  INTO
    parent_company_id,
    parent_property_id,
    parent_template_version_id,
    parent_status
  FROM public.inspections AS inspection_state
  WHERE inspection_state.id = parent_inspection_id
  FOR SHARE OF inspection_state;

  IF parent_company_id IS NULL THEN
    RAISE EXCEPTION 'inspection result requires an existing inspection'
      USING ERRCODE = '55000';
  END IF;

  IF parent_status = 'COMPLETED' THEN
    RAISE EXCEPTION 'completed inspection results are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.company_id <> parent_company_id
      OR OLD.property_id <> parent_property_id
    THEN
      RAISE EXCEPTION 'inspection result tenant identity must match its inspection'
        USING ERRCODE = '55000';
    END IF;

    RETURN OLD;
  END IF;

  IF NEW.company_id <> parent_company_id
    OR NEW.property_id <> parent_property_id
  THEN
    RAISE EXCEPTION 'inspection result tenant identity must match its inspection'
      USING ERRCODE = '55000';
  END IF;

  SELECT version_state.id
  INTO item_template_version_id
  FROM public.inspection_template_items AS item_state
  JOIN public.inspection_template_sections AS section_state
    ON section_state.id = item_state.section_id
  JOIN public.inspection_template_versions AS version_state
    ON version_state.id = section_state.version_id
  WHERE item_state.id = NEW.template_item_id
  FOR SHARE OF item_state, section_state, version_state;

  IF item_template_version_id IS NULL
    OR item_template_version_id <> parent_template_version_id
  THEN
    RAISE EXCEPTION 'inspection result item must belong to the inspection template version'
      USING ERRCODE = '55000';
  END IF;

  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE FUNCTION security.protect_meter_reading()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  parent_inspection_id uuid;
  parent_company_id uuid;
  parent_property_id uuid;
  parent_status public.inspection_lifecycle_status;
BEGIN
  IF TG_OP = 'DELETE' THEN
    parent_inspection_id := OLD.inspection_id;
  ELSE
    parent_inspection_id := NEW.inspection_id;
  END IF;

  IF TG_OP = 'INSERT' THEN
    actor_id := security.current_profile_id();
    IF actor_id IS NULL THEN
      RAISE EXCEPTION 'meter creation requires an authenticated profile'
        USING ERRCODE = '42501';
    END IF;

    NEW.recorded_by := actor_id;
  ELSIF TG_OP = 'UPDATE'
    AND (
      NEW.company_id IS DISTINCT FROM OLD.company_id
      OR NEW.property_id IS DISTINCT FROM OLD.property_id
      OR NEW.inspection_id IS DISTINCT FROM OLD.inspection_id
      OR NEW.recorded_by IS DISTINCT FROM OLD.recorded_by
    )
  THEN
    RAISE EXCEPTION 'meter reading identity is immutable'
      USING ERRCODE = '55000';
  END IF;

  SELECT
    inspection_state.company_id,
    inspection_state.property_id,
    inspection_state.status
  INTO parent_company_id, parent_property_id, parent_status
  FROM public.inspections AS inspection_state
  WHERE inspection_state.id = parent_inspection_id
  FOR SHARE OF inspection_state;

  IF parent_company_id IS NULL THEN
    RAISE EXCEPTION 'meter reading requires an existing inspection'
      USING ERRCODE = '55000';
  END IF;

  IF parent_status = 'COMPLETED' THEN
    RAISE EXCEPTION 'completed inspection meter readings are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.company_id <> parent_company_id
      OR OLD.property_id <> parent_property_id
    THEN
      RAISE EXCEPTION 'meter reading tenant identity must match its inspection'
        USING ERRCODE = '55000';
    END IF;

    RETURN OLD;
  END IF;

  IF NEW.company_id <> parent_company_id
    OR NEW.property_id <> parent_property_id
  THEN
    RAISE EXCEPTION 'meter reading tenant identity must match its inspection'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

CREATE FUNCTION security.write_inspection_lifecycle_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  lifecycle_change_type text;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  actor_id := security.current_profile_id();
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'inspection lifecycle history requires an authenticated profile'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.status = 'SCHEDULED' AND NEW.status = 'IN_PROGRESS' THEN
    lifecycle_change_type := 'STARTED';
  ELSIF OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED' THEN
    lifecycle_change_type := 'COMPLETED';
  ELSE
    RAISE EXCEPTION 'unsupported inspection lifecycle history transition'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.inspection_changes (
    inspection_id,
    company_id,
    property_id,
    changed_by,
    change_type,
    old_value,
    new_value
  )
  VALUES (
    NEW.id,
    NEW.company_id,
    NEW.property_id,
    actor_id,
    lifecycle_change_type,
    to_jsonb(OLD),
    to_jsonb(NEW)
  );

  RETURN NEW;
END;
$$;

CREATE FUNCTION security.write_inspection_result_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  inspection_state public.inspections%ROWTYPE;
BEGIN
  actor_id := security.current_profile_id();
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'inspection result history requires an authenticated profile'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'DELETE' THEN
    SELECT *
    INTO inspection_state
    FROM public.inspections
    WHERE id = OLD.inspection_id;

    INSERT INTO public.inspection_changes (
      inspection_id,
      company_id,
      property_id,
      changed_by,
      change_type,
      old_value,
      new_value
    )
    VALUES (
      OLD.inspection_id,
      inspection_state.company_id,
      inspection_state.property_id,
      actor_id,
      'RESULT_CHANGED',
      to_jsonb(OLD),
      NULL
    );

    RETURN OLD;
  END IF;

  SELECT *
  INTO inspection_state
  FROM public.inspections
  WHERE id = NEW.inspection_id;

  INSERT INTO public.inspection_changes (
    inspection_id,
    company_id,
    property_id,
    changed_by,
    change_type,
    old_value,
    new_value
  )
  VALUES (
    NEW.inspection_id,
    inspection_state.company_id,
    inspection_state.property_id,
    actor_id,
    'RESULT_CHANGED',
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
    to_jsonb(NEW)
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION security.protect_inspection_runtime()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.protect_inspection_result()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.protect_meter_reading()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.write_inspection_lifecycle_change()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.write_inspection_result_change()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER inspections_protect_runtime
BEFORE INSERT OR UPDATE ON public.inspections
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_runtime();

CREATE TRIGGER inspections_write_lifecycle_change
AFTER UPDATE ON public.inspections
FOR EACH ROW
EXECUTE FUNCTION security.write_inspection_lifecycle_change();

CREATE TRIGGER inspection_results_protect_runtime
BEFORE INSERT OR UPDATE OR DELETE ON public.inspection_results
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_result();

CREATE TRIGGER inspection_results_write_change
AFTER INSERT OR UPDATE OR DELETE ON public.inspection_results
FOR EACH ROW
EXECUTE FUNCTION security.write_inspection_result_change();

CREATE TRIGGER meter_readings_protect_runtime
BEFORE INSERT OR UPDATE OR DELETE ON public.meter_readings
FOR EACH ROW
EXECUTE FUNCTION security.protect_meter_reading();

REVOKE ALL PRIVILEGES ON TABLE public.inspections
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_results
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_changes
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.meter_readings
  FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE
  ON TABLE public.inspections
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.inspection_results
  TO authenticated;
GRANT SELECT
  ON TABLE public.inspection_changes
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.meter_readings
  TO authenticated;

CREATE POLICY inspections_company_select
ON public.inspections
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

CREATE POLICY inspections_operational_insert
ON public.inspections
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

CREATE POLICY inspections_operational_update
ON public.inspections
FOR UPDATE
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
)
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

CREATE POLICY inspection_results_company_select
ON public.inspection_results
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

CREATE POLICY inspection_results_operational_insert
ON public.inspection_results
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

CREATE POLICY inspection_results_operational_update
ON public.inspection_results
FOR UPDATE
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
)
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

CREATE POLICY inspection_results_operational_delete
ON public.inspection_results
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

CREATE POLICY inspection_changes_company_select
ON public.inspection_changes
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

CREATE POLICY meter_readings_company_select
ON public.meter_readings
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

CREATE POLICY meter_readings_operational_insert
ON public.meter_readings
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

CREATE POLICY meter_readings_operational_update
ON public.meter_readings
FOR UPDATE
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
)
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

CREATE POLICY meter_readings_operational_delete
ON public.meter_readings
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
