BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_table('public', 'media_assets', 'media_assets exists in public');

SELECT ok(
  COALESCE((
    SELECT array_agg(attribute.attname ORDER BY attribute.attnum) = ARRAY[
      'id',
      'company_id',
      'property_id',
      'inspection_id',
      'inspection_result_id',
      'meter_reading_id',
      'storage_bucket',
      'storage_path',
      'mime_type',
      'file_size_bytes',
      'created_by',
      'created_at'
    ]::name[]
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = to_regclass('public.media_assets')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'media_assets has exactly the approved Task 10 columns'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(
          pg_get_expr(default_value.adbin, default_value.adrelid),
          '<none>'
        )
      )
      ORDER BY attribute.attnum
    ) = '[
      ["id", "uuid", true, "gen_random_uuid()"],
      ["company_id", "uuid", true, "<none>"],
      ["property_id", "uuid", true, "<none>"],
      ["inspection_id", "uuid", false, "<none>"],
      ["inspection_result_id", "uuid", false, "<none>"],
      ["meter_reading_id", "uuid", false, "<none>"],
      ["storage_bucket", "text", true, "<none>"],
      ["storage_path", "text", true, "<none>"],
      ["mime_type", "text", false, "<none>"],
      ["file_size_bytes", "bigint", false, "<none>"],
      ["created_by", "uuid", true, "<none>"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute AS attribute
    LEFT JOIN pg_attrdef AS default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.media_assets')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'media_assets types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT constraint_state.conkey = ARRAY[attribute.attnum]::smallint[]
    FROM pg_constraint AS constraint_state
    JOIN pg_attribute AS attribute
      ON attribute.attrelid = constraint_state.conrelid
     AND attribute.attname = 'id'
    WHERE constraint_state.conrelid = to_regclass('public.media_assets')
      AND constraint_state.contype = 'p'
  ), false),
  'media_assets uses id as its UUID primary key'
);

WITH expected(child_column, parent_table) AS (
  VALUES
    ('company_id'::name, 'companies'::name),
    ('property_id', 'properties'),
    ('inspection_id', 'inspections'),
    ('inspection_result_id', 'inspection_results'),
    ('meter_reading_id', 'meter_readings'),
    ('created_by', 'profiles')
), actual AS (
  SELECT
    child_attribute.attname AS child_column,
    parent.relname AS parent_table
  FROM pg_constraint AS constraint_state
  JOIN pg_class AS parent ON parent.oid = constraint_state.confrelid
  JOIN pg_attribute AS child_attribute
    ON child_attribute.attrelid = constraint_state.conrelid
   AND child_attribute.attnum = constraint_state.conkey[1]
  WHERE constraint_state.conrelid = to_regclass('public.media_assets')
    AND constraint_state.contype = 'f'
    AND constraint_state.confdeltype = 'a'
    AND cardinality(constraint_state.conkey) = 1
    AND cardinality(constraint_state.confkey) = 1
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'media_assets has exact non-cascading company, property, parent, and actor foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE
          '%num_nonnulls(inspection_id, inspection_result_id, meter_reading_id) = 1%'
      ) = 1
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE
          '%storage_bucket = ''inspection-media''%'
      ) = 1
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE
          '%file_size_bytes >= 0%'
      ) = 1
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE
          '%mime_type = ANY%image/jpeg%image/png%image/webp%image/heic%image/heif%'
      ) = 1
    FROM pg_constraint AS constraint_state
    WHERE constraint_state.conrelid = to_regclass('public.media_assets')
      AND constraint_state.contype = 'c'
  ), false),
  'media_assets has only the parent, bucket, nonnegative-size, and image MIME checks'
);

WITH expected(index_name) AS (
  VALUES
    ('media_assets_storage_bucket_storage_path_key'::name),
    ('media_assets_company_id_property_id_idx'),
    ('media_assets_inspection_id_idx'),
    ('media_assets_inspection_result_id_idx'),
    ('media_assets_meter_reading_id_idx')
), actual AS (
  SELECT index_relation.relname AS index_name
  FROM pg_index AS index_state
  JOIN pg_class AS index_relation ON index_relation.oid = index_state.indexrelid
  WHERE index_state.indrelid = to_regclass('public.media_assets')
    AND NOT index_state.indisprimary
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'media_assets has only the exact path and authorization parent indexes'
);

