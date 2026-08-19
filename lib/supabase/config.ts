const SUPABASE_URL_PATTERN = /^https:\/\/[a-z0-9-]+\.supabase\.(co|in)\/?$/;
const DB_URI_PATTERN = /^postgres(ql)?:\/\//i;

/**
 * Guards against exactly the incident this project hit once already: a
 * Postgres connection string (with an embedded password) or a service-role
 * key landing in a NEXT_PUBLIC_* variable, where it would ship straight to
 * the browser. Fails loudly and immediately rather than silently exposing
 * a secret.
 */
export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !publishableKey) {
    throw new Error("Missing Supabase environment configuration.");
  }

  if (DB_URI_PATTERN.test(url)) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL is a database connection string, not the Supabase API URL. " +
        "It must never hold a postgres:// / postgresql:// URI (or the credentials embedded in one) — " +
        "that variable ships to the browser. Use https://<project-ref>.supabase.co instead.",
    );
  }

  if (!SUPABASE_URL_PATTERN.test(url)) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL must be the Supabase API project URL (https://<project-ref>.supabase.co).",
    );
  }

  if (DB_URI_PATTERN.test(publishableKey) || publishableKey.includes("@")) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY does not look like a public key — it must never hold a " +
        "database connection string or embedded credentials.",
    );
  }

  if (/service_role/i.test(publishableKey) || /^sb_secret_/.test(publishableKey)) {
    throw new Error(
      "A service-role/secret key was supplied as the public Supabase key. Service-role credentials must " +
        "never be used in browser-exposed configuration — use the publishable/anon key instead.",
    );
  }

  return { url, publishableKey };
}
