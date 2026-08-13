BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_table(
  'public',
  'inspection_templates',
  'inspection_templates exists in public'
);
SELECT has_table(
  'public',
  'inspection_template_versions',
  'inspection_template_versions exists in public'
);
SELECT has_table(
  'public',
  'inspection_template_sections',
  'inspection_template_sections exists in public'
);
SELECT has_table(
  'public',
  'inspection_template_items',
  'inspection_template_items exists in public'
);

WITH expected(table_name, columns) AS (
  VALUES
    (
      'inspection_templates'::name,
      ARRAY['id', 'company_id', 'name', 'is_active', 'created_at']::name[]
    ),
    (
      'inspection_template_versions'::name,
      ARRAY[
        'id',
        'template_id',
        'version_number',
        'is_current',
        'frozen_at',
        'created_at'
      ]::name[]
    ),
    (
      'inspection_template_sections'::name,
      ARRAY['id', 'version_id', 'title', 'sort_order', 'created_at']::name[]
    ),
    (
      'inspection_template_items'::name,
      ARRAY[
        'id',
        'section_id',
        'label',
        'sort_order',
        'is_required',
        'created_at'
      ]::name[]
    )
), actual AS (
  SELECT
    relation.relname AS table_name,
    array_agg(attribute.attname ORDER BY attribute.attnum) AS columns
  FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
  WHERE namespace.nspname = 'public'
    AND relation.relname = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
  GROUP BY relation.relname
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'all four template tables have exactly the approved columns'
);

WITH expected(table_name, specification) AS (
  VALUES
    (
      'inspection_templates'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["company_id", "uuid", true, "<none>"],
        ["name", "text", true, "<none>"],
        ["is_active", "boolean", true, "true"],
        ["created_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'inspection_template_versions'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["template_id", "uuid", true, "<none>"],
        ["version_number", "integer", true, "<none>"],
        ["is_current", "boolean", true, "true"],
        ["frozen_at", "timestamp with time zone", false, "<none>"],
        ["created_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'inspection_template_sections'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["version_id", "uuid", true, "<none>"],
        ["title", "text", true, "<none>"],
        ["sort_order", "integer", true, "<none>"],
        ["created_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'inspection_template_items'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["section_id", "uuid", true, "<none>"],
        ["label", "text", true, "<none>"],
        ["sort_order", "integer", true, "<none>"],
        ["is_required", "boolean", true, "true"],
        ["created_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    )
), actual AS (
  SELECT
    relation.relname AS table_name,
    jsonb_agg(
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
    ) AS specification
  FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
  LEFT JOIN pg_attrdef default_value
    ON default_value.adrelid = attribute.attrelid
   AND default_value.adnum = attribute.attnum
  WHERE namespace.nspname = 'public'
    AND relation.relname = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
  GROUP BY relation.relname
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'template column types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(
        constraint_state.conkey = ARRAY[attribute.attnum]::smallint[]
      )
    FROM pg_constraint constraint_state
    JOIN pg_class relation ON relation.oid = constraint_state.conrelid
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    JOIN pg_attribute attribute
      ON attribute.attrelid = relation.oid
     AND attribute.attname = 'id'
    WHERE namespace.nspname = 'public'
      AND relation.relname = ANY (ARRAY[
        'inspection_templates',
        'inspection_template_versions',
        'inspection_template_sections',
        'inspection_template_items'
      ])
      AND constraint_state.contype = 'p'
  ), false),
  'all four template tables use id as their UUID primary key'
);

WITH expected(child_table, child_column, parent_table) AS (
  VALUES
    ('inspection_templates'::name, 'company_id'::name, 'companies'::name),
    (
      'inspection_template_versions'::name,
      'template_id'::name,
      'inspection_templates'::name
    ),
    (
      'inspection_template_sections'::name,
      'version_id'::name,
      'inspection_template_versions'::name
    ),
    (
      'inspection_template_items'::name,
      'section_id'::name,
      'inspection_template_sections'::name
    )
), actual AS (
  SELECT
    child.relname AS child_table,
    child_attribute.attname AS child_column,
    parent.relname AS parent_table
  FROM pg_constraint constraint_state
  JOIN pg_class child ON child.oid = constraint_state.conrelid
  JOIN pg_namespace namespace ON namespace.oid = child.relnamespace
  JOIN pg_class parent ON parent.oid = constraint_state.confrelid
  JOIN pg_attribute child_attribute
    ON child_attribute.attrelid = child.oid
   AND child_attribute.attnum = constraint_state.conkey[1]
  WHERE namespace.nspname = 'public'
    AND child.relname = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND constraint_state.contype = 'f'
    AND constraint_state.confdeltype = 'c'
    AND cardinality(constraint_state.conkey) = 1
    AND cardinality(constraint_state.confkey) = 1
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'the four approved parent links are single-column ON DELETE CASCADE foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(
        pg_get_constraintdef(constraint_state.oid) =
          'CHECK ((version_number > 0))'
      )
    FROM pg_constraint constraint_state
    WHERE constraint_state.conrelid =
        to_regclass('public.inspection_template_versions')
      AND constraint_state.contype = 'c'
  ), false),
  'version_number has exactly the positive-number check'
);

