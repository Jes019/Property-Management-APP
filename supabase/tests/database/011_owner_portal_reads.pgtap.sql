BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_function(
  'security',
  'owner_can_view_report',
  ARRAY['uuid']::name[],
  'owner_can_view_report accepts only a report version UUID'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
      AND procedure.provolatile = 's'
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
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'owner_can_view_report'
      AND procedure.pronargs = 1
  ), false),
  'owner_can_view_report is a fixed-path SECURITY DEFINER function callable only by authenticated clients'
);

SELECT has_function(
  'security',
  'owner_can_view_media',
  ARRAY['text', 'text']::name[],
  'owner_can_view_media accepts only bucket and path'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
      AND procedure.provolatile = 's'
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
    WHERE namespace.nspname = 'security'
      AND procedure.proname = 'owner_can_view_media'
      AND procedure.pronargs = 2
  ), false),
  'owner_can_view_media is a fixed-path SECURITY DEFINER function callable only by authenticated clients'
);

SELECT has_function(
  'public',
  'owner_report_media',
  ARRAY['uuid']::name[],
  'owner_report_media exists as the sole owner media projection'
);

SELECT ok(
  COALESCE((
    SELECT procedure.prosecdef
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
      AND procedure.proname = 'owner_report_media'
      AND procedure.pronargs = 1
  ), false),
  'owner_report_media is a fixed-path SECURITY DEFINER function callable only by authenticated clients'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'inspection_report_versions'
      AND policyname = 'inspection_report_versions_owner_select'
      AND cmd = 'SELECT'
      AND roles = ARRAY['authenticated']::name[]
      AND position('security.owner_can_view_report' in qual) > 0
  ), false),
  'inspection_report_versions has an owner-scoped SELECT policy using owner_can_view_report'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'inspection_media_objects_owner_select'
      AND cmd = 'SELECT'
      AND roles = ARRAY['authenticated']::name[]
      AND position('security.owner_can_view_media' in qual) > 0
  ), false),
  'storage.objects has an owner-scoped SELECT policy using owner_can_view_media'
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
  'media_assets policies remain exactly Task 10''s set; no owner policy was added to raw media'
);

WITH expected(schemaname, tablename, policyname) AS (
  VALUES
    ('public'::name, 'properties'::name, 'properties_owner_select'::name),
    ('public', 'property_owners', 'property_owners_owner_select'),
    ('public', 'inspection_report_versions', 'inspection_report_versions_owner_select'),
    ('storage', 'objects', 'inspection_media_objects_owner_select')
), actual AS (
  SELECT schemaname, tablename, policyname
  FROM pg_policies
  WHERE position('is_property_owner' in COALESCE(qual, '') || COALESCE(with_check, '')) > 0
     OR position('owner_can_view' in COALESCE(qual, '') || COALESCE(with_check, '')) > 0
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'exactly the expected tables carry an owner-derived policy; no other table gained owner access'
);

SELECT (
  to_regprocedure('security.owner_can_view_report(uuid)') IS NOT NULL
    AND to_regprocedure('security.owner_can_view_media(text,text)') IS NOT NULL
    AND to_regprocedure('public.owner_report_media(uuid)') IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'inspection_report_versions'
        AND policyname = 'inspection_report_versions_owner_select'
    )
    AND EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND policyname = 'inspection_media_objects_owner_select'
    )
)::integer AS owner_surface_ready
\gset

\if :owner_surface_ready

INSERT INTO auth.users (id)
VALUES
  ('b1000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000002'),
  ('b1000000-0000-0000-0000-000000000003');

INSERT INTO public.profiles (id)
SELECT id FROM auth.users WHERE id::text LIKE 'b1000000-%';

