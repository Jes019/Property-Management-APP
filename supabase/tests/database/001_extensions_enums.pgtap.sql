BEGIN;

SELECT plan(16);

SELECT has_type('public', 'company_role', 'company_role exists in public');
SELECT enum_has_labels(
  'public',
  'company_role',
  ARRAY['ADMIN', 'MANAGER', 'INSPECTOR', 'COORDINATOR', 'READ_ONLY']::name[],
  'company_role has exactly the required ordered labels'
);

SELECT has_type('public', 'property_company_relationship_status', 'property_company_relationship_status exists in public');
SELECT enum_has_labels(
  'public',
  'property_company_relationship_status',
  ARRAY['ACTIVE', 'INACTIVE']::name[],
  'property_company_relationship_status has exactly the required ordered labels'
);

SELECT has_type('public', 'property_company_relationship_type', 'property_company_relationship_type exists in public');
SELECT enum_has_labels(
  'public',
  'property_company_relationship_type',
  ARRAY['PRIMARY', 'SERVICE']::name[],
  'property_company_relationship_type has exactly the required ordered labels'
);

SELECT has_type('public', 'property_company_relationship_scope', 'property_company_relationship_scope exists in public');
SELECT enum_has_labels(
  'public',
  'property_company_relationship_scope',
  ARRAY['FULL_MANAGEMENT', 'INSPECTION_SERVICE', 'MAINTENANCE_SERVICE', 'COORDINATION_SERVICE']::name[],
  'property_company_relationship_scope has exactly the required ordered labels'
);

SELECT has_type('public', 'inspection_lifecycle_status', 'inspection_lifecycle_status exists in public');
SELECT enum_has_labels(
  'public',
  'inspection_lifecycle_status',
  ARRAY['SCHEDULED', 'IN_PROGRESS', 'COMPLETED']::name[],
  'inspection_lifecycle_status has exactly the required ordered labels'
);

SELECT has_type('public', 'inspection_severity', 'inspection_severity exists in public');
SELECT enum_has_labels(
  'public',
  'inspection_severity',
  ARRAY['PASS', 'ATTENTION', 'URGENT']::name[],
  'inspection_severity has exactly the required ordered labels'
);

SELECT has_type('public', 'operational_action', 'operational_action exists in public');
SELECT enum_has_labels(
  'public',
  'operational_action',
  ARRAY['MONITOR', 'INCLUDED_IN_SERVICE', 'OWNER_APPROVAL_REQUIRED']::name[],
  'operational_action has exactly the required ordered labels'
);

SELECT has_type('public', 'report_status', 'report_status exists in public');
SELECT enum_has_labels(
  'public',
  'report_status',
  ARRAY['DRAFT', 'FINAL', 'SUPERSEDED']::name[],
  'report_status has exactly the required ordered labels'
);

SELECT * FROM finish();

ROLLBACK;
