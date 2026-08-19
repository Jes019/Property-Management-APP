BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_table('public', 'audit_log', 'audit_log exists in public');

SELECT ok(
  COALESCE((
    SELECT array_agg(attribute.attname ORDER BY attribute.attnum) = ARRAY[
      'id',
      'company_id',
      'property_id',
      'actor_profile_id',
      'action',
      'entity_type',
      'entity_id',
      'old_values',
      'new_values',
      'metadata',
      'created_at'
    ]::name[]
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = to_regclass('public.audit_log')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'audit_log has exactly the approved Task 13 columns'
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
      ["property_id", "uuid", false],
      ["actor_profile_id", "uuid", false],
      ["action", "text", true],
      ["entity_type", "text", true],
      ["entity_id", "uuid", false],
      ["old_values", "jsonb", false],
      ["new_values", "jsonb", false],
      ["metadata", "jsonb", false],
      ["created_at", "timestamp with time zone", true]
    ]'::jsonb
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = to_regclass('public.audit_log')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'audit_log types and nullability are exact'
);

SELECT ok(
  COALESCE((
    SELECT constraint_state.conkey = ARRAY[attribute.attnum]::smallint[]
    FROM pg_constraint AS constraint_state
    JOIN pg_attribute AS attribute
      ON attribute.attrelid = constraint_state.conrelid
     AND attribute.attname = 'id'
    WHERE constraint_state.conrelid = to_regclass('public.audit_log')
      AND constraint_state.contype = 'p'
  ), false),
  'audit_log uses id as its UUID primary key'
);

WITH expected(child_column, parent_table) AS (
  VALUES
    ('company_id'::name, 'companies'::name),
    ('property_id', 'properties'),
    ('actor_profile_id', 'profiles')
), actual AS (
  SELECT
    child_attribute.attname AS child_column,
    parent.relname AS parent_table
  FROM pg_constraint AS constraint_state
  JOIN pg_class AS parent ON parent.oid = constraint_state.confrelid
  JOIN pg_attribute AS child_attribute
    ON child_attribute.attrelid = constraint_state.conrelid
   AND child_attribute.attnum = constraint_state.conkey[1]
  WHERE constraint_state.conrelid = to_regclass('public.audit_log')
    AND constraint_state.contype = 'f'
    AND cardinality(constraint_state.conkey) = 1
    AND cardinality(constraint_state.confkey) = 1
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'audit_log has exact company, property, and actor foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE '%INSPECTION_COMPLETED%REPORT_PUBLISHED%REPORT_SUPERSEDED%'
      ) = 1
      AND count(*) FILTER (
        WHERE pg_get_constraintdef(constraint_state.oid) LIKE '%inspection%inspection_report_version%'
      ) = 1
    FROM pg_constraint AS constraint_state
    WHERE constraint_state.conrelid = to_regclass('public.audit_log')
      AND constraint_state.contype = 'c'
  ), false),
  'audit_log constrains action and entity_type to the approved Task 13 vocabulary'
);

WITH expected(index_name) AS (
  VALUES
    ('audit_log_company_id_created_at_idx'::name),
    ('audit_log_company_id_property_id_created_at_idx'),
    ('audit_log_entity_type_entity_id_created_at_idx')
), actual AS (
  SELECT index_relation.relname AS index_name
  FROM pg_index AS index_state
  JOIN pg_class AS index_relation ON index_relation.oid = index_state.indexrelid
  WHERE index_state.indrelid = to_regclass('public.audit_log')
    AND NOT index_state.indisprimary
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'audit_log has only the exact expected lookup indexes'
);

SELECT ok(
  COALESCE((
    SELECT relation.relrowsecurity AND NOT relation.relforcerowsecurity
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.audit_log')
  ), false),
  'audit_log uses ordinary non-forced RLS'
);

WITH expected(policyname, cmd) AS (
  VALUES
    ('audit_log_company_select'::name, 'SELECT'::text)
), actual AS (
  SELECT policyname, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'audit_log'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'audit_log has exactly one SELECT policy and no write path for any role'
);

