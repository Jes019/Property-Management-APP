import { MediaGallery } from "@/components/media-gallery";
import { SeverityPill } from "@/components/status-pill";
import type {
  Inspection,
  InspectionResult,
  InspectionTemplateSection,
  MeterReading,
} from "@/lib/types";

const ACTION_LABEL: Record<InspectionResult["operational_action"], string> = {
  MONITOR: "Monitor",
  INCLUDED_IN_SERVICE: "Included in Service",
  OWNER_APPROVAL_REQUIRED: "Owner Approval Required",
};

/** Pure display of actual database records — no derived approvals or maintenance logic. */
export function InspectionReview({
  inspection,
  sections,
  results,
  meterReadings,
}: {
  inspection: Inspection;
  sections: InspectionTemplateSection[];
  results: InspectionResult[];
  meterReadings: MeterReading[];
}) {
  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold tracking-tight">Inspection Review</h2>

      {sections.map((section) => (
        <section key={section.id} className="space-y-3">
          <h3 className="text-lg font-bold">{section.title}</h3>
          <div className="space-y-3">
            {section.items.map((item) => {
              const result = results.find((entry) => entry.template_item_id === item.id);
              return (
                <div key={item.id} className="rounded-xl border border-border bg-white p-4 shadow-sm">
                  <p className="mb-2 text-sm font-bold">{item.label}</p>
                  {result ? (
                    <div className="space-y-1">
                      <SeverityPill severity={result.severity} />
                      <p className="text-xs font-semibold uppercase tracking-widest text-navy/50">
                        {ACTION_LABEL[result.operational_action]}
                      </p>
                      {result.comment ? <p className="text-sm text-navy/70">{result.comment}</p> : null}
                    </div>
                  ) : (
                    <p className="text-sm text-navy/40">No result recorded.</p>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      ))}

      <section className="space-y-2">
        <h3 className="text-lg font-bold">Meter Readings</h3>
        <ul className="space-y-2">
          {meterReadings.map((reading) => (
            <li
              key={reading.id}
              className="flex items-center justify-between rounded-xl border border-border bg-white px-4 py-3 text-sm"
            >
              <span className="font-semibold">{reading.meter_type}</span>
              <span>
                {reading.reading_value} {reading.unit}
              </span>
            </li>
          ))}
          {meterReadings.length === 0 ? <li className="text-sm text-navy/50">No meter readings recorded.</li> : null}
        </ul>
      </section>

      <MediaGallery
        inspectionId={inspection.id}
        companyId={inspection.company_id}
        propertyId={inspection.property_id}
        readOnly
      />
    </div>
  );
}
