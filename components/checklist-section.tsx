import { ChecklistItemEditor, type ChecklistItemValues } from "@/components/checklist-item-editor";
import type { InspectionResult, InspectionTemplateSection } from "@/lib/types";

export function ChecklistSection({
  section,
  results,
  readOnly,
  onSaveItem,
}: {
  section: InspectionTemplateSection;
  results: InspectionResult[];
  readOnly: boolean;
  onSaveItem: (templateItemId: string, values: ChecklistItemValues) => Promise<void>;
}) {
  return (
    <section className="space-y-3">
      <h2 className="text-lg font-bold">{section.title}</h2>
      <div className="space-y-3">
        {section.items.map((item) => (
          <ChecklistItemEditor
            key={item.id}
            item={item}
            result={results.find((result) => result.template_item_id === item.id) ?? null}
            readOnly={readOnly}
            onSave={(values) => onSaveItem(item.id, values)}
          />
        ))}
      </div>
    </section>
  );
}