WITH expected(table_name, columns) AS (
  VALUES
    (
      'inspection_template_versions'::name,
      ARRAY['template_id', 'version_number']::name[]
    ),
    (
      'inspection_template_sections'::name,
      ARRAY['version_id', 'sort_order']::name[]
    ),
    (
      'inspection_template_items'::name,
      ARRAY['section_id', 'sort_order']::name[]
    )
), actual AS (
  SELECT
    relation.relname AS table_name,
    array_agg(attribute.attname ORDER BY key_position.ordinality) AS columns
  FROM pg_constraint constraint_state
  JOIN pg_class relation ON relation.oid = constraint_state.conrelid
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  CROSS JOIN LATERAL unnest(constraint_state.conkey)
    WITH ORDINALITY AS key_position(attnum, ordinality)
  JOIN pg_attribute attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attnum = key_position.attnum
  WHERE namespace.nspname = 'public'
    AND relation.relname = ANY (ARRAY[
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND constraint_state.contype = 'u'
  GROUP BY relation.relname, constraint_state.oid
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'version numbers and section/item order are unique only within their parent'
);

WITH expected(index_name) AS (
  VALUES
    ('inspection_templates_company_active_idx'::name),
    ('inspection_template_versions_template_id_version_number_key'::name),
    ('inspection_template_versions_one_current_idx'::name),
    ('inspection_template_sections_version_id_sort_order_key'::name),
    ('inspection_template_items_section_id_sort_order_key'::name)
), actual AS (
  SELECT index_relation.relname AS index_name
  FROM pg_index index_state
  JOIN pg_class table_relation ON table_relation.oid = index_state.indrelid
  JOIN pg_namespace namespace ON namespace.oid = table_relation.relnamespace
  JOIN pg_class index_relation ON index_relation.oid = index_state.indexrelid
  WHERE namespace.nspname = 'public'
    AND table_relation.relname = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND NOT index_state.indisprimary
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'only the approved authorization, order, version, and current indexes exist'
);

SELECT ok(
  COALESCE((
    SELECT index_state.indisunique
      AND index_state.indpred IS NOT NULL
      AND pg_get_expr(index_state.indpred, index_state.indrelid) = 'is_current'
      AND ARRAY(
        SELECT attribute.attname
        FROM unnest(index_state.indkey::smallint[])
          WITH ORDINALITY AS key_position(attnum, ordinality)
        JOIN pg_attribute attribute
          ON attribute.attrelid = index_state.indrelid
         AND attribute.attnum = key_position.attnum
        ORDER BY key_position.ordinality
      ) = ARRAY['template_id']::name[]
    FROM pg_index index_state
    WHERE index_state.indexrelid =
      to_regclass('public.inspection_template_versions_one_current_idx')
  ), false),
  'the partial unique current-version index permits at most one current row per template'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(relation.relrowsecurity)
      AND bool_and(NOT relation.relforcerowsecurity)
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.inspection_templates'),
      to_regclass('public.inspection_template_versions'),
      to_regclass('public.inspection_template_sections'),
      to_regclass('public.inspection_template_items')
    ])
  ), false),
  'all four template tables keep ordinary RLS enabled and not forced'
);

