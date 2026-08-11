BEGIN;

SET LOCAL search_path = extensions, public;

SELECT no_plan();

SELECT has_table('public', 'properties', 'properties exists in public');
SELECT has_table('public', 'property_owners', 'property_owners exists in public');
SELECT has_table(
  'public',
  'property_company_relationships',
  'property_company_relationships exists in public'
);
SELECT has_table(
  'public',
  'company_property_settings',
  'company_property_settings exists in public'
);
SELECT has_table(
  'public',
  'property_staff_assignments',
  'property_staff_assignments exists in public'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'id',
      'name',
      'address_line_1',
      'address_line_2',
      'locality',
      'postcode',
      'country',
      'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.properties')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'properties has exactly the approved columns'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'property_id', 'profile_id', 'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.property_owners')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'property_owners has exactly the approved columns'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'id',
      'property_id',
      'company_id',
      'relationship_type',
      'status',
      'scope',
      'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.property_company_relationships')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'property_company_relationships has exactly the approved columns'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'company_id', 'property_id', 'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.company_property_settings')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'company_property_settings has exactly the approved columns'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(attname ORDER BY attnum) = ARRAY[
      'company_id', 'property_id', 'profile_id', 'is_active', 'created_at'
    ]::name[]
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.property_staff_assignments')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'property_staff_assignments has exactly the approved columns'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(pg_get_expr(default_value.adbin, default_value.adrelid), '<none>')
      )
      ORDER BY attribute.attnum
    ) = '[
      ["id", "uuid", true, "gen_random_uuid()"],
      ["name", "text", true, "<none>"],
      ["address_line_1", "text", false, "<none>"],
      ["address_line_2", "text", false, "<none>"],
      ["locality", "text", false, "<none>"],
      ["postcode", "text", false, "<none>"],
      ["country", "text", false, "<none>"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute attribute
    LEFT JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.properties')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'properties column types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(pg_get_expr(default_value.adbin, default_value.adrelid), '<none>')
      )
      ORDER BY attribute.attnum
    ) = '[
      ["property_id", "uuid", true, "<none>"],
      ["profile_id", "uuid", true, "<none>"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute attribute
    LEFT JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.property_owners')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'property_owners column types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(pg_get_expr(default_value.adbin, default_value.adrelid), '<none>')
      )
      ORDER BY attribute.attnum
    ) = '[
      ["id", "uuid", true, "gen_random_uuid()"],
      ["property_id", "uuid", true, "<none>"],
      ["company_id", "uuid", true, "<none>"],
      ["relationship_type", "property_company_relationship_type", true, "<none>"],
      ["status", "property_company_relationship_status", true, "<none>"],
      ["scope", "property_company_relationship_scope", true, "<none>"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute attribute
    LEFT JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.property_company_relationships')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'property company relationship types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(pg_get_expr(default_value.adbin, default_value.adrelid), '<none>')
      )
      ORDER BY attribute.attnum
    ) = '[
      ["company_id", "uuid", true, "<none>"],
      ["property_id", "uuid", true, "<none>"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute attribute
    LEFT JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.company_property_settings')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'company property settings types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_array(
        attribute.attname,
        format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        COALESCE(pg_get_expr(default_value.adbin, default_value.adrelid), '<none>')
      )
      ORDER BY attribute.attnum
    ) = '[
      ["company_id", "uuid", true, "<none>"],
      ["property_id", "uuid", true, "<none>"],
      ["profile_id", "uuid", true, "<none>"],
      ["is_active", "boolean", true, "true"],
      ["created_at", "timestamp with time zone", true, "now()"]
    ]'::jsonb
    FROM pg_attribute attribute
    LEFT JOIN pg_attrdef default_value
      ON default_value.adrelid = attribute.attrelid
     AND default_value.adnum = attribute.attnum
    WHERE attribute.attrelid = to_regclass('public.property_staff_assignments')
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ), false),
  'property staff assignment types, nullability, and defaults are exact'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.properties') AND attname = 'id')
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.properties')
      AND contype = 'p'
  ), false),
  'properties primary key is id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_owners') AND attname = 'property_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_owners') AND attname = 'profile_id')
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_owners')
      AND contype = 'p'
  ), false),
  'property_owners primary key is property_id and profile_id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_company_relationships') AND attname = 'id')
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_company_relationships')
      AND contype = 'p'
  ), false),
  'property_company_relationships primary key is id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.company_property_settings') AND attname = 'company_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.company_property_settings') AND attname = 'property_id')
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_property_settings')
      AND contype = 'p'
  ), false),
  'company_property_settings primary key is company_id and property_id'
);

