BEGIN;

SET LOCAL search_path = extensions, public;

SELECT plan(44);

SELECT has_schema('security', 'security schema exists');

SELECT has_function(
  'security',
  'current_profile_id',
  ARRAY[]::name[],
  'current_profile_id has no caller-supplied identity argument'
);

SELECT has_function(
  'security',
  'is_company_member',
  ARRAY['uuid']::name[],
  'is_company_member accepts only a company UUID'
);

SELECT has_function(
  'security',
  'company_role',
  ARRAY['uuid']::name[],
  'company_role accepts only a company UUID'
);

SELECT has_function(
  'security',
  'has_company_role',
  ARRAY['uuid', 'public.company_role[]']::name[],
  'has_company_role accepts a company UUID and an exact role set'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND count(*) FILTER (
        WHERE proname = 'current_profile_id'
          AND pronargs = 0
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'is_company_member'
          AND proargtypes = ARRAY['uuid'::regtype]::oidvector
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'company_role'
          AND proargtypes = ARRAY['uuid'::regtype]::oidvector
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'has_company_role'
          AND proargtypes = ARRAY[
            'uuid'::regtype,
            'public.company_role[]'::regtype
          ]::oidvector
      ) = 1
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'current_profile_id',
        'is_company_member',
        'company_role',
        'has_company_role'
      ])
  ), false),
  'security contains exactly the four approved Task 5 helper signatures'
);

SELECT ok(
  COALESCE((
    SELECT NOT procedure.prosecdef
      AND procedure.provolatile = 's'
      AND language.lanname = 'sql'
      AND procedure.prorettype = 'uuid'::regtype
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    JOIN pg_language language ON language.oid = procedure.prolang
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'current_profile_id'
      AND procedure.pronargs = 0
  ), false),
  'current_profile_id is a stable SQL invoker returning uuid with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
      AND procedure.provolatile = 's'
      AND language.lanname = 'sql'
      AND procedure.prorettype = 'boolean'::regtype
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    JOIN pg_language language ON language.oid = procedure.prolang
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'is_company_member'
      AND procedure.proargtypes = ARRAY['uuid'::regtype]::oidvector
  ), false),
  'is_company_member is a stable SQL definer returning boolean with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
      AND procedure.provolatile = 's'
      AND language.lanname = 'sql'
      AND procedure.prorettype = 'public.company_role'::regtype
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    JOIN pg_language language ON language.oid = procedure.prolang
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'company_role'
      AND procedure.proargtypes = ARRAY['uuid'::regtype]::oidvector
  ), false),
  'company_role is a stable SQL definer returning company_role with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT NOT procedure.prosecdef
      AND procedure.provolatile = 's'
      AND language.lanname = 'sql'
      AND procedure.prorettype = 'boolean'::regtype
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    JOIN pg_language language ON language.oid = procedure.prolang
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'has_company_role'
      AND procedure.proargtypes = ARRAY[
        'uuid'::regtype,
        'public.company_role[]'::regtype
      ]::oidvector
  ), false),
  'has_company_role is a stable SQL invoker returning boolean with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT NOT EXISTS (
      SELECT 1
      FROM aclexplode(COALESCE(
        namespace.nspacl,
        acldefault('n', namespace.nspowner)
      )) privilege
      WHERE privilege.grantee = 0
    )
    FROM pg_namespace namespace
    WHERE namespace.nspname = 'security'
  ), false),
  'PUBLIC has no privileges on the security schema'
);

SELECT ok(
  COALESCE((
    SELECT NOT has_schema_privilege('anon', namespace.oid, 'USAGE')
      AND NOT has_schema_privilege('anon', namespace.oid, 'CREATE')
    FROM pg_namespace namespace
    WHERE namespace.nspname = 'security'
  ), false),
  'anon has no privileges on the security schema'
);

SELECT ok(
  COALESCE((
    SELECT has_schema_privilege('authenticated', namespace.oid, 'USAGE')
      AND NOT has_schema_privilege('authenticated', namespace.oid, 'CREATE')
    FROM pg_namespace namespace
    WHERE namespace.nspname = 'security'
  ), false),
  'authenticated has schema usage but cannot create security objects'
);

SELECT ok(
  COALESCE((
    SELECT count(DISTINCT procedure.oid) = 4
      AND count(*) FILTER (
        WHERE privilege.grantee = 0
          AND privilege.privilege_type = 'EXECUTE'
      ) = 0
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    LEFT JOIN LATERAL aclexplode(COALESCE(
      procedure.proacl,
      acldefault('f', procedure.proowner)
    )) privilege ON true
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'current_profile_id',
        'is_company_member',
        'company_role',
        'has_company_role'
      ])
  ), false),
  'PUBLIC execute is revoked from all four Task 5 helpers'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(NOT has_function_privilege('anon', procedure.oid, 'EXECUTE'))
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'current_profile_id',
        'is_company_member',
        'company_role',
        'has_company_role'
      ])
  ), false),
  'anon cannot execute any Task 5 helper'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(has_function_privilege('authenticated', procedure.oid, 'EXECUTE'))
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'current_profile_id',
        'is_company_member',
        'company_role',
        'has_company_role'
      ])
  ), false),
  'authenticated can execute exactly the four Task 5 helpers'
);

SELECT ok(
  COALESCE((
    SELECT relrowsecurity AND NOT relforcerowsecurity
    FROM pg_class
    WHERE oid = to_regclass('public.company_memberships')
  ), false),
  'company_memberships keeps ordinary RLS enabled without forced owner filtering'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policy
    WHERE polrelid = to_regclass('public.company_memberships')
  ),
  'company_memberships still has zero RLS policies'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'is_assigned_to_inspection',
        'can_view_operational_record',
        'can_manage_operational_record',
        'owner_can_view_report',
        'owner_can_view_quote_version',
        'owner_can_view_document'
      ])
  ),
  'later inspection and operational helpers remain deferred'
);

