"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

import { isOwner } from "@/lib/data/session";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);

    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });

    setSubmitting(false);

    if (signInError) {
      setError("Could not sign in with those details.");
      return;
    }

    // A user with no company membership at all should never land on the
    // company dashboard — route them straight into their own portal.
    // property_owners ownership is the reliable, RLS-safe signal for this
    // (see lib/data/session.ts); every destination page still enforces its
    // own access independently regardless of this choice.
    const ownerAccount = await isOwner(supabase).catch(() => false);
    router.push(ownerAccount ? "/owner" : "/dashboard");
    router.refresh();
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-surface px-6">
      <div className="w-full max-w-sm rounded-2xl border border-border bg-white p-8 shadow-sm">
        <h1 className="mb-1 text-2xl font-bold tracking-tight">JTC Property Services</h1>
        <p className="mb-6 text-sm text-navy/60">Sign in to continue.</p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="email" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Email
            </label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm focus:border-navy focus:outline-none"
            />
          </div>
          <div>
            <label htmlFor="password" className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-navy/50">
              Password
            </label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="min-h-[44px] w-full rounded-lg border border-border bg-[#F4F7F9] px-3 py-2 text-sm focus:border-navy focus:outline-none"
            />
          </div>

          {error ? (
            <p role="alert" className="text-xs font-semibold text-urgent">
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={submitting}
            className="min-h-[48px] w-full rounded-xl bg-navy text-sm font-bold uppercase tracking-widest text-white disabled:opacity-50"
          >
            {submitting ? "Signing in…" : "Sign In"}
          </button>
        </form>
      </div>
    </main>
  );
}
