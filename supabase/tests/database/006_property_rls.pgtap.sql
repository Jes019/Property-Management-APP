BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
      AND bool_and(relrowsecurity)
      AND bool_and(NOT relforcerowsecurity)
    FROM pg_class
    WHERE oid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships'),
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
  ), false),
  'all five property tables keep ordinary row level security enabled'
);

WITH expected(policyname, tablename, cmd) AS (
  VALUES
    ('properties_owner_select', 'properties', 'SELECT'),
    ('properties_company_select', 'properties', 'SELECT'),
    ('property_owners_owner_select', 'property_owners', 'SELECT'),
    ('property_owners_company_select', 'property_owners', 'SELECT'),
    (
      'property_company_relationships_company_select',
      'property_company_relationships',
      'SELECT'
    ),
    (
      'company_property_settings_company_select',
      'company_property_settings',
      'SELECT'
    ),
    (
      'company_property_settings_admin_manager_insert',
      'company_property_settings',
      'INSERT'
    ),
    (
      'company_property_settings_admin_manager_update',
      'company_property_settings',
      'UPDATE'
    ),
    (
      'company_property_settings_admin_manager_delete',
      'company_property_settings',
      'DELETE'
    ),
    (
      'property_staff_assignments_company_select',
      'property_staff_assignments',
      'SELECT'
    ),
    (
      'property_staff_assignments_admin_manager_insert',
      'property_staff_assignments',
      'INSERT'
    ),
    (
      'property_staff_assignments_admin_manager_update',
      'property_staff_assignments',
      'UPDATE'
    ),
    (
      'property_staff_assignments_admin_manager_delete',
      'property_staff_assignments',
      'DELETE'
    )
), actual AS (
  SELECT policyname, tablename, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = ANY (ARRAY[
      'properties',
      'property_owners',
      'property_company_relationships',
      'company_property_settings',
      'property_staff_assignments'
    ])
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'the property tables have exactly the thirteen command-specific policies'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 13
      AND bool_and(permissive = 'PERMISSIVE')
      AND bool_and(roles = ARRAY['authenticated']::name[])
      AND bool_and(cmd <> 'ALL')
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'properties',
        'property_owners',
        'property_company_relationships',
        'company_property_settings',
        'property_staff_assignments'
      ])
  ), false),
  'all property policies are authenticated-only, permissive, and command-specific'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 13
      AND bool_and(
        CASE cmd
          WHEN 'SELECT' THEN qual IS NOT NULL AND with_check IS NULL
          WHEN 'INSERT' THEN qual IS NULL AND with_check IS NOT NULL
          WHEN 'UPDATE' THEN qual IS NOT NULL AND with_check IS NOT NULL
          WHEN 'DELETE' THEN qual IS NOT NULL AND with_check IS NULL
          ELSE false
        END
      )
      AND bool_and(COALESCE(qual, '') NOT IN ('true', '(true)'))
      AND bool_and(COALESCE(with_check, '') NOT IN ('true', '(true)'))
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'properties',
        'property_owners',
        'property_company_relationships',
        'company_property_settings',
        'property_staff_assignments'
      ])
  ), false),
  'every policy has a restrictive qualification in the correct command position'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND bool_and(position('security.is_property_owner' in qual) > 0)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname IN (
        'properties_owner_select',
        'property_owners_owner_select'
      )
  ), false),
  'the two owner policies use only the current owner authorization path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
      AND bool_and(position('security.company_has_property_access' in qual) > 0)
      AND bool_and(position('security.has_company_role' in qual) > 0)
      AND bool_and(position('security.is_assigned_to_property' in qual) > 0)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname = ANY (ARRAY[
        'properties_company_select',
        'property_owners_company_select',
        'property_company_relationships_company_select',
        'company_property_settings_company_select',
        'property_staff_assignments_company_select'
      ])
  ), false),
  'all five company SELECT paths require active access, role, and inspector bounding'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 6
      AND bool_and(
        position(
          'security.company_has_property_access'
          in COALESCE(qual, with_check)
        ) > 0
      )
      AND bool_and(
        position('security.has_company_role' in COALESCE(qual, with_check)) > 0
      )
      AND bool_and(
        CASE
          WHEN cmd = 'UPDATE' THEN
            position('security.company_has_property_access' in qual) > 0
            AND position('security.has_company_role' in qual) > 0
            AND position('security.company_has_property_access' in with_check) > 0
            AND position('security.has_company_role' in with_check) > 0
          ELSE true
        END
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
      AND tablename IN (
        'company_property_settings',
        'property_staff_assignments'
      )
  ), false),
  'all six mutation policies require active access and ADMIN or MANAGER authorization'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname LIKE '%owner%select'
      AND tablename IN (
        'property_company_relationships',
        'company_property_settings',
        'property_staff_assignments'
      )
  ),
  'owners have no relationship, settings, or assignment policy path'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class relation
    CROSS JOIN LATERAL aclexplode(COALESCE(
      relation.relacl,
      acldefault('r', relation.relowner)
    )) privilege
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships'),
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
      AND privilege.grantee = 0
  ),
  'PUBLIC has no property table privileges'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
      AND bool_and(
        NOT has_table_privilege('anon', relation.oid, 'SELECT')
        AND NOT has_table_privilege('anon', relation.oid, 'INSERT')
        AND NOT has_table_privilege('anon', relation.oid, 'UPDATE')
        AND NOT has_table_privilege('anon', relation.oid, 'DELETE')
        AND NOT has_table_privilege('anon', relation.oid, 'TRUNCATE')
        AND NOT has_table_privilege('anon', relation.oid, 'REFERENCES')
        AND NOT has_table_privilege('anon', relation.oid, 'TRIGGER')
      )
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships'),
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
  ), false),
  'anon has no property table privileges'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 3
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'SELECT'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'INSERT'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'UPDATE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'DELETE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRUNCATE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'REFERENCES'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRIGGER'))
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships')
    ])
  ), false),
  'authenticated has SELECT-only access to property, owner, and relationship tables'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'SELECT'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'INSERT'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'UPDATE'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'DELETE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRUNCATE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'REFERENCES'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRIGGER'))
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
  ), false),
  'authenticated has only SELECT and DML access to settings and assignments'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND bool_and(NOT rolsuper)
      AND bool_and(NOT rolbypassrls)
    FROM pg_roles
    WHERE rolname IN ('anon', 'authenticated')
  ), false),
  'client roles are neither superusers nor RLS bypass roles'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
      AND bool_and(owner.rolname NOT IN ('anon', 'authenticated'))
    FROM pg_class relation
    JOIN pg_roles owner ON owner.oid = relation.relowner
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships'),
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
  ), false),
  'neither client role owns a property table'
);