INSERT INTO public.companies (id, name)
VALUES
  ('b2000000-0000-0000-0000-000000000001', 'Owner Test Company A'),
  ('b2000000-0000-0000-0000-000000000002', 'Owner Test Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'ADMIN', true),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES
  ('b3000000-0000-0000-0000-000000000001', 'A1 owned by Andrea, Company A'),
  ('b3000000-0000-0000-0000-000000000002', 'C unowned, Company A'),
  ('b3000000-0000-0000-0000-000000000003', 'B1 owned by Andrea, Company B');

INSERT INTO public.property_company_relationships (
  id, property_id, company_id, relationship_type, status, scope
)
VALUES
  ('b3100000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('b3100000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('b3100000-0000-0000-0000-000000000003', 'b3000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES
  ('b3000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001'),
  ('b3000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001');

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Owner test template A'),
  ('b4000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'Owner test template B');

INSERT INTO public.inspection_template_versions (id, template_id, version_number, is_current)
VALUES
  ('b5000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 1, false),
  ('b5000000-0000-0000-0000-000000000002', 'b4000000-0000-0000-0000-000000000002', 1, false);

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES
  ('b6000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001', 'A', 1),
  ('b6000000-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-000000000002', 'B', 1);

INSERT INTO public.inspection_template_items (id, section_id, label, sort_order)
VALUES
  ('b7000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 'A item', 1),
  ('b7000000-0000-0000-0000-000000000002', 'b6000000-0000-0000-0000-000000000002', 'B item', 1);

UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-13 10:00:00+00'
WHERE id IN (
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000002'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'b1000000-0000-0000-0000-000000000002';

INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES
  ('b8000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001'),
  ('b8000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-000000000001');

UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id IN (
  'b8000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000002'
);

INSERT INTO public.inspection_results (
  id, company_id, property_id, inspection_id, template_item_id, severity, operational_action
)
VALUES (
  'b9a00000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001',
  'PASS',
  'MONITOR'
);

INSERT INTO public.meter_readings (
  id, company_id, property_id, inspection_id, meter_type, reading_value, unit
)
VALUES (
  'b9b00000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'WATER',
  10,
  'm3'
);

INSERT INTO public.media_assets (
  id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type
)
VALUES
  ('ba000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000001/current.jpg', 'image/jpeg'),
  ('ba000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000002/superseded.jpg', 'image/jpeg'),
  ('ba000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000003/draftonly.jpg', 'image/jpeg'),
  ('ba000000-0000-0000-0000-000000000006', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000006/internal.jpg', 'image/jpeg');

INSERT INTO public.media_assets (
  id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type
)
VALUES (
  'ba000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000002', 'inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000002/inspection/b8000000-0000-0000-0000-000000000002/ba000000-0000-0000-0000-000000000004/unowned.jpg', 'image/jpeg'
);

INSERT INTO storage.objects (bucket_id, name)
VALUES
  ('inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000001/current.jpg'),
  ('inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000002/superseded.jpg'),
  ('inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000003/draftonly.jpg'),
  ('inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000001/inspection/b8000000-0000-0000-0000-000000000001/ba000000-0000-0000-0000-000000000006/internal.jpg'),
  ('inspection-media', 'b2000000-0000-0000-0000-000000000001/b3000000-0000-0000-0000-000000000002/inspection/b8000000-0000-0000-0000-000000000002/ba000000-0000-0000-0000-000000000004/unowned.jpg');

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id IN (
  'b8000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000002'
);

INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'b9000000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'A1 report v1',
  '{"media":["ba000000-0000-0000-0000-000000000002"]}'::jsonb
);
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('b9000000-0000-0000-0000-000000000001')$$,
  'Company A publishes A1 report v1'
);

INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'b9000000-0000-0000-0000-000000000002',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'A1 report v2',
  '{"media":["ba000000-0000-0000-0000-000000000001"]}'::jsonb
);
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('b9000000-0000-0000-0000-000000000002')$$,
  'Company A publishes A1 report v2, superseding v1'
);

INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'b9000000-0000-0000-0000-000000000003',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'A1 report v3 draft',
  '{"media":["ba000000-0000-0000-0000-000000000003"]}'::jsonb
);

INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'b9000000-0000-0000-0000-000000000004',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000002',
  'b8000000-0000-0000-0000-000000000002',
  'C report v1',
  '{"media":["ba000000-0000-0000-0000-000000000004"]}'::jsonb
);
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('b9000000-0000-0000-0000-000000000004')$$,
  'Company A publishes C report v1'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'b1000000-0000-0000-0000-000000000003';

INSERT INTO public.inspections (id, company_id, property_id, template_version_id)
VALUES ('b8000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000003', 'b5000000-0000-0000-0000-000000000002');

UPDATE public.inspections
SET status = 'IN_PROGRESS'
WHERE id = 'b8000000-0000-0000-0000-000000000003';

INSERT INTO public.media_assets (
  id, company_id, property_id, inspection_id, storage_bucket, storage_path, mime_type
)
VALUES (
  'ba000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000003', 'b8000000-0000-0000-0000-000000000003', 'inspection-media', 'b2000000-0000-0000-0000-000000000002/b3000000-0000-0000-0000-000000000003/inspection/b8000000-0000-0000-0000-000000000003/ba000000-0000-0000-0000-000000000005/b1current.jpg', 'image/jpeg'
);

INSERT INTO storage.objects (bucket_id, name)
VALUES ('inspection-media', 'b2000000-0000-0000-0000-000000000002/b3000000-0000-0000-0000-000000000003/inspection/b8000000-0000-0000-0000-000000000003/ba000000-0000-0000-0000-000000000005/b1current.jpg');

UPDATE public.inspections
SET status = 'COMPLETED'
WHERE id = 'b8000000-0000-0000-0000-000000000003';

INSERT INTO public.inspection_report_versions (id, company_id, property_id, inspection_id, title, content)
VALUES (
  'b9000000-0000-0000-0000-000000000005',
  'b2000000-0000-0000-0000-000000000002',
  'b3000000-0000-0000-0000-000000000003',
  'b8000000-0000-0000-0000-000000000003',
  'B1 report v1',
  '{"media":["ba000000-0000-0000-0000-000000000005"]}'::jsonb
);
SELECT lives_ok(
  $$SELECT public.publish_inspection_report('b9000000-0000-0000-0000-000000000005')$$,
  'Company B publishes B1 report v1'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'b1000000-0000-0000-0000-000000000001';

-- Scenario: owner own-property read
SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'b3000000-0000-0000-0000-000000000001'),
  1::bigint,
  'Andrea can read her owned property A1'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000002'),
  1::bigint,
  'Andrea can read A1''s current FINAL report'
);
SELECT is(
  (SELECT title FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000002'),
  'A1 report v2',
  'Andrea sees the FINAL report content as published'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE property_id = 'b3000000-0000-0000-0000-000000000001'),
  1::bigint,
  'Andrea sees exactly one report version for A1 (only current FINAL)'
);

-- Scenario: unowned property
SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'b3000000-0000-0000-0000-000000000002'),
  0::bigint,
  'Andrea cannot read unowned property C'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000004'),
  0::bigint,
  'Andrea cannot read C''s report by known UUID'
);

