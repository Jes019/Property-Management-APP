"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { createClient } from "@/lib/supabase/client";

/**
 * Full sign-out: clears the real Supabase Auth session (not just a client
 * route change), then sends the user back to /login so a stale session
 * cookie can never be reused by navigating to another route.
 */
export function SignOutButton() {
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);

  async function handleSignOut() {
    setSigningOut(true);
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={handleSignOut}
      disabled={signingOut}
      className="text-xs font-bold uppercase tracking-widest text-navy/50 disabled:opacity-50"
    >
      {signingOut ? "Signing out…" : "Sign Out"}
    </button>
  );
}
