BEGIN;

SET LOCAL search_path = extensions, public;

SELECT plan(31);

SELECT ok(
  to_regclass('public.companies') IS NOT NULL,
  'companies exists in public'
);

SELECT ok(
  to_regclass('public.company_branding') IS NOT NULL,
  'company_branding exists in public'
);

SELECT ok(
  to_regclass('public.company_memberships') IS NOT NULL,
  'company_memberships exists in public'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY['id', 'name', 'created_at']::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.companies')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'companies has only id, name, and created_at columns'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[(
      SELECT attnum
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.companies')
        AND attname = 'id'
        AND NOT attisdropped
    )]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.companies')
      AND contype = 'p'
  ), false),
  'companies primary key is id'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute attribute
    JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.companies')
      AND attribute.attname = 'id'
      AND NOT attribute.attisdropped
      AND attribute.atttypid = 'uuid'::regtype
      AND attribute.attnotnull
      AND pg_get_expr(default_value.adbin, default_value.adrelid) = 'gen_random_uuid()'
  ),
  'companies.id is a generated uuid'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.companies')
      AND attname = 'name'
      AND NOT attisdropped
      AND atttypid = 'text'::regtype
      AND attnotnull
  ),
  'companies.name is required text'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute attribute
    JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.companies')
      AND attribute.attname = 'created_at'
      AND NOT attribute.attisdropped
      AND attribute.atttypid = 'timestamp with time zone'::regtype
      AND attribute.attnotnull
      AND pg_get_expr(default_value.adbin, default_value.adrelid) = 'now()'
  ),
  'companies.created_at is required and defaults to now'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'company_id', 'logo_path', 'favicon_path', 'primary_color', 'accent_color', 'background_color'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.company_branding')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'company_branding has only the one-to-one branding columns'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[(
      SELECT attnum
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.company_branding')
        AND attname = 'company_id'
        AND NOT attisdropped
    )]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_branding')
      AND contype = 'p'
  ), false),
  'company_branding primary key is company_id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[(
      SELECT attnum
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.company_branding')
        AND attname = 'company_id'
        AND NOT attisdropped
    )]::smallint[]
      AND confrelid = 'public.companies'::regclass
      AND confdeltype = 'c'
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_branding')
      AND contype = 'f'
  ), false),
  'company_branding company foreign key cascades on delete'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'company_id', 'profile_id', 'role', 'is_active', 'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.company_memberships')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'company_memberships has only the required relationship columns'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (
        SELECT attnum
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.company_memberships')
          AND attname = 'company_id'
          AND NOT attisdropped
      ),
      (
        SELECT attnum
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.company_memberships')
          AND attname = 'profile_id'
          AND NOT attisdropped
      )
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_memberships')
      AND contype = 'p'
  ), false),
  'company_memberships primary key is company_id and profile_id'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_memberships')
      AND contype = 'f'
      AND conkey = ARRAY[(
      SELECT attnum
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.company_memberships')
        AND attname = 'company_id'
        AND NOT attisdropped
      )]::smallint[]
      AND confrelid = 'public.companies'::regclass
      AND confdeltype = 'c'
  ),
  'company_memberships company foreign key cascades on delete'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_memberships')
      AND contype = 'f'
      AND conkey = ARRAY[(
      SELECT attnum
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.company_memberships')
        AND attname = 'profile_id'
        AND NOT attisdropped
      )]::smallint[]
      AND confrelid = 'public.profiles'::regclass
      AND confdeltype = 'c'
  ),
  'company_memberships profile foreign key cascades on delete'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.company_memberships')
      AND attname = 'role'
      AND NOT attisdropped
      AND atttypid = 'public.company_role'::regtype
      AND attnotnull
  ),
  'company_memberships.role uses the public.company_role enum'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute attribute
    JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.company_memberships')
      AND attribute.attname = 'is_active'
      AND NOT attribute.attisdropped
      AND attribute.atttypid = 'boolean'::regtype
      AND attribute.attnotnull
      AND pg_get_expr(default_value.adbin, default_value.adrelid) = 'true'
  ),
  'company_memberships.is_active is required boolean and defaults true'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute attribute
    JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.company_memberships')
      AND attribute.attname = 'created_at'
      AND NOT attribute.attisdropped
      AND attribute.atttypid = 'timestamp with time zone'::regtype
      AND attribute.attnotnull
      AND pg_get_expr(default_value.adbin, default_value.adrelid) = 'now()'
  ),
  'company_memberships.created_at is required and defaults to now'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY['id']::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.profiles')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'profiles remains global with only its id column'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.profiles')
      AND attname = 'company_id'
      AND NOT attisdropped
  ),
  'profiles has no company_id column'
);

