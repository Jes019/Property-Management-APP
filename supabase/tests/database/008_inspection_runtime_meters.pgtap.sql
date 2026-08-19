BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_type('public', 'meter_type', 'meter_type exists in public');

SELECT ok(
  COALESCE((
    SELECT array_agg(enum_state.enumlabel ORDER BY enum_state.enumsortorder) =
      ARRAY['ELECTRICITY', 'WATER']::name[]
    FROM pg_type type_state
    JOIN pg_namespace namespace ON namespace.oid = type_state.typnamespace
    JOIN pg_enum enum_state ON enum_state.enumtypid = type_state.oid
    WHERE namespace.nspname = 'public'
      AND type_state.typname = 'meter_type'
  ), false),
  'meter_type has exactly ELECTRICITY and WATER in order'
);

SELECT has_table('public', 'inspections', 'inspections exists in public');
SELECT has_table(
  'public',
  'inspection_results',
  'inspection_results exists in public'
);
SELECT has_table(
  'public',
  'inspection_changes',
  'inspection_changes exists in public'
);
SELECT has_table('public', 'meter_readings', 'meter_readings exists in public');

WITH expected(table_name, columns) AS (
  VALUES
    (
      'inspections'::name,
      ARRAY[
        'id',
        'company_id',
        'property_id',
        'template_version_id',
        'status',
        'scheduled_at',
        'started_at',
        'completed_at',
        'created_by',
        'created_at',
        'updated_at'
      ]::name[]
    ),
    (
      'inspection_results'::name,
      ARRAY[
        'id',
        'company_id',
        'property_id',
        'inspection_id',
        'template_item_id',
        'severity',
        'operational_action',
        'comment',
        'created_at',
        'updated_at'
      ]::name[]
    ),
    (
      'inspection_changes'::name,
      ARRAY[
        'id',
        'inspection_id',
        'company_id',
        'property_id',
        'changed_by',
        'change_type',
        'old_value',
        'new_value',
        'created_at'
      ]::name[]
    ),
    (
      'meter_readings'::name,
      ARRAY[
        'id',
        'company_id',
        'property_id',
        'inspection_id',
        'meter_type',
        'reading_value',
        'unit',
        'recorded_at',
        'recorded_by',
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
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
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
  'all four runtime tables have exactly the approved columns'
);

WITH expected(table_name, specification) AS (
  VALUES
    (
      'inspections'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["company_id", "uuid", true, "<none>"],
        ["property_id", "uuid", true, "<none>"],
        ["template_version_id", "uuid", true, "<none>"],
        ["status", "inspection_lifecycle_status", true, "''SCHEDULED''::inspection_lifecycle_status"],
        ["scheduled_at", "timestamp with time zone", false, "<none>"],
        ["started_at", "timestamp with time zone", false, "<none>"],
        ["completed_at", "timestamp with time zone", false, "<none>"],
        ["created_by", "uuid", true, "<none>"],
        ["created_at", "timestamp with time zone", true, "now()"],
        ["updated_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'inspection_results'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["company_id", "uuid", true, "<none>"],
        ["property_id", "uuid", true, "<none>"],
        ["inspection_id", "uuid", true, "<none>"],
        ["template_item_id", "uuid", true, "<none>"],
        ["severity", "inspection_severity", true, "<none>"],
        ["operational_action", "operational_action", true, "<none>"],
        ["comment", "text", false, "<none>"],
        ["created_at", "timestamp with time zone", true, "now()"],
        ["updated_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'inspection_changes'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["inspection_id", "uuid", true, "<none>"],
        ["company_id", "uuid", true, "<none>"],
        ["property_id", "uuid", true, "<none>"],
        ["changed_by", "uuid", true, "<none>"],
        ["change_type", "text", true, "<none>"],
        ["old_value", "jsonb", false, "<none>"],
        ["new_value", "jsonb", false, "<none>"],
        ["created_at", "timestamp with time zone", true, "now()"]
      ]'::jsonb
    ),
    (
      'meter_readings'::name,
      '[
        ["id", "uuid", true, "gen_random_uuid()"],
        ["company_id", "uuid", true, "<none>"],
        ["property_id", "uuid", true, "<none>"],
        ["inspection_id", "uuid", true, "<none>"],
        ["meter_type", "meter_type", true, "<none>"],
        ["reading_value", "numeric", true, "<none>"],
        ["unit", "text", true, "<none>"],
        ["recorded_at", "timestamp with time zone", true, "now()"],
        ["recorded_by", "uuid", true, "<none>"],
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
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
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
  'runtime column types, nullability, and defaults are exact'
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
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
      AND constraint_state.contype = 'p'
  ), false),
  'all runtime tables use id as their UUID primary key'
);

WITH expected(child_table, child_column, parent_table, delete_action) AS (
  VALUES
    ('inspections'::name, 'company_id'::name, 'companies'::name, 'a'::text),
    ('inspections', 'property_id', 'properties', 'a'),
    (
      'inspections',
      'template_version_id',
      'inspection_template_versions',
      'a'
    ),
    ('inspections', 'created_by', 'profiles', 'a'),
    ('inspection_results', 'company_id', 'companies', 'a'),
    ('inspection_results', 'property_id', 'properties', 'a'),
    ('inspection_results', 'inspection_id', 'inspections', 'c'),
    (
      'inspection_results',
      'template_item_id',
      'inspection_template_items',
      'a'
    ),
    ('inspection_changes', 'inspection_id', 'inspections', 'a'),
    ('inspection_changes', 'company_id', 'companies', 'a'),
    ('inspection_changes', 'property_id', 'properties', 'a'),
    ('inspection_changes', 'changed_by', 'profiles', 'a'),
    ('meter_readings', 'company_id', 'companies', 'a'),
    ('meter_readings', 'property_id', 'properties', 'a'),
    ('meter_readings', 'inspection_id', 'inspections', 'a'),
    ('meter_readings', 'recorded_by', 'profiles', 'a')
), actual AS (
  SELECT
    child.relname AS child_table,
    child_attribute.attname AS child_column,
    parent.relname AS parent_table,
    constraint_state.confdeltype::text AS delete_action
  FROM pg_constraint constraint_state
  JOIN pg_class child ON child.oid = constraint_state.conrelid
  JOIN pg_namespace namespace ON namespace.oid = child.relnamespace
  JOIN pg_class parent ON parent.oid = constraint_state.confrelid
  JOIN pg_attribute child_attribute
    ON child_attribute.attrelid = child.oid
   AND child_attribute.attnum = constraint_state.conkey[1]
  WHERE namespace.nspname = 'public'
    AND child.relname = ANY (ARRAY[
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
    ])
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
  'runtime foreign keys and delete actions are exact'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(
        ARRAY(
          SELECT attribute.attname
          FROM unnest(constraint_state.conkey)
            WITH ORDINALITY AS key_position(attnum, ordinality)
          JOIN pg_attribute attribute
            ON attribute.attrelid = constraint_state.conrelid
           AND attribute.attnum = key_position.attnum
          ORDER BY key_position.ordinality
        ) = ARRAY['inspection_id', 'template_item_id']::name[]
      )
    FROM pg_constraint constraint_state
    WHERE constraint_state.conrelid =
        to_regclass('public.inspection_results')
      AND constraint_state.contype = 'u'
  ), false),
  'results are unique only by inspection and template item'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(
        pg_get_constraintdef(constraint_state.oid) =
          'CHECK ((change_type = ANY (ARRAY[''STARTED''::text, ''RESULT_CHANGED''::text, ''COMPLETED''::text])))'
      )
    FROM pg_constraint constraint_state
    WHERE constraint_state.conrelid =
        to_regclass('public.inspection_changes')
      AND constraint_state.contype = 'c'
  ), false),
  'change_type accepts exactly STARTED, RESULT_CHANGED, and COMPLETED'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(
        lower(pg_get_constraintdef(constraint_state.oid)) LIKE
          '%nan%infinity%'
      )
    FROM pg_constraint constraint_state
    WHERE constraint_state.conrelid = to_regclass('public.meter_readings')
      AND constraint_state.contype = 'c'
  ), false),
  'meter readings have one hard non-finite numeric rejection check'
);