SELECT ok(
  COALESCE((
    SELECT NOT has_table_privilege('anon', relation.oid, 'SELECT')
      AND NOT has_table_privilege('anon', relation.oid, 'INSERT')
      AND NOT has_table_privilege('authenticated', relation.oid, 'INSERT')
      AND NOT has_table_privilege('authenticated', relation.oid, 'UPDATE')
      AND NOT has_table_privilege('authenticated', relation.oid, 'DELETE')
      AND has_table_privilege('authenticated', relation.oid, 'SELECT')
    FROM pg_class AS relation
    WHERE relation.oid = to_regclass('public.audit_log')
  ), false),
  'audit_log grants only SELECT to authenticated; no write privilege to any client role'
);

SELECT has_function(
  'security',
  'append_audit_log',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'text', 'uuid', 'jsonb', 'jsonb', 'jsonb']::name[],
  'append_audit_log exists as the sole internal audit-write path'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
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
      AND procedure.proname = 'append_audit_log'
  ), false),
  'append_audit_log is a fixed-path SECURITY DEFINER function callable by no client role at all'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
      AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
      AND NOT has_function_privilege('anon', procedure.oid, 'EXECUTE')
      AND NOT has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'audit_inspection_completion'
      AND procedure.pronargs = 0
  ), false),
  'audit_inspection_completion is a fixed-path SECURITY DEFINER trigger function callable by no client role'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(trigger_state.tgenabled = 'O')
    FROM pg_trigger AS trigger_state
    WHERE trigger_state.tgrelid = to_regclass('public.inspections')
      AND trigger_state.tgname = 'inspections_audit_completion'
      AND NOT trigger_state.tgisinternal
  ), false),
  'one enabled AFTER trigger audits inspection completion'
);

SELECT (
  to_regclass('public.audit_log') IS NOT NULL
    AND to_regprocedure(
      'security.append_audit_log(uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb)'
    ) IS NOT NULL
    AND to_regprocedure('security.audit_inspection_completion()') IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = to_regclass('public.inspections')
        AND tgname = 'inspections_audit_completion'
    )
)::integer AS audit_surface_ready
\gset

\if :audit_surface_ready

INSERT INTO auth.users (id)
VALUES
  ('c1000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000002'),
  ('c1000000-0000-0000-0000-000000000003'),
  ('c1000000-0000-0000-0000-000000000004');

INSERT INTO public.profiles (id)
SELECT id FROM auth.users WHERE id::text LIKE 'c1000000-%';