SELECT ok(
  COALESCE((
    SELECT conkey = ARRAY[
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'company_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'property_id'),
      (SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'profile_id')
    ]::smallint[]
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_staff_assignments')
      AND contype = 'p'
  ), false),
  'property_staff_assignments primary key is company, property, and profile'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_owners') AND attname = 'property_id')]::smallint[]
          AND confrelid = to_regclass('public.properties')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.properties') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_owners') AND attname = 'profile_id')]::smallint[]
          AND confrelid = to_regclass('public.profiles')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.profiles') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_owners')
      AND contype = 'f'
  ), false),
  'property_owners has exact cascading property and profile foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_company_relationships') AND attname = 'property_id')]::smallint[]
          AND confrelid = to_regclass('public.properties')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.properties') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_company_relationships') AND attname = 'company_id')]::smallint[]
          AND confrelid = to_regclass('public.companies')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.companies') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_company_relationships')
      AND contype = 'f'
  ), false),
  'property company relationships has exact cascading property and company foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 2
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.company_property_settings') AND attname = 'company_id')]::smallint[]
          AND confrelid = to_regclass('public.companies')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.companies') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.company_property_settings') AND attname = 'property_id')]::smallint[]
          AND confrelid = to_regclass('public.properties')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.properties') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.company_property_settings')
      AND contype = 'f'
  ), false),
  'company property settings has exact cascading company and property foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 3
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'company_id')]::smallint[]
          AND confrelid = to_regclass('public.companies')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.companies') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'property_id')]::smallint[]
          AND confrelid = to_regclass('public.properties')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.properties') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
      AND count(*) FILTER (
        WHERE conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.property_staff_assignments') AND attname = 'profile_id')]::smallint[]
          AND confrelid = to_regclass('public.profiles')
          AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = to_regclass('public.profiles') AND attname = 'id')]::smallint[]
          AND confdeltype = 'c'
      ) = 1
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_staff_assignments')
      AND contype = 'f'
  ), false),
  'property staff assignments has exact cascading company, property, and profile foreign keys'
);

SELECT ok(
  COALESCE((
    SELECT count(*) FILTER (
      WHERE attname = 'relationship_type'
        AND atttypid = 'public.property_company_relationship_type'::regtype
        AND attnotnull
    ) = 1
      AND count(*) FILTER (
        WHERE attname = 'status'
          AND atttypid = 'public.property_company_relationship_status'::regtype
          AND attnotnull
      ) = 1
      AND count(*) FILTER (
        WHERE attname = 'scope'
          AND atttypid = 'public.property_company_relationship_scope'::regtype
          AND attnotnull
      ) = 1
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.property_company_relationships')
      AND attnum > 0
      AND NOT attisdropped
  ), false),
  'relationship type, status, and scope use their required enums'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 1
      AND bool_and(pg_get_constraintdef(oid) LIKE 'CHECK (%')
    FROM pg_constraint
    WHERE conrelid = to_regclass('public.property_company_relationships')
      AND contype = 'c'
  ), false),
  'property company relationships has exactly one type and scope check'
);

SELECT ok(
  COALESCE((
    SELECT NOT index_state.indisunique
      AND index_state.indpred IS NULL
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['profile_id', 'property_id']
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_owners_profile_property_idx')
      AND index_state.indrelid = to_regclass('public.property_owners')
  ), false),
  'property owners has the profile and property authorization index'
);

SELECT ok(
  COALESCE((
    SELECT NOT index_state.indisunique
      AND index_state.indpred IS NULL
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['company_id', 'property_id', 'status']
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_company_relationships_company_property_status_idx')
      AND index_state.indrelid = to_regclass('public.property_company_relationships')
  ), false),
  'property company relationships has the company access index'
);

