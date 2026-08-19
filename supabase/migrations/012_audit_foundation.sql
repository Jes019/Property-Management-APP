CREATE TABLE public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies (id),
  property_id uuid REFERENCES public.properties (id),
  actor_profile_id uuid REFERENCES public.profiles (id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_log_action_check CHECK (
    action IN (
      'INSPECTION_COMPLETED',
      'REPORT_PUBLISHED',
      'REPORT_SUPERSEDED'
    )
  ),
  CONSTRAINT audit_log_entity_type_check CHECK (
    entity_type IN (
      'inspection',
      'inspection_report_version'
    )
  )
);

CREATE INDEX audit_log_company_id_created_at_idx
  ON public.audit_log (company_id, created_at);

CREATE INDEX audit_log_company_id_property_id_created_at_idx
  ON public.audit_log (company_id, property_id, created_at);

CREATE INDEX audit_log_entity_type_entity_id_created_at_idx
  ON public.audit_log (entity_type, entity_id, created_at);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.append_audit_log(
  p_company_id uuid,
  p_property_id uuid,
  p_actor_profile_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_old_values jsonb,
  p_new_values jsonb,
  p_metadata jsonb
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  inserted_id uuid;
BEGIN
  INSERT INTO public.audit_log (
    company_id,
    property_id,
    actor_profile_id,
    action,
    entity_type,
    entity_id,
    old_values,
    new_values,
    metadata
  ) VALUES (
    p_company_id,
    p_property_id,
    p_actor_profile_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_old_values,
    p_new_values,
    p_metadata
  )
  RETURNING id INTO inserted_id;

  RETURN inserted_id;
END;
$$;

REVOKE ALL ON FUNCTION security.append_audit_log(
  uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, jsonb
) FROM PUBLIC, anon, authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.audit_log
  FROM PUBLIC, anon, authenticated;

GRANT SELECT
  ON TABLE public.audit_log
  TO authenticated;

CREATE POLICY audit_log_company_select
ON public.audit_log
FOR SELECT
TO authenticated
USING (
  security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
  AND (
    property_id IS NULL
    OR security.company_has_property_scope(
      company_id,
      property_id,
      ARRAY[
        'FULL_MANAGEMENT',
        'INSPECTION_SERVICE'
      ]::public.property_company_relationship_scope[]
    )
  )
);

CREATE FUNCTION security.audit_inspection_completion()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED' THEN
    PERFORM security.append_audit_log(
      NEW.company_id,
      NEW.property_id,
      security.current_profile_id(),
      'INSPECTION_COMPLETED',
      'inspection',
      NEW.id,
      jsonb_build_object('status', 'IN_PROGRESS'),
      jsonb_build_object('status', 'COMPLETED', 'completed_at', NEW.completed_at),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION security.audit_inspection_completion()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER inspections_audit_completion
AFTER UPDATE ON public.inspections
FOR EACH ROW
EXECUTE FUNCTION security.audit_inspection_completion();

CREATE OR REPLACE FUNCTION public.publish_inspection_report(p_report_id uuid)
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
  superseded_report_id uuid;
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
    AND status = 'FINAL'
  RETURNING id INTO superseded_report_id;

  UPDATE public.inspection_report_versions
  SET
    status = 'FINAL',
    published_at = clock_timestamp(),
    published_by = actor_id
  WHERE id = draft_report.id
  RETURNING * INTO published_report;

  IF superseded_report_id IS NOT NULL THEN
    PERFORM security.append_audit_log(
      published_report.company_id,
      published_report.property_id,
      actor_id,
      'REPORT_SUPERSEDED',
      'inspection_report_version',
      superseded_report_id,
      jsonb_build_object('status', 'FINAL'),
      jsonb_build_object('status', 'SUPERSEDED'),
      jsonb_build_object(
        'inspection_id', published_report.inspection_id,
        'superseded_by', published_report.id
      )
    );
  END IF;

  PERFORM security.append_audit_log(
    published_report.company_id,
    published_report.property_id,
    actor_id,
    'REPORT_PUBLISHED',
    'inspection_report_version',
    published_report.id,
    jsonb_build_object('status', 'DRAFT'),
    jsonb_build_object(
      'status', 'FINAL',
      'version_number', published_report.version_number,
      'published_at', published_report.published_at
    ),
    jsonb_build_object('inspection_id', published_report.inspection_id)
  );

  RETURN published_report;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_inspection_report(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.publish_inspection_report(uuid)
  TO authenticated;
