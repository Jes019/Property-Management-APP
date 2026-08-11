BEGIN;

SET LOCAL search_path = extensions, public;

SELECT plan(11);

SELECT ok(
  to_regclass('public.profiles') IS NOT NULL,
  'profiles exists in public'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.profiles')
      AND attname = 'id'
      AND NOT attisdropped
      AND atttypid = 'uuid'::regtype
  ),
  'profiles.id is uuid'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.profiles')
      AND attname = 'id'
      AND NOT attisdropped
      AND attnotnull
  ),
  'profiles.id is not null'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (
        SELECT attnum
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.profiles')
          AND attname = 'id'
          AND NOT attisdropped
      )
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.profiles')
      AND contype = 'p'
  ), false),
  'profiles primary key is id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (
        SELECT attnum
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.profiles')
          AND attname = 'id'
          AND NOT attisdropped
      )
    ]::smallint[]
      AND confrelid = 'auth.users'::regclass
      AND confkey = ARRAY[
        (
          SELECT attnum
          FROM pg_attribute
          WHERE attrelid = 'auth.users'::regclass
            AND attname = 'id'
            AND NOT attisdropped
        )
      ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.profiles')
      AND contype = 'f'
  ), false),
  'profiles.id foreign key targets auth.users(id)'
);

SELECT ok(
  COALESCE((
    SELECT confdeltype = 'c'
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.profiles')
      AND contype = 'f'
  ), false),
  'profiles auth foreign key cascades on delete'
);

SELECT ok(
  COALESCE((
    SELECT confupdtype = 'a'
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.profiles')
      AND contype = 'f'
  ), false),
  'profiles auth foreign key uses no action on update'
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
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = to_regclass('public.profiles')
  ), false),
  'profiles has row level security enabled'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policy
    WHERE polrelid = to_regclass('public.profiles')
  ),
  'profiles has no row level security policies'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY['id']::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.profiles')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'profiles has only the identity column in this slice'
);

SELECT * FROM finish();

ROLLBACK;