WITH expected(index_name) AS (
  VALUES
    ('inspections_company_id_property_id_status_idx'::name),
    ('inspections_property_id_scheduled_at_idx'),
    ('inspection_results_inspection_id_template_item_id_key'),
    ('inspection_results_company_id_property_id_idx'),
    ('meter_readings_inspection_id_meter_type_idx'),
    ('meter_readings_company_id_property_id_idx'),
    ('inspection_changes_inspection_id_created_at_idx')
), actual AS (
  SELECT index_relation.relname AS index_name
  FROM pg_index index_state
  JOIN pg_class table_relation ON table_relation.oid = index_state.indrelid
  JOIN pg_namespace namespace ON namespace.oid = table_relation.relnamespace
  JOIN pg_class index_relation ON index_relation.oid = index_state.indexrelid
  WHERE namespace.nspname = 'public'
    AND table_relation.relname = ANY (ARRAY[
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
    ])
    AND NOT index_state.indisprimary
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'only the seven approved runtime indexes exist'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(relation.relrowsecurity)
      AND bool_and(NOT relation.relforcerowsecurity)
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.inspections'),
      to_regclass('public.inspection_results'),
      to_regclass('public.inspection_changes'),
      to_regclass('public.meter_readings')
    ])
  ), false),
  'all runtime tables use ordinary non-forced RLS'
);

WITH expected(policyname, tablename, cmd) AS (
  VALUES
    ('inspections_company_select'::name, 'inspections'::name, 'SELECT'::text),
    ('inspections_operational_insert', 'inspections', 'INSERT'),
    ('inspections_operational_update', 'inspections', 'UPDATE'),
    ('inspection_results_company_select', 'inspection_results', 'SELECT'),
    ('inspection_results_operational_insert', 'inspection_results', 'INSERT'),
    ('inspection_results_operational_update', 'inspection_results', 'UPDATE'),
    ('inspection_results_operational_delete', 'inspection_results', 'DELETE'),
    ('inspection_changes_company_select', 'inspection_changes', 'SELECT'),
    ('meter_readings_company_select', 'meter_readings', 'SELECT'),
    ('meter_readings_operational_insert', 'meter_readings', 'INSERT'),
    ('meter_readings_operational_update', 'meter_readings', 'UPDATE'),
    ('meter_readings_operational_delete', 'meter_readings', 'DELETE')
), actual AS (
  SELECT policyname, tablename, cmd
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = ANY (ARRAY[
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
    ])
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'runtime tables have exactly twelve command-specific policies'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 12
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
      AND bool_and(
        position(
          'security.company_has_property_scope' in
          COALESCE(qual, with_check)
        ) > 0
      )
      AND bool_and(
        CASE WHEN cmd = 'UPDATE'
          THEN position('security.company_has_property_scope' in qual) > 0
            AND position(
              'security.company_has_property_scope' in with_check
            ) > 0
          ELSE true
        END
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
  ), false),
  'every runtime policy is nontrivial and enforces the approved property scopes'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 12
      AND bool_and(
        position('FULL_MANAGEMENT' in COALESCE(qual, with_check)) > 0
      )
      AND bool_and(
        position('INSPECTION_SERVICE' in COALESCE(qual, with_check)) > 0
      )
      AND bool_and(
        position('MAINTENANCE_SERVICE' in COALESCE(qual, with_check)) = 0
      )
      AND bool_and(
        position('COORDINATION_SERVICE' in COALESCE(qual, with_check)) = 0
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
  ), false),
  'policies use only FULL_MANAGEMENT and INSPECTION_SERVICE scope'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 12
      AND bool_and(
        position('security.has_company_role' in COALESCE(qual, with_check)) > 0
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
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
  ), false),
  'every runtime policy uses explicit company roles'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 12
      AND bool_and(
        position('security.is_assigned_to_property' in COALESCE(qual, with_check)) > 0
      )
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
  ), false),
  'every role path states the inspector assignment boundary'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'inspections',
        'inspection_results',
        'inspection_changes',
        'meter_readings'
      ])
      AND lower(COALESCE(qual, '') || ' ' || COALESCE(with_check, ''))
        LIKE '%owner%'
  ),
  'runtime policies contain no owner access path'
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
      to_regclass('public.inspections'),
      to_regclass('public.inspection_results'),
      to_regclass('public.inspection_changes'),
      to_regclass('public.meter_readings')
    ])
      AND privilege.grantee = 0
  ),
  'PUBLIC has no runtime table privilege'
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
      to_regclass('public.inspections'),
      to_regclass('public.inspection_results'),
      to_regclass('public.inspection_changes'),
      to_regclass('public.meter_readings')
    ])
  ), false),
  'anon has no runtime table privilege'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(has_table_privilege('authenticated', relation.oid, 'SELECT'))
      AND bool_and(
        has_table_privilege('authenticated', relation.oid, 'INSERT') =
          (relation.relname <> 'inspection_changes')
      )
      AND bool_and(
        has_table_privilege('authenticated', relation.oid, 'UPDATE') =
          (relation.relname <> 'inspection_changes')
      )
      AND bool_and(
        has_table_privilege('authenticated', relation.oid, 'DELETE') =
          (relation.relname IN ('inspection_results', 'meter_readings'))
      )
      AND bool_and(
        NOT has_table_privilege('authenticated', relation.oid, 'TRUNCATE')
      )
      AND bool_and(
        NOT has_table_privilege('authenticated', relation.oid, 'REFERENCES')
      )
      AND bool_and(
        NOT has_table_privilege('authenticated', relation.oid, 'TRIGGER')
      )
    FROM pg_class relation
    WHERE relation.oid = ANY (ARRAY[
      to_regclass('public.inspections'),
      to_regclass('public.inspection_results'),
      to_regclass('public.inspection_changes'),
      to_regclass('public.meter_readings')
    ])
  ), false),
  'authenticated runtime grants are exactly the approved minimum DML surface'
);

