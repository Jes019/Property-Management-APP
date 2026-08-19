import Link from "next/link";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export default async function HomePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-surface px-6 text-center">
      <h1 className="text-2xl font-bold tracking-tight">JTC Property Platform</h1>
      <div className="flex gap-4">
        <Link href="/dashboard" className="rounded-xl bg-navy px-6 py-3 text-sm font-bold text-white">
          Company Dashboard
        </Link>
        <Link href="/owner" className="rounded-xl border border-border bg-white px-6 py-3 text-sm font-bold text-navy">
          Owner Portal
        </Link>
      </div>
    </main>
  );
}