SELECT ok(
  COALESCE((
    SELECT NOT index_state.indisunique
      AND index_state.indpred IS NULL
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['property_id', 'status', 'relationship_type']
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_company_relationships_property_status_type_idx')
      AND index_state.indrelid = to_regclass('public.property_company_relationships')
  ), false),
  'property company relationships has the property relationship index'
);

SELECT ok(
  COALESCE((
    SELECT NOT index_state.indisunique
      AND index_state.indpred IS NULL
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['profile_id', 'company_id', 'property_id', 'is_active']
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_staff_assignments_profile_company_property_active_idx')
      AND index_state.indrelid = to_regclass('public.property_staff_assignments')
  ), false),
  'property staff assignments has the profile bounding index'
);

SELECT ok(
  COALESCE((
    SELECT index_state.indisunique
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['property_id']
      AND regexp_replace(
        pg_get_expr(index_state.indpred, index_state.indrelid),
        '\s+',
        ' ',
        'g'
      ) = '((relationship_type = ''PRIMARY''::property_company_relationship_type) AND (status = ''ACTIVE''::property_company_relationship_status))'
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_company_relationships_one_active_primary_idx')
      AND index_state.indrelid = to_regclass('public.property_company_relationships')
  ), false),
  'active primary uniqueness is a partial unique property index'
);

SELECT ok(
  COALESCE((
    SELECT index_state.indisunique
      AND ARRAY(
        SELECT pg_get_indexdef(index_state.indexrelid, key_number, true)
        FROM generate_series(1, index_state.indnkeyatts) AS key_number
        ORDER BY key_number
      ) = ARRAY['company_id', 'property_id', 'relationship_type', 'scope']
      AND regexp_replace(
        pg_get_expr(index_state.indpred, index_state.indrelid),
        '\s+',
        ' ',
        'g'
      ) = '(status = ''ACTIVE''::property_company_relationship_status)'
    FROM pg_index index_state
    WHERE index_state.indexrelid = to_regclass('public.property_company_relationships_no_duplicate_active_idx')
      AND index_state.indrelid = to_regclass('public.property_company_relationships')
  ), false),
  'active relationship duplicate prevention is an exact partial unique index'
);

SELECT ok(
  COALESCE((
    SELECT array_agg(index_relation.relname ORDER BY index_relation.relname) = ARRAY[
      'property_company_relationships_company_property_status_idx',
      'property_company_relationships_no_duplicate_active_idx',
      'property_company_relationships_one_active_primary_idx',
      'property_company_relationships_property_status_type_idx',
      'property_owners_profile_property_idx',
      'property_staff_assignments_profile_company_property_active_idx'
    ]::name[]
    FROM pg_index index_state
    JOIN pg_class index_relation ON index_relation.oid = index_state.indexrelid
    LEFT JOIN pg_constraint constraint_state ON constraint_state.conindid = index_state.indexrelid
    WHERE index_state.indrelid = ANY (ARRAY[
      to_regclass('public.properties'),
      to_regclass('public.property_owners'),
      to_regclass('public.property_company_relationships'),
      to_regclass('public.company_property_settings'),
      to_regclass('public.property_staff_assignments')
    ])
      AND constraint_state.oid IS NULL
  ), false),
  'Task 6 creates only the six approved non-constraint indexes'
);

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
  'all five Task 6 tables have ordinary row level security enabled'
);

SELECT ok(
  to_regclass('public.properties') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.properties')
        AND attname = ANY (ARRAY[
          'company_id',
          'primary_company_id',
          'owner_profile_id',
          'manager_id',
          'primary_owner_id',
          'inspection_status',
          'maintenance_status'
        ])
        AND NOT attisdropped
    )
    AND (
      SELECT array_agg(attname ORDER BY attnum) = ARRAY['id']::name[]
      FROM pg_attribute
      WHERE attrelid = to_regclass('public.profiles')
        AND attnum > 0
        AND NOT attisdropped
    ),
  'properties and profiles contain no company or owner shortcut columns'
);

SELECT has_function(
  'security',
  'is_property_owner',
  ARRAY['uuid']::name[],
  'is_property_owner accepts only a property UUID'
);