SELECT ok(
  COALESCE((
    SELECT relation.relrowsecurity AND NOT relation.relforcerowsecurity
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.media_assets')
  ), false),
  'media_assets uses ordinary non-forced RLS'
);

WITH expected(policyname, cmd) AS (
  VALUES
    ('media_assets_company_select'::name, 'SELECT'::text),
    ('media_assets_operational_insert', 'INSERT'),
    ('media_assets_operational_delete', 'DELETE')
), actual AS (
  SELECT policyname, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'media_assets'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'media_assets has exactly SELECT, INSERT, and DELETE policies and no UPDATE path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 3
      AND bool_and(permissive = 'PERMISSIVE')
      AND bool_and(roles = ARRAY['authenticated']::name[])
      AND bool_and(
        position('security.company_has_property_scope' in
          COALESCE(qual, with_check)) > 0
      )
      AND bool_and(position('FULL_MANAGEMENT' in COALESCE(qual, with_check)) > 0)
      AND bool_and(position('INSPECTION_SERVICE' in COALESCE(qual, with_check)) > 0)
      AND bool_and(position('MAINTENANCE_SERVICE' in COALESCE(qual, with_check)) = 0)
      AND bool_and(position('COORDINATION_SERVICE' in COALESCE(qual, with_check)) = 0)
      AND bool_and(lower(COALESCE(qual, '') || COALESCE(with_check, '')) NOT LIKE '%owner%')
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'media_assets'
  ), false),
  'media policies are authenticated, inspection-scoped, and contain no owner path'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class AS relation
    CROSS JOIN LATERAL aclexplode(COALESCE(
      relation.relacl,
      acldefault('r', relation.relowner)
    )) AS privilege
    WHERE relation.oid = to_regclass('public.media_assets')
      AND privilege.grantee = 0
  ),
  'PUBLIC has no media_assets privilege'
);

SELECT ok(
  COALESCE((
    SELECT NOT has_table_privilege('anon', relation.oid, 'SELECT')
      AND NOT has_table_privilege('anon', relation.oid, 'INSERT')
      AND NOT has_table_privilege('anon', relation.oid, 'UPDATE')
      AND NOT has_table_privilege('anon', relation.oid, 'DELETE')
      AND has_table_privilege('authenticated', relation.oid, 'SELECT')
      AND has_table_privilege('authenticated', relation.oid, 'INSERT')
      AND NOT has_table_privilege('authenticated', relation.oid, 'UPDATE')
      AND has_table_privilege('authenticated', relation.oid, 'DELETE')
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.media_assets')
  ), false),
  'media_assets grants only SELECT, INSERT, DELETE to authenticated and nothing to anon'
);

SELECT ok(
  COALESCE((
    SELECT NOT bucket.public
      AND bucket.allowed_mime_types = ARRAY[
        'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
      ]::text[]
    FROM storage.buckets AS bucket
    WHERE bucket.id = 'inspection-media'
      AND bucket.name = 'inspection-media'
  ), false),
  'inspection-media bucket exists, is private, and permits only approved image MIME types'
);

WITH expected(policyname, cmd) AS (
  VALUES
    ('inspection_media_objects_select'::name, 'SELECT'::text),
    ('inspection_media_objects_insert', 'INSERT'),
    ('inspection_media_objects_update', 'UPDATE'),
    ('inspection_media_objects_delete', 'DELETE')
), actual AS (
  SELECT policyname, cmd
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname LIKE 'inspection_media_objects_%'
    AND policyname NOT LIKE '%\_owner\_%' ESCAPE '\'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'storage.objects has exactly four Task 10 inspection-media policies (Task 12''s owner policy is separate)'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(permissive = 'PERMISSIVE')
      AND bool_and(roles = ARRAY['authenticated']::name[])
      AND bool_and(position('security.can_' in COALESCE(qual, with_check)) > 0)
      AND bool_and(
        CASE WHEN cmd = 'UPDATE'
          THEN position('security.can_mutate_inspection_media_object' in qual) > 0
            AND position('security.can_mutate_inspection_media_object' in with_check) > 0
          ELSE true
        END
      )
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname LIKE 'inspection_media_objects_%'
      AND policyname NOT LIKE '%\_owner\_%' ESCAPE '\'
  ), false),
  'storage policies are authenticated-only and resolve through dedicated DB helpers'
);