INSERT INTO public.companies (id, name)
VALUES
  ('c2000000-0000-0000-0000-000000000001', 'Audit Company A'),
  ('c2000000-0000-0000-0000-000000000002', 'Audit Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'INSPECTOR', true),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000003', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES
  ('c3000000-0000-0000-0000-000000000001', 'Audit A1'),
  ('c3000000-0000-0000-0000-000000000002', 'Audit B1');

INSERT INTO public.property_company_relationships (
  id, property_id, company_id, relationship_type, status, scope
)
VALUES
  ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('c3100000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES ('c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000004');

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Audit template A');

INSERT INTO public.inspection_template_versions (id, template_id, version_number, is_current)
VALUES ('c5000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 1, false);

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES ('c6000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', 'A', 1);

INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES ('c7000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001', 'A item', 1);

UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id = 'c5000000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'c1000000-0000-0000-0000-000000000001';

INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES ('c8000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001');

UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id = 'c8000000-0000-0000-0000-000000000001';

SAVEPOINT completion_rollback_test;

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = 'c8000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  1::bigint,
  'a successful completion creates exactly one INSPECTION_COMPLETED audit row'
);

ROLLBACK TO SAVEPOINT completion_rollback_test;

SELECT is(
  (SELECT status FROM public.inspections WHERE id = 'c8000000-0000-0000-0000-000000000001'),
  'IN_PROGRESS'::public.inspection_lifecycle_status,
  'rolling back the completion transaction reverts the inspection status'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  0::bigint,
  'rolling back the completion transaction rolls back its audit row too (no orphan success audit)'
);

-- Scenario: an invalid transition (SCHEDULED-like re-entry) produces no audit row
INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES ('c8000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001');

SELECT throws_ok(
  $$UPDATE public.inspections SET status = 'COMPLETED' WHERE id = 'c8000000-0000-0000-0000-000000000002'$$,
  '55000', NULL,
  'a rejected SCHEDULED-to-COMPLETED transition is denied'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000002'),
  0::bigint,
  'a rejected completion attempt creates no audit row'
);

-- Now perform the real completion for later report-publication scenarios
UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id = 'c8000000-0000-0000-0000-000000000001';

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = 'c8000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  1::bigint,
  'the durable completion creates exactly one audit row'
);
SELECT is(
  (SELECT actor_profile_id FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  'c1000000-0000-0000-0000-000000000001'::uuid,
  'the audit row records the real authenticated actor, not a spoofable value'
);
SELECT is(
  (SELECT action FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  'INSPECTION_COMPLETED',
  'the audit row records the correct action'
);
SELECT is(
  (SELECT company_id FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  'c2000000-0000-0000-0000-000000000001'::uuid,
  'the audit row records the correct company'
);
SELECT is(
  (SELECT property_id FROM public.audit_log WHERE entity_type = 'inspection' AND entity_id = 'c8000000-0000-0000-0000-000000000001'),
  'c3000000-0000-0000-0000-000000000001'::uuid,
  'the audit row records the correct property'
);

-- Scenario: report publication audit
INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'c9000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000001',
  'c8000000-0000-0000-0000-000000000001',
  'Audit report v1',
  '{"media":[]}'::jsonb
);

SAVEPOINT publish_rollback_test;

SELECT lives_ok(
  $$SELECT public.publish_inspection_report('c9000000-0000-0000-0000-000000000001')$$,
  'publishing the first draft succeeds'
);

SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001' AND action = 'REPORT_PUBLISHED'),
  1::bigint,
  'publishing the first draft creates exactly one REPORT_PUBLISHED audit row'
);

ROLLBACK TO SAVEPOINT publish_rollback_test;

SELECT is(
  (SELECT status FROM public.inspection_report_versions WHERE id = 'c9000000-0000-0000-0000-000000000001'),
  'DRAFT'::public.report_status,
  'rolling back the publish transaction reverts the report status'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001'),
  0::bigint,
  'rolling back the publish transaction rolls back its audit row too (no orphan success audit)'
);

-- Now perform the real publish for downstream scenarios
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('c9000000-0000-0000-0000-000000000001')$$,
  'the durable publish succeeds'
);

SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001' AND action = 'REPORT_PUBLISHED'),
  1::bigint,
  'the durable publish creates exactly one REPORT_PUBLISHED audit row'
);
SELECT is(
  (SELECT actor_profile_id FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001' AND action = 'REPORT_PUBLISHED'),
  'c1000000-0000-0000-0000-000000000001'::uuid,
  'the publish audit row records the real authenticated publishing actor'
);
SELECT is(
  (SELECT (new_values ->> 'version_number')::integer FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001' AND action = 'REPORT_PUBLISHED'),
  1,
  'the publish audit row preserves version metadata'
);

-- Scenario: republishing supersedes and audits both events exactly once
INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'c9000000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000001',
  'c8000000-0000-0000-0000-000000000001',
  'Audit report v2',
  '{"media":[]}'::jsonb
);
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('c9000000-0000-0000-0000-000000000002')$$,
  'publishing the second draft succeeds and supersedes the first'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001' AND action = 'REPORT_SUPERSEDED'),
  1::bigint,
  'exactly one REPORT_SUPERSEDED audit row is created for the superseded version'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000002' AND action = 'REPORT_PUBLISHED'),
  1::bigint,
  'exactly one REPORT_PUBLISHED audit row is created for the new current version'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE entity_type = 'inspection_report_version' AND entity_id = 'c9000000-0000-0000-0000-000000000001'),
  2::bigint,
  'the superseded version has exactly its original publish and supersession events, no duplicates'
);