WITH expected(function_name) AS (
  VALUES
    ('protect_inspection_runtime'::name),
    ('protect_inspection_result'::name),
    ('protect_meter_reading'::name),
    ('write_inspection_lifecycle_change'::name),
    ('write_inspection_result_change'::name)
), actual AS (
  SELECT procedure.proname AS function_name
  FROM pg_proc procedure
  JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
  WHERE namespace.nspname = 'security'
    AND procedure.proname = ANY (ARRAY[
      'protect_inspection_runtime',
      'protect_inspection_result',
      'protect_meter_reading',
      'write_inspection_lifecycle_change',
      'write_inspection_result_change'
    ])
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'exactly the five approved narrow runtime trigger functions exist'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
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
        'protect_inspection_runtime',
        'protect_inspection_result',
        'protect_meter_reading',
        'write_inspection_lifecycle_change',
        'write_inspection_result_change'
      ])
  ), false),
  'runtime trigger functions are volatile SECURITY DEFINER PL/pgSQL with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
      AND bool_and(procedure.proowner = table_relation.relowner)
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    JOIN LATERAL (
      SELECT CASE procedure.proname
        WHEN 'protect_inspection_runtime' THEN 'inspections'
        WHEN 'protect_inspection_result' THEN 'inspection_results'
        WHEN 'protect_meter_reading' THEN 'meter_readings'
        WHEN 'write_inspection_lifecycle_change' THEN 'inspection_changes'
        WHEN 'write_inspection_result_change' THEN 'inspection_changes'
      END AS table_name
    ) mapping ON true
    JOIN pg_class table_relation ON table_relation.relname = mapping.table_name
    JOIN pg_namespace table_namespace
      ON table_namespace.oid = table_relation.relnamespace
     AND table_namespace.nspname = 'public'
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'protect_inspection_runtime',
        'protect_inspection_result',
        'protect_meter_reading',
        'write_inspection_lifecycle_change',
        'write_inspection_result_change'
      ])
  ), false),
  'runtime trigger functions share their protected or written table owner'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 5
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
        'protect_inspection_runtime',
        'protect_inspection_result',
        'protect_meter_reading',
        'write_inspection_lifecycle_change',
        'write_inspection_result_change'
      ])
  ), false),
  'PUBLIC, anon, and authenticated cannot execute runtime trigger functions'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 3
      AND bool_and(
        position('FOR SHARE' in upper(pg_get_functiondef(procedure.oid))) > 0
      )
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname IN (
        'protect_inspection_runtime',
        'protect_inspection_result',
        'protect_meter_reading'
      )
  ), false),
  'runtime invariant guards take conflicting parent or ancestry locks'
);

WITH expected(trigger_name, table_name, trigger_type) AS (
  VALUES
    ('inspections_protect_runtime'::name, 'inspections'::name, 23::smallint),
    (
      'inspections_write_lifecycle_change',
      'inspections',
      17::smallint
    ),
    (
      'inspection_results_protect_runtime',
      'inspection_results',
      31::smallint
    ),
    (
      'inspection_results_write_change',
      'inspection_results',
      29::smallint
    ),
    ('meter_readings_protect_runtime', 'meter_readings', 31::smallint)
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
      'inspections',
      'inspection_results',
      'inspection_changes',
      'meter_readings'
    ])
    AND NOT trigger_state.tgisinternal
    AND trigger_state.tgenabled = 'O'
    AND trigger_state.tgname NOT LIKE '%\_audit\_%' ESCAPE '\'
)
SELECT ok(
  NOT EXISTS (
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ),
  'exactly five enabled row-level runtime and history triggers exist (Task 13''s audit trigger is separate)'
);

SELECT ok(
  to_regclass('public.inspection_media') IS NULL
    AND to_regclass('public.inspection_reports') IS NULL
    AND to_regclass('public.reports') IS NULL
    AND to_regclass('public.maintenance_jobs') IS NULL
    AND to_regclass('public.issues') IS NULL
    AND to_regclass('public.quotes') IS NULL
    AND to_regclass('public.approvals') IS NULL,
  'Task 9 adds no Task 10 media/report or later operational tables'
);

SELECT (
  to_regclass('public.inspections') IS NOT NULL
    AND to_regclass('public.inspection_results') IS NOT NULL
    AND to_regclass('public.inspection_changes') IS NOT NULL
    AND to_regclass('public.meter_readings') IS NOT NULL
    AND to_regprocedure('security.protect_inspection_runtime()') IS NOT NULL
    AND to_regprocedure('security.protect_inspection_result()') IS NOT NULL
    AND to_regprocedure('security.protect_meter_reading()') IS NOT NULL
    AND to_regprocedure(
      'security.write_inspection_lifecycle_change()'
    ) IS NOT NULL
    AND to_regprocedure(
      'security.write_inspection_result_change()'
    ) IS NOT NULL
)::integer AS inspection_runtime_ready
\gset