-- Scenario: DRAFT denial
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000003'),
  0::bigint,
  'Andrea cannot read A1''s DRAFT report by known UUID'
);

-- Scenario: SUPERSEDED denial
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000001'),
  0::bigint,
  'Andrea cannot read A1''s SUPERSEDED report by known UUID'
);

-- Scenario: multi-company ownership
SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'b3000000-0000-0000-0000-000000000003'),
  1::bigint,
  'Andrea can read her owned property B1 under Company B'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_report_versions WHERE id = 'b9000000-0000-0000-0000-000000000005'),
  1::bigint,
  'Andrea can read B1''s current FINAL report'
);

-- Scenario: owner_can_view_report helper direct
SELECT ok(
  security.owner_can_view_report('b9000000-0000-0000-0000-000000000002'),
  'helper: Andrea can view A1 current FINAL report'
);
SELECT ok(
  NOT security.owner_can_view_report('b9000000-0000-0000-0000-000000000001'),
  'helper: Andrea cannot view A1 SUPERSEDED report'
);
SELECT ok(
  NOT security.owner_can_view_report('b9000000-0000-0000-0000-000000000003'),
  'helper: Andrea cannot view A1 DRAFT report'
);
SELECT ok(
  NOT security.owner_can_view_report('b9000000-0000-0000-0000-000000000004'),
  'helper: Andrea cannot view unowned property C report'
);

-- Scenario: owner-visible media via storage path
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000001/%'),
  1::bigint,
  'Andrea can read the storage object referenced by A1''s current FINAL report'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000002/%'),
  0::bigint,
  'Andrea cannot read media referenced only by A1''s SUPERSEDED report'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000003/%'),
  0::bigint,
  'Andrea cannot read media referenced only by A1''s DRAFT report'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000004/%'),
  0::bigint,
  'Andrea cannot read media for unowned property C even though its report is published'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000005/%'),
  1::bigint,
  'Andrea can read B1''s published media under Company B'
);
SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000006/%'),
  0::bigint,
  'Andrea cannot read internal evidence never referenced by any published report'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name) VALUES ('inspection-media', 'hostile-owner-write.jpg')$$,
  '42501', NULL,
  'Andrea (owner) has no INSERT path into storage.objects; owner access is read-only'
);

