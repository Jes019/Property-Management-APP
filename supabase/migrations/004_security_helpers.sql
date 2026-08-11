CREATE SCHEMA security;

REVOKE ALL ON SCHEMA security FROM PUBLIC;
REVOKE ALL ON SCHEMA security FROM anon;
GRANT USAGE ON SCHEMA security TO authenticated;

CREATE FUNCTION security.current_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT auth.uid();
$$;

CREATE FUNCTION security.is_company_member(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_memberships AS membership
    WHERE membership.company_id = p_company_id
      AND membership.profile_id = auth.uid()
      AND membership.is_active
  );
$$;

CREATE FUNCTION security.company_role(p_company_id uuid)
RETURNS public.company_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT membership.role
  FROM public.company_memberships AS membership
  WHERE membership.company_id = p_company_id
    AND membership.profile_id = auth.uid()
    AND membership.is_active;
$$;

CREATE FUNCTION security.has_company_role(
  p_company_id uuid,
  p_roles public.company_role[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(
    security.company_role(p_company_id) = ANY (p_roles),
    false
  );
$$;

REVOKE ALL ON FUNCTION security.current_profile_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION security.is_company_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.company_role(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION security.has_company_role(uuid, public.company_role[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION security.current_profile_id() FROM anon;
REVOKE ALL ON FUNCTION security.is_company_member(uuid) FROM anon;
REVOKE ALL ON FUNCTION security.company_role(uuid) FROM anon;
REVOKE ALL ON FUNCTION security.has_company_role(uuid, public.company_role[]) FROM anon;

GRANT EXECUTE ON FUNCTION security.current_profile_id() TO authenticated;
GRANT EXECUTE ON FUNCTION security.is_company_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION security.company_role(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION security.has_company_role(uuid, public.company_role[]) TO authenticated;
