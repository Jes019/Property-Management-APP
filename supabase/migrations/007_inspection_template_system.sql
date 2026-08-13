CREATE TABLE public.inspection_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL
    REFERENCES public.companies (id) ON DELETE CASCADE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.inspection_template_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL
    REFERENCES public.inspection_templates (id) ON DELETE CASCADE,
  version_number integer NOT NULL CHECK (version_number > 0),
  is_current boolean NOT NULL DEFAULT true,
  frozen_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_id, version_number)
);

CREATE TABLE public.inspection_template_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL
    REFERENCES public.inspection_template_versions (id) ON DELETE CASCADE,
  title text NOT NULL,
  sort_order integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version_id, sort_order)
);

CREATE TABLE public.inspection_template_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id uuid NOT NULL
    REFERENCES public.inspection_template_sections (id) ON DELETE CASCADE,
  label text NOT NULL,
  sort_order integer NOT NULL,
  is_required boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (section_id, sort_order)
);

CREATE INDEX inspection_templates_company_active_idx
  ON public.inspection_templates (company_id, is_active);

CREATE UNIQUE INDEX inspection_template_versions_one_current_idx
  ON public.inspection_template_versions (template_id)
  WHERE is_current;

ALTER TABLE public.inspection_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_template_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_template_items ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.protect_inspection_template_delete()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    WHERE version_state.template_id = OLD.id
      AND version_state.frozen_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'cannot delete an inspection template with frozen history'
      USING ERRCODE = '55000';
  END IF;

  RETURN OLD;
END;
$$;

CREATE FUNCTION security.protect_inspection_template_version()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF OLD.frozen_at IS NOT NULL THEN
    RAISE EXCEPTION 'frozen inspection template versions are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

CREATE FUNCTION security.protect_inspection_template_section()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    WHERE version_state.id = OLD.version_id
      AND version_state.frozen_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'sections in frozen inspection template versions are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP <> 'DELETE' AND EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    WHERE version_state.id = NEW.version_id
      AND version_state.frozen_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'sections cannot be inserted into or moved to frozen versions'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

CREATE FUNCTION security.protect_inspection_template_item()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    WHERE section_state.id = OLD.section_id
      AND version_state.frozen_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'items in frozen inspection template versions are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP <> 'DELETE' AND EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    WHERE section_state.id = NEW.section_id
      AND version_state.frozen_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'items cannot be inserted into or moved to frozen versions'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION security.protect_inspection_template_delete()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION security.protect_inspection_template_version()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION security.protect_inspection_template_section()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION security.protect_inspection_template_item()
  FROM PUBLIC;

REVOKE ALL ON FUNCTION security.protect_inspection_template_delete()
  FROM anon;
REVOKE ALL ON FUNCTION security.protect_inspection_template_version()
  FROM anon;
REVOKE ALL ON FUNCTION security.protect_inspection_template_section()
  FROM anon;
REVOKE ALL ON FUNCTION security.protect_inspection_template_item()
  FROM anon;

REVOKE ALL ON FUNCTION security.protect_inspection_template_delete()
  FROM authenticated;
REVOKE ALL ON FUNCTION security.protect_inspection_template_version()
  FROM authenticated;
REVOKE ALL ON FUNCTION security.protect_inspection_template_section()
  FROM authenticated;
REVOKE ALL ON FUNCTION security.protect_inspection_template_item()
  FROM authenticated;

CREATE TRIGGER inspection_templates_protect_frozen_delete
BEFORE DELETE ON public.inspection_templates
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_template_delete();

CREATE TRIGGER inspection_template_versions_protect_frozen
BEFORE UPDATE OR DELETE ON public.inspection_template_versions
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_template_version();

CREATE TRIGGER inspection_template_sections_protect_frozen
BEFORE INSERT OR UPDATE OR DELETE ON public.inspection_template_sections
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_template_section();

CREATE TRIGGER inspection_template_items_protect_frozen
BEFORE INSERT OR UPDATE OR DELETE ON public.inspection_template_items
FOR EACH ROW
EXECUTE FUNCTION security.protect_inspection_template_item();

REVOKE ALL PRIVILEGES ON TABLE public.inspection_templates FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_versions FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_sections FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_items FROM PUBLIC;

REVOKE ALL PRIVILEGES ON TABLE public.inspection_templates FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_versions FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_sections FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_items FROM anon;