-- Scenario: owner_report_media projection
SELECT is(
  (SELECT count(*) FROM public.owner_report_media('b9000000-0000-0000-0000-000000000002')),
  1::bigint,
  'owner_report_media returns exactly the media referenced by A1''s current FINAL report'
);
SELECT is(
  (SELECT media_id FROM public.owner_report_media('b9000000-0000-0000-0000-000000000002')),
  'ba000000-0000-0000-0000-000000000001'::uuid,
  'owner_report_media returns the correct media asset id'
);
SELECT is(
  (SELECT count(*) FROM public.owner_report_media('b9000000-0000-0000-0000-000000000001')),
  0::bigint,
  'owner_report_media returns nothing for a SUPERSEDED report'
);
SELECT is(
  (SELECT count(*) FROM public.owner_report_media('b9000000-0000-0000-0000-000000000003')),
  0::bigint,
  'owner_report_media returns nothing for a DRAFT report'
);
SELECT is(
  (SELECT count(*) FROM public.owner_report_media('b9000000-0000-0000-0000-000000000004')),
  0::bigint,
  'owner_report_media returns nothing for an unowned property''s report'
);

-- Scenario: raw runtime denial
SELECT is(
  (SELECT count(*) FROM public.inspections),
  0::bigint,
  'Andrea cannot directly read inspections'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_results),
  0::bigint,
  'Andrea cannot directly read inspection_results'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_changes),
  0::bigint,
  'Andrea cannot directly read inspection_changes'
);
SELECT is(
  (SELECT count(*) FROM public.meter_readings),
  0::bigint,
  'Andrea cannot directly read meter_readings'
);
SELECT is(
  (SELECT count(*) FROM public.media_assets),
  0::bigint,
  'Andrea cannot directly read raw media_assets rows'
);

-- Scenario: template denial
SELECT is(
  (SELECT count(*) FROM public.inspection_templates),
  0::bigint,
  'Andrea cannot directly read inspection_templates'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_template_versions),
  0::bigint,
  'Andrea cannot directly read inspection_template_versions'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_template_sections),
  0::bigint,
  'Andrea cannot directly read inspection_template_sections'
);
SELECT is(
  (SELECT count(*) FROM public.inspection_template_items),
  0::bigint,
  'Andrea cannot directly read inspection_template_items'
);

-- Scenario: company-internal denial
SELECT throws_ok(
  $$SELECT count(*) FROM public.company_memberships$$,
  '42501', NULL,
  'Andrea has no table privilege on company_memberships'
);
SELECT is(
  (SELECT count(*) FROM public.company_property_settings),
  0::bigint,
  'Andrea cannot directly read company_property_settings'
);
SELECT is(
  (SELECT count(*) FROM public.property_staff_assignments),
  0::bigint,
  'Andrea cannot directly read property_staff_assignments'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO 'b1000000-0000-0000-0000-000000000002';

-- Scenario: company portfolio-isolation regression
SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'b3000000-0000-0000-0000-000000000003'),
  0::bigint,
  'Company A cannot discover Andrea''s B1 property managed by Company B'
);

SET LOCAL request.jwt.claim.sub TO 'b1000000-0000-0000-0000-000000000003';

SELECT is(
  (SELECT count(*) FROM public.properties WHERE id = 'b3000000-0000-0000-0000-000000000001'),
  0::bigint,
  'Company B cannot discover Andrea''s A1 property managed by Company A'
);

RESET ROLE;
SET LOCAL ROLE anon;

SELECT is(
  (SELECT count(*) FROM storage.objects WHERE name LIKE '%/ba000000-0000-0000-0000-000000000001/%'),
  0::bigint,
  'anon cannot read owner-visible media through the owner storage policy'
);

RESET ROLE;

\else

SELECT * FROM skip(
  45,
  'owner portal read behavior requires the complete Task 12 helpers and policies'
);

\endif

SELECT * FROM finish();

ROLLBACK;