SELECT has_function(
  'security',
  'company_has_property_access',
  ARRAY['uuid', 'uuid']::name[],
  'company_has_property_access accepts company and property UUIDs'
);

SELECT has_function(
  'security',
  'company_has_property_scope',
  ARRAY[
    'uuid',
    'uuid',
    'public.property_company_relationship_scope[]'
  ]::name[],
  'company_has_property_scope accepts company, property, and exact scopes'
);

SELECT has_function(
  'security',
  'is_assigned_to_property',
  ARRAY['uuid', 'uuid']::name[],
  'is_assigned_to_property accepts only company and property UUIDs'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND count(*) FILTER (
        WHERE proname = 'is_property_owner'
          AND proargtypes = ARRAY['uuid'::regtype]::oidvector
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'company_has_property_access'
          AND proargtypes = ARRAY['uuid'::regtype, 'uuid'::regtype]::oidvector
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'company_has_property_scope'
          AND proargtypes = ARRAY[
            'uuid'::regtype,
            'uuid'::regtype,
            'public.property_company_relationship_scope[]'::regtype
          ]::oidvector
      ) = 1
      AND count(*) FILTER (
        WHERE proname = 'is_assigned_to_property'
          AND proargtypes = ARRAY['uuid'::regtype, 'uuid'::regtype]::oidvector
      ) = 1
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'is_property_owner',
        'company_has_property_access',
        'company_has_property_scope',
        'is_assigned_to_property'
      ])
  ), false),
  'security has exactly the four approved property helper signatures'
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
      AND procedure.proname = 'is_property_owner'
      AND procedure.proargtypes = ARRAY['uuid'::regtype]::oidvector
  ), false),
  'is_property_owner is a stable SQL definer with fixed search_path'
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
      AND procedure.proname = 'company_has_property_access'
      AND procedure.proargtypes = ARRAY['uuid'::regtype, 'uuid'::regtype]::oidvector
  ), false),
  'company_has_property_access is a stable SQL definer with fixed search_path'
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
      AND procedure.proname = 'company_has_property_scope'
      AND procedure.proargtypes = ARRAY[
        'uuid'::regtype,
        'uuid'::regtype,
        'public.property_company_relationship_scope[]'::regtype
      ]::oidvector
  ), false),
  'company_has_property_scope is a stable SQL definer with fixed search_path'
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
      AND procedure.proname = 'is_assigned_to_property'
      AND procedure.proargtypes = ARRAY['uuid'::regtype, 'uuid'::regtype]::oidvector
  ), false),
  'is_assigned_to_property is a stable SQL definer with fixed search_path'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(procedure.proowner = table_relation.relowner)
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    CROSS JOIN pg_class table_relation
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'is_property_owner',
        'company_has_property_access',
        'company_has_property_scope',
        'is_assigned_to_property'
      ])
      AND table_relation.oid = to_regclass('public.properties')
  ), false),
  'property helpers use the Task 6 table owner as their definer'
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
        'is_property_owner',
        'company_has_property_access',
        'company_has_property_scope',
        'is_assigned_to_property'
      ])
  ), false),
  'PUBLIC execute is revoked from all four property helpers'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(NOT has_function_privilege('anon', procedure.oid, 'EXECUTE'))
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'is_property_owner',
        'company_has_property_access',
        'company_has_property_scope',
        'is_assigned_to_property'
      ])
  ), false),
  'anon cannot execute any property helper'
);

SELECT ok(
  COALESCE((
    SELECT count(*) = 4
      AND bool_and(has_function_privilege('authenticated', procedure.oid, 'EXECUTE'))
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'security'
      AND procedure.proname = ANY (ARRAY[
        'is_property_owner',
        'company_has_property_access',
        'company_has_property_scope',
        'is_assigned_to_property'
      ])
  ), false),
  'authenticated alone can execute all four property helpers'
);

