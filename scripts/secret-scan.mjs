#!/usr/bin/env node
/**
 * Durable secret/config scan for tracked files. Exists specifically because
 * a Postgres connection string with an embedded password once landed in
 * NEXT_PUBLIC_SUPABASE_URL in a local, gitignored .env — this catches the
 * class of mistake before it can reach a tracked file, and rejects
 * service-role material from ever being treated as public config.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const DB_URI_WITH_CREDENTIALS = /postgres(?:ql)?:\/\/[^\s'"]*:[^\s'"]*@/i;
const NEXT_PUBLIC_ASSIGNED_TO_DB_URI = /NEXT_PUBLIC_[A-Z0-9_]*\s*[:=]\s*['"]?postgres(?:ql)?:\/\//i;
const SECRET_KEY_PREFIX = /\bsb_secret_[A-Za-z0-9_-]+/;
const GENERIC_SECRET_ASSIGNMENT =
  /\b(api[_-]?key|secret|password|db_password|database_url)\b\s*[:=]\s*['"][^'"\s]{8,}['"]/i;

const patterns = [
  { name: "database URI with embedded credentials", pattern: DB_URI_WITH_CREDENTIALS },
  { name: "NEXT_PUBLIC_* assigned a database URI", pattern: NEXT_PUBLIC_ASSIGNED_TO_DB_URI },
  { name: "service-role key material", pattern: SECRET_KEY_PREFIX },
  { name: "generic secret-looking assignment", pattern: GENERIC_SECRET_ASSIGNMENT },
];

const trackedFiles = execFileSync("git", ["ls-files"], { encoding: "utf8" })
  .split("\n")
  .filter(Boolean);

let findings = [];

for (const file of trackedFiles) {
  let content;
  try {
    content = readFileSync(file, "utf8");
  } catch {
    continue; // binary or unreadable — not a text-secret concern
  }

  for (const { name, pattern } of patterns) {
    if (pattern.test(content)) {
      findings.push(`${file}: matched "${name}"`);
    }
  }
}

if (findings.length > 0) {
  console.error("Secret scan failed:\n" + findings.map((line) => `  - ${line}`).join("\n"));
  process.exit(1);
}

console.log(`Secret scan passed (${trackedFiles.length} tracked files checked).`);