INSERT INTO auth.users (id)
VALUES
  ('61000000-0000-0000-0000-000000000001'),
  ('61000000-0000-0000-0000-000000000002'),
  ('61000000-0000-0000-0000-000000000003'),
  ('61000000-0000-0000-0000-000000000004'),
  ('61000000-0000-0000-0000-000000000005'),
  ('61000000-0000-0000-0000-000000000006'),
  ('61000000-0000-0000-0000-000000000007'),
  ('61000000-0000-0000-0000-000000000008'),
  ('61000000-0000-0000-0000-000000000009'),
  ('61000000-0000-0000-0000-000000000010');

INSERT INTO public.profiles (id)
VALUES
  ('61000000-0000-0000-0000-000000000001'),
  ('61000000-0000-0000-0000-000000000002'),
  ('61000000-0000-0000-0000-000000000003'),
  ('61000000-0000-0000-0000-000000000004'),
  ('61000000-0000-0000-0000-000000000005'),
  ('61000000-0000-0000-0000-000000000006'),
  ('61000000-0000-0000-0000-000000000007'),
  ('61000000-0000-0000-0000-000000000008'),
  ('61000000-0000-0000-0000-000000000009'),
  ('61000000-0000-0000-0000-000000000010');

INSERT INTO public.companies (id, name)
VALUES
  ('62000000-0000-0000-0000-000000000001', 'Property RLS Company A'),
  ('62000000-0000-0000-0000-000000000002', 'Property RLS Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000002', 'MANAGER', true),
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000003', 'INSPECTOR', true),
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000004', 'INSPECTOR', true),
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000005', 'COORDINATOR', true),
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000006', 'READ_ONLY', true),
  ('62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000007', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES
  ('63000000-0000-0000-0000-000000000001', 'Property A1'),
  ('63000000-0000-0000-0000-000000000002', 'Property A2'),
  ('63000000-0000-0000-0000-000000000003', 'Property B1'),
  ('63000000-0000-0000-0000-000000000004', 'Property B2'),
  ('63000000-0000-0000-0000-000000000005', 'Service Property');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES
  ('63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000008'),
  ('63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000008'),
  ('63000000-0000-0000-0000-000000000003', '61000000-0000-0000-0000-000000000008'),
  ('63000000-0000-0000-0000-000000000004', '61000000-0000-0000-0000-000000000009'),
  ('63000000-0000-0000-0000-000000000005', '61000000-0000-0000-0000-000000000009');

INSERT INTO public.property_company_relationships (
  id,
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES
  ('64000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('64000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('64000000-0000-0000-0000-000000000003', '63000000-0000-0000-0000-000000000003', '62000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('64000000-0000-0000-0000-000000000004', '63000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('64000000-0000-0000-0000-000000000005', '63000000-0000-0000-0000-000000000005', '62000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'INSPECTION_SERVICE'),
  ('64000000-0000-0000-0000-000000000006', '63000000-0000-0000-0000-000000000005', '62000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.company_property_settings (company_id, property_id, created_at)
VALUES
  ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000001', '2026-01-01 00:00:00+00'),
  ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000003', '2026-02-01 00:00:00+00');

INSERT INTO public.property_staff_assignments (
  company_id,
  property_id,
  profile_id,
  is_active,
  created_at
)
VALUES
  ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000003', true, '2026-01-01 00:00:00+00'),
  ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000003', '61000000-0000-0000-0000-000000000007', true, '2026-02-01 00:00:00+00');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000008';

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.properties),
  ARRAY[
    '63000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000002',
    '63000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'Andrea reads A1, A2, and B1 across company boundaries without membership'
);

SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = '63000000-0000-0000-0000-000000000004'),
  0::bigint,
  'Andrea cannot read Owner B property B2 by hostile UUID substitution'
);

SELECT is(
  (SELECT array_agg(property_id ORDER BY property_id) FROM public.property_owners),
  ARRAY[
    '63000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000002',
    '63000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'Andrea reads ownership rows only for properties she owns'
);

SELECT ok(
  (SELECT count(*) FROM public.property_company_relationships) = 0
    AND (SELECT count(*) FROM public.company_property_settings) = 0
    AND (SELECT count(*) FROM public.property_staff_assignments) = 0,
  'Andrea ownership does not expose company relationships, settings, or assignments'
);

SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  '42501',
  NULL,
  'an owner cannot create company settings for an owned property'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.properties),
  ARRAY[
    '63000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000002',
    '63000000-0000-0000-0000-000000000005'
  ]::uuid[],
  'Admin A reads A1, A2, and its service property shell'
);

SELECT ok(
  (SELECT count(*) FROM public.properties WHERE id IN (
    '63000000-0000-0000-0000-000000000003',
    '63000000-0000-0000-0000-000000000004'
  )) = 0
    AND (SELECT count(*) FROM public.property_owners WHERE property_id = '63000000-0000-0000-0000-000000000003') = 0
    AND (SELECT count(*) FROM public.property_company_relationships WHERE property_id = '63000000-0000-0000-0000-000000000003') = 0,
  'Admin A cannot discover B1 or B2 even though Andrea also owns B1'
);

SELECT is(
  (SELECT array_agg(property_id ORDER BY property_id) FROM public.property_owners),
  ARRAY[
    '63000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000002',
    '63000000-0000-0000-0000-000000000005'
  ]::uuid[],
  'Admin A sees ownership rows only for Company A authorized properties'
);

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.property_company_relationships),
  ARRAY[
    '64000000-0000-0000-0000-000000000001',
    '64000000-0000-0000-0000-000000000002',
    '64000000-0000-0000-0000-000000000005'
  ]::uuid[],
  'Admin A reads only Company A relationship rows'
);