SELECT (
  to_regclass('public.properties') IS NOT NULL
    AND to_regclass('public.property_owners') IS NOT NULL
    AND to_regclass('public.property_company_relationships') IS NOT NULL
    AND to_regclass('public.company_property_settings') IS NOT NULL
    AND to_regclass('public.property_staff_assignments') IS NOT NULL
    AND to_regprocedure('security.is_property_owner(uuid)') IS NOT NULL
    AND to_regprocedure('security.company_has_property_access(uuid,uuid)') IS NOT NULL
    AND to_regprocedure(
      'security.company_has_property_scope(uuid,uuid,public.property_company_relationship_scope[])'
    ) IS NOT NULL
    AND to_regprocedure('security.is_assigned_to_property(uuid,uuid)') IS NOT NULL
)::integer AS property_core_ready
\gset

\if :property_core_ready

INSERT INTO auth.users (id)
VALUES
  ('51000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000002'),
  ('51000000-0000-0000-0000-000000000003'),
  ('51000000-0000-0000-0000-000000000004'),
  ('51000000-0000-0000-0000-000000000005');

INSERT INTO public.profiles (id)
VALUES
  ('51000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000002'),
  ('51000000-0000-0000-0000-000000000003'),
  ('51000000-0000-0000-0000-000000000004'),
  ('51000000-0000-0000-0000-000000000005');

INSERT INTO public.companies (id, name)
VALUES
  ('52000000-0000-0000-0000-000000000001', 'Company A'),
  ('52000000-0000-0000-0000-000000000002', 'Company B'),
  ('52000000-0000-0000-0000-000000000003', 'Inspection Service Company'),
  ('52000000-0000-0000-0000-000000000004', 'Inactive Relationship Company'),
  ('52000000-0000-0000-0000-000000000005', 'Cascade Company');

INSERT INTO public.company_memberships (company_id, profile_id, role, is_active)
VALUES
  (
    '52000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    'ADMIN',
    true
  ),
  (
    '52000000-0000-0000-0000-000000000003',
    '51000000-0000-0000-0000-000000000001',
    'INSPECTOR',
    true
  );

WITH created_property AS (
  INSERT INTO public.properties (name)
  VALUES ('Generated Property')
  RETURNING id, created_at
)
SELECT ok(
  (SELECT id IS NOT NULL AND created_at IS NOT NULL FROM created_property),
  'properties generates an id and timestamp'
);

INSERT INTO public.properties (id, name)
VALUES
  ('53000000-0000-0000-0000-000000000001', 'Property A'),
  ('53000000-0000-0000-0000-000000000002', 'Property B'),
  ('53000000-0000-0000-0000-000000000003', 'Property C'),
  ('53000000-0000-0000-0000-000000000004', 'Inactive Relationship Property'),
  ('53000000-0000-0000-0000-000000000005', 'Property Cascade Target'),
  ('53000000-0000-0000-0000-000000000006', 'Profile Cascade Target'),
  ('53000000-0000-0000-0000-000000000007', 'Company Cascade Target');

INSERT INTO public.property_owners (property_id, profile_id)
VALUES
  ('53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001'),
  ('53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002'),
  ('53000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001'),
  ('53000000-0000-0000-0000-000000000005', '51000000-0000-0000-0000-000000000002'),
  ('53000000-0000-0000-0000-000000000006', '51000000-0000-0000-0000-000000000005');

SELECT throws_ok(
  $$INSERT INTO public.property_owners (property_id, profile_id) VALUES ('53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001')$$,
  '23505',
  NULL,
  'duplicate property owner rows are rejected'
);

SELECT ok(
  (SELECT count(*) = 2 FROM public.property_owners WHERE profile_id = '51000000-0000-0000-0000-000000000001')
    AND (SELECT count(*) = 2 FROM public.property_owners WHERE property_id = '53000000-0000-0000-0000-000000000001'),
  'one profile can own multiple properties and one property can have multiple owners'
);