WITH expected(policyname, tablename, cmd) AS (
  VALUES
    ('inspection_templates_company_select', 'inspection_templates', 'SELECT'),
    (
      'inspection_templates_admin_manager_insert',
      'inspection_templates',
      'INSERT'
    ),
    (
      'inspection_templates_admin_manager_update',
      'inspection_templates',
      'UPDATE'
    ),
    (
      'inspection_templates_admin_manager_delete',
      'inspection_templates',
      'DELETE'
    ),
    (
      'inspection_template_versions_company_select',
      'inspection_template_versions',
      'SELECT'
    ),
    (
      'inspection_template_versions_admin_manager_insert',
      'inspection_template_versions',
      'INSERT'
    ),
    (
      'inspection_template_versions_admin_manager_update',
      'inspection_template_versions',
      'UPDATE'
    ),
    (
      'inspection_template_versions_admin_manager_delete',
      'inspection_template_versions',
      'DELETE'
    ),
    (
      'inspection_template_sections_company_select',
      'inspection_template_sections',
      'SELECT'
    ),
    (
      'inspection_template_sections_admin_manager_insert',
      'inspection_template_sections',
      'INSERT'
    ),
    (
      'inspection_template_sections_admin_manager_update',
      'inspection_template_sections',
      'UPDATE'
    ),
    (
      'inspection_template_sections_admin_manager_delete',
      'inspection_template_sections',
      'DELETE'
    ),
    (
      'inspection_template_items_company_select',
      'inspection_template_items',
      'SELECT'
    ),
    (
      'inspection_template_items_admin_manager_insert',
      'inspection_template_items',
      'INSERT'
    ),
    (
      'inspection_template_items_admin_manager_update',
      'inspection_template_items',
      'UPDATE'
    ),
    (
      'inspection_template_items_admin_manager_delete',
      'inspection_template_items',
      'DELETE'
    )
), actual AS (
  SELECT policyname, tablename, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'the template graph has exactly sixteen command-specific policies'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 16
      AND bool_and(permissive = 'PERMISSIVE')
      AND bool_and(roles = ARRAY['authenticated']::name[])
      AND bool_and(cmd <> 'ALL')
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
        'inspection_templates',
        'inspection_template_versions',
        'inspection_template_sections',
        'inspection_template_items'
      ])
  ), false),
  'all template policies are restrictive, authenticated-only, and command-specific'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 16
      AND bool_and(
        position(
          'security.has_company_role'
          in COALESCE(qual, with_check)
        ) > 0
      )
      AND bool_and(
        CASE WHEN cmd = 'UPDATE'
          THEN position('security.has_company_role' in qual) > 0
            AND position('security.has_company_role' in with_check) > 0
          ELSE true
        END
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspection_templates',
        'inspection_template_versions',
        'inspection_template_sections',
        'inspection_template_items'
      ])
  ), false),
  'every template policy derives access from explicit company-role membership'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 9
      AND bool_and(
        position('frozen_at' in COALESCE(qual, with_check)) > 0
      )
      AND bool_and(
        CASE WHEN cmd = 'UPDATE'
          THEN position('frozen_at' in qual) > 0
            AND position('frozen_at' in with_check) > 0
          ELSE true
        END
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'inspection_template_versions',
        'inspection_template_sections',
        'inspection_template_items'
      )
      AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  ), false),
  'all version, section, and item mutation policies constrain frozen ancestry'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspection_templates',
        'inspection_template_versions',
        'inspection_template_sections',
        'inspection_template_items'
      ])
      AND (
        lower(COALESCE(qual, '') || ' ' || COALESCE(with_check, ''))
          LIKE '%property%'
        OR lower(COALESCE(qual, '') || ' ' || COALESCE(with_check, ''))
          LIKE '%owner%'
      )
  ),
  'template authorization never depends on property assignments or owner identity'
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
      to_regclass('public.inspection_templates'),
      to_regclass('public.inspection_template_versions'),
      to_regclass('public.inspection_template_sections'),
      to_regclass('public.inspection_template_items')
    ])
      AND privilege.grantee = 0
  ),
  'PUBLIC has no template table privilege'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'SELECT'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'INSERT'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'UPDATE'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'DELETE'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'TRUNCATE'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'REFERENCES'))
      AND bool_and(NOT has_table_privilege('anon', relation.oid, 'TRIGGER'))
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.inspection_templates'),
      to_regclass('public.inspection_template_versions'),
      to_regclass('public.inspection_template_sections'),
      to_regclass('public.inspection_template_items')
    ])
  ), false),
  'anon has no template table privilege'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'SELECT'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'INSERT'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'UPDATE'))
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'DELETE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRUNCATE'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'REFERENCES'))
      AND bool_and(NOT has_table_privilege('authenticated', relation.oid, 'TRIGGER'))
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.inspection_templates'),
      to_regclass('public.inspection_template_versions'),
      to_regclass('public.inspection_template_sections'),
      to_regclass('public.inspection_template_items')
    ])
  ), false),
  'authenticated has exactly SELECT and DML template table privileges'
);

WITH expected(function_name) AS (
  VALUES
    ('protect_inspection_template_delete'::name),
    ('protect_inspection_template_version'::name),
    ('protect_inspection_template_section'::name),
    ('protect_inspection_template_item'::name)
), actual AS (
  SELECT procedure.proname AS function_name
  FROM pg_proc procedure
  JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
  WHERE namespace.nspname = 'security'
    AND procedure.proname LIKE 'protect_inspection_template%'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'exactly four narrow inspection-template trigger functions exist'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(procedure.prorettype = 'trigger'::regtype)
      AND bool_and(procedure.prosecdef)
      AND bool_and(procedure.provolatile = 'v')
      AND bool_and(procedure.prolang = (
        SELECT oid FROM pg_language WHERE lanname = 'plpgsql'
      ))
      AND bool_and(
        procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
      )
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'protect_inspection_template_delete',
        'protect_inspection_template_version',
        'protect_inspection_template_section',
        'protect_inspection_template_item'
      ])
  ), false),
  'template trigger functions are volatile SECURITY DEFINER PL/pgSQL with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(
        procedure.proowner = table_relation.relowner
      )
    FROM pg_proc procedure
    JOIN pg_namespace function_namespace
      ON function_namespace.oid = procedure.pronamespace
    JOIN LATERAL (
      SELECT CASE procedure.proname
        WHEN 'protect_inspection_template_delete'
          THEN 'inspection_templates'
        WHEN 'protect_inspection_template_version'
          THEN 'inspection_template_versions'
        WHEN 'protect_inspection_template_section'
          THEN 'inspection_template_sections'
        WHEN 'protect_inspection_template_item'
          THEN 'inspection_template_items'
      END AS table_name
    ) mapping ON true
    JOIN pg_class table_relation ON table_relation.relname = mapping.table_name
    JOIN pg_namespace table_namespace
      ON table_namespace.oid = table_relation.relnamespace
     AND table_namespace.nspname = 'public'
    WHERE function_namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'protect_inspection_template_delete',
        'protect_inspection_template_version',
        'protect_inspection_template_section',
        'protect_inspection_template_item'
      ])
  ), false),
  'each immutability function has the same owner as its protected table'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(NOT has_function_privilege('anon', procedure.oid, 'EXECUTE'))
      AND bool_and(
        NOT has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      )
      AND bool_and(
        NOT EXISTS (
          SELECT 1
          FROM aclexplode(COALESCE(
            procedure.proacl,
            acldefault('f', procedure.proowner)
          )) privilege
          WHERE privilege.grantee = 0
        )
      )
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'protect_inspection_template_delete',
        'protect_inspection_template_version',
        'protect_inspection_template_section',
        'protect_inspection_template_item'
      ])
  ), false),
  'PUBLIC, anon, and authenticated cannot execute immutability functions directly'
);

