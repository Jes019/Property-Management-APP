import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { StatusPill } from "@/components/status-pill";
import { requireUser } from "@/lib/auth";
import { listRecentInspections } from "@/lib/data/inspections";
import { listAccessibleProperties } from "@/lib/data/properties";
import { createClient } from "@/lib/supabase/server";
import type { InspectionStatus } from "@/lib/types";

const STATUS_LABEL: Record<InspectionStatus, string> = {
  SCHEDULED: "Scheduled",
  IN_PROGRESS: "In Progress",
  COMPLETED: "Completed",
};

export default async function DashboardPage() {
  await requireUser();
  const supabase = await createClient();

  const [properties, recentInspections] = await Promise.all([
    listAccessibleProperties(supabase),
    listRecentInspections(supabase, 5),
  ]);

  return (
    <AppShell title="JTC Property Services" variant="company" activeHref="/dashboard">
      <section>
        <h2 className="mb-2 text-3xl font-bold tracking-tight">Dashboard</h2>
        <p className="text-navy/70">Your portfolio at a glance.</p>
      </section>

      <section className="grid grid-cols-2 gap-4">
        <div className="rounded-2xl border border-border bg-white p-5 shadow-sm">
          <p className="mb-1 text-[10px] font-bold uppercase tracking-widest text-navy/40">Properties</p>
          <p className="text-xl font-bold">{properties.length}</p>
        </div>
        <div className="rounded-2xl border border-border bg-white p-5 shadow-sm">
          <p className="mb-1 text-[10px] font-bold uppercase tracking-widest text-navy/40">Recent Activity</p>
          <p className="text-xl font-bold">{recentInspections.length} inspections</p>
        </div>
      </section>

      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold">Recent Inspections</h2>
          <Link href="/properties" className="text-sm font-semibold text-navy">
            See All Properties
          </Link>
        </div>
        {recentInspections.length === 0 ? (
          <p className="text-sm text-navy/50">No inspections yet.</p>
        ) : (
          <ul className="space-y-3">
            {recentInspections.map((inspection) => (
              <li key={inspection.id}>
                <Link
                  href={`/inspections/${inspection.id}`}
                  className="flex items-center justify-between rounded-xl border border-border bg-white p-4 shadow-sm"
                >
                  <span className="text-sm font-semibold">
                    Inspection {inspection.id.slice(0, 8)}
                  </span>
                  <StatusPill
                    label={STATUS_LABEL[inspection.status]}
                    tone={inspection.status === "COMPLETED" ? "good" : "neutral"}
                  />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </AppShell>
  );
}