INSERT INTO public.property_company_relationships (
  id,
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES
  (
    '54000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001',
    '52000000-0000-0000-0000-000000000001',
    'PRIMARY',
    'ACTIVE',
    'FULL_MANAGEMENT'
  ),
  (
    '54000000-0000-0000-0000-000000000002',
    '53000000-0000-0000-0000-000000000002',
    '52000000-0000-0000-0000-000000000002',
    'PRIMARY',
    'ACTIVE',
    'FULL_MANAGEMENT'
  ),
  (
    '54000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'ACTIVE',
    'INSPECTION_SERVICE'
  ),
  (
    '54000000-0000-0000-0000-000000000004',
    '53000000-0000-0000-0000-000000000004',
    '52000000-0000-0000-0000-000000000001',
    'PRIMARY',
    'INACTIVE',
    'FULL_MANAGEMENT'
  ),
  (
    '54000000-0000-0000-0000-000000000005',
    '53000000-0000-0000-0000-000000000005',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'ACTIVE',
    'MAINTENANCE_SERVICE'
  ),
  (
    '54000000-0000-0000-0000-000000000006',
    '53000000-0000-0000-0000-000000000007',
    '52000000-0000-0000-0000-000000000005',
    'SERVICE',
    'ACTIVE',
    'COORDINATION_SERVICE'
  ),
  (
    '54000000-0000-0000-0000-000000000007',
    '53000000-0000-0000-0000-000000000004',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'ACTIVE',
    'INSPECTION_SERVICE'
  );

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.property_company_relationships
    WHERE id = '54000000-0000-0000-0000-000000000001'
      AND relationship_type = 'PRIMARY'
      AND status = 'ACTIVE'
      AND scope = 'FULL_MANAGEMENT'
  ),
  'active PRIMARY with FULL_MANAGEMENT is accepted'
);

SELECT throws_ok(
  $$INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope) VALUES ('53000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', 'PRIMARY', 'ACTIVE', 'FULL_MANAGEMENT')$$,
  '23505',
  NULL,
  'a second active primary for one property is rejected'
);

INSERT INTO public.property_company_relationships (
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES (
  '53000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000002',
  'PRIMARY',
  'INACTIVE',
  'FULL_MANAGEMENT'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.property_company_relationships
    WHERE property_id = '53000000-0000-0000-0000-000000000001'
      AND company_id = '52000000-0000-0000-0000-000000000002'
      AND relationship_type = 'PRIMARY'
      AND status = 'INACTIVE'
  ),
  'an inactive historical primary is retained'
);

SELECT throws_ok(
  $$INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope) VALUES ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000001', 'PRIMARY', 'INACTIVE', 'INSPECTION_SERVICE')$$,
  '23514',
  NULL,
  'PRIMARY with a service scope is rejected'
);

SELECT throws_ok(
  $$INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope) VALUES ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000001', 'SERVICE', 'INACTIVE', 'FULL_MANAGEMENT')$$,
  '23514',
  NULL,
  'SERVICE with FULL_MANAGEMENT is rejected'
);

INSERT INTO public.property_company_relationships (
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES
  (
    '53000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'ACTIVE',
    'MAINTENANCE_SERVICE'
  ),
  (
    '53000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'ACTIVE',
    'COORDINATION_SERVICE'
  );

SELECT ok(
  (
    SELECT array_agg(scope ORDER BY scope::text) = ARRAY[
      'COORDINATION_SERVICE',
      'INSPECTION_SERVICE',
      'MAINTENANCE_SERVICE'
    ]::public.property_company_relationship_scope[]
    FROM public.property_company_relationships
    WHERE property_id = '53000000-0000-0000-0000-000000000003'
      AND company_id = '52000000-0000-0000-0000-000000000003'
      AND relationship_type = 'SERVICE'
      AND status = 'ACTIVE'
  ),
  'all three explicit service scopes are accepted'
);

SELECT throws_ok(
  $$INSERT INTO public.property_company_relationships (property_id, company_id, relationship_type, status, scope) VALUES ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000003', 'SERVICE', 'ACTIVE', 'INSPECTION_SERVICE')$$,
  '23505',
  NULL,
  'a duplicate active company property type and scope is rejected'
);

INSERT INTO public.property_company_relationships (
  property_id,
  company_id,
  relationship_type,
  status,
  scope
)
VALUES
  (
    '53000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'INACTIVE',
    'INSPECTION_SERVICE'
  ),
  (
    '53000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000003',
    'SERVICE',
    'INACTIVE',
    'INSPECTION_SERVICE'
  );

SELECT is(
  (
    SELECT count(*)
    FROM public.property_company_relationships
    WHERE property_id = '53000000-0000-0000-0000-000000000003'
      AND company_id = '52000000-0000-0000-0000-000000000003'
      AND relationship_type = 'SERVICE'
      AND status = 'INACTIVE'
      AND scope = 'INSPECTION_SERVICE'
  ),
  2::bigint,
  'inactive duplicate relationship history is retained'
);

INSERT INTO public.company_property_settings (company_id, property_id)
VALUES ('52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001');

SELECT throws_ok(
  $$INSERT INTO public.company_property_settings (company_id, property_id) VALUES ('52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001')$$,
  '23505',
  NULL,
  'company property settings pair is unique'
);

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES (
  '52000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000001'
);

SELECT ok(
  (
    SELECT is_active
    FROM public.property_staff_assignments
    WHERE company_id = '52000000-0000-0000-0000-000000000001'
      AND property_id = '53000000-0000-0000-0000-000000000001'
      AND profile_id = '51000000-0000-0000-0000-000000000001'
  ),
  'a property staff assignment is active by default'
);

INSERT INTO public.property_staff_assignments (
  company_id,
  property_id,
  profile_id,
  is_active
)
VALUES (
  '52000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  false
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.property_staff_assignments
    WHERE company_id = '52000000-0000-0000-0000-000000000001'
      AND property_id = '53000000-0000-0000-0000-000000000004'
      AND profile_id = '51000000-0000-0000-0000-000000000001'
      AND NOT is_active
  ),
  'an inactive property staff assignment remains as a row'
);