-- Scenario: append-only / no rewriting history, even for ADMIN
SELECT throws_ok(
  $$UPDATE public.audit_log SET action = 'REPORT_PUBLISHED' WHERE entity_id = 'c8000000-0000-0000-0000-000000000001'$$,
  '42501', NULL,
  'ADMIN cannot UPDATE an audit row (no UPDATE grant at all)'
);
SELECT throws_ok(
  $$DELETE FROM public.audit_log WHERE entity_id = 'c8000000-0000-0000-0000-000000000001'$$,
  '42501', NULL,
  'ADMIN cannot DELETE an audit row (no DELETE grant at all)'
);

-- Scenario: no generic client-side audit insertion, no actor spoofing
SELECT throws_ok(
  $$INSERT INTO public.audit_log (company_id, property_id, actor_profile_id, action, entity_type, entity_id) VALUES ('c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000003', 'INSPECTION_COMPLETED', 'inspection', 'c8000000-0000-0000-0000-000000000001')$$,
  '42501', NULL,
  'authenticated clients have no INSERT grant on audit_log at all, so actor spoofing via direct insert is impossible'
);
SELECT throws_ok(
  $$SELECT security.append_audit_log('c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000003', 'INSPECTION_COMPLETED', 'inspection', 'c8000000-0000-0000-0000-000000000001', NULL, NULL, NULL)$$,
  '42501', NULL,
  'authenticated clients cannot call the internal audit-write helper directly, even with a fabricated actor id'
);

-- Scenario: tenant isolation for SELECT
SELECT ok(
  (SELECT count(*) FROM public.audit_log WHERE company_id = 'c2000000-0000-0000-0000-000000000001') >= 4,
  'Company A ADMIN can read Company A audit records'
);
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE company_id = 'c2000000-0000-0000-0000-000000000002'),
  0::bigint,
  'Company A ADMIN cannot read Company B audit records, even with a known company UUID'
);

SET LOCAL request.jwt.claim.sub TO 'c1000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM public.audit_log),
  0::bigint,
  'INSPECTOR has no audit_log visibility by default'
);

SET LOCAL request.jwt.claim.sub TO 'c1000000-0000-0000-0000-000000000003';
SELECT is(
  (SELECT count(*) FROM public.audit_log WHERE company_id = 'c2000000-0000-0000-0000-000000000001'),
  0::bigint,
  'Company B ADMIN cannot read Company A audit records even with known UUIDs'
);

-- Scenario: owner denial
SET LOCAL request.jwt.claim.sub TO 'c1000000-0000-0000-0000-000000000004';
SELECT is(
  (SELECT count(*) FROM public.audit_log),
  0::bigint,
  'the property OWNER has zero audit_log visibility'
);
SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'c3000000-0000-0000-0000-000000000001'),
  1::bigint,
  'Task 12 owner property read remains intact after Task 13'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'c9000000-0000-0000-0000-000000000002'),
  1::bigint,
  'Task 12 owner FINAL report read remains intact after Task 13'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.audit_log$$,
  '42501', NULL,
  'anon cannot read audit_log'
);
SELECT throws_ok(
  $$INSERT INTO public.audit_log (company_id, action, entity_type) VALUES ('c2000000-0000-0000-0000-000000000001', 'INSPECTION_COMPLETED', 'inspection')$$,
  '42501', NULL,
  'anon cannot write audit_log'
);

RESET ROLE;

\else

SELECT * FROM skip(
  35,
  'audit foundation behavior requires the complete Task 13 table, helpers, triggers, and policies'
);

\endif

SELECT * FROM finish();

ROLLBACK;
