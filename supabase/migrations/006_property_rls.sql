REVOKE ALL PRIVILEGES ON TABLE public.properties FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.property_owners FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.property_company_relationships FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.company_property_settings FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.property_staff_assignments FROM PUBLIC;

REVOKE ALL PRIVILEGES ON TABLE public.properties FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.property_owners FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.property_company_relationships FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.company_property_settings FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.property_staff_assignments FROM anon;

REVOKE ALL PRIVILEGES ON TABLE public.properties FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.property_owners FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.property_company_relationships FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_property_settings FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.property_staff_assignments FROM authenticated;

GRANT SELECT ON TABLE public.properties TO authenticated;
GRANT SELECT ON TABLE public.property_owners TO authenticated;
GRANT SELECT ON TABLE public.property_company_relationships TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.company_property_settings
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.property_staff_assignments
  TO authenticated;

CREATE POLICY properties_owner_select
ON public.properties
FOR SELECT
TO authenticated
USING (security.is_property_owner(id));

CREATE POLICY properties_company_select
ON public.properties
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.property_company_relationships AS relationship
    WHERE relationship.property_id = properties.id
      AND security.company_has_property_access(
        relationship.company_id,
        properties.id
      )
      AND (
        security.has_company_role(
          relationship.company_id,
          ARRAY[
            'ADMIN',
            'MANAGER',
            'COORDINATOR',
            'READ_ONLY'
          ]::public.company_role[]
        )
        OR (
          security.has_company_role(
            relationship.company_id,
            ARRAY['INSPECTOR']::public.company_role[]
          )
          AND security.is_assigned_to_property(
            relationship.company_id,
            properties.id
          )
        )
      )
  )
);

CREATE POLICY property_owners_owner_select
ON public.property_owners
FOR SELECT
TO authenticated
USING (security.is_property_owner(property_id));

CREATE POLICY property_owners_company_select
ON public.property_owners
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.property_company_relationships AS relationship
    WHERE relationship.property_id = property_owners.property_id
      AND security.company_has_property_access(
        relationship.company_id,
        property_owners.property_id
      )
      AND (
        security.has_company_role(
          relationship.company_id,
          ARRAY[
            'ADMIN',
            'MANAGER',
            'COORDINATOR',
            'READ_ONLY'
          ]::public.company_role[]
        )
        OR (
          security.has_company_role(
            relationship.company_id,
            ARRAY['INSPECTOR']::public.company_role[]
          )
          AND security.is_assigned_to_property(
            relationship.company_id,
            property_owners.property_id
          )
        )
      )
  )
);

CREATE POLICY property_company_relationships_company_select
ON public.property_company_relationships
FOR SELECT
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
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

CREATE POLICY company_property_settings_company_select
ON public.company_property_settings
FOR SELECT
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
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

CREATE POLICY company_property_settings_admin_manager_insert
ON public.company_property_settings
FOR INSERT
TO authenticated
WITH CHECK (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY company_property_settings_admin_manager_update
ON public.company_property_settings
FOR UPDATE
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
)
WITH CHECK (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY company_property_settings_admin_manager_delete
ON public.company_property_settings
FOR DELETE
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY property_staff_assignments_company_select
ON public.property_staff_assignments
FOR SELECT
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
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

CREATE POLICY property_staff_assignments_admin_manager_insert
ON public.property_staff_assignments
FOR INSERT
TO authenticated
WITH CHECK (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY property_staff_assignments_admin_manager_update
ON public.property_staff_assignments
FOR UPDATE
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
)
WITH CHECK (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);

CREATE POLICY property_staff_assignments_admin_manager_delete
ON public.property_staff_assignments
FOR DELETE
TO authenticated
USING (
  security.company_has_property_access(company_id, property_id)
  AND security.has_company_role(
    company_id,
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  )
);