\if :inspection_runtime_ready

INSERT INTO auth.users (id)
VALUES
  ('81000000-0000-0000-0000-000000000001'),
  ('81000000-0000-0000-0000-000000000002'),
  ('81000000-0000-0000-0000-000000000003'),
  ('81000000-0000-0000-0000-000000000004'),
  ('81000000-0000-0000-0000-000000000005'),
  ('81000000-0000-0000-0000-000000000006'),
  ('81000000-0000-0000-0000-000000000007'),
  ('81000000-0000-0000-0000-000000000008'),
  ('81000000-0000-0000-0000-000000000009'),
  ('81000000-0000-0000-0000-000000000010');

INSERT INTO public.profiles (id)
VALUES
  ('81000000-0000-0000-0000-000000000001'),
  ('81000000-0000-0000-0000-000000000002'),
  ('81000000-0000-0000-0000-000000000003'),
  ('81000000-0000-0000-0000-000000000004'),
  ('81000000-0000-0000-0000-000000000005'),
  ('81000000-0000-0000-0000-000000000006'),
  ('81000000-0000-0000-0000-000000000007'),
  ('81000000-0000-0000-0000-000000000008'),
  ('81000000-0000-0000-0000-000000000009'),
  ('81000000-0000-0000-0000-000000000010');

INSERT INTO public.companies (id, name)
VALUES
  ('82000000-0000-0000-0000-000000000001', 'Runtime Company A'),
  ('82000000-0000-0000-0000-000000000002', 'Runtime Company B');

INSERT INTO public.company_memberships (
  company_id,
  profile_id,
  role,
  is_active
)
VALUES
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'ADMIN', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002', 'MANAGER', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000003', 'INSPECTOR', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000004', 'INSPECTOR', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000005', 'COORDINATOR', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000006', 'READ_ONLY', true),
  ('82000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000007', 'ADMIN', true),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000010', 'ADMIN', false);

INSERT INTO public.properties (id, name)
VALUES
  ('83000000-0000-0000-0000-000000000001', 'A1 full management'),
  ('83000000-0000-0000-0000-000000000002', 'A2 inspection service'),
  ('83000000-0000-0000-0000-000000000003', 'A inactive'),
  ('83000000-0000-0000-0000-000000000004', 'A maintenance only'),
  ('83000000-0000-0000-0000-000000000005', 'A coordination only'),
  ('83000000-0000-0000-0000-000000000006', 'B1 full management');

INSERT INTO public.property_company_relationships (
  id,
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES
  ('83100000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT'),
  ('83100000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'INSPECTION_SERVICE'),
  ('83100000-0000-0000-0000-000000000003', '83000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', 'SERVICE', 'INACTIVE', 'INSPECTION_SERVICE'),
  ('83100000-0000-0000-0000-000000000004', '83000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'MAINTENANCE_SERVICE'),
  ('83100000-0000-0000-0000-000000000005', '83000000-0000-0000-0000-000000000005', '82000000-0000-0000-0000-000000000001', 'SERVICE', 'ACTIVE', 'COORDINATION_SERVICE'),
  ('83100000-0000-0000-0000-000000000006', '83000000-0000-0000-0000-000000000006', '82000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT');

INSERT INTO public.property_staff_assignments (
  company_id,
  property_id,
  profile_id
)
VALUES
  ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000003'),
  ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000004');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES (
  '83000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000008'
);

INSERT INTO public.inspection_templates (id, company_id, name)
VALUES
  ('84000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', 'A frozen one'),
  ('84000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', 'A frozen two'),
  ('84000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', 'A unfrozen'),
  ('84000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000002', 'B frozen');

INSERT INTO public.inspection_template_versions (
  id,
  template_id,
  version_number,
  is_current,
  frozen_at
)
VALUES
  ('85000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', 1, false, NULL),
  ('85000000-0000-0000-0000-000000000002', '84000000-0000-0000-0000-000000000002', 1, false, NULL),
  ('85000000-0000-0000-0000-000000000003', '84000000-0000-0000-0000-000000000003', 1, true, NULL),
  ('85000000-0000-0000-0000-000000000004', '84000000-0000-0000-0000-000000000004', 1, false, NULL);

INSERT INTO public.inspection_template_sections (id, version_id, title, sort_order)
VALUES
  ('86000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'A one', 1),
  ('86000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000002', 'A two', 1),
  ('86000000-0000-0000-0000-000000000003', '85000000-0000-0000-0000-000000000003', 'A unfrozen', 1),
  ('86000000-0000-0000-0000-000000000004', '85000000-0000-0000-0000-000000000004', 'B one', 1);

INSERT INTO public.inspection_template_items (
  id,
  section_id,
  label,
  sort_order
)
VALUES
  ('87000000-0000-0000-0000-000000000001', '86000000-0000-0000-0000-000000000001', 'A item one', 1),
  ('87000000-0000-0000-0000-000000000002', '86000000-0000-0000-0000-000000000001', 'A item two', 2),
  ('87000000-0000-0000-0000-000000000003', '86000000-0000-0000-0000-000000000002', 'A second-version item', 1),
  ('87000000-0000-0000-0000-000000000004', '86000000-0000-0000-0000-000000000003', 'A unfrozen item', 1),
  ('87000000-0000-0000-0000-000000000005', '86000000-0000-0000-0000-000000000004', 'B item', 1);

UPDATE public.inspection_template_versions
SET frozen_at = '2026-08-01 10:00:00+00'
WHERE id IN (
  '85000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000002',
  '85000000-0000-0000-0000-000000000004'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id, created_by, scheduled_at, started_at, completed_at, updated_at) VALUES ('88000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000007', '2026-08-20 09:00:00+00', '2000-01-01 00:00:00+00', '2000-01-02 00:00:00+00', '2000-01-03 00:00:00+00')$$,
  'Company A ADMIN creates an A1 full-management inspection'
);

SELECT lives_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id, created_by) VALUES ('88000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000007')$$,
  'Company A ADMIN creates an A2 inspection-service inspection'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspections
    WHERE id = '88000000-0000-0000-0000-000000000001'
      AND created_by = '81000000-0000-0000-0000-000000000001'
      AND status = 'SCHEDULED'
      AND started_at IS NULL
      AND completed_at IS NULL
      AND updated_at <> '2000-01-03 00:00:00+00'
  ),
  'inspection creation overwrites actor spoofing and normalizes lifecycle timestamps'
);

SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000011', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000003', '85000000-0000-0000-0000-000000000001')$$,
  '55000', NULL,
  'inactive property relationship is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000012', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000004', '85000000-0000-0000-0000-000000000001')$$,
  '55000', NULL,
  'maintenance-only property relationship is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000013', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000005', '85000000-0000-0000-0000-000000000001')$$,
  '55000', NULL,
  'coordination-only property relationship is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000014', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000003')$$,
  '55000', NULL,
  'unfrozen template version is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000015', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000004')$$,
  '55000', NULL,
  'Company B template version cannot be combined with Company A'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000016', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000006', '85000000-0000-0000-0000-000000000001')$$,
  '55000', NULL,
  'Company B property cannot be combined with Company A'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000017', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000004')$$,
  '55000', NULL,
  'hostile mixed company/property/template UUIDs fail closed'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id, status) VALUES ('88000000-0000-0000-0000-000000000018', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'IN_PROGRESS')$$,
  '55000', NULL,
  'inspection insertion must begin as SCHEDULED'
);

SELECT throws_ok(
  $$UPDATE public.inspections SET status = 'COMPLETED' WHERE id = '88000000-0000-0000-0000-000000000002'$$,
  '55000', NULL,
  'SCHEDULED cannot jump directly to COMPLETED'
);

SELECT lives_ok(
  $$UPDATE public.inspections SET template_version_id = '85000000-0000-0000-0000-000000000002' WHERE id = '88000000-0000-0000-0000-000000000002'$$,
  'an evidence-free scheduled inspection may select another valid frozen version'
);

SELECT lives_ok(
  $$UPDATE public.inspections SET template_version_id = '85000000-0000-0000-0000-000000000001' WHERE id = '88000000-0000-0000-0000-000000000002'$$,
  'scheduled template selection may move back before evidence exists'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001')$$,
  'Company A MANAGER creates an inspection'
);
SELECT lives_ok(
  $$UPDATE public.inspections SET scheduled_at = '2026-08-21 10:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000003'$$,
  'Company A MANAGER updates a scheduled inspection'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000003';

SELECT is(
  (SELECT count(*) FROM public.inspections),
  2::bigint,
  'assigned Inspector A sees A1 inspections only'
);
SELECT is(
  (
    SELECT count(*)
    FROM public.inspections
    WHERE id = '88000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'assigned Inspector A cannot select unassigned A2'
);

SELECT lives_ok(
  $$UPDATE public.inspections SET status = 'IN_PROGRESS', started_at = '2000-01-01 00:00:00+00', completed_at = '2000-01-02 00:00:00+00', updated_at = '2000-01-03 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  'assigned Inspector A starts the A1 inspection'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspections
    WHERE id = '88000000-0000-0000-0000-000000000001'
      AND status = 'IN_PROGRESS'
      AND started_at IS NOT NULL
      AND started_at <> '2000-01-01 00:00:00+00'
      AND completed_at IS NULL
      AND updated_at <> '2000-01-03 00:00:00+00'
  ),
  'SCHEDULED to IN_PROGRESS sets trusted timestamps'
);

CREATE TEMPORARY TABLE task9_started_timestamp AS
SELECT started_at
FROM public.inspections
WHERE id = '88000000-0000-0000-0000-000000000001';

SELECT lives_ok(
  $$UPDATE public.inspections SET scheduled_at = '2026-08-22 11:00:00+00', started_at = '2000-01-01 00:00:00+00', completed_at = '2000-01-02 00:00:00+00', updated_at = '2000-01-03 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  'same-status update remains valid before completion'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspections inspection_state
    CROSS JOIN task9_started_timestamp started_state
    WHERE inspection_state.id = '88000000-0000-0000-0000-000000000001'
      AND inspection_state.started_at = started_state.started_at
      AND inspection_state.completed_at IS NULL
      AND inspection_state.updated_at <> '2000-01-03 00:00:00+00'
  ),
  'same-status update preserves lifecycle timestamps and replaces spoofed updated_at'
);

SELECT lives_ok(
  $$INSERT INTO public.inspection_results (id, company_id, property_id, inspection_id, template_item_id, severity, operational_action, comment) VALUES ('89000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000001', 'PASS', 'MONITOR', 'Initial pass')$$,
  'assigned Inspector stores PASS independently from MONITOR'
);

SELECT lives_ok(
  $$UPDATE public.inspection_results SET severity = 'ATTENTION', operational_action = 'INCLUDED_IN_SERVICE', comment = 'Watch closely', updated_at = '2000-01-01 00:00:00+00' WHERE id = '89000000-0000-0000-0000-000000000001'$$,
  'assigned Inspector updates the result to ATTENTION independently'
);

SELECT lives_ok(
  $$INSERT INTO public.inspection_results (id, company_id, property_id, inspection_id, template_item_id, severity, operational_action, comment) VALUES ('89000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'URGENT', 'OWNER_APPROVAL_REQUIRED', 'Escalate')$$,
  'assigned Inspector stores URGENT with OWNER_APPROVAL_REQUIRED'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspection_results
    WHERE id = '89000000-0000-0000-0000-000000000001'
      AND severity = 'ATTENTION'
      AND operational_action = 'INCLUDED_IN_SERVICE'
      AND updated_at <> '2000-01-01 00:00:00+00'
  )
    AND EXISTS (
      SELECT 1
      FROM public.inspection_results
      WHERE id = '89000000-0000-0000-0000-000000000002'
        AND severity = 'URGENT'
        AND operational_action = 'OWNER_APPROVAL_REQUIRED'
    ),
  'severity and operational action remain independently persisted'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'PASS', 'MONITOR')$$,
  '23505', NULL,
  'duplicate result for one inspection item is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000003', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'item from another frozen version is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000005', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'Company B template item is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'wrong result company is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'wrong result property is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'INVALID', 'MONITOR')$$,
  '22P02', NULL,
  'invalid severity label is denied'
);