SELECT ok(
  (SELECT count(*) FROM public.company_property_settings) = 1
    AND (SELECT count(*) FROM public.property_staff_assignments) = 1,
  'Admin A reads only Company A settings and assignments'
);

SELECT ok(
  security.company_has_property_access(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000005'
  )
    AND security.company_has_property_scope(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000005',
      ARRAY['INSPECTION_SERVICE']::public.property_company_relationship_scope[]
    )
    AND NOT security.company_has_property_scope(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000005',
      ARRAY['FULL_MANAGEMENT']::public.property_company_relationship_scope[]
    )
    AND NOT security.company_has_property_scope(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000005',
      ARRAY['MAINTENANCE_SERVICE']::public.property_company_relationship_scope[]
    ),
  'SERVICE shell access does not broaden to full management or another service scope'
);

SELECT throws_ok(
  $$INSERT INTO public.property_owners (property_id, profile_id) VALUES ('63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001')$$,
  '42501',
  NULL,
  'Admin A cannot self-attach as a property owner'
);

SELECT throws_ok(
  $$DELETE FROM public.property_company_relationships WHERE id = '64000000-0000-0000-0000-000000000001'$$,
  '42501',
  NULL,
  'Admin A cannot mutate relationship lifecycle directly'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000003';

SELECT ok(
  (SELECT array_agg(id ORDER BY id) FROM public.properties) = ARRAY['63000000-0000-0000-0000-000000000001']::uuid[]
    AND (SELECT array_agg(property_id ORDER BY property_id) FROM public.property_owners) = ARRAY['63000000-0000-0000-0000-000000000001']::uuid[]
    AND (SELECT array_agg(id ORDER BY id) FROM public.property_company_relationships) = ARRAY['64000000-0000-0000-0000-000000000001']::uuid[]
    AND (SELECT count(*) FROM public.company_property_settings) = 1
    AND (SELECT count(*) FROM public.property_staff_assignments) = 1,
  'Inspector A reads assigned A1 context only'
);

SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = '63000000-0000-0000-0000-000000000002'),
  0::bigint,
  'Inspector A cannot read unassigned A2 by hostile UUID substitution'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000004';