SELECT throws_ok(
  $$INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id) VALUES ('52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001')$$,
  '23505',
  NULL,
  'duplicate composite property staff assignments are rejected'
);

INSERT INTO public.company_property_settings (company_id, property_id)
VALUES ('52000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000005');

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES (
  '52000000-0000-0000-0000-000000000003',
  '53000000-0000-0000-0000-000000000005',
  '51000000-0000-0000-0000-000000000002'
);

DELETE FROM public.properties
WHERE id = '53000000-0000-0000-0000-000000000005';

SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.property_owners WHERE property_id = '53000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.property_company_relationships WHERE property_id = '53000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.company_property_settings WHERE property_id = '53000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.property_staff_assignments WHERE property_id = '53000000-0000-0000-0000-000000000005'),
  'deleting a property cascades all property-owned relationship rows'
);

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES (
  '52000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000005'
);

DELETE FROM auth.users
WHERE id = '51000000-0000-0000-0000-000000000005';

SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.property_owners WHERE profile_id = '51000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.property_staff_assignments WHERE profile_id = '51000000-0000-0000-0000-000000000005'),
  'deleting an auth profile cascades owner and assignment rows'
);

INSERT INTO public.company_property_settings (company_id, property_id)
VALUES ('52000000-0000-0000-0000-000000000005', '53000000-0000-0000-0000-000000000007');

INSERT INTO public.property_staff_assignments (company_id, property_id, profile_id)
VALUES (
  '52000000-0000-0000-0000-000000000005',
  '53000000-0000-0000-0000-000000000007',
  '51000000-0000-0000-0000-000000000002'
);

DELETE FROM public.companies
WHERE id = '52000000-0000-0000-0000-000000000005';

SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.property_company_relationships WHERE company_id = '52000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.company_property_settings WHERE company_id = '52000000-0000-0000-0000-000000000005')
    AND NOT EXISTS (SELECT 1 FROM public.property_staff_assignments WHERE company_id = '52000000-0000-0000-0000-000000000005'),
  'deleting a company cascades all company-owned Task 6 rows'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.property_owners owner_link
    JOIN public.property_company_relationships relationship
      ON relationship.property_id = owner_link.property_id
    WHERE owner_link.profile_id = '51000000-0000-0000-0000-000000000001'
      AND relationship.property_id = '53000000-0000-0000-0000-000000000001'
      AND relationship.company_id = '52000000-0000-0000-0000-000000000001'
  )
    AND EXISTS (
      SELECT 1
      FROM public.property_owners owner_link
      JOIN public.property_company_relationships relationship
        ON relationship.property_id = owner_link.property_id
      WHERE owner_link.profile_id = '51000000-0000-0000-0000-000000000001'
        AND relationship.property_id = '53000000-0000-0000-0000-000000000002'
        AND relationship.company_id = '52000000-0000-0000-0000-000000000002'
    ),
  'Andrea globally owns Property A and Property B managed by separate companies'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000001';