SELECT has_function(
  'security',
  'can_read_inspection_media_object',
  ARRAY['text', 'text']::name[],
  'storage read helper accepts only exact bucket and path'
);
SELECT has_function(
  'security',
  'can_mutate_inspection_media_object',
  ARRAY['text', 'text']::name[],
  'storage mutation helper accepts only exact bucket and path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND bool_and(procedure.prosecdef)
      AND count(*) FILTER (
        WHERE procedure.proname = 'can_read_inspection_media_object'
          AND procedure.provolatile = 's'
          AND procedure.prolang = (
            SELECT oid FROM pg_language WHERE lanname = 'sql'
          )
      ) = 1
      AND count(*) FILTER (
        WHERE procedure.proname = 'can_mutate_inspection_media_object'
          AND procedure.provolatile = 'v'
          AND procedure.prolang = (
            SELECT oid FROM pg_language WHERE lanname = 'plpgsql'
          )
          AND position('FOR SHARE' in upper(pg_get_functiondef(procedure.oid))) > 0
      ) = 1
      AND bool_and(procedure.prorettype = 'boolean'::regtype)
      AND bool_and(procedure.proconfig = ARRAY['search_path=pg_catalog']::text[])
      AND bool_and(position('public.media_assets' in pg_get_functiondef(procedure.oid)) > 0)
      AND bool_and(position('asset.storage_bucket = p_bucket_id' in pg_get_functiondef(procedure.oid)) > 0)
      AND bool_and(position('asset.storage_path = p_name' in pg_get_functiondef(procedure.oid)) > 0)
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname IN (
        'can_read_inspection_media_object',
        'can_mutate_inspection_media_object'
      )
  ), false),
  'storage helpers are fixed-path definers with exact row lookup and mutation locking'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND bool_and(NOT has_function_privilege('anon', procedure.oid, 'EXECUTE'))
      AND bool_and(has_function_privilege('authenticated', procedure.oid, 'EXECUTE'))
      AND bool_and(NOT EXISTS (
        SELECT 1
        FROM aclexplode(COALESCE(
          procedure.proacl,
          acldefault('f', procedure.proowner)
        )) AS privilege
        WHERE privilege.grantee = 0
      ))
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname IN (
        'can_read_inspection_media_object',
        'can_mutate_inspection_media_object'
      )
  ), false),
  'storage helpers are executable only by authenticated clients'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prorettype = 'trigger'::regtype
      AND procedure.prosecdef
      AND procedure.provolatile = 'v'
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND NOT has_function_privilege('anon', procedure.oid, 'EXECUTE')
      AND NOT has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1
        FROM aclexplode(COALESCE(
          procedure.proacl,
          acldefault('f', procedure.proowner)
        )) AS privilege
        WHERE privilege.grantee = 0
      )
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'protect_media_asset'
      AND procedure.pronargs = 0
  ), false),
  'media hard guard is a non-callable fixed-path SECURITY DEFINER trigger function'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(trigger_state.tgtype = 31)
      AND bool_and(trigger_state.tgenabled = 'O')
    FROM pg_trigger AS trigger_state
    WHERE trigger_state.tgrelid = to_regclass('public.media_assets')
      AND trigger_state.tgname = 'media_assets_protect_runtime'
      AND NOT trigger_state.tgisinternal
  ), false),
  'one enabled row-level BEFORE trigger protects every media_assets mutation'
);

SELECT (
  to_regclass('public.media_assets') IS NOT NULL
    AND to_regprocedure(
      'security.can_read_inspection_media_object(text,text)'
    ) IS NOT NULL
    AND to_regprocedure(
      'security.can_mutate_inspection_media_object(text,text)'
    ) IS NOT NULL
    AND to_regprocedure('security.protect_media_asset()') IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM storage.buckets WHERE id = 'inspection-media'
    )
)::integer AS media_surface_ready
\gset

