BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_table('public', 'inspection_report_versions', 'inspection_report_versions exists in public');

SELECT ok(
  COALESCE((
    SELECT array_agg(attribute.attname ORDER BY attribute.attnum) = ARRAY[
      'id',
      'company_id',
      'property_id',
      'inspection_id',
      'version_number',
      'status',
      'title',
      'summary',
      'content',
      'created_by',
      'created_at',
      'updated_at',
      'published_at',
      'published_by'
    ]::name[]
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = to_regclass('public.inspection_report_versions')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'inspection_report_versions has exactly the approved Task 11 columns'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      ORDER BY attribute.attnum
    ) = '[
      ["id", "uuid", true],
      ["company_id", "uuid", true],
      ["property_id", "uuid", true],
      ["inspection_id", "uuid", true],
      ["version_number", "integer", true],
      ["status", "report_status", true],
      ["title", "text", false],
      ["summary", "text", false],
      ["content", "jsonb", false],
      ["created_by", "uuid", true],
      ["created_at", "timestamp with time zone", true],
      ["updated_at", "timestamp with time zone", true],
      ["published_at", "timestamp with time zone", false],
      ["published_by", "uuid", false]
    ]'::jsonb
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = to_regclass('public.inspection_report_versions')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'inspection_report_versions types and nullability are exact'
);