REVOKE ALL PRIVILEGES ON TABLE public.inspection_templates FROM authenticated;
REVOKE ALL PRIVILEGES
  ON TABLE public.inspection_template_versions
  FROM authenticated;
REVOKE ALL PRIVILEGES
  ON TABLE public.inspection_template_sections
  FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.inspection_template_items FROM authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.inspection_templates
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.inspection_template_versions
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.inspection_template_sections
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.inspection_template_items
  TO authenticated;

CREATE POLICY inspection_templates_company_select
ON public.inspection_templates
FOR SELECT
TO authenticated
USING (
  security.has_company_role(
    company_id,
    ARRAY[
      'ADMIN',
      'MANAGER',
      'INSPECTOR',
      'COORDINATOR',
      'READ_ONLY'
    ]::public.company_role[]
  )
);

CREATE POLICY inspection_templates_admin_manager_insert
ON public.inspection_templates
FOR INSERT
TO authenticated
WITH CHECK (
  security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY inspection_templates_admin_manager_update
ON public.inspection_templates
FOR UPDATE
TO authenticated
USING (
  security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
)
WITH CHECK (
  security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY inspection_templates_admin_manager_delete
ON public.inspection_templates
FOR DELETE
TO authenticated
USING (
  security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    WHERE version_state.template_id = inspection_templates.id
      AND version_state.frozen_at IS NOT NULL
  )
);

CREATE POLICY inspection_template_versions_company_select
ON public.inspection_template_versions
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_templates AS template_state
    WHERE template_state.id = inspection_template_versions.template_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY[
          'ADMIN',
          'MANAGER',
          'INSPECTOR',
          'COORDINATOR',
          'READ_ONLY'
        ]::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_versions_admin_manager_insert
ON public.inspection_template_versions
FOR INSERT
TO authenticated
WITH CHECK (
  frozen_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.inspection_templates AS template_state
    WHERE template_state.id = inspection_template_versions.template_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_versions_admin_manager_update
ON public.inspection_template_versions
FOR UPDATE
TO authenticated
USING (
  frozen_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.inspection_templates AS template_state
    WHERE template_state.id = inspection_template_versions.template_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
)
WITH CHECK (
  (frozen_at IS NULL OR NOT is_current)
  AND EXISTS (
    SELECT 1
    FROM public.inspection_templates AS template_state
    WHERE template_state.id = inspection_template_versions.template_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_versions_admin_manager_delete
ON public.inspection_template_versions
FOR DELETE
TO authenticated
USING (
  frozen_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.inspection_templates AS template_state
    WHERE template_state.id = inspection_template_versions.template_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_sections_company_select
ON public.inspection_template_sections
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE version_state.id = inspection_template_sections.version_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY[
          'ADMIN',
          'MANAGER',
          'INSPECTOR',
          'COORDINATOR',
          'READ_ONLY'
        ]::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_sections_admin_manager_insert
ON public.inspection_template_sections
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE version_state.id = inspection_template_sections.version_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_sections_admin_manager_update
ON public.inspection_template_sections
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE version_state.id = inspection_template_sections.version_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE version_state.id = inspection_template_sections.version_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_sections_admin_manager_delete
ON public.inspection_template_sections
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions AS version_state
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE version_state.id = inspection_template_sections.version_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_items_company_select
ON public.inspection_template_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE section_state.id = inspection_template_items.section_id
      AND security.has_company_role(
        template_state.company_id,
        ARRAY[
          'ADMIN',
          'MANAGER',
          'INSPECTOR',
          'COORDINATOR',
          'READ_ONLY'
        ]::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_items_admin_manager_insert
ON public.inspection_template_items
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE section_state.id = inspection_template_items.section_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_items_admin_manager_update
ON public.inspection_template_items
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE section_state.id = inspection_template_items.section_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE section_state.id = inspection_template_items.section_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);

CREATE POLICY inspection_template_items_admin_manager_delete
ON public.inspection_template_items
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.inspection_template_sections AS section_state
    JOIN public.inspection_template_versions AS version_state
      ON version_state.id = section_state.version_id
    JOIN public.inspection_templates AS template_state
      ON template_state.id = version_state.template_id
    WHERE section_state.id = inspection_template_items.section_id
      AND version_state.frozen_at IS NULL
      AND security.has_company_role(
        template_state.company_id,
        ARRAY['ADMIN', 'MANAGER']::public.company_role[]
      )
  )
);