SELECT ok(
  (SELECT count(*) FROM public.properties) = 0
    AND (SELECT count(*) FROM public.property_owners) = 0
    AND (SELECT count(*) FROM public.property_company_relationships) = 0
    AND (SELECT count(*) FROM public.company_property_settings) = 0
    AND (SELECT count(*) FROM public.property_staff_assignments) = 0,
  'unassigned Inspector A2 cannot read A1 or any other Company A property context'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000006';

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.properties),
  ARRAY[
    '63000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000002',
    '63000000-0000-0000-0000-000000000005'
  ]::uuid[],
  'READ_ONLY selects authorized Company A property context'
);

SELECT throws_ok(
  $$INSERT INTO public.properties (name) VALUES ('ReadOnly attack')$$,
  '42501', NULL, 'READ_ONLY cannot insert properties'
);
SELECT throws_ok(
  $$UPDATE public.properties SET name = 'ReadOnly attack' WHERE id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot update properties'
);
SELECT throws_ok(
  $$DELETE FROM public.properties WHERE id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot delete properties'
);
SELECT throws_ok(
  $$INSERT INTO public.property_owners (property_id, profile_id) VALUES ('63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000006')$$,
  '42501', NULL, 'READ_ONLY cannot insert ownership rows'
);
SELECT throws_ok(
  $$UPDATE public.property_owners SET profile_id = '61000000-0000-0000-0000-000000000006' WHERE property_id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot update ownership rows'
);
SELECT throws_ok(
  $$DELETE FROM public.property_owners WHERE property_id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot delete ownership rows'
);
SELECT throws_ok(
  $$INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope) VALUES ('63000000-0000-0000-0000-000000000004', '62000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'INSPECTION_SERVICE')$$,
  '42501', NULL, 'READ_ONLY cannot insert relationship rows'
);
SELECT throws_ok(
  $$UPDATE public.property_company_relationships SET status = 'INACTIVE' WHERE id = '64000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot update relationship rows'
);
SELECT throws_ok(
  $$DELETE FROM public.property_company_relationships WHERE id = '64000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'READ_ONLY cannot delete relationship rows'
);
SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  '42501', NULL, 'READ_ONLY cannot insert company settings'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.company_property_settings
    SET created_at = '2000-01-01 00:00:00+00'
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (0::bigint)$$,
  'READ_ONLY cannot update authorized company settings'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'READ_ONLY cannot delete authorized company settings'
);
SELECT throws_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000006')$$,
  '42501', NULL, 'READ_ONLY cannot insert staff assignments'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.property_staff_assignments
    SET is_active = false
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (0::bigint)$$,
  'READ_ONLY cannot update authorized staff assignments'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'READ_ONLY cannot delete authorized staff assignments'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000005';

