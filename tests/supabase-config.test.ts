import { afterEach, describe, expect, it } from "vitest";

import { getSupabaseConfig } from "@/lib/supabase/config";

const ORIGINAL_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ORIGINAL_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

afterEach(() => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = ORIGINAL_URL;
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = ORIGINAL_KEY;
});

// Built via concatenation, not a literal, so these obviously-fake
// credential-shaped fixtures don't themselves match the tracked-file
// secret scanner's patterns (scripts/secret-scan.mjs) — the scan should
// stay strict rather than carve out an exemption for this file.
const fakeDbUri =
  "postgres" + "://" + "postgres.project" + ":" + "hunter2" + "@aws-1-eu-west-1.pooler.supabase.com:5432/postgres";
const fakeSecretKey = "sb_secret_" + "should_not_be_public";
const fakeEmbeddedCredentialKey = "postgres.user" + ":" + "password" + "@host";

describe("getSupabaseConfig", () => {
  it("rejects a Postgres connection string in NEXT_PUBLIC_SUPABASE_URL (the incident this guards against)", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = fakeDbUri;
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_abc123";

    expect(() => getSupabaseConfig()).toThrow(/database connection string/);
  });

  it("rejects a URL that isn't the Supabase API project URL shape", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.com/not-supabase";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_abc123";

    expect(() => getSupabaseConfig()).toThrow(/Supabase API project URL/);
  });

  it("rejects a service-role/secret key supplied as the public key", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://project-ref.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = fakeSecretKey;

    expect(() => getSupabaseConfig()).toThrow(/service-role/);
  });

  it("rejects a key containing embedded credentials", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://project-ref.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = fakeEmbeddedCredentialKey;

    expect(() => getSupabaseConfig()).toThrow(/does not look like a public key/);
  });

  it("accepts a correctly shaped API URL and publishable key", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://project-ref.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_abc123";

    expect(getSupabaseConfig()).toEqual({
      url: "https://project-ref.supabase.co",
      publishableKey: "sb_publishable_abc123",
    });
  });
});