WITH expected(trigger_name, table_name, trigger_type) AS (
  VALUES
    (
      'inspection_templates_protect_frozen_delete'::name,
      'inspection_templates'::name,
      11::smallint
    ),
    (
      'inspection_template_versions_protect_frozen'::name,
      'inspection_template_versions'::name,
      27::smallint
    ),
    (
      'inspection_template_sections_protect_frozen'::name,
      'inspection_template_sections'::name,
      31::smallint
    ),
    (
      'inspection_template_items_protect_frozen'::name,
      'inspection_template_items'::name,
      31::smallint
    )
), actual AS (
  SELECT
    trigger_state.tgname AS trigger_name,
    relation.relname AS table_name,
    trigger_state.tgtype AS trigger_type
  FROM pg_trigger trigger_state
  JOIN pg_class relation ON relation.oid = trigger_state.tgrelid
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public'
    AND relation.relname = ANY (ARRAY[
      'inspection_templates',
      'inspection_template_versions',
      'inspection_template_sections',
      'inspection_template_items'
    ])
    AND NOT trigger_state.tgisinternal
    AND trigger_state.tgenabled = 'O'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'exactly four enabled row-level BEFORE immutability triggers protect the graph'
);

SELECT ok(
  to_regclass('public.inspections') IS NULL
    AND to_regclass('public.inspection_results') IS NULL
    AND to_regclass('public.inspection_changes') IS NULL
    AND to_regclass('public.meter_readings') IS NULL
    AND to_regclass('public.maintenance_jobs') IS NULL,
  'Task 8 adds no inspection runtime or maintenance tables'
);

SELECT (
  to_regclass('public.inspection_templates') IS NOT NULL
    AND to_regclass('public.inspection_template_versions') IS NOT NULL
    AND to_regclass('public.inspection_template_sections') IS NOT NULL
    AND to_regclass('public.inspection_template_items') IS NOT NULL
    AND to_regprocedure(
      'security.protect_inspection_template_delete()'
    ) IS NOT NULL
    AND to_regprocedure(
      'security.protect_inspection_template_version()'
    ) IS NOT NULL
    AND to_regprocedure(
      'security.protect_inspection_template_section()'
    ) IS NOT NULL
    AND to_regprocedure(
      'security.protect_inspection_template_item()'
    ) IS NOT NULL
)::integer AS inspection_template_system_ready
\gset

\if :inspection_template_system_ready

INSERT INTO auth.users (id)
VALUES
  ('71000000-0000-0000-0000-000000000001'),
  ('71000000-0000-0000-0000-000000000002'),
  ('71000000-0000-0000-0000-000000000003'),
  ('71000000-0000-0000-0000-000000000004'),
  ('71000000-0000-0000-0000-000000000005'),
  ('71000000-0000-0000-0000-000000000006'),
  ('71000000-0000-0000-0000-000000000007'),
  ('71000000-0000-0000-0000-000000000008');

INSERT INTO public.profiles (id)
VALUES
  ('71000000-0000-0000-0000-000000000001'),
  ('71000000-0000-0000-0000-000000000002'),
  ('71000000-0000-0000-0000-000000000003'),
  ('71000000-0000-0000-0000-000000000004'),
  ('71000000-0000-0000-0000-000000000005'),
  ('71000000-0000-0000-0000-000000000006'),
  ('71000000-0000-0000-0000-000000000007'),
  ('71000000-0000-0000-0000-000000000008');

INSERT INTO public.companies (id, name)
VALUES
  ('72000000-0000-0000-0000-000000000001', 'Template Company A'),
  ('72000000-0000-0000-0000-000000000002', 'Template Company B');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002', 'MANAGER', true),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000003', 'INSPECTOR', true),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000004', 'COORDINATOR', true),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000005', 'READ_ONLY', true),
  ('72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000006', 'ADMIN', true);

INSERT INTO public.properties (id, name)
VALUES ('73000000-0000-0000-0000-000000000001', 'Owner-only property');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES (
  '73000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000007'
);

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  (
    '74000000-0000-0000-0000-000000000101',
    '72000000-0000-0000-0000-000000000001',
    'Company A Primary'
  ),
  (
    '74000000-0000-0000-0000-000000000102',
    '72000000-0000-0000-0000-000000000001',
    'Company A Secondary'
  ),
  (
    '74000000-0000-0000-0000-000000000201',
    '72000000-0000-0000-0000-000000000002',
    'Company B Primary'
  );

INSERT INTO public.inspection_template_versions (
  id,
  template_id,
  version_number
)
VALUES
  (
    '75000000-0000-0000-0000-000000000101',
    '74000000-0000-0000-0000-000000000101',
    1
  ),
  (
    '75000000-0000-0000-0000-000000000102',
    '74000000-0000-0000-0000-000000000102',
    1
  ),
  (
    '75000000-0000-0000-0000-000000000201',
    '74000000-0000-0000-0000-000000000201',
    1
  );