SELECT (count(*) = 4)::integer AS helpers_ready
FROM pg_proc procedure
JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
WHERE namespace.nspname = 'security'
  AND procedure.proname = ANY (ARRAY[
    'current_profile_id',
    'is_company_member',
    'company_role',
    'has_company_role'
  ])
\gset

\if :helpers_ready

INSERT INTO auth.users (id)
VALUES
  ('41000000-0000-0000-0000-000000000001'),
  ('41000000-0000-0000-0000-000000000002');

INSERT INTO public.profiles (id)
VALUES
  ('41000000-0000-0000-0000-000000000001'),
  ('41000000-0000-0000-0000-000000000002');

INSERT INTO public.companies (id, name)
VALUES
  ('42000000-0000-0000-0000-000000000001', 'Security Company A'),
  ('42000000-0000-0000-0000-000000000002', 'Security Company B'),
  ('42000000-0000-0000-0000-000000000003', 'Inactive Membership Company');

INSERT INTO public.company_memberships (
  company_id,
  profile_id,
  role,
  is_active
)
VALUES
  (
    '42000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001',
    'ADMIN',
    true
  ),
  (
    '42000000-0000-0000-0000-000000000002',
    '41000000-0000-0000-0000-000000000001',
    'READ_ONLY',
    true
  ),
  (
    '42000000-0000-0000-0000-000000000003',
    '41000000-0000-0000-0000-000000000001',
    'MANAGER',
    false
  );

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT is(
  security.current_profile_id(),
  '41000000-0000-0000-0000-000000000001'::uuid,
  'current_profile_id returns the authenticated JWT profile'
);

SELECT throws_ok(
  $$SELECT count(*) FROM public.company_memberships$$,
  '42501', NULL,
  'authenticated has no direct table privilege on company_memberships; access is mediated only through SECURITY DEFINER helpers'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT is(
  security.current_profile_id(),
  NULL::uuid,
  'current_profile_id returns NULL without an authenticated subject'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT ok(
  security.is_company_member('42000000-0000-0000-0000-000000000001'),
  'an active membership is recognized'
);

SELECT ok(
  NOT security.is_company_member('42000000-0000-0000-0000-000000000003'),
  'an inactive membership is rejected'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000002';

SELECT ok(
  NOT security.is_company_member('42000000-0000-0000-0000-000000000001'),
  'another profile cannot use the active membership'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT ok(
  NOT security.is_company_member('42000000-0000-0000-0000-000000000099'),
  'a nonexistent company has no membership'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  NOT security.is_company_member('42000000-0000-0000-0000-000000000001'),
  'no Auth context has no membership'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000001'),
  'ADMIN'::public.company_role,
  'Company A returns the active ADMIN role'
);

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000002'),
  'READ_ONLY'::public.company_role,
  'Company B returns the active READ_ONLY role'
);

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000003'),
  NULL::public.company_role,
  'an inactive membership returns no role'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000002';

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000001'),
  NULL::public.company_role,
  'a profile with no membership returns no role'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000001'),
  NULL::public.company_role,
  'no Auth context returns no company role'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT ok(
  security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    ARRAY['ADMIN']::public.company_role[]
  ),
  'ADMIN requested as ADMIN is true'
);

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    ARRAY['MANAGER']::public.company_role[]
  ),
  'ADMIN requested only as MANAGER is false without role hierarchy'
);

SELECT ok(
  security.has_company_role(
    '42000000-0000-0000-0000-000000000002',
    ARRAY['READ_ONLY']::public.company_role[]
  ),
  'READ_ONLY requested as READ_ONLY is true'
);

SELECT ok(
  security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    ARRAY['MANAGER', 'ADMIN']::public.company_role[]
  ),
  'a role included in a multi-role set is true'
);

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000002',
    ARRAY['ADMIN', 'MANAGER']::public.company_role[]
  ),
  'a role absent from a multi-role set is false'
);

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000003',
    ARRAY['MANAGER']::public.company_role[]
  ),
  'an inactive role never grants access'
);

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    ARRAY[]::public.company_role[]
  ),
  'an empty requested role set is false'
);

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    NULL::public.company_role[]
  ),
  'a NULL requested role set is false'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  NOT security.has_company_role(
    '42000000-0000-0000-0000-000000000001',
    ARRAY['ADMIN']::public.company_role[]
  ),
  'no Auth context never has a company role'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000001';

SELECT ok(
  security.company_role('42000000-0000-0000-0000-000000000001') = 'ADMIN'::public.company_role
    AND security.company_role('42000000-0000-0000-0000-000000000002') = 'READ_ONLY'::public.company_role,
  'one global profile receives its different correct roles for Companies A and B'
);

SET LOCAL request.jwt.claim.sub TO '41000000-0000-0000-0000-000000000002';

SELECT is(
  security.company_role('42000000-0000-0000-0000-000000000001'),
  NULL::public.company_role,
  'Profile B cannot obtain Profile A role from only a company UUID'
);

SELECT ok(
  NOT security.is_company_member('42000000-0000-0000-0000-000000000001'),
  'Profile B cannot claim Profile A membership from only a company UUID'
);

RESET ROLE;

\else

SELECT * FROM skip(25, 'helper behavior requires migration 004');

\endif

SELECT * FROM finish();

ROLLBACK;