\if :media_surface_ready

INSERT INTO auth.users (id)
VALUES
  ('91000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000002'),
  ('91000000-0000-0000-0000-000000000003'),
  ('91000000-0000-0000-0000-000000000004'),
  ('91000000-0000-0000-0000-000000000005'),
  ('91000000-0000-0000-0000-000000000006'),
  ('91000000-0000-0000-0000-000000000007'),
  ('91000000-0000-0000-0000-000000000008'),
  ('91000000-0000-0000-0000-000000000009');

INSERT INTO public.profiles (id)
SELECT id
FROM auth.users
WHERE id::text LIKE '91000000-%';

INSERT INTO public.companies (id, name)
VALUES
  ('92000000-0000-0000-0000-000000000001', 'Media Company A'),
  ('92000000-0000-0000-0000-000000000002', 'Media Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002', 'MANAGER', true),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000003', 'INSPECTOR', true),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000004', 'INSPECTOR', true),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000005', 'COORDINATOR', true),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000006', 'READ_ONLY', true),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000007', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES
  ('93000000-0000-0000-0000-000000000001', 'A1 full management'),
  ('93000000-0000-0000-0000-000000000002', 'A2 inspection service'),
  ('93000000-0000-0000-0000-000000000003', 'A3 maintenance service'),
  ('93000000-0000-0000-0000-000000000004', 'A4 coordination service'),
  ('93000000-0000-0000-0000-000000000005', 'B1 full management');

INSERT INTO public.property_company_relationships (
  id, property_id, company_id, relationship_type, status, scope
)
VALUES
  ('93100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('93100000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'INSPECTION_SERVICE'),
  ('93100000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'MAINTENANCE_SERVICE'),
  ('93100000-0000-0000-0000-000000000004', '93000000-0000-0000-0000-000000000004', '92000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'COORDINATION_SERVICE'),
  ('93100000-0000-0000-0000-000000000005', '93000000-0000-0000-0000-000000000005', '92000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES
  ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000003'),
  ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000004');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000008');

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  ('94000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'Media template A'),
  ('94000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002', 'Media template B');

INSERT INTO public.inspection_template_versions (
  id, template_id, version_number, is_current
)
VALUES
  ('95000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001', 1, false),
  ('95000000-0000-0000-0000-000000000002', '94000000-0000-0000-0000-000000000002', 1, false);

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 'A', 1),
  ('96000000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', 'B', 1);

INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES
  ('97000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', 'A item', 1),
  ('97000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', 'B item', 1);

UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id IN (
  '95000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000002'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000001';

INSERT INTO public.inspections (
  id, company_id, property_id, template_version_id
)
VALUES
  ('98000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001');

UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id IN (
  '98000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000003'
);

INSERT INTO public.inspection_results (
  id, company_id, property_id, inspection_id, template_item_id,
  severity, operational_action
)
VALUES (
  '99000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000001',
  'PASS',
  'MONITOR'
);

INSERT INTO public.meter_readings (
  id, company_id, property_id, inspection_id, meter_type, reading_value, unit
)
VALUES (
  '9a000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001',
  'WATER',
  10,
  'm3'
);

SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type, file_size_bytes, created_by) VALUES ('9b000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000001/overview.jpg', 'image/jpeg', 100, '91000000-0000-0000-0000-000000000007')$$,
  'ADMIN registers an in-progress inspection photo'
);
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_result_id, storage_bucket, storage_path, mime_type, file_size_bytes, created_by) VALUES ('9b000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/result/99000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000002/result.png', 'image/png', 200, '91000000-0000-0000-0000-000000000007')$$,
  'ADMIN registers an in-progress checklist result photo'
);
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, meter_reading_id, storage_bucket, storage_path, mime_type, file_size_bytes, created_by) VALUES ('9b000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '9a000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/meter/9a000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000003/meter.webp', 'image/webp', 0, '91000000-0000-0000-0000-000000000007')$$,
  'ADMIN registers an in-progress meter photo'
);
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type, created_by) VALUES ('9b000000-0000-0000-0000-000000000004', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002', '98000000-0000-0000-0000-000000000002', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/inspection/98000000-0000-0000-0000-000000000002/9b000000-0000-0000-0000-000000000004/a2.jpg', 'image/jpeg', '91000000-0000-0000-0000-000000000007')$$,
  'ADMIN registers media through INSPECTION_SERVICE scope'
);
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type, created_by) VALUES ('9b000000-0000-0000-0000-000000000005', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000003', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000003/9b000000-0000-0000-0000-000000000005/completed.jpg', 'image/jpeg', '91000000-0000-0000-0000-000000000007')$$,
  'ADMIN registers evidence before its inspection completes'
);