SELECT lives_ok(
  $$INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit, recorded_by) VALUES ('8a000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'ELECTRICITY', 123.45, 'kWh', '81000000-0000-0000-0000-000000000007')$$,
  'assigned Inspector stores a decimal electricity reading'
);
SELECT lives_ok(
  $$INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('8a000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', -5.25, 'm3')$$,
  'assigned Inspector stores a negative decimal water reading without invented range rules'
);
SELECT lives_ok(
  $$INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('8a000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'ELECTRICITY', 124.75, 'kWh')$$,
  'multiple readings of the same meter type are allowed'
);

SELECT ok(
  (
    SELECT count(*)
    FROM public.meter_readings
    WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
      AND meter_type = 'ELECTRICITY'
  ) = 2
    AND (
      SELECT recorded_by
      FROM public.meter_readings
      WHERE id = '8a000000-0000-0000-0000-000000000001'
    ) = '81000000-0000-0000-0000-000000000003',
  'same-type meter rows persist and actor spoofing stores only the current profile'
);

SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', 'NaN'::numeric, 'm3')$$,
  '23514', NULL,
  'NaN meter reading is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', 'Infinity'::numeric, 'm3')$$,
  '23514', NULL,
  'positive infinity meter reading is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', '-Infinity'::numeric, 'm3')$$,
  '23514', NULL,
  'negative infinity meter reading is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', 1, 'm3')$$,
  '55000', NULL,
  'wrong meter company is denied'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', '88000000-0000-0000-0000-000000000001', 'WATER', 1, 'm3')$$,
  '55000', NULL,
  'wrong meter property is denied'
);

SELECT throws_ok(
  $$UPDATE public.inspections SET template_version_id = '85000000-0000-0000-0000-000000000002' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'template version cannot change after runtime evidence exists'
);
SELECT throws_ok(
  $$UPDATE public.inspections SET created_by = '81000000-0000-0000-0000-000000000002' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'inspection creator identity is immutable after insert'
);
SELECT throws_ok(
  $$UPDATE public.inspection_results SET template_item_id = '87000000-0000-0000-0000-000000000002' WHERE id = '89000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'inspection result identity is immutable after insert'
);
SELECT throws_ok(
  $$UPDATE public.meter_readings SET recorded_by = '81000000-0000-0000-0000-000000000001' WHERE id = '8a000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'meter actor identity is immutable after insert'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_changes
    WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
      AND change_type = 'STARTED'
      AND changed_by = '81000000-0000-0000-0000-000000000003'
      AND company_id = '82000000-0000-0000-0000-000000000001'
      AND property_id = '83000000-0000-0000-0000-000000000001'
      AND old_value ->> 'status' = 'SCHEDULED'
      AND new_value ->> 'status' = 'IN_PROGRESS'
  ),
  1::bigint,
  'STARTED history stores trusted actor, tenant identity, and snapshots'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_changes
    WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
      AND change_type = 'RESULT_CHANGED'
      AND changed_by = '81000000-0000-0000-0000-000000000003'
  ),
  3::bigint,
  'result insert and update events create minimal history rows'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspection_changes
    WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
      AND change_type = 'RESULT_CHANGED'
      AND old_value IS NULL
      AND new_value ->> 'severity' = 'PASS'
  )
    AND EXISTS (
      SELECT 1
      FROM public.inspection_changes
      WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
        AND change_type = 'RESULT_CHANGED'
        AND old_value ->> 'severity' = 'PASS'
        AND new_value ->> 'severity' = 'ATTENTION'
    ),
  'result history snapshots distinguish inserts and updates'
);

SELECT lives_ok(
  $$UPDATE public.inspections SET status = 'COMPLETED', completed_at = '2000-01-02 00:00:00+00', updated_at = '2000-01-03 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  'assigned Inspector completes the assigned A1 inspection'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspections inspection_state
    CROSS JOIN task9_started_timestamp started_state
    WHERE inspection_state.id = '88000000-0000-0000-0000-000000000001'
      AND inspection_state.status = 'COMPLETED'
      AND inspection_state.started_at = started_state.started_at
      AND inspection_state.completed_at IS NOT NULL
      AND inspection_state.completed_at <> '2000-01-02 00:00:00+00'
      AND inspection_state.updated_at <> '2000-01-03 00:00:00+00'
  ),
  'IN_PROGRESS to COMPLETED preserves start and sets trusted completion timestamps'
);

SELECT is(
  (
    SELECT count(*)
    FROM public.inspection_changes
    WHERE inspection_id = '88000000-0000-0000-0000-000000000001'
      AND change_type = 'COMPLETED'
      AND changed_by = '81000000-0000-0000-0000-000000000003'
      AND old_value ->> 'status' = 'IN_PROGRESS'
      AND new_value ->> 'status' = 'COMPLETED'
  ),
  1::bigint,
  'COMPLETED history stores actor and lifecycle snapshots'
);