INSERT INTO public.inspection_template_sections (
  id,
  version_id,
  title,
  sort_order
)
VALUES
  (
    '76000000-0000-0000-0000-000000000101',
    '75000000-0000-0000-0000-000000000101',
    'Exterior',
    10
  ),
  (
    '76000000-0000-0000-0000-000000000102',
    '75000000-0000-0000-0000-000000000101',
    'Interior',
    20
  ),
  (
    '76000000-0000-0000-0000-000000000103',
    '75000000-0000-0000-0000-000000000102',
    'Secondary Exterior',
    10
  ),
  (
    '76000000-0000-0000-0000-000000000201',
    '75000000-0000-0000-0000-000000000201',
    'Company B Exterior',
    10
  );

INSERT INTO public.inspection_template_items (
  id,
  section_id,
  label,
  sort_order,
  is_required
)
VALUES
  (
    '77000000-0000-0000-0000-000000000101',
    '76000000-0000-0000-0000-000000000101',
    'Walls',
    20,
    true
  ),
  (
    '77000000-0000-0000-0000-000000000102',
    '76000000-0000-0000-0000-000000000101',
    'Roof',
    10,
    false
  ),
  (
    '77000000-0000-0000-0000-000000000103',
    '76000000-0000-0000-0000-000000000102',
    'Floor',
    10,
    true
  ),
  (
    '77000000-0000-0000-0000-000000000104',
    '76000000-0000-0000-0000-000000000103',
    'Secondary Roof',
    10,
    true
  ),
  (
    '77000000-0000-0000-0000-000000000201',
    '76000000-0000-0000-0000-000000000201',
    'Company B Roof',
    10,
    true
  );

SELECT throws_ok(
  $$INSERT INTO public.inspection_template_versions (template_id, version_number) VALUES ('74000000-0000-0000-0000-000000000101', 0)$$,
  '23514',
  NULL,
  'non-positive version numbers are rejected'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_template_versions (template_id, version_number, is_current) VALUES ('74000000-0000-0000-0000-000000000101', 1, false)$$,
  '23505',
  NULL,
  'a version number cannot repeat within one template'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_versions
    WHERE version_number = 1
  ),
  3::bigint,
  'the same version number is valid for three different templates'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_template_versions (template_id, version_number) VALUES ('74000000-0000-0000-0000-000000000101', 2)$$,
  '23505',
  NULL,
  'a template cannot have two current versions'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_template_sections (version_id, title, sort_order) VALUES ('75000000-0000-0000-0000-000000000101', 'Duplicate order', 10)$$,
  '23505',
  NULL,
  'section order cannot repeat within one version'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_sections
    WHERE sort_order = 10
  ),
  3::bigint,
  'the same section order is valid under different versions'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_template_items (section_id, label, sort_order) VALUES ('76000000-0000-0000-0000-000000000101', 'Duplicate order', 10)$$,
  '23505',
  NULL,
  'item order cannot repeat within one section'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_items
    WHERE sort_order = 10
  ),
  4::bigint,
  'the same item order is valid under different sections'
);

SELECT is(
  (
    SELECT array_agg(title ORDER BY sort_order)
    FROM public.inspection_template_sections
    WHERE version_id = '75000000-0000-0000-0000-000000000101'
  ),
  ARRAY['Exterior', 'Interior']::text[],
  'sections have deterministic parent-local ordering'
);

SELECT is(
  (
    SELECT array_agg(label ORDER BY sort_order)
    FROM public.inspection_template_items
    WHERE section_id = '76000000-0000-0000-0000-000000000101'
  ),
  ARRAY['Roof', 'Walls']::text[],
  'items have deterministic parent-local ordering'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*) FROM public.inspection_templates),
  2::bigint,
  'Company A ADMIN lists only Company A templates'
);
SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_templates
    WHERE id = '74000000-0000-0000-0000-000000000201'
  ),
  0::bigint,
  'Company A ADMIN cannot directly query Company B template UUIDs'
);
SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_versions
    WHERE id = '75000000-0000-0000-0000-000000000201'
  ),
  0::bigint,
  'Company A ADMIN cannot directly query Company B version UUIDs'
);
SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_sections
    WHERE id = '76000000-0000-0000-0000-000000000201'
  ),
  0::bigint,
  'Company A ADMIN cannot directly query Company B section UUIDs'
);
SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_template_items
    WHERE id = '77000000-0000-0000-0000-000000000201'
  ),
  0::bigint,
  'Company A ADMIN cannot directly query Company B item UUIDs'
);

SELECT results_eq(
  $$UPDATE public.inspection_template_versions SET is_current = false, frozen_at = '2026-08-13 10:00:00+00' WHERE id = '75000000-0000-0000-0000-000000000101' RETURNING is_current, frozen_at$$,
  $$VALUES (false, '2026-08-13 10:00:00+00'::timestamptz)$$,
  'ADMIN atomically makes v1 non-current while freezing it'
);

RESET ROLE;