SELECT is(
  (SELECT created_by FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000001'),
  '91000000-0000-0000-0000-000000000001'::uuid,
  'media creator spoofing stores the actual authenticated profile'
);

SELECT throws_ok(
  $$INSERT INTO public.media_assets (company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', NULL, 'inspection-media', 'bad')$$,
  '55000', NULL, 'an asset with no evidence parent is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, inspection_result_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000090', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000090/two.jpg')$$,
  '23514', NULL, 'an asset with two evidence parents is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000002/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000099/hostile.jpg')$$,
  '55000', NULL, 'hostile company substitution is rejected by the hard parent guard'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (company_id, property_id, inspection_result_id, storage_bucket, storage_path) VALUES ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002', '99000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/result/99000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000098/hostile.jpg')$$,
  '55000', NULL, 'hostile property substitution on result evidence is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (company_id, property_id, meter_reading_id, storage_bucket, storage_path) VALUES ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002', '9a000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/meter/9a000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000097/hostile.jpg')$$,
  '55000', NULL, 'a meter from another inspection/property is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000099', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000099/9b000000-0000-0000-0000-000000000096/hostile.jpg')$$,
  '55000', NULL, 'a nonexistent evidence parent is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type) VALUES ('9b000000-0000-0000-0000-000000000095', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000095/file.pdf', 'application/pdf')$$,
  '23514', NULL, 'non-image MIME metadata is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, file_size_bytes) VALUES ('9b000000-0000-0000-0000-000000000094', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000094/file.jpg', -1)$$,
  '23514', NULL, 'negative file size metadata is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000093', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000093/hostile.jpg')$$,
  '55000', NULL, 'path tenant components must exactly match metadata and parent'
);

SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, metadata) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000001/overview.jpg', '{"mimetype":"image/jpeg"}'::jsonb)$$,
  'authorized upload succeeds only after exact metadata registration'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/result/99000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000002/result.png')$$,
  'result object upload resolves its registered media row'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/meter/9a000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000003/meter.webp')$$,
  'meter object upload resolves its registered media row'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/inspection/98000000-0000-0000-0000-000000000002/9b000000-0000-0000-0000-000000000004/a2.jpg')$$,
  'inspection-service object upload is allowed after registration'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000003/9b000000-0000-0000-0000-000000000005/completed.jpg')$$,
  'object for soon-completed evidence uploads while still editable'
);

RESET ROLE;
SET LOCAL session_replication_role TO replica;
INSERT INTO public.inspections (
  id, company_id, property_id, template_version_id, status, created_by
)
VALUES
  ('98000000-0000-0000-0000-000000000004', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000003', '95000000-0000-0000-0000-000000000001', 'IN_PROGRESS', '91000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000005', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000004', '95000000-0000-0000-0000-000000000001', 'IN_PROGRESS', '91000000-0000-0000-0000-000000000001');
SET LOCAL session_replication_role TO origin;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000089', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000003', '98000000-0000-0000-0000-000000000004', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000003/inspection/98000000-0000-0000-0000-000000000004/9b000000-0000-0000-0000-000000000089/maintenance.jpg')$$,
  '42501', NULL, 'MAINTENANCE_SERVICE alone cannot register inspection media'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000088', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000004', '98000000-0000-0000-0000-000000000005', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000004/inspection/98000000-0000-0000-0000-000000000005/9b000000-0000-0000-0000-000000000088/coordination.jpg')$$,
  '42501', NULL, 'COORDINATION_SERVICE alone cannot register inspection media'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000007';