SELECT ok(
  COALESCE((
    SELECT bool_and(relrowsecurity)
    FROM pg_class
    WHERE oid = ANY (ARRAY[
      'public.companies'::regclass,
      'public.company_branding'::regclass,
      'public.company_memberships'::regclass
    ])
  ), false),
  'row level security is enabled on all Task 4 tables'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policy
    WHERE polrelid = ANY (ARRAY[
      'public.companies'::regclass,
      'public.company_branding'::regclass,
      'public.company_memberships'::regclass
    ])
  ),
  'Task 4 tables have zero row level security policies'
);

INSERT INTO auth.users (id)
VALUES ('10000000-0000-0000-0000-000000000001');

INSERT INTO public.profiles (id)
VALUES ('10000000-0000-0000-0000-000000000001');

WITH created_company AS (
  INSERT INTO public.companies (name)
  VALUES ('Generated UUID company')
  RETURNING id, created_at
)
SELECT ok(
  (SELECT id IS NOT NULL AND created_at IS NOT NULL FROM created_company),
  'companies generates an id and timestamp for a new company'
);

INSERT INTO public.companies (id, name)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'Company A'),
  ('20000000-0000-0000-0000-000000000002', 'Company B');

INSERT INTO public.company_branding (company_id, primary_color)
VALUES ('20000000-0000-0000-0000-000000000001', '#004B87');

SELECT throws_ok(
  $$INSERT INTO public.company_branding (company_id) VALUES ('20000000-0000-0000-0000-000000000001')$$,
  '23505',
  NULL,
  'company_branding permits at most one row for a company'
);

INSERT INTO public.company_memberships (company_id, profile_id, role)
VALUES (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'ADMIN'
);

SELECT ok(
  (SELECT is_active FROM public.company_memberships
   WHERE company_id = '20000000-0000-0000-0000-000000000001'
     AND profile_id = '10000000-0000-0000-0000-000000000001'),
  'a new membership is active by default'
);

UPDATE public.company_memberships
SET is_active = false
WHERE company_id = '20000000-0000-0000-0000-000000000001'
  AND profile_id = '10000000-0000-0000-0000-000000000001';

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.company_memberships
    WHERE company_id = '20000000-0000-0000-0000-000000000001'
      AND profile_id = '10000000-0000-0000-0000-000000000001'
      AND is_active = false
  ),
  'an inactive membership remains as a row'
);

SELECT throws_ok(
  $$INSERT INTO public.company_memberships (company_id, profile_id, role) VALUES ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'MANAGER')$$,
  '23505',
  NULL,
  'duplicate company and profile memberships are rejected'
);

SELECT throws_ok(
  $$INSERT INTO public.company_memberships (company_id, profile_id, role) VALUES ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'OWNER')$$,
  '22P02',
  NULL,
  'OWNER is rejected as a company membership role'
);

INSERT INTO public.company_memberships (company_id, profile_id, role)
VALUES (
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  'READ_ONLY'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(company_id ORDER BY company_id) = ARRAY[
      '20000000-0000-0000-0000-000000000002'::uuid
    ]
    FROM public.company_memberships
    WHERE profile_id = '10000000-0000-0000-0000-000000000001'
      AND is_active
  ), false),
  'active membership lookup excludes inactive Company A and returns active Company B'
);

SELECT ok(
  (
    SELECT count(*) = 2
       AND count(*) FILTER (WHERE role = 'ADMIN'::public.company_role) = 1
       AND count(*) FILTER (WHERE role = 'READ_ONLY'::public.company_role) = 1
    FROM public.company_memberships
    WHERE profile_id = '10000000-0000-0000-0000-000000000001'
  )
  AND (
    SELECT count(*) = 1
    FROM public.profiles
    WHERE id = '10000000-0000-0000-0000-000000000001'
  ),
  'one global profile can be ADMIN in Company A and READ_ONLY in Company B'
);

DELETE FROM public.companies
WHERE id = '20000000-0000-0000-0000-000000000001';

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.company_branding
    WHERE company_id = '20000000-0000-0000-0000-000000000001'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.company_memberships
    WHERE company_id = '20000000-0000-0000-0000-000000000001'
  )
  AND EXISTS (
    SELECT 1 FROM public.company_memberships
    WHERE company_id = '20000000-0000-0000-0000-000000000002'
      AND profile_id = '10000000-0000-0000-0000-000000000001'
  ),
  'deleting a company cascades its branding and membership only'
);

SELECT * FROM finish();

ROLLBACK;