CREATE TEMPORARY TABLE task8_v1_snapshot AS
SELECT convert_to(
  jsonb_build_object(
    'version_id', version_state.id,
    'version_number', version_state.version_number,
    'sections', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', section_state.id,
          'title', section_state.title,
          'sort_order', section_state.sort_order,
          'items', (
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', item_state.id,
                'label', item_state.label,
                'sort_order', item_state.sort_order,
                'is_required', item_state.is_required
              )
              ORDER BY item_state.sort_order
            )
            FROM public.inspection_template_items item_state
            WHERE item_state.section_id = section_state.id
          )
        )
        ORDER BY section_state.sort_order
      )
      FROM public.inspection_template_sections section_state
      WHERE section_state.version_id = version_state.id
    )
  )::text,
  'UTF8'
) AS graph_bytes
FROM public.inspection_template_versions version_state
WHERE version_state.id = '75000000-0000-0000-0000-000000000101';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$INSERT INTO public.inspection_template_versions (id, template_id, version_number) VALUES ('75000000-0000-0000-0000-000000000104', '74000000-0000-0000-0000-000000000101', 2)$$,
  'ADMIN creates current v2 after freezing and retiring v1'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order) VALUES ('76000000-0000-0000-0000-000000000104', '75000000-0000-0000-0000-000000000104', 'Draft section', 10)$$,
  'ADMIN creates a section in unfrozen v2'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_items (id, section_id, label, sort_order) VALUES ('77000000-0000-0000-0000-000000000105', '76000000-0000-0000-0000-000000000104', 'Draft item', 10)$$,
  'ADMIN creates an item in unfrozen v2'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_sections SET title = 'Edited v2 section' WHERE id = '76000000-0000-0000-0000-000000000104' RETURNING title$$,
  $$VALUES ('Edited v2 section'::text)$$,
  'ADMIN edits an unfrozen v2 section'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_items SET label = 'Edited v2 item', is_required = false WHERE id = '77000000-0000-0000-0000-000000000105' RETURNING label, is_required$$,
  $$VALUES ('Edited v2 item'::text, false)$$,
  'ADMIN edits an unfrozen v2 item'
);

RESET ROLE;

SELECT ok(
  (SELECT count(*) FROM public.inspection_template_versions
    WHERE id = '75000000-0000-0000-0000-000000000101') = 1
    AND (SELECT graph_bytes FROM task8_v1_snapshot) = (
      SELECT convert_to(
        jsonb_build_object(
          'version_id', version_state.id,
          'version_number', version_state.version_number,
          'sections', (
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', section_state.id,
                'title', section_state.title,
                'sort_order', section_state.sort_order,
                'items', (
                  SELECT jsonb_agg(
                    jsonb_build_object(
                      'id', item_state.id,
                      'label', item_state.label,
                      'sort_order', item_state.sort_order,
                      'is_required', item_state.is_required
                    )
                    ORDER BY item_state.sort_order
                  )
                  FROM public.inspection_template_items item_state
                  WHERE item_state.section_id = section_state.id
                )
              )
              ORDER BY section_state.sort_order
            )
            FROM public.inspection_template_sections section_state
            WHERE section_state.version_id = version_state.id
          )
        )::text,
        'UTF8'
      )
      FROM public.inspection_template_versions version_state
      WHERE version_state.id = '75000000-0000-0000-0000-000000000101'
    ),
  'frozen v1 stays queryable and byte-for-byte structurally stable after v2 edits'
);