INSERT INTO public.inspections (
  id, company_id, property_id, template_version_id
)
VALUES (
  '98000000-0000-0000-0000-000000000201',
  '92000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000005',
  '95000000-0000-0000-0000-000000000002'
);
UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id = '98000000-0000-0000-0000-000000000201';
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type) VALUES ('9b000000-0000-0000-0000-000000000201', '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000005', '98000000-0000-0000-0000-000000000201', 'inspection-media', '92000000-0000-0000-0000-000000000002/93000000-0000-0000-0000-000000000005/inspection/98000000-0000-0000-0000-000000000201/9b000000-0000-0000-0000-000000000201/b.jpg', 'image/jpeg')$$,
  'Company B ADMIN registers its independent media row'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000002/93000000-0000-0000-0000-000000000005/inspection/98000000-0000-0000-0000-000000000201/9b000000-0000-0000-0000-000000000201/b.jpg')$$,
  'Company B ADMIN uploads its exact registered object'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000001';
SELECT ok(
  (SELECT count(*) FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000201') = 0
    AND (SELECT count(*) FROM storage.objects WHERE name LIKE '%/9b000000-0000-0000-0000-000000000201/%') = 0,
  'Company A direct known UUID and path queries reveal no Company B media'
);
SELECT results_eq(
  $$UPDATE storage.objects SET metadata = '{"hostile":true}'::jsonb WHERE name LIKE '%/9b000000-0000-0000-0000-000000000201/%' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot replace Company B object by exact known path'
);

SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000099/guessed.jpg')$$,
  '42501', NULL, 'a plausible path without an exact media row cannot upload'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000002/93000000-0000-0000-0000-000000000005/inspection/98000000-0000-0000-0000-000000000099/9b000000-0000-0000-0000-000000000099/foreign.jpg')$$,
  '42501', NULL, 'Company B-looking path grants Company A no upload authorization'
);

SELECT results_eq(
  $$SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media'$$,
  $$VALUES (5::bigint)$$,
  'ADMIN reads exactly the five registered and uploaded Company A objects'
);

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = '98000000-0000-0000-0000-000000000003';

SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000092', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000003', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000003/9b000000-0000-0000-0000-000000000092/late.jpg')$$,
  '55000', NULL, 'completed inspection rejects new media metadata'
);
SELECT throws_ok(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000005'$$,
  '55000', NULL,
  'completed inspection rejects media metadata deletion'
);
SELECT throws_ok(
  $$UPDATE public.media_assets SET mime_type = 'image/png' WHERE id = '9b000000-0000-0000-0000-000000000005'$$,
  '42501', NULL, 'authenticated clients have no media metadata UPDATE surface'
);
SELECT results_eq(
  $$UPDATE storage.objects SET metadata = '{"hostile":true}'::jsonb WHERE bucket_id = 'inspection-media' AND name LIKE '%/9b000000-0000-0000-0000-000000000005/%' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'completed inspection rejects storage object replacement'
);
SET LOCAL storage.allow_delete_query TO 'true';
SELECT results_eq(
  $$DELETE FROM storage.objects WHERE bucket_id = 'inspection-media' AND name LIKE '%/9b000000-0000-0000-0000-000000000005/%' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'completed inspection rejects storage object deletion'
);

