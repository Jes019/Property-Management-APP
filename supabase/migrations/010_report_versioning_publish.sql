CREATE TABLE public.inspection_report_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid NOT NULL REFERENCES public.properties (id),
  inspection_id uuid NOT NULL REFERENCES public.inspections (id),
  version_number integer NOT NULL,
  status public.report_status NOT NULL DEFAULT 'DRAFT',
  title text,
  summary text,
  content jsonb,
  created_by uuid NOT NULL REFERENCES public.profiles (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  published_by uuid REFERENCES public.profiles (id),
  CONSTRAINT inspection_report_versions_version_positive_check CHECK (
    version_number > 0
  ),
  CONSTRAINT inspection_report_versions_publication_consistency_check CHECK (
    (
      status = 'DRAFT'
      AND published_at IS NULL
      AND published_by IS NULL
    )
    OR (
      status IN ('FINAL', 'SUPERSEDED')
      AND published_at IS NOT NULL
      AND published_by IS NOT NULL
    )
  ),
  UNIQUE (inspection_id, version_number)
);

CREATE INDEX inspection_report_versions_company_id_property_id_idx
  ON public.inspection_report_versions (company_id, property_id);

CREATE UNIQUE INDEX inspection_report_versions_one_current_final_idx
  ON public.inspection_report_versions (inspection_id)
  WHERE status = 'FINAL';

ALTER TABLE public.inspection_report_versions ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.protect_report_version()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  parent_company_id uuid;
  parent_property_id uuid;
  next_version integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'published report versions are immutable history and cannot be deleted'
        USING ERRCODE = '55000';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    actor_id := security.current_profile_id();
    IF actor_id IS NULL THEN
      RAISE EXCEPTION 'report creation requires an authenticated profile'
        USING ERRCODE = '42501';
    END IF;
    NEW.created_by := actor_id;

    IF NEW.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'report versions must be created as drafts'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.published_at IS NOT NULL OR NEW.published_by IS NOT NULL THEN
      RAISE EXCEPTION 'draft report versions cannot carry publication metadata'
        USING ERRCODE = '55000';
    END IF;

    SELECT inspection_state.company_id, inspection_state.property_id
    INTO parent_company_id, parent_property_id
    FROM public.inspections AS inspection_state
    WHERE inspection_state.id = NEW.inspection_id
    FOR UPDATE OF inspection_state;

    IF parent_company_id IS NULL THEN
      RAISE EXCEPTION 'report version requires an existing inspection'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.company_id <> parent_company_id
      OR NEW.property_id <> parent_property_id
    THEN
      RAISE EXCEPTION 'report tenant identity must match its inspection'
        USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(MAX(version.version_number), 0) + 1
    INTO next_version
    FROM public.inspection_report_versions AS version
    WHERE version.inspection_id = NEW.inspection_id;

    NEW.version_number := next_version;
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
  END IF;

  IF NEW.company_id IS DISTINCT FROM OLD.company_id
    OR NEW.property_id IS DISTINCT FROM OLD.property_id
    OR NEW.inspection_id IS DISTINCT FROM OLD.inspection_id
    OR NEW.version_number IS DISTINCT FROM OLD.version_number
    OR NEW.created_by IS DISTINCT FROM OLD.created_by
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'report identity is immutable'
      USING ERRCODE = '55000';
  END IF;

  IF OLD.status = 'DRAFT' AND NEW.status = 'DRAFT' THEN
    IF NEW.published_at IS DISTINCT FROM OLD.published_at
      OR NEW.published_by IS DISTINCT FROM OLD.published_by
    THEN
      RAISE EXCEPTION 'draft publication metadata cannot be set outside publication'
        USING ERRCODE = '55000';
    END IF;
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
  END IF;

  IF OLD.status = 'DRAFT' AND NEW.status = 'FINAL' THEN
    IF NEW.title IS DISTINCT FROM OLD.title
      OR NEW.summary IS DISTINCT FROM OLD.summary
      OR NEW.content IS DISTINCT FROM OLD.content
    THEN
      RAISE EXCEPTION 'publication cannot alter report content'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.published_at IS NULL OR NEW.published_by IS NULL THEN
      RAISE EXCEPTION 'publication must record publication actor and time'
        USING ERRCODE = '55000';
    END IF;

    NEW.updated_at := clock_timestamp();
    RETURN NEW;
  END IF;

  IF OLD.status = 'FINAL' AND NEW.status = 'SUPERSEDED' THEN
    IF NEW.title IS DISTINCT FROM OLD.title
      OR NEW.summary IS DISTINCT FROM OLD.summary
      OR NEW.content IS DISTINCT FROM OLD.content
      OR NEW.published_at IS DISTINCT FROM OLD.published_at
      OR NEW.published_by IS DISTINCT FROM OLD.published_by
    THEN
      RAISE EXCEPTION 'supersession cannot alter published report content or publication record'
        USING ERRCODE = '55000';
    END IF;

    NEW.updated_at := clock_timestamp();
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'invalid report status transition'
    USING ERRCODE = '55000';