SELECT throws_ok(
  $$UPDATE public.inspection_template_versions SET version_number = 9 WHERE id = '75000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'a frozen version rejects direct UPDATE even outside RLS'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_template_versions WHERE id = '75000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'a frozen version rejects direct DELETE even outside RLS'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_template_sections (version_id, title, sort_order) VALUES ('75000000-0000-0000-0000-000000000101', 'Late section', 30)$$,
  '55000', NULL, 'a section cannot be inserted into a frozen version'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_sections SET title = 'Changed frozen section' WHERE id = '76000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'a section in frozen history rejects UPDATE'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_template_sections WHERE id = '76000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'a section in frozen history rejects DELETE'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_sections SET version_id = '75000000-0000-0000-0000-000000000104' WHERE id = '76000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'a section cannot be moved out of frozen history'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_sections SET version_id = '75000000-0000-0000-0000-000000000101' WHERE id = '76000000-0000-0000-0000-000000000104'$$,
  '55000', NULL, 'a section cannot be moved into frozen history'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_template_items (section_id, label, sort_order) VALUES ('76000000-0000-0000-0000-000000000101', 'Late item', 30)$$,
  '55000', NULL, 'an item cannot be inserted under frozen ancestry'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_items SET label = 'Changed frozen item' WHERE id = '77000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'an item under frozen ancestry rejects UPDATE'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_template_items WHERE id = '77000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'an item under frozen ancestry rejects DELETE'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_items SET section_id = '76000000-0000-0000-0000-000000000104' WHERE id = '77000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'an item cannot be moved out of frozen ancestry'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_items SET section_id = '76000000-0000-0000-0000-000000000101' WHERE id = '77000000-0000-0000-0000-000000000105'$$,
  '55000', NULL, 'an item cannot be moved into frozen ancestry'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_templates WHERE id = '74000000-0000-0000-0000-000000000101'$$,
  '55000', NULL, 'logical template deletion cannot cascade away frozen history'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$INSERT INTO public.inspection_templates (id, company_id, name) VALUES ('74000000-0000-0000-0000-000000000110', '72000000-0000-0000-0000-000000000001', 'Manager draft')$$,
  'MANAGER creates a Company A template'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_versions (id, template_id, version_number) VALUES ('75000000-0000-0000-0000-000000000110', '74000000-0000-0000-0000-000000000110', 1)$$,
  'MANAGER creates its unfrozen version'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order) VALUES ('76000000-0000-0000-0000-000000000110', '75000000-0000-0000-0000-000000000110', 'Manager section', 10)$$,
  'MANAGER creates its unfrozen section'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_items (id, section_id, label, sort_order) VALUES ('77000000-0000-0000-0000-000000000110', '76000000-0000-0000-0000-000000000110', 'Manager item', 10)$$,
  'MANAGER creates its unfrozen item'
);
SELECT results_eq(
  $$UPDATE public.inspection_templates SET name = 'Manager edited' WHERE id = '74000000-0000-0000-0000-000000000110' RETURNING name$$,
  $$VALUES ('Manager edited'::text)$$,
  'MANAGER updates its own logical template'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_versions SET version_number = 2 WHERE id = '75000000-0000-0000-0000-000000000110' RETURNING version_number$$,
  $$VALUES (2)$$,
  'MANAGER updates its own unfrozen version'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_sections SET title = 'Manager edited section' WHERE id = '76000000-0000-0000-0000-000000000110' RETURNING title$$,
  $$VALUES ('Manager edited section'::text)$$,
  'MANAGER updates its own unfrozen section'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_items SET label = 'Manager edited item' WHERE id = '77000000-0000-0000-0000-000000000110' RETURNING label$$,
  $$VALUES ('Manager edited item'::text)$$,
  'MANAGER updates its own unfrozen item'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_templates (company_id, name) VALUES ('72000000-0000-0000-0000-000000000002', 'Hostile B insert')$$,
  '42501', NULL, 'Company A MANAGER cannot insert a Company B template'
);
SELECT throws_ok(
  $$UPDATE public.inspection_templates SET company_id = '72000000-0000-0000-0000-000000000002' WHERE id = '74000000-0000-0000-0000-000000000110'$$,
  '42501', NULL, 'Company A MANAGER cannot reparent its template into Company B'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_versions SET template_id = '74000000-0000-0000-0000-000000000201' WHERE id = '75000000-0000-0000-0000-000000000110'$$,
  '42501', NULL, 'Company A MANAGER cannot reparent its version into Company B'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_sections SET version_id = '75000000-0000-0000-0000-000000000201' WHERE id = '76000000-0000-0000-0000-000000000110'$$,
  '42501', NULL, 'Company A MANAGER cannot reparent its section into Company B'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_items SET section_id = '76000000-0000-0000-0000-000000000201' WHERE id = '77000000-0000-0000-0000-000000000110'$$,
  '42501', NULL, 'Company A MANAGER cannot reparent its item into Company B'
);
SELECT results_eq(
  $$UPDATE public.inspection_templates SET name = 'Hostile edit' WHERE id = '74000000-0000-0000-0000-000000000201' RETURNING 1$$,
  $$VALUES (NULL::integer) LIMIT 0$$,
  'Company A MANAGER cannot update an existing Company B template'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_template_items WHERE id = '77000000-0000-0000-0000-000000000201' RETURNING 1$$,
  $$VALUES (NULL::integer) LIMIT 0$$,
  'Company A MANAGER cannot delete an existing Company B item'
);

