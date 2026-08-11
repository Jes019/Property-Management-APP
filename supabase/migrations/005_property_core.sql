CREATE TABLE public.properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address_line_1 text,
  address_line_2 text,
  locality text,
  postcode text,
  country text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.property_owners (
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (property_id, profile_id)
);

CREATE TABLE public.property_company_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  relationship_type public.property_company_relationship_type NOT NULL,
  status public.property_company_relationship_status NOT NULL,
  scope public.property_company_relationship_scope NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT property_company_relationships_type_scope_check CHECK (
    (
      relationship_type = 'PRIMARY'
      AND scope = 'FULL_MANAGEMENT'
    )
    OR
    (
      relationship_type = 'SERVICE'
      AND scope IN (
        'INSPECTION_SERVICE',
        'MAINTENANCE_SERVICE',
        'COORDINATION_SERVICE'
      )
    )
  )
);

CREATE TABLE public.company_property_settings (
  company_id uuid NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, property_id)
);

CREATE TABLE public.property_staff_assignments (
  company_id uuid NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, property_id, profile_id)
);

CREATE INDEX property_owners_profile_property_idx
  ON public.property_owners (profile_id, property_id);

CREATE INDEX property_company_relationships_company_property_status_idx
  ON public.property_company_relationships (company_id, property_id, status);

CREATE INDEX property_company_relationships_property_status_type_idx
  ON public.property_company_relationships (property_id, status, relationship_type);

CREATE INDEX property_staff_assignments_profile_company_property_active_idx
  ON public.property_staff_assignments (
    profile_id,
    company_id,
    property_id,
    is_active
  );

CREATE UNIQUE INDEX property_company_relationships_one_active_primary_idx
  ON public.property_company_relationships (property_id)
  WHERE relationship_type = 'PRIMARY' AND status = 'ACTIVE';

CREATE UNIQUE INDEX property_company_relationships_no_duplicate_active_idx
  ON public.property_company_relationships (
    company_id,
    property_id,
    relationship_type,
    scope
  )
  WHERE status = 'ACTIVE';

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_owners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_company_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_property_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_staff_assignments ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION security.is_property_owner(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.property_owners AS owner_link
    WHERE owner_link.property_id = p_property_id
      AND owner_link.profile_id = security.current_profile_id()
  );
$$;

CREATE FUNCTION security.company_has_property_access(
  p_company_id uuid,
  p_property_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(security.is_company_member(p_company_id), false)
    AND EXISTS (
      SELECT 1
      FROM public.property_company_relationships AS relationship
      WHERE relationship.company_id = p_company_id
        AND relationship.property_id = p_property_id
        AND relationship.status = 'ACTIVE'
    );
$$;

CREATE FUNCTION security.company_has_property_scope(
  p_company_id uuid,
  p_property_id uuid,
  p_scopes public.property_company_relationship_scope[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(security.is_company_member(p_company_id), false)
    AND EXISTS (
      SELECT 1
      FROM public.property_company_relationships AS relationship
      WHERE relationship.company_id = p_company_id
        AND relationship.property_id = p_property_id
        AND relationship.status = 'ACTIVE'
        AND relationship.scope = ANY (p_scopes)
    );
$$;

CREATE FUNCTION security.is_assigned_to_property(
  p_company_id uuid,
  p_property_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.property_staff_assignments AS assignment
    WHERE assignment.company_id = p_company_id
      AND assignment.property_id = p_property_id
      AND assignment.profile_id = security.current_profile_id()
      AND assignment.is_active
  );
$$;

REVOKE ALL ON FUNCTION security.is_property_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.company_has_property_access(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.company_has_property_scope(
  uuid,
  uuid,
  public.property_company_relationship_scope[]
) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.is_assigned_to_property(uuid, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION security.is_property_owner(uuid) FROM anon;
REVOKE ALL ON FUNCTION security.company_has_property_access(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION security.company_has_property_scope(
  uuid,
  uuid,
  public.property_company_relationship_scope[]
) FROM anon;
REVOKE ALL ON FUNCTION security.is_assigned_to_property(uuid, uuid) FROM anon;

GRANT EXECUTE ON FUNCTION security.is_property_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION security.company_has_property_access(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION security.company_has_property_scope(
  uuid,
  uuid,
  public.property_company_relationship_scope[]
) TO authenticated;
GRANT EXECUTE ON FUNCTION security.is_assigned_to_property(uuid, uuid) TO authenticated;