RESET ROLE;
SELECT throws_ok(
  $$UPDATE public.media_assets SET mime_type = 'image/png' WHERE id = '9b000000-0000-0000-0000-000000000005'$$,
  '55000', NULL, 'hard trigger rejects completed metadata rewriting below RLS'
);
SELECT throws_ok(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000005'$$,
  '55000', NULL, 'hard trigger rejects completed metadata deletion below RLS'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000002';
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000081', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000081/manager.jpg')$$,
  'MANAGER registers in-progress evidence'
);
SELECT lives_ok(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000081'$$,
  'MANAGER removes in-progress evidence metadata'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000003';
SELECT is(
  (SELECT count(*) FROM public.media_assets),
  4::bigint,
  'assigned Inspector A reads only assigned A1 evidence'
);
SELECT is(
  (SELECT count(*) FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000004'),
  0::bigint,
  'assigned Inspector A cannot read unassigned A2 media by UUID'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media'),
  4::bigint,
  'assigned Inspector A reads only exact assigned-property storage objects'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000002/inspection/98000000-0000-0000-0000-000000000002/9b000000-0000-0000-0000-000000000004/a2.jpg')$$,
  '42501', NULL, 'assigned Inspector A cannot upload to unassigned A2 even with an exact known path'
);
SELECT lives_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type) VALUES ('9b000000-0000-0000-0000-000000000080', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000080/inspector.jpg', 'image/jpeg')$$,
  'assigned Inspector registers in-progress evidence'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000080/inspector.jpg')$$,
  'assigned Inspector uploads its exact registered evidence object'
);
SELECT lives_ok(
  $$DELETE FROM storage.objects WHERE name LIKE '%/9b000000-0000-0000-0000-000000000080/%'$$,
  'assigned Inspector removes its in-progress evidence object'
);
SELECT lives_ok(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000080'$$,
  'assigned Inspector removes its in-progress evidence metadata'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000004';
SELECT is(
  (SELECT count(*) FROM public.media_assets),
  1::bigint,
  'Inspector assigned only to A2 reads only A2 metadata'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media'),
  1::bigint,
  'Inspector assigned only to A2 reads only the A2 object'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000005';
SELECT ok(
  (SELECT count(*) FROM public.media_assets) = 5
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media') = 5,
  'COORDINATOR receives read-only operational media access'
);
SELECT throws_ok(
  $$INSERT INTO public.media_assets (id, company_id, property_id, inspection_id, storage_bucket, storage_path) VALUES ('9b000000-0000-0000-0000-000000000091', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000091/coordinator.jpg')$$,
  '42501', NULL, 'COORDINATOR cannot register media'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000006';
SELECT ok(
  (SELECT count(*) FROM public.media_assets) = 5
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media') = 5,
  'READ_ONLY receives read-only operational media access'
);
SELECT results_eq(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'READ_ONLY cannot delete media metadata'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000008';
SELECT ok(
  (SELECT count(*) FROM public.media_assets) = 0
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media') = 0,
  'OWNER has zero Task 10 metadata and raw storage access'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', '92000000-0000-0000-0000-000000000001/93000000-0000-0000-0000-000000000001/inspection/98000000-0000-0000-0000-000000000001/9b000000-0000-0000-0000-000000000001/overview.jpg')$$,
  '42501', NULL, 'OWNER cannot upload to an exact known owned-property path'
);

SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000009';
SELECT ok(
  (SELECT count(*) FROM public.media_assets) = 0
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media') = 0,
  'unrelated authenticated profile receives zero media access'
);

SET LOCAL request.jwt.claim.sub TO '';
SELECT ok(
  (SELECT count(*) FROM public.media_assets) = 0
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media') = 0,
  'authenticated without a JWT subject fails closed'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.media_assets$$,
  '42501', NULL, 'anon cannot read media metadata'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE bucket_id = 'inspection-media'),
  0::bigint,
  'anon reads no private inspection media object'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', 'hostile/path.jpg')$$,
  '42501', NULL, 'anon cannot upload inspection media'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '91000000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$UPDATE storage.objects SET metadata = '{"mimetype":"image/jpeg","replaced":true}'::jsonb WHERE bucket_id = 'inspection-media' AND name LIKE '%/9b000000-0000-0000-0000-000000000001/%'$$,
  'ADMIN may replace an exact registered object while its inspection is in progress'
);
SELECT lives_ok(
  $$DELETE FROM storage.objects WHERE bucket_id = 'inspection-media' AND name LIKE '%/9b000000-0000-0000-0000-000000000002/%'$$,
  'ADMIN may remove an exact registered object while its inspection is in progress'
);
SELECT lives_ok(
  $$DELETE FROM public.media_assets WHERE id = '9b000000-0000-0000-0000-000000000002'$$,
  'ADMIN may remove metadata after deleting the in-progress object'
);

RESET ROLE;

\else

SELECT * FROM skip(
  62,
  'media behavior requires the complete Task 10 table, helpers, trigger, and bucket'
);

\endif

SELECT * FROM finish();

ROLLBACK;