SELECT results_eq(
  $$DELETE FROM public.inspection_template_items WHERE id = '77000000-0000-0000-0000-000000000110' RETURNING 1$$,
  $$VALUES (1)$$,
  'MANAGER deletes its own unfrozen item'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_template_sections WHERE id = '76000000-0000-0000-0000-000000000110' RETURNING 1$$,
  $$VALUES (1)$$,
  'MANAGER deletes its own unfrozen section'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_template_versions WHERE id = '75000000-0000-0000-0000-000000000110' RETURNING 1$$,
  $$VALUES (1)$$,
  'MANAGER deletes its own unfrozen version'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_templates WHERE id = '74000000-0000-0000-0000-000000000110' RETURNING 1$$,
  $$VALUES (1)$$,
  'MANAGER deletes its own version-free template'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$INSERT INTO public.inspection_templates (id, company_id, name) VALUES ('74000000-0000-0000-0000-000000000111', '72000000-0000-0000-0000-000000000001', 'Admin draft')$$,
  'ADMIN creates a Company A template'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_versions (id, template_id, version_number) VALUES ('75000000-0000-0000-0000-000000000111', '74000000-0000-0000-0000-000000000111', 1)$$,
  'ADMIN creates an unfrozen version'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order) VALUES ('76000000-0000-0000-0000-000000000111', '75000000-0000-0000-0000-000000000111', 'Admin section', 10)$$,
  'ADMIN creates an unfrozen section'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_template_items (id, section_id, label, sort_order) VALUES ('77000000-0000-0000-0000-000000000111', '76000000-0000-0000-0000-000000000111', 'Admin item', 10)$$,
  'ADMIN creates an unfrozen item'
);
SELECT results_eq(
  $$UPDATE public.inspection_templates SET name = 'Admin edited' WHERE id = '74000000-0000-0000-0000-000000000111' RETURNING name$$,
  $$VALUES ('Admin edited'::text)$$,
  'ADMIN updates its own logical template'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_items SET label = 'Admin edited item' WHERE id = '77000000-0000-0000-0000-000000000111' RETURNING label$$,
  $$VALUES ('Admin edited item'::text)$$,
  'ADMIN updates its own unfrozen descendants'
);
SELECT results_eq(
  $$UPDATE public.inspection_template_versions SET version_number = 9 WHERE id = '75000000-0000-0000-0000-000000000201' RETURNING 1$$,
  $$VALUES (NULL::integer) LIMIT 0$$,
  'Company A ADMIN cannot update an existing Company B version'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_template_sections WHERE id = '76000000-0000-0000-0000-000000000201' RETURNING 1$$,
  $$VALUES (NULL::integer) LIMIT 0$$,
  'Company A ADMIN cannot delete an existing Company B section'
);
SELECT throws_ok(
  $$UPDATE public.inspection_template_versions SET template_id = '74000000-0000-0000-0000-000000000201' WHERE id = '75000000-0000-0000-0000-000000000111'$$,
  '42501', NULL, 'Company A ADMIN cannot reparent its version into Company B'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_templates WHERE id = '74000000-0000-0000-0000-000000000111' RETURNING 1$$,
  $$VALUES (1)$$,
  'ADMIN deletes its own unfrozen graph by cascade'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000003';
SELECT is(
  (SELECT count(*) FROM public.inspection_templates),
  2::bigint,
  'INSPECTOR selects its own company template graph without property assignment'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_templates (company_id, name) VALUES ('72000000-0000-0000-0000-000000000001', 'Inspector write')$$,
  '42501', NULL, 'INSPECTOR cannot mutate templates'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000004';
SELECT is(
  (SELECT count(*) FROM public.inspection_template_versions),
  3::bigint,
  'COORDINATOR selects its own company version graph'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_template_versions (template_id, version_number, is_current) VALUES ('74000000-0000-0000-0000-000000000102', 2, false)$$,
  '42501', NULL, 'COORDINATOR cannot mutate versions'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000005';
SELECT is(
  (SELECT count(*) FROM public.inspection_template_items),
  5::bigint,
  'READ_ONLY selects its own company item graph'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_template_items (section_id, label, sort_order) VALUES ('76000000-0000-0000-0000-000000000104', 'Read-only write', 20)$$,
  '42501', NULL, 'READ_ONLY cannot mutate items'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000006';
SELECT ok(
  (SELECT count(*) FROM public.inspection_templates) = 1
    AND (SELECT count(*) FROM public.inspection_template_versions) = 1
    AND (SELECT count(*) FROM public.inspection_template_sections) = 1
    AND (SELECT count(*) FROM public.inspection_template_items) = 1
    AND (SELECT count(*) FROM public.inspection_templates
      WHERE id = '74000000-0000-0000-0000-000000000101') = 0,
  'Company B sees its independent graph and no Company A template'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000007';
SELECT ok(
  (SELECT count(*) FROM public.inspection_templates) = 0
    AND (SELECT count(*) FROM public.inspection_template_versions) = 0
    AND (SELECT count(*) FROM public.inspection_template_sections) = 0
    AND (SELECT count(*) FROM public.inspection_template_items) = 0,
  'a global property owner has no template-internal access'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_templates (company_id, name) VALUES ('72000000-0000-0000-0000-000000000001', 'Owner write')$$,
  '42501', NULL, 'global owner identity grants no template mutation'
);

SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000008';
SELECT ok(
  (SELECT count(*) FROM public.inspection_templates) = 0
    AND (SELECT count(*) FROM public.inspection_template_versions) = 0
    AND (SELECT count(*) FROM public.inspection_template_sections) = 0
    AND (SELECT count(*) FROM public.inspection_template_items) = 0,
  'an unrelated authenticated profile has no template-internal access'
);

SET LOCAL request.jwt.claim.sub TO '';
SELECT ok(
  (SELECT count(*) FROM public.inspection_templates) = 0
    AND (SELECT count(*) FROM public.inspection_template_versions) = 0
    AND (SELECT count(*) FROM public.inspection_template_sections) = 0
    AND (SELECT count(*) FROM public.inspection_template_items) = 0,
  'authenticated without a JWT subject fails closed on the template graph'
);
SELECT throws_ok(
  $$SELECT security.protect_inspection_template_version()$$,
  '42501', NULL, 'authenticated cannot invoke an immutability trigger function directly'
);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$SELECT count(*) FROM public.inspection_templates$$,
  '42501', NULL, 'anon cannot read template internals'
);

RESET ROLE;

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspection_template_versions
    WHERE id = '75000000-0000-0000-0000-000000000101'
      AND version_number = 1
      AND NOT is_current
      AND frozen_at = '2026-08-13 10:00:00+00'
  )
    AND EXISTS (
      SELECT 1
      FROM public.inspection_template_versions
      WHERE id = '75000000-0000-0000-0000-000000000104'
        AND version_number = 2
        AND is_current
        AND frozen_at IS NULL
    ),
  'v1 remains frozen and non-current while v2 remains current and editable'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '71000000-0000-0000-0000-000000000001';
SELECT ok(
  security.has_company_role(
    '72000000-0000-0000-0000-000000000001',
    ARRAY['ADMIN']::public.company_role[]
  )
    AND NOT security.has_company_role(
      '72000000-0000-0000-0000-000000000002',
      ARRAY['ADMIN']::public.company_role[]
    ),
  'existing company-role helper remains recursion-free and tenant-exact'
);
RESET ROLE;

\else

SELECT * FROM skip(
  79,
  'template behavior requires all four Task 8 tables and immutability triggers'
);

\endif

SELECT * FROM finish();

ROLLBACK;