CREATE TEMPORARY TABLE task9_completed_snapshot AS
SELECT
  (SELECT to_jsonb(row_state) FROM public.inspections row_state WHERE id = '88000000-0000-0000-0000-000000000001') AS inspection_state,
  (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.inspection_results row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001') AS result_state,
  (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.meter_readings row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001') AS meter_state,
  (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.inspection_changes row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001') AS change_state;

SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'completed inspection rejects result INSERT'
);
SELECT throws_ok(
  $$UPDATE public.inspection_results SET comment = 'forbidden' WHERE id = '89000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects result UPDATE'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_results WHERE id = '89000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects result DELETE'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'WATER', 10, 'm3')$$,
  '55000', NULL,
  'completed inspection rejects meter INSERT'
);
SELECT throws_ok(
  $$UPDATE public.meter_readings SET reading_value = 999 WHERE id = '8a000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects meter UPDATE'
);
SELECT throws_ok(
  $$DELETE FROM public.meter_readings WHERE id = '8a000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects meter DELETE'
);
SELECT throws_ok(
  $$UPDATE public.inspections SET template_version_id = '85000000-0000-0000-0000-000000000002' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects template change'
);
SELECT throws_ok(
  $$UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects lifecycle rollback'
);
SELECT throws_ok(
  $$UPDATE public.inspections SET scheduled_at = '2027-01-01 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000001'$$,
  '55000', NULL,
  'completed inspection rejects every other inspection update'
);

SELECT ok(
  (SELECT inspection_state FROM task9_completed_snapshot) =
    (SELECT to_jsonb(row_state) FROM public.inspections row_state WHERE id = '88000000-0000-0000-0000-000000000001')
    AND (SELECT result_state FROM task9_completed_snapshot) =
      (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.inspection_results row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001')
    AND (SELECT meter_state FROM task9_completed_snapshot) =
      (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.meter_readings row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001')
    AND (SELECT change_state FROM task9_completed_snapshot) =
      (SELECT jsonb_agg(to_jsonb(row_state) ORDER BY id) FROM public.inspection_changes row_state WHERE inspection_id = '88000000-0000-0000-0000-000000000001'),
  'all post-completion hostility leaves inspection, evidence, and history byte-identical'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000004';

SELECT is(
  (
    SELECT count(*)
    FROM public.inspections
    WHERE id = '88000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'Inspector assigned only to A2 cannot select A1'
);
SELECT results_eq(
  $$UPDATE public.inspections SET scheduled_at = '2026-09-01 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000001' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Inspector assigned only to A2 cannot update A1'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002', 'PASS', 'MONITOR')$$,
  '55000', NULL,
  'Inspector assigned only to A2 cannot add A1 result evidence'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = '88000000-0000-0000-0000-000000000002'$$,
  'ADMIN starts the A2 inspection for assignment tests'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000003';
SELECT is(
  (
    SELECT count(*)
    FROM public.inspections
    WHERE id = '88000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'Inspector A1 cannot select unassigned A2 after it starts'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', '88000000-0000-0000-0000-000000000002', 'WATER', 1, 'm3')$$,
  '42501', NULL,
  'Inspector A1 cannot add meter evidence to unassigned A2'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = '88000000-0000-0000-0000-000000000003'$$,
  'MANAGER starts its own A1 inspection'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_results (id, company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('89000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', '87000000-0000-0000-0000-000000000001', 'PASS', 'MONITOR')$$,
  'MANAGER inserts a result'
);
SELECT lives_ok(
  $$UPDATE public.inspection_results SET comment = 'manager update' WHERE id = '89000000-0000-0000-0000-000000000003'$$,
  'MANAGER updates a result'
);
SELECT lives_ok(
  $$DELETE FROM public.inspection_results WHERE id = '89000000-0000-0000-0000-000000000003'$$,
  'MANAGER deletes a result before completion'
);
SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.inspection_changes
    WHERE inspection_id = '88000000-0000-0000-0000-000000000003'
      AND change_type = 'RESULT_CHANGED'
      AND old_value IS NOT NULL
      AND new_value IS NULL
  ),
  'result DELETE history stores old-only snapshot'
);

SELECT lives_ok(
  $$INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('8a000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', 'WATER', 11.1, 'm3')$$,
  'MANAGER inserts a meter reading'
);
SELECT lives_ok(
  $$UPDATE public.meter_readings SET reading_value = 12.2 WHERE id = '8a000000-0000-0000-0000-000000000004'$$,
  'MANAGER updates a meter reading'
);
SELECT lives_ok(
  $$DELETE FROM public.meter_readings WHERE id = '8a000000-0000-0000-0000-000000000004'$$,
  'MANAGER deletes a meter reading before completion'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000007';

SELECT lives_ok(
  $$INSERT INTO public.inspections (id, company_id, property_id, template_version_id) VALUES ('88000000-0000-0000-0000-000000000201', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '85000000-0000-0000-0000-000000000004')$$,
  'Company B ADMIN creates its inspection'
);
SELECT lives_ok(
  $$UPDATE public.inspections SET status = 'IN_PROGRESS' WHERE id = '88000000-0000-0000-0000-000000000201'$$,
  'Company B ADMIN starts its inspection'
);
SELECT lives_ok(
  $$INSERT INTO public.inspection_results (id, company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('89000000-0000-0000-0000-000000000201', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '88000000-0000-0000-0000-000000000201', '87000000-0000-0000-0000-000000000005', 'PASS', 'MONITOR')$$,
  'Company B ADMIN stores its result'
);
SELECT lives_ok(
  $$INSERT INTO public.meter_readings (id, company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('8a000000-0000-0000-0000-000000000201', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '88000000-0000-0000-0000-000000000201', 'ELECTRICITY', 88.8, 'kWh')$$,
  'Company B ADMIN stores its meter reading'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000001';

SELECT ok(
  (SELECT count(*) FROM public.inspections WHERE id = '88000000-0000-0000-0000-000000000201') = 0
    AND (SELECT count(*) FROM public.inspection_results WHERE id = '89000000-0000-0000-0000-000000000201') = 0
    AND (SELECT count(*) FROM public.meter_readings WHERE id = '8a000000-0000-0000-0000-000000000201') = 0
    AND (SELECT count(*) FROM public.inspection_changes WHERE inspection_id = '88000000-0000-0000-0000-000000000201') = 0,
  'Company A direct hostile UUID SELECTs reveal no Company B runtime rows'
);

SELECT results_eq(
  $$UPDATE public.inspections SET scheduled_at = '2030-01-01 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000201' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot update Company B inspection by hostile UUID'
);
SELECT results_eq(
  $$UPDATE public.inspection_results SET comment = 'hostile' WHERE id = '89000000-0000-0000-0000-000000000201' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot update Company B result by hostile UUID'
);
SELECT results_eq(
  $$DELETE FROM public.inspection_results WHERE id = '89000000-0000-0000-0000-000000000201' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot delete Company B result by hostile UUID'
);
SELECT results_eq(
  $$UPDATE public.meter_readings SET reading_value = 1 WHERE id = '8a000000-0000-0000-0000-000000000201' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot update Company B meter by hostile UUID'
);
SELECT results_eq(
  $$DELETE FROM public.meter_readings WHERE id = '8a000000-0000-0000-0000-000000000201' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'Company A cannot delete Company B meter by hostile UUID'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (company_id, property_id, template_version_id) VALUES ('82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '85000000-0000-0000-0000-000000000004')$$,
  '42501', NULL,
  'Company A cannot insert a valid Company B inspection'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '88000000-0000-0000-0000-000000000201', '87000000-0000-0000-0000-000000000005', 'PASS', 'MONITOR')$$,
  '42501', NULL,
  'Company A cannot insert a valid Company B result'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '88000000-0000-0000-0000-000000000201', 'WATER', 99, 'm3')$$,
  '42501', NULL,
  'Company A cannot insert a valid Company B meter reading'
);

SELECT throws_ok(
  $$INSERT INTO public.inspection_changes (inspection_id, company_id, property_id, changed_by, change_type) VALUES ('88000000-0000-0000-0000-000000000201', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000006', '81000000-0000-0000-0000-000000000001', 'STARTED')$$,
  '42501', NULL,
  'Company A cannot insert hostile Company B internal history'
);
SELECT throws_ok(
  $$UPDATE public.inspection_changes SET change_type = 'COMPLETED' WHERE inspection_id = '88000000-0000-0000-0000-000000000201'$$,
  '42501', NULL,
  'Company A cannot update Company B internal history'
);
SELECT throws_ok(
  $$DELETE FROM public.inspection_changes WHERE inspection_id = '88000000-0000-0000-0000-000000000201'$$,
  '42501', NULL,
  'Company A cannot delete Company B internal history'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000005';

SELECT ok(
  (SELECT count(*) FROM public.inspections) >= 3
    AND (SELECT count(*) FROM public.inspection_results) >= 2
    AND (SELECT count(*) FROM public.meter_readings) >= 3
    AND (SELECT count(*) FROM public.inspection_changes) >= 1,
  'COORDINATOR has read-only access to all in-scope Company A runtime tables'
);
SELECT results_eq(
  $$UPDATE public.inspections SET scheduled_at = '2031-01-01 00:00:00+00' WHERE id = '88000000-0000-0000-0000-000000000003' RETURNING id$$,
  $$SELECT NULL::uuid WHERE false$$,
  'COORDINATOR cannot update inspections'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', 'WATER', 1, 'm3')$$,
  '42501', NULL,
  'COORDINATOR cannot insert evidence'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000006';
SELECT ok(
  (SELECT count(*) FROM public.inspections) >= 3
    AND (SELECT count(*) FROM public.inspection_results) >= 2
    AND (SELECT count(*) FROM public.meter_readings) >= 3
    AND (SELECT count(*) FROM public.inspection_changes) >= 1,
  'READ_ONLY has read-only access to all in-scope Company A runtime tables'
);
SELECT throws_ok(
  $$INSERT INTO public.inspection_results (company_id, property_id, inspection_id, template_item_id, severity, operational_action) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', '87000000-0000-0000-0000-000000000001', 'PASS', 'MONITOR')$$,
  '42501', NULL,
  'READ_ONLY cannot insert results'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000008';
SELECT ok(
  (SELECT count(*) FROM public.inspections) = 0
    AND (SELECT count(*) FROM public.inspection_results) = 0
    AND (SELECT count(*) FROM public.inspection_changes) = 0
    AND (SELECT count(*) FROM public.meter_readings) = 0,
  'global property owner receives no Task 9 access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000009';
SELECT ok(
  (SELECT count(*) FROM public.inspections) = 0
    AND (SELECT count(*) FROM public.inspection_results) = 0
    AND (SELECT count(*) FROM public.inspection_changes) = 0
    AND (SELECT count(*) FROM public.meter_readings) = 0,
  'unrelated authenticated profile receives no Task 9 access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000010';
SELECT ok(
  (SELECT count(*) FROM public.inspections) = 0
    AND (SELECT count(*) FROM public.inspection_results) = 0
    AND (SELECT count(*) FROM public.inspection_changes) = 0
    AND (SELECT count(*) FROM public.meter_readings) = 0,
  'inactive company membership receives no Task 9 access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '';
SELECT ok(
  (SELECT count(*) FROM public.inspections) = 0
    AND (SELECT count(*) FROM public.inspection_results) = 0
    AND (SELECT count(*) FROM public.inspection_changes) = 0
    AND (SELECT count(*) FROM public.meter_readings) = 0,
  'authenticated role without JWT subject receives no Task 9 access'
);
SELECT throws_ok(
  $$INSERT INTO public.inspections (company_id, property_id, template_version_id) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001')$$,
  '42501', NULL,
  'inspection creation fails closed without a current profile'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', 'WATER', 1, 'm3')$$,
  '42501', NULL,
  'meter creation fails closed without a current profile'
);

RESET ROLE;
SELECT throws_ok(
  $$INSERT INTO public.inspections (company_id, property_id, template_version_id) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001')$$,
  '42501', NULL,
  'hard inspection actor trigger fails closed without a current profile even outside RLS'
);
SELECT throws_ok(
  $$INSERT INTO public.meter_readings (company_id, property_id, inspection_id, meter_type, reading_value, unit) VALUES ('82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000003', 'WATER', 1, 'm3')$$,
  '42501', NULL,
  'hard meter actor trigger fails closed without a current profile even outside RLS'
);

SET LOCAL ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.inspections$$,
  '42501', NULL,
  'anon cannot select inspections'
);
SELECT throws_ok(
  $$SELECT * FROM public.inspection_results$$,
  '42501', NULL,
  'anon cannot select results'
);
SELECT throws_ok(
  $$SELECT * FROM public.inspection_changes$$,
  '42501', NULL,
  'anon cannot select changes'
);
SELECT throws_ok(
  $$SELECT * FROM public.meter_readings$$,
  '42501', NULL,
  'anon cannot select meter readings'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '81000000-0000-0000-0000-000000000001';
SELECT ok(
  security.has_company_role(
    '82000000-0000-0000-0000-000000000001',
    ARRAY['ADMIN']::public.company_role[]
  )
    AND security.company_has_property_scope(
      '82000000-0000-0000-0000-000000000001',
      '83000000-0000-0000-0000-000000000001',
      ARRAY['FULL_MANAGEMENT']::public.property_company_relationship_scope[]
    )
    AND NOT security.company_has_property_scope(
      '82000000-0000-0000-0000-000000000001',
      '83000000-0000-0000-0000-000000000004',
      ARRAY['FULL_MANAGEMENT', 'INSPECTION_SERVICE']::public.property_company_relationship_scope[]
    ),
  'existing authorization helpers remain recursion-free and tenant-exact'
);

RESET ROLE;

\else

SELECT * FROM skip(
  1,
  'runtime behavior requires the four Task 9 tables and five trigger functions'
);

\endif

SELECT * FROM finish();

ROLLBACK;