SELECT ok(
  COALESCE((
    SELECT column_default.adbin IS NOT NULL
    FROM pg_attribute AS attribute
    JOIN pg_attrdef AS column_default
      ON column_default.adrelid = attribute.attrelid
     AND column_default.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.inspection_report_versions')
      AND attribute.attname = 'status'
      AND pg_get_expr(column_default.adbin, column_default.adrelid) = '''DRAFT''::report_status'
  ), false),
  'inspection_report_versions.status defaults to DRAFT'
);

SELECT ok(
  COALESCE((
    SELECT constraint_state.conkey = ARRAY[attribute.attnum]::smallint[]
    FROM pg_constraint AS constraint_state
    JOIN pg_attribute AS attribute
      ON attribute.attrelid = constraint_state.conrelid
     AND attribute.attname = 'id'
    WHERE constraint_state.conrelid = to_regclass('public.inspection_report_versions')
      AND constraint_state.contype = 'p'
  ), false),
  'inspection_report_versions uses id as its UUID primary key'
);

WITH expected(child_column, parent_table) AS (
  VALUES
    ('company_id'::name, 'companies'::name),
    ('property_id', 'properties'),
    ('inspection_id', 'inspections'),
    ('created_by', 'profiles'),
    ('published_by', 'profiles')
), actual AS (
  SELECT
    child_attribute.attname AS child_column,
    parent.relname AS parent_table
  FROM pg_constraint AS constraint_state
  JOIN pg_class AS parent ON parent.oid = constraint_state.confrelid
  JOIN pg_attribute AS child_attribute
    ON child_attribute.attrelid = constraint_state.conrelid
   AND child_attribute.attnum = constraint_state.conkey[1]
  WHERE constraint_state.conrelid = to_regclass('public.inspection_report_versions')
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
  'inspection_report_versions has exact non-cascading company, property, inspection, and actor foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE '%version_number > 0%'
      ) = 1
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE '%status = ''DRAFT''%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%published_at IS NULL%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%published_by IS NULL%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%FINAL%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%SUPERSEDED%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%published_at IS NOT NULL%'
          AND pg_get_constraintdef(constraint_state.oid) LIKE '%published_by IS NOT NULL%'
      ) = 1
    FROM pg_constraint AS constraint_state
    WHERE constraint_state.conrelid = to_regclass('public.inspection_report_versions')
      AND constraint_state.contype = 'c'
  ), false),
  'inspection_report_versions has only the positive-version and publication-consistency checks'
);

SELECT ok(
  COALESCE((
    SELECT bool_or(constraint_state.contype = 'u'
      AND (
        SELECT array_agg(attribute.attname ORDER BY column_position)
        FROM unnest(constraint_state.conkey) WITH ORDINALITY AS u(attnum, column_position)
        JOIN pg_attribute AS attribute
          ON attribute.attrelid = constraint_state.conrelid
         AND attribute.attnum = u.attnum
      ) = ARRAY['inspection_id', 'version_number']::name[]
    )
    FROM pg_constraint AS constraint_state
    WHERE constraint_state.conrelid = to_regclass('public.inspection_report_versions')
  ), false),
  'inspection_report_versions enforces a unique version number per inspection'
);

WITH expected(index_name) AS (
  VALUES
    ('inspection_report_versions_inspection_id_version_number_key'::name),
    ('inspection_report_versions_company_id_property_id_idx'),
    ('inspection_report_versions_one_current_final_idx')
), actual AS (
  SELECT index_relation.relname AS index_name
  FROM pg_index AS index_state
  JOIN pg_class AS index_relation ON index_relation.oid = index_state.indexrelid
  WHERE index_state.indrelid = to_regclass('public.inspection_report_versions')
    AND NOT index_state.indisprimary
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'inspection_report_versions has only the exact version, lookup, and single-FINAL indexes'
);

SELECT ok(
  COALESCE((
    SELECT index_state.indisunique
    FROM pg_index AS index_state
    JOIN pg_class AS index_relation ON index_relation.oid = index_state.indexrelid
    WHERE index_relation.relname = 'inspection_report_versions_one_current_final_idx'
  ), false),
  'the one-current-FINAL index is a unique partial index'
);

SELECT ok(
  COALESCE((
    SELECT relation.relrowsecurity AND NOT relation.relforcerowsecurity
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.inspection_report_versions')
  ), false),
  'inspection_report_versions uses ordinary non-forced RLS'
);

WITH expected(policyname, cmd) AS (
  VALUES
    ('inspection_report_versions_company_select'::name, 'SELECT'::text),
    ('inspection_report_versions_draft_insert', 'INSERT'),
    ('inspection_report_versions_draft_update', 'UPDATE')
), actual AS (
  SELECT policyname, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'inspection_report_versions'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'inspection_report_versions has exactly SELECT, INSERT, and DRAFT-scoped UPDATE policies and no DELETE path'
);

SELECT ok(
  COALESCE((
    SELECT bool_and(permissive = 'PERMISSIVE')
      AND bool_and(roles = ARRAY['authenticated']::name[])
      AND bool_and(
        position('security.company_has_property_scope' in COALESCE(qual, with_check)) > 0
      )
      AND bool_and(position('FULL_MANAGEMENT' in COALESCE(qual, with_check)) > 0)
      AND bool_and(position('INSPECTION_SERVICE' in COALESCE(qual, with_check)) > 0)
      AND bool_and(position('MAINTENANCE_SERVICE' in COALESCE(qual, with_check)) = 0)
      AND bool_and(position('COORDINATION_SERVICE' in COALESCE(qual, with_check)) = 0)
      AND bool_and(lower(COALESCE(qual, '') || COALESCE(with_check, '')) NOT LIKE '%owner%')
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'inspection_report_versions'
  ), false),
  'report policies are authenticated, scope-gated, and contain no owner path'
);

SELECT ok(
  COALESCE((
    SELECT NOT has_table_privilege('anon', relation.oid, 'SELECT')
      AND NOT has_table_privilege('anon', relation.oid, 'INSERT')
      AND NOT has_table_privilege('anon', relation.oid, 'UPDATE')
      AND NOT has_table_privilege('anon', relation.oid, 'DELETE')
      AND has_table_privilege('authenticated', relation.oid, 'SELECT')
      AND has_table_privilege('authenticated', relation.oid, 'INSERT')
      AND has_table_privilege('authenticated', relation.oid, 'UPDATE')
      AND NOT has_table_privilege('authenticated', relation.oid, 'DELETE')
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.inspection_report_versions')
  ), false),
  'inspection_report_versions grants only SELECT, INSERT, UPDATE to authenticated, nothing to anon, and no DELETE to anyone'
);

SELECT has_function(
  'security',
  'protect_report_version',
  ARRAY[]::name[],
  'report trigger guard function exists'
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
      AND procedure.proname = 'protect_report_version'
      AND procedure.pronargs = 0
  ), false),
  'report trigger guard is a non-callable fixed-path SECURITY DEFINER function'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(trigger_state.tgtype = 31)
      AND bool_and(trigger_state.tgenabled = 'O')
    FROM pg_trigger AS trigger_state
    WHERE trigger_state.tgrelid = to_regclass('public.inspection_report_versions')
      AND trigger_state.tgname = 'inspection_report_versions_protect_runtime'
      AND NOT trigger_state.tgisinternal
  ), false),
  'one enabled row-level BEFORE trigger protects every report version mutation'
);

SELECT has_function(
  'public',
  'publish_inspection_report',
  ARRAY['uuid']::name[],
  'publish_inspection_report exists as the sole publication entry point'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prorettype = to_regtype('public.inspection_report_versions')
      AND procedure.prosecdef
      AND procedure.provolatile = 'v'
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND NOT has_function_privilege('anon', procedure.oid, 'EXECUTE')
      AND has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
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
    WHERE namespace.nspname = 'public'
      AND procedure.proname = 'publish_inspection_report'
      AND procedure.pronargs = 1
  ), false),
  'publish_inspection_report is a fixed-path SECURITY DEFINER function callable only by authenticated clients'
);

SELECT (
  to_regclass('public.inspection_report_versions') IS NOT NULL
    AND to_regprocedure('security.protect_report_version()') IS NOT NULL
    AND to_regprocedure('public.publish_inspection_report(uuid)') IS NOT NULL
)::integer AS report_surface_ready
\gset

\if :report_surface_ready

INSERT INTO auth.users (id)
VALUES
  ('a1000000-0000-0000-0000-000000000001'),
  ('a1000000-0000-0000-0000-000000000002'),
  ('a1000000-0000-0000-0000-000000000003'),
  ('a1000000-0000-0000-0000-000000000004'),
  ('a1000000-0000-0000-0000-000000000005'),
  ('a1000000-0000-0000-0000-000000000006'),
  ('a1000000-0000-0000-0000-000000000007'),
  ('a1000000-0000-0000-0000-000000000008'),
  ('a1000000-0000-0000-0000-000000000009');

INSERT INTO public.profiles (id)
SELECT id FROM auth.users WHERE id::text LIKE 'a1000000-%';

INSERT INTO public.companies (id, name)
VALUES
  ('a2000000-0000-0000-0000-000000000001', 'Report Company A'),
  ('a2000000-0000-0000-0000-000000000002', 'Report Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'MANAGER', true),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000003', 'INSPECTOR', true),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000004', 'COORDINATOR', true),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000005', 'READ_ONLY', true),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000006', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES
  ('a3000000-0000-0000-0000-000000000001', 'A1 full management'),
  ('a3000000-0000-0000-0000-000000000002', 'A2 maintenance service'),
  ('a3000000-0000-0000-0000-000000000003', 'A3 coordination service'),
  ('a3000000-0000-0000-0000-000000000004', 'A4 scheduled inspection'),
  ('a3000000-0000-0000-0000-000000000005', 'A5 in progress inspection'),
  ('a3000000-0000-0000-0000-000000000006', 'B1 full management');

INSERT INTO public.property_company_relationships (
  id, property_id, company_id, relationship_type, status, scope
)
VALUES
  ('a3100000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('a3100000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('a3100000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('a3100000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('a3100000-0000-0000-0000-000000000005', 'a3000000-0000-0000-0000-000000000005', 'a2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('a3100000-0000-0000-0000-000000000006', 'a3000000-0000-0000-0000-000000000006', 'a2000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES ('a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000007');

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Report template A'),
  ('a4000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'Report template B');

INSERT INTO public.inspection_template_versions (id, template_id, version_number, is_current)
VALUES
  ('a5000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 1, false),
  ('a5000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000002', 1, false);

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES
  ('a6000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001', 'A', 1),
  ('a6000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000002', 'B', 1);

INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES
  ('a7000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001', 'A item', 1),
  ('a7000000-0000-0000-0000-000000000002', 'a6000000-0000-0000-0000-000000000002', 'B item', 1);

UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id IN (
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000002'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000001';

INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES
  ('a8000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001'),
  ('a8000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000001'),
  ('a8000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000005', 'a5000000-0000-0000-0000-000000000001');

UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id IN (
  'a8000000-0000-0000-0000-000000000001',
  'a8000000-0000-0000-0000-000000000003'
);

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = 'a8000000-0000-0000-0000-000000000001';

INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES
  ('a8000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000001'),
  ('a8000000-0000-0000-0000-000000000005', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000001');

SELECT lives_ok(
  $$INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, summary, content) VALUES ('a9000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001', 'A1 Inspection Report', 'Summary v1', '{"sections":[]}'::jsonb)$$,
  'ADMIN creates the first draft report for a completed inspection'
);

SELECT is(
  (SELECT version_number FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  1,
  'the first draft is automatically assigned version 1'
);

SELECT is(
  (SELECT created_by FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'a1000000-0000-0000-0000-000000000001'::uuid,
  'report creator spoofing stores the actual authenticated profile'
);

SELECT is(
  (SELECT status FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'DRAFT'::public.report_status,
  'a newly created report starts as DRAFT'
);

SELECT lives_ok(
  $$UPDATE public.inspection_report_versions SET title = 'A1 Inspection Report (v1)', summary = 'Revised summary' WHERE id = 'a9000000-0000-0000-0000-000000000001'$$,
  'ADMIN edits its own draft report content'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001')$$,
  '55000', NULL, 'hostile company substitution is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000006', 'a8000000-0000-0000-0000-000000000001')$$,
  '55000', NULL, 'hostile property substitution is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000006', 'a8000000-0000-0000-0000-000000000001')$$,
  '55000', NULL, 'Company B identity cannot be attached to Company A''s inspection'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000099')$$,
  '55000', NULL, 'a nonexistent evidence inspection is rejected'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000003';
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'INSPECTOR cannot create a draft report'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'INSPECTOR cannot publish a report'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000004';
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'COORDINATOR cannot create a draft report'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'COORDINATOR cannot publish a report'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000005';
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET title = 'hostile' WHERE id = 'a9000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'READ_ONLY cannot mutate a draft report'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'READ_ONLY cannot publish a report'
);
SELECT ok(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001') = 1,
  'READ_ONLY can read the operational draft report'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title) VALUES ('a9000000-0000-0000-0000-000000000020', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000004', 'a8000000-0000-0000-0000-000000000002', 'A4 scheduled draft')$$,
  'ADMIN drafts a report against a scheduled inspection'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000020')$$,
  '55000', NULL, 'publish is rejected while the inspection is still SCHEDULED'
);

SELECT lives_ok(
  $$INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title) VALUES ('a9000000-0000-0000-0000-000000000010', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000005', 'a8000000-0000-0000-0000-000000000003', 'A5 in-progress draft')$$,
  'ADMIN drafts a report against an in-progress inspection'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000010')$$,
  '55000', NULL, 'publish is rejected while the inspection is IN_PROGRESS'
);

SELECT lives_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  'ADMIN publishes the first draft of a completed inspection'
);

SELECT is(
  (SELECT status FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'FINAL'::public.report_status,
  'the published version becomes FINAL'
);
SELECT ok(
  (SELECT published_at FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001') IS NOT NULL,
  'publication records a timestamp'
);
SELECT is(
  (SELECT published_by FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'a1000000-0000-0000-0000-000000000001'::uuid,
  'publication records the actual authenticated publishing actor'
);
SELECT is(
  (SELECT title FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'A1 Inspection Report (v1)',
  'publication does not alter report content'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE inspection_id = 'a8000000-0000-0000-0000-000000000001' AND status = 'FINAL'),
  1::bigint,
  'exactly one FINAL report exists after the first publication'
);

SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  '55000', NULL, 'republishing an already-FINAL report is rejected'
);

SELECT lives_ok(
  $$INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title) VALUES ('a9000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001', 'A1 Inspection Report v2')$$,
  'MANAGER creates a second draft report for the same inspection'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT version_number FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000002'),
  2,
  'the second draft is automatically assigned version 2'
);

SELECT lives_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000002')$$,
  'MANAGER publishes the second draft, superseding the first'
);

SELECT is(
  (SELECT status FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'SUPERSEDED'::public.report_status,
  'v1 becomes SUPERSEDED after v2 publishes'
);
SELECT is(
  (SELECT status FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000002'),
  'FINAL'::public.report_status,
  'v2 becomes FINAL after publication'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE inspection_id = 'a8000000-0000-0000-0000-000000000001' AND status = 'FINAL'),
  1::bigint,
  'exactly one FINAL report exists after supersession'
);
SELECT is(
  (SELECT title FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'),
  'A1 Inspection Report (v1)',
  'v1 content remains unchanged and queryable after supersession'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000001';
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET content = '{"hostile":true}'::jsonb WHERE id = 'a9000000-0000-0000-0000-000000000002' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'FINAL report content update is denied'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET summary = 'hostile' WHERE id = 'a9000000-0000-0000-0000-000000000002' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'FINAL report summary update is denied'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET version_number = 99 WHERE id = 'a9000000-0000-0000-0000-000000000002' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'FINAL report version_number update is denied'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET company_id = 'a2000000-0000-0000-0000-000000000002' WHERE id = 'a9000000-0000-0000-0000-000000000002' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'FINAL report parent identity update is denied'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET status = 'DRAFT' WHERE id = 'a9000000-0000-0000-0000-000000000002' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'FINAL report rollback to DRAFT is denied'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000002'$$,
  '42501', NULL, 'FINAL report deletion is denied'
);

SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET content = '{"hostile":true}'::jsonb WHERE id = 'a9000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'SUPERSEDED report content update is denied'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET status = 'FINAL' WHERE id = 'a9000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'direct SUPERSEDED to FINAL conversion is denied'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000001'$$,
  '42501', NULL, 'SUPERSEDED report deletion is denied'
);

RESET ROLE;
SELECT throws_ok(
  $$UPDATE public.inspection_report_versions SET status = 'DRAFT' WHERE id = 'a9000000-0000-0000-0000-000000000002'$$,
  '55000', NULL, 'hard trigger rejects FINAL rollback below RLS'
);
SELECT throws_ok(
  $$UPDATE public.inspection_report_versions SET status = 'FINAL' WHERE id = 'a9000000-0000-0000-0000-000000000001'$$,
  '55000', NULL, 'hard trigger rejects direct SUPERSEDED to FINAL below RLS'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_report_versions WHERE id = 'a9000000-0000-0000-0000-000000000002'$$,
  '55000', NULL, 'hard trigger rejects FINAL deletion below RLS'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000006';
SELECT ok(
  (SELECT count(*) FROM public.inspection_report_versions WHERE inspection_id = 'a8000000-0000-0000-0000-000000000001') = 0,
  'Company B ADMIN cannot see Company A report versions by known UUID'
);
SELECT results_eq(
  $$UPDATE public.inspection_report_versions SET title = 'hostile' WHERE id = 'a9000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company B ADMIN cannot update a Company A draft by known UUID'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000010')$$,
  '42501', NULL, 'Company B ADMIN cannot publish a Company A report by known UUID'
);

RESET ROLE;
UPDATE public.property_company_relationships
SET relationship_type = 'SERVICE', scope = 'MAINTENANCE_SERVICE'
WHERE id = 'a3100000-0000-0000-0000-000000000002';
UPDATE public.property_company_relationships
SET relationship_type = 'SERVICE', scope = 'COORDINATION_SERVICE'
WHERE id = 'a3100000-0000-0000-0000-000000000003';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'a8000000-0000-0000-0000-000000000004')$$,
  '42501', NULL, 'MAINTENANCE_SERVICE-only scope cannot back a draft report'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'a8000000-0000-0000-0000-000000000005')$$,
  '42501', NULL, 'COORDINATION_SERVICE-only scope cannot back a draft report'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000007';
SELECT ok(
  (SELECT count(*) FROM public.inspection_report_versions) = 0,
  'OWNER cannot read any report version, including DRAFT'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_report_versions (company_id, property_id, inspection_id) VALUES ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'OWNER cannot create a report'
);

SET LOCAL request.jwt.claim.sub TO 'a1000000-0000-0000-0000-000000000008';
SELECT ok(
  (SELECT count(*) FROM public.inspection_report_versions) = 0,
  'unrelated authenticated profile receives zero report access'
);

SET LOCAL request.jwt.claim.sub TO '';
SELECT ok(
  (SELECT count(*) FROM public.inspection_report_versions) = 0,
  'authenticated without a JWT subject fails closed'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.inspection_report_versions$$,
  '42501', NULL, 'anon cannot read report versions'
);
SELECT throws_ok(
  $$SELECT public.publish_inspection_report('a9000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'anon cannot call publish_inspection_report'
);

RESET ROLE;

\else

SELECT * FROM skip(
  57,
  'report behavior requires the complete Task 11 table, trigger, function, and policies'
);

\endif

SELECT * FROM finish();

ROLLBACK;
