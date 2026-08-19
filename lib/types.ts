export type CompanyRole = "ADMIN" | "MANAGER" | "INSPECTOR" | "COORDINATOR" | "READ_ONLY";

export type PropertyScope =
  | "FULL_MANAGEMENT"
  | "INSPECTION_SERVICE"
  | "MAINTENANCE_SERVICE"
  | "COORDINATION_SERVICE";

export type InspectionStatus = "SCHEDULED" | "IN_PROGRESS" | "COMPLETED";

export type InspectionSeverity = "PASS" | "ATTENTION" | "URGENT";

export type OperationalAction = "MONITOR" | "INCLUDED_IN_SERVICE" | "OWNER_APPROVAL_REQUIRED";

export type MeterType = "ELECTRICITY" | "WATER";

export type ReportStatus = "DRAFT" | "FINAL" | "SUPERSEDED";

export interface Property {
  id: string;
  name: string;
  address_line_1: string | null;
  address_line_2: string | null;
  locality: string | null;
  postcode: string | null;
  country: string | null;
  created_at: string;
}

export interface Inspection {
  id: string;
  company_id: string;
  property_id: string;
  template_version_id: string;
  status: InspectionStatus;
  scheduled_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface InspectionTemplateItem {
  id: string;
  section_id: string;
  label: string;
  sort_order: number;
}

export interface InspectionTemplateSection {
  id: string;
  version_id: string;
  title: string;
  sort_order: number;
  items: InspectionTemplateItem[];
}

export interface InspectionResult {
  id: string;
  inspection_id: string;
  template_item_id: string;
  severity: InspectionSeverity;
  operational_action: OperationalAction;
  comment: string | null;
}

export interface MeterReading {
  id: string;
  inspection_id: string;
  meter_type: MeterType;
  reading_value: number;
  unit: string;
  recorded_at: string;
}

export interface MediaAsset {
  id: string;
  company_id: string;
  property_id: string;
  inspection_id: string | null;
  inspection_result_id: string | null;
  meter_reading_id: string | null;
  storage_bucket: string;
  storage_path: string;
  mime_type: string | null;
  file_size_bytes: number | null;
  created_at: string;
}

/**
 * Minimum stable shape for inspection_report_versions.content (Task 11 leaves
 * it free-form jsonb). `media` holds media_assets.id values the report author
 * has explicitly selected as owner-visible (the Task 12 content->'media'
 * convention) — no other structure is required for the first slice.
 */
export interface ReportContent {
  summary?: string;
  media: string[];
}

export interface ReportVersion {
  id: string;
  company_id: string;
  property_id: string;
  inspection_id: string;
  version_number: number;
  status: ReportStatus;
  title: string | null;
  summary: string | null;
  content: ReportContent | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  published_at: string | null;
  published_by: string | null;
}

export interface OwnerVisibleMedia {
  media_id: string;
  storage_bucket: string;
  storage_path: string;
  mime_type: string | null;
}