SELECT is(
  (SELECT count(*) FROM public.properties),
  3::bigint,
  'COORDINATOR selects authorized Company A property context'
);
SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  '42501', NULL, 'COORDINATOR cannot insert company settings'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.company_property_settings
    SET created_at = '2000-01-01 00:00:00+00'
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (0::bigint)$$,
  'COORDINATOR cannot update company settings'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'COORDINATOR cannot delete company settings'
);
SELECT throws_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000005')$$,
  '42501', NULL, 'COORDINATOR cannot insert staff assignments'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.property_staff_assignments
    SET is_active = false
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (0::bigint)$$,
  'COORDINATOR cannot update staff assignments'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'COORDINATOR cannot delete staff assignments'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  'MANAGER can insert settings for an authorized Company A property'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.company_property_settings
    SET created_at = '2001-01-01 00:00:00+00'
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (1::bigint)$$,
  'MANAGER can update settings for an authorized Company A property'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (1::bigint)$$,
  'MANAGER can delete settings for an authorized Company A property'
);
SELECT lives_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000005')$$,
  'MANAGER can insert assignments for an authorized Company A property'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.property_staff_assignments
    SET is_active = false
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
      AND profile_id = '61000000-0000-0000-0000-000000000005'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (1::bigint)$$,
  'MANAGER can update assignments for an authorized Company A property'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
      AND profile_id = '61000000-0000-0000-0000-000000000005'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (1::bigint)$$,
  'MANAGER can delete assignments for an authorized Company A property'
);

SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000004')$$,
  '42501', NULL, 'MANAGER cannot insert settings with hostile Company B UUIDs'
);
SELECT throws_ok(
  $$UPDATE public.company_property_settings SET company_id = '62000000-0000-0000-0000-000000000002', property_id = '63000000-0000-0000-0000-000000000003' WHERE company_id = '62000000-0000-0000-0000-000000000001' AND property_id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'MANAGER cannot reassign a Company A settings row to Company B UUIDs'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000002'
      AND property_id = '63000000-0000-0000-0000-000000000003'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'MANAGER cannot delete Company B settings by hostile UUID substitution'
);
SELECT throws_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000004', '61000000-0000-0000-0000-000000000002')$$,
  '42501', NULL, 'MANAGER cannot insert assignments with hostile Company B UUIDs'
);
SELECT throws_ok(
  $$UPDATE public.property_staff_assignments SET company_id = '62000000-0000-0000-0000-000000000002', property_id = '63000000-0000-0000-0000-000000000003', profile_id = '61000000-0000-0000-0000-000000000007' WHERE company_id = '62000000-0000-0000-0000-000000000001' AND property_id = '63000000-0000-0000-0000-000000000001' AND profile_id = '61000000-0000-0000-0000-000000000003'$$,
  '42501', NULL, 'MANAGER cannot reassign a Company A assignment to Company B UUIDs'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000002'
      AND property_id = '63000000-0000-0000-0000-000000000003'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (0::bigint)$$,
  'MANAGER cannot delete Company B assignments by hostile UUID substitution'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  'ADMIN can insert settings for an authorized Company A property'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.company_property_settings
    SET created_at = '2002-01-01 00:00:00+00'
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (1::bigint)$$,
  'ADMIN can update settings for an authorized Company A property'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (1::bigint)$$,
  'ADMIN can delete settings for an authorized Company A property'
);
SELECT lives_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000006')$$,
  'ADMIN can insert assignments for an authorized Company A property'
);
SELECT results_eq(
  $$WITH changed AS (
    UPDATE public.property_staff_assignments
    SET is_active = false
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
      AND profile_id = '61000000-0000-0000-0000-000000000006'
    RETURNING 1
  ) SELECT count(*) FROM changed$$,
  $$VALUES (1::bigint)$$,
  'ADMIN can update assignments for an authorized Company A property'
);
SELECT results_eq(
  $$WITH removed AS (
    DELETE FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000002'
      AND profile_id = '61000000-0000-0000-0000-000000000006'
    RETURNING 1
  ) SELECT count(*) FROM removed$$,
  $$VALUES (1::bigint)$$,
  'ADMIN can delete assignments for an authorized Company A property'
);
SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000004')$$,
  '42501', NULL, 'ADMIN cannot insert settings with hostile Company B UUIDs'
);
SELECT throws_ok(
  $$UPDATE public.company_property_settings SET company_id = '62000000-0000-0000-0000-000000000002', property_id = '63000000-0000-0000-0000-000000000003' WHERE company_id = '62000000-0000-0000-0000-000000000001' AND property_id = '63000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'ADMIN cannot reassign settings to hostile Company B UUIDs'
);
SELECT throws_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('62000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-000000000004', '61000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'ADMIN cannot insert assignments with hostile Company B UUIDs'
);
SELECT throws_ok(
  $$UPDATE public.property_staff_assignments SET company_id = '62000000-0000-0000-0000-000000000002', property_id = '63000000-0000-0000-0000-000000000003', profile_id = '61000000-0000-0000-0000-000000000007' WHERE company_id = '62000000-0000-0000-0000-000000000001' AND property_id = '63000000-0000-0000-0000-000000000001' AND profile_id = '61000000-0000-0000-0000-000000000003'$$,
  '42501', NULL, 'ADMIN cannot reassign assignments to hostile Company B UUIDs'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000007';

SELECT ok(
  (SELECT array_agg(id ORDER BY id) FROM public.properties) = ARRAY[
    '63000000-0000-0000-0000-000000000003',
    '63000000-0000-0000-0000-000000000004',
    '63000000-0000-0000-0000-000000000005'
  ]::uuid[]
    AND (SELECT count(*) FROM public.properties WHERE id = '63000000-0000-0000-0000-000000000001') = 0,
  'Admin B reads Company B context but cannot read tenant A property A1'
);

SET LOCAL request.jwt.claim.sub TO '61000000-0000-0000-0000-000000000010';

SELECT ok(
  (SELECT count(*) FROM public.properties) = 0
    AND (SELECT count(*) FROM public.property_owners) = 0
    AND (SELECT count(*) FROM public.property_company_relationships) = 0
    AND (SELECT count(*) FROM public.company_property_settings) = 0
    AND (SELECT count(*) FROM public.property_staff_assignments) = 0,
  'an unrelated nonmember profile fails closed on all five property tables'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  (SELECT count(*) FROM public.properties) = 0
    AND (SELECT count(*) FROM public.property_owners) = 0
    AND (SELECT count(*) FROM public.property_company_relationships) = 0
    AND (SELECT count(*) FROM public.company_property_settings) = 0
    AND (SELECT count(*) FROM public.property_staff_assignments) = 0,
  'an authenticated role without a JWT subject fails closed on every SELECT path'
);

SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002')$$,
  '42501',
  NULL,
  'an authenticated role without a JWT subject cannot mutate settings'
);

RESET ROLE;

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.company_property_settings
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
      AND created_at = '2026-01-01 00:00:00+00'
  )
    AND EXISTS (
      SELECT 1
      FROM public.company_property_settings
      WHERE company_id = '62000000-0000-0000-0000-000000000002'
        AND property_id = '63000000-0000-0000-0000-000000000003'
        AND created_at = '2026-02-01 00:00:00+00'
    )
    AND (SELECT count(*) FROM public.company_property_settings) = 2,
  'hostile and denied settings mutations leave both tenant rows unchanged'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.property_staff_assignments
    WHERE company_id = '62000000-0000-0000-0000-000000000001'
      AND property_id = '63000000-0000-0000-0000-000000000001'
      AND profile_id = '61000000-0000-0000-0000-000000000003'
      AND is_active
      AND created_at = '2026-01-01 00:00:00+00'
  )
    AND EXISTS (
      SELECT 1
      FROM public.property_staff_assignments
      WHERE company_id = '62000000-0000-0000-0000-000000000002'
        AND property_id = '63000000-0000-0000-0000-000000000003'
        AND profile_id = '61000000-0000-0000-0000-000000000007'
        AND is_active
        AND created_at = '2026-02-01 00:00:00+00'
    )
    AND (SELECT count(*) FROM public.property_staff_assignments) = 2,
  'hostile and denied assignment mutations leave both tenant rows unchanged'
);

SELECT * FROM finish();

ROLLBACK;
