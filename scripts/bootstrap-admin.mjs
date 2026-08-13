#!/usr/bin/env node
/**
 * Creates the very first user — your Managing Director account.
 *
 * A fresh install has no users, and self-signup is disabled on purpose, so
 * this is the only way in. Run it once, immediately after the stack is up.
 *
 *   node scripts/bootstrap-admin.mjs "md@yourcompany.com" "ChooseAStrongPassword"
 *
 * Or, if you do not have Node.js installed, run it through Docker from this
 * folder (no install needed):
 *
 *   docker run --rm --network host -v "%cd%":/w -w /w node:20-alpine \
 *     node scripts/bootstrap-admin.mjs "md@yourcompany.com" "ChooseAStrongPassword"
 *
 * Choose the password yourself and change it after first sign-in
 * (Settings -> Account). It is not stored anywhere by this script.
 */
import { readFileSync } from "node:fs";

const [email, password] = process.argv.slice(2);
if (!email || !password) {
  console.error('Usage: node scripts/bootstrap-admin.mjs "<email>" "<password>"');
  process.exit(1);
}
if (password.length < 10) {
  console.error("Choose a password of at least 10 characters.");
  process.exit(1);
}

// Read the generated secrets rather than asking for them again.
const env = Object.fromEntries(
  readFileSync(".env.docker", "utf8")
    .split(/\r?\n/)
    .filter((l) => l.includes("=") && !l.trimStart().startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }),
);

const base = env.NEXT_PUBLIC_SUPABASE_URL || "http://localhost:8000";
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
if (!serviceKey) {
  console.error("SUPABASE_SERVICE_ROLE_KEY missing from .env.docker — generate secrets first (see INSTALL.md).");
  process.exit(1);
}

const authHeaders = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  "Content-Type": "application/json",
};

// 1. Create the auth user. email_confirm skips the verification mail, which
//    matters because SMTP may not be configured yet on a fresh install.
const createRes = await fetch(`${base}/auth/v1/admin/users`, {
  method: "POST",
  headers: authHeaders,
  body: JSON.stringify({ email, password, email_confirm: true }),
});

const created = await createRes.json().catch(() => ({}));
if (!createRes.ok) {
  const msg = created.msg || created.message || JSON.stringify(created);
  if (/already|exists|registered/i.test(msg)) {
    console.error(`A user with ${email} already exists. Nothing to do.`);
    console.error("If you have lost the password, delete that user and re-run this script.");
  } else {
    console.error(`Could not create the user: ${msg}`);
    console.error("Is the stack running? Check: docker compose ps");
  }
  process.exit(1);
}

// 2. A database trigger creates the matching profile automatically; promote it
//    to Managing Director, the only role that can create other roles.
const promoteRes = await fetch(
  `${base}/rest/v1/profiles?email=eq.${encodeURIComponent(email)}`,
  {
    method: "PATCH",
    headers: { ...authHeaders, Prefer: "return=representation" },
    body: JSON.stringify({ role: "managing_director", status: "active", full_name: "Managing Director" }),
  },
);

const promoted = await promoteRes.json().catch(() => []);
if (!promoteRes.ok || promoted.length === 0) {
  console.error("User was created but could not be promoted to Managing Director.");
  console.error(typeof promoted === "object" ? JSON.stringify(promoted) : String(promoted));
  process.exit(1);
}

console.log("Managing Director account created.\n");
console.log(`  Sign in at : ${env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000"}`);
console.log(`  Email      : ${email}`);
console.log("  Password   : (the one you just chose)\n");
console.log("Change the password after your first sign-in: Settings -> Account.");