SELECT ok(
  security.is_property_owner('53000000-0000-0000-0000-000000000001'),
  'Andrea is recognized as an owner of Property A'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000003';

SELECT ok(
  NOT security.is_property_owner('53000000-0000-0000-0000-000000000001'),
  'an unrelated profile is not recognized as an owner'
);

SELECT ok(
  NOT security.is_property_owner('53000000-0000-0000-0000-000000000099'),
  'a nonexistent property has no owner'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  NOT security.is_property_owner('53000000-0000-0000-0000-000000000001'),
  'no Auth context has no property ownership'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000001';

SELECT ok(
  security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  ),
  'an active company member with an active property relationship has access'
);

SELECT ok(
  NOT security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000004'
  ),
  'an inactive property relationship grants no company access'
);

SELECT ok(
  NOT security.company_has_property_access(
    '52000000-0000-0000-0000-000000000002',
    '53000000-0000-0000-0000-000000000002'
  ),
  'a nonmember cannot use another company active relationship'
);

SELECT ok(
  NOT security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000003'
  ),
  'membership in an unrelated company does not broaden property access'
);

SELECT ok(
  NOT security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000099'
  ),
  'a nonexistent property grants no company access'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  NOT security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  ),
  'no Auth context has no company property access'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000001';

SELECT ok(
  security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000004',
    ARRAY['INSPECTION_SERVICE']::public.property_company_relationship_scope[]
  ),
  'inspection service access matches an explicitly requested inspection scope'
);

SELECT ok(
  NOT security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000004',
    ARRAY['MAINTENANCE_SERVICE']::public.property_company_relationship_scope[]
  ),
  'an inspection-only service relationship does not grant maintenance scope'
);

SELECT ok(
  NOT security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000004',
    ARRAY['FULL_MANAGEMENT']::public.property_company_relationship_scope[]
  ),
  'service scope does not expand implicitly to full management'
);

SELECT ok(
  security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001',
    ARRAY['FULL_MANAGEMENT']::public.property_company_relationship_scope[]
  ),
  'primary full management matches an explicitly requested full management scope'
);

SELECT ok(
  NOT security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000003',
    NULL::public.property_company_relationship_scope[]
  ),
  'a NULL requested property scope set is false'
);

SELECT ok(
  NOT security.company_has_property_scope(
    '52000000-0000-0000-0000-000000000003',
    '53000000-0000-0000-0000-000000000003',
    ARRAY[]::public.property_company_relationship_scope[]
  ),
  'an empty requested property scope set is false'
);

SELECT ok(
  security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  ),
  'the current profile active property assignment is recognized'
);

SELECT ok(
  NOT security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000004'
  ),
  'an inactive property assignment is rejected'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000002';

SELECT ok(
  NOT security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  ),
  'another profile cannot use the active property assignment'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000001';

SELECT ok(
  NOT security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000002'
  ),
  'an assignment does not apply to another property'
);

SELECT ok(
  NOT security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000002',
    '53000000-0000-0000-0000-000000000001'
  ),
  'an assignment does not apply to another company'
);

SET LOCAL request.jwt.claim.sub TO '';

SELECT ok(
  NOT security.is_assigned_to_property(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  ),
  'no Auth context has no property assignment'
);

SET LOCAL request.jwt.claim.sub TO '51000000-0000-0000-0000-000000000001';

SELECT ok(
  security.company_has_property_access(
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000001'
  )
    AND NOT security.company_has_property_access(
      '52000000-0000-0000-0000-000000000001',
      '53000000-0000-0000-0000-000000000002'
    )
    AND security.is_property_owner('53000000-0000-0000-0000-000000000001')
    AND security.is_property_owner('53000000-0000-0000-0000-000000000002'),
  'Company A access is limited to Property A even though Andrea owns A and B'
);

RESET ROLE;

\else

SELECT * FROM skip(34, 'property core behavior requires migration 005');

\endif

SELECT * FROM finish();

ROLLBACK;