END;
$$;

REVOKE ALL ON FUNCTION security.protect_report_version()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER inspection_report_versions_protect_runtime
BEFORE INSERT OR UPDATE OR DELETE ON public.inspection_report_versions
FOR EACH ROW
EXECUTE FUNCTION security.protect_report_version();

REVOKE ALL PRIVILEGES ON TABLE public.inspection_report_versions
  FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE
  ON TABLE public.inspection_report_versions
  TO authenticated;

CREATE POLICY inspection_report_versions_company_select
ON public.inspection_report_versions
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

CREATE POLICY inspection_report_versions_draft_insert
ON public.inspection_report_versions
FOR INSERT
TO authenticated
WITH CHECK (
  status = 'DRAFT'
  AND security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY inspection_report_versions_draft_update
ON public.inspection_report_versions
FOR UPDATE
TO authenticated
USING (
  status = 'DRAFT'
  AND security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
)
WITH CHECK (
  status = 'DRAFT'
  AND security.company_has_property_scope(
    company_id,
    property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  )
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE FUNCTION public.publish_inspection_report(p_report_id uuid)
RETURNS public.inspection_report_versions
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  actor_id uuid;
  draft_report public.inspection_report_versions%ROWTYPE;
  parent_company_id uuid;
  parent_property_id uuid;
  parent_status public.inspection_lifecycle_status;
  published_report public.inspection_report_versions%ROWTYPE;
BEGIN
  actor_id := security.current_profile_id();
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'report publication requires an authenticated profile'
      USING ERRCODE = '42501';
  END IF;

  SELECT report.*
  INTO draft_report
  FROM public.inspection_report_versions AS report
  WHERE report.id = p_report_id
  FOR UPDATE OF report;

  IF draft_report.id IS NULL THEN
    RAISE EXCEPTION 'report version does not exist'
      USING ERRCODE = '42501';
  END IF;

  IF NOT security.has_company_role(
    draft_report.company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  ) THEN
    RAISE EXCEPTION 'report publication requires an authorized company role'
      USING ERRCODE = '42501';
  END IF;

  IF NOT security.company_has_property_scope(
    draft_report.company_id,
    draft_report.property_id,
    ARRAY[
      'FULL_MANAGEMENT',
      'INSPECTION_SERVICE'
    ]::public.property_company_relationship_scope[]
  ) THEN
    RAISE EXCEPTION 'company lacks an inspection-capable property relationship'
      USING ERRCODE = '42501';
  END IF;

  IF draft_report.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'only draft report versions can be published'
      USING ERRCODE = '55000';
  END IF;

  SELECT inspection_state.company_id, inspection_state.property_id, inspection_state.status
  INTO parent_company_id, parent_property_id, parent_status
  FROM public.inspections AS inspection_state
  WHERE inspection_state.id = draft_report.inspection_id
  FOR UPDATE OF inspection_state;

  IF parent_company_id IS NULL THEN
    RAISE EXCEPTION 'report requires an existing inspection'
      USING ERRCODE = '55000';
  END IF;

  IF parent_company_id <> draft_report.company_id
    OR parent_property_id <> draft_report.property_id
  THEN
    RAISE EXCEPTION 'report tenant identity must match its inspection'
      USING ERRCODE = '55000';
  END IF;

  IF parent_status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'inspection must be completed before publishing a report'
      USING ERRCODE = '55000';
  END IF;

  UPDATE public.inspection_report_versions
  SET
    status = 'SUPERSEDED'
  WHERE inspection_id = draft_report.inspection_id
    AND status = 'FINAL';

  UPDATE public.inspection_report_versions
  SET
    status = 'FINAL',
    published_at = clock_timestamp(),
    published_by = actor_id
  WHERE id = draft_report.id
  RETURNING * INTO published_report;

  RETURN published_report;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_inspection_report(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.publish_inspection_report(uuid)
  TO authenticated;
