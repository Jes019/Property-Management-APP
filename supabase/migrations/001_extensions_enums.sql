CREATE TYPE public.company_role AS ENUM (
  'ADMIN',
  'MANAGER',
  'INSPECTOR',
  'COORDINATOR',
  'READ_ONLY'
);

CREATE TYPE public.property_company_relationship_status AS ENUM (
  'ACTIVE',
  'INACTIVE'
);

CREATE TYPE public.property_company_relationship_type AS ENUM (
  'PRIMARY',
  'SERVICE'
);

CREATE TYPE public.property_company_relationship_scope AS ENUM (
  'FULL_MANAGEMENT',
  'INSPECTION_SERVICE',
  'MAINTENANCE_SERVICE',
  'COORDINATION_SERVICE'
);

CREATE TYPE public.inspection_lifecycle_status AS ENUM (
  'SCHEDULED',
  'IN_PROGRESS',
  'COMPLETED'
);

CREATE TYPE public.inspection_severity AS ENUM (
  'PASS',
  'ATTENTION',
  'URGENT'
);

CREATE TYPE public.operational_action AS ENUM (
  'MONITOR',
  'INCLUDED_IN_SERVICE',
  'OWNER_APPROVAL_REQUIRED'
);

CREATE TYPE public.report_status AS ENUM (
  'DRAFT',
  'FINAL',
  'SUPERSEDED'
);
