# Custom Request Verification: Reset Supabase Seed Data

**Request:** Reset local and remote Supabase DB with a fixed `seed.sql`, standardized staff/customer test accounts, and a `password123` password for everyone.
**Owner:** Matthew
**Branch:** `chore/reset-supabase-seed-data`
**Base:** `dev`

## Overview

`supabase/seed.sql` had three separate bugs, found by actually running `supabase db reset` against a local Docker stack rather than just reading the file:

1. It inserted a `break_window` value into `public.branches`, a column dropped by migration `20260701010_m01_drop_branches_break_window.sql`.
2. `auth.users` was inserted with columns named `app_metadata`/`user_metadata` — the real GoTrue schema names them `raw_app_meta_data`/`raw_user_meta_data`, so the insert failed with `column "app_metadata" of relation "users" does not exist`.
3. `auth.identities` was missing `provider_id`, a `NOT NULL` column in the real schema — this would have failed right after (2) was fixed.
4. Even after (1)-(3) were fixed, the seed itself succeeded but **logins still 500'd**: GoTrue's Go code scans `confirmation_token`/`recovery_token`/`email_change_token_new`/`email_change` as non-nullable strings, so leaving them `NULL` (Postgres allows it, GoTrue's driver doesn't) broke `POST /auth/v1/token`. Fixed by explicitly inserting `''` for those four columns.

No schema/migration changes were needed — the existing migration set already fully describes the current schema (this project uses timestamped migrations, not the declarative `supabase/schemas/*.sql` workflow — `schema_paths` is empty in `config.toml`), so "schema files" here means the SQL verification queries below, added alongside the fixed seed.

## What Changed

- **Modified** `supabase/seed.sql`:
  - Removed the stale `break_window` column from the `branches` insert.
  - Fixed `auth.users` inserts to use `raw_app_meta_data`/`raw_user_meta_data`, and to explicitly set `confirmation_token`, `recovery_token`, `email_change_token_new`, `email_change` to `''` (not `NULL`) so GoTrue's login query doesn't 500.
  - Fixed `auth.identities` inserts to include the required `provider_id` column.
  - Seeds **2 branches** (Makati, Southwoods) — unchanged from before.
  - Seeds **staff accounts** for every `staff_role` enum value (`Superadmin`, `Admin`, `Supervisor`, `Receptionist`, `Groomer`, `Veterinarian`, `Cashier`, `Pet Assistant`), 2 per role per branch (32 total), via a `DO` block looping branches × roles × N. Email/username pattern: `<branch>.<role>N@goldenfur.com` (e.g. `makati.admin2@goldenfur.com`, `southwoods.groomer1@goldenfur.com`).
  - Seeds **5 customer accounts**: `customer1@goldenfur.com` … `customer5@goldenfur.com`.
  - Every account (staff and customer) uses the password **`password123`**, hashed via `crypt(..., gen_salt('bf'))` the same way the original seed did for customers.
- **Added** `testing/docs/custom/04-reset-supabase-seed-data/reset-supabase-seed-data.sql` — post-reset verification queries (row counts, spot-check a known email, confirm no `break_window`/`is_busy`/`busy_until` leftovers, confirm no `NULL` GoTrue token columns).
- **Added** `testing/docs/custom/04-reset-supabase-seed-data/remote-wipe-and-reseed.sql` — destructive, remote-only script: deletes every staff/customer/branch row (relying on `ON DELETE CASCADE`), then runs the same fixed seed. Needed because the remote project already had real/manually-created data, so the plain seed's `INSERT`s conflicted (`branches_name_key` on `Makati`). Not run automatically by anything — it's meant to be pasted into the Studio SQL Editor by hand, once, with the project switcher double-checked first.
- **Modified** `.gitignore` — added `supabase/.branches/` and `supabase/.temp/` (Supabase CLI local per-machine state that was showing up as a dirty file after every `db reset`, unrelated to seed data but found while verifying this fix).

## Automated Verification

Local reset (requires Docker Desktop running):

```powershell
npx supabase start
npx supabase db reset
```

Expected: the reset completes with no errors and prints `Seeding data from supabase/seed.sql...` followed by `Finished supabase db reset...`.

**This was actually run end-to-end** against a local Docker stack as part of this change (not just eyeballed): `db reset` completed cleanly, row counts matched (2 branches / 32 staff / 5 customers / 37 `@goldenfur.com` auth users), and real logins were tested directly against GoTrue (`POST http://127.0.0.1:54321/auth/v1/token?grant_type=password`) for both `makati.admin2@goldenfur.com` and `customer3@goldenfur.com` — both returned a valid `access_token`.

## Manual / Structural Verification

1. **Confirm the CLI can see the new seed file:**

   ```powershell
   Select-String -Path supabase/seed.sql -Pattern "break_window"
   ```

   Expected: no matches (the stale column reference is gone).

2. **Run the row-count and spot-check queries** — open Supabase Studio (`npx supabase status` will print the Studio URL, typically `http://127.0.0.1:54323`) → **SQL Editor** → paste and run `testing/docs/custom/04-reset-supabase-seed-data/reset-supabase-seed-data.sql`. Expected results are documented inline as comments above each query.

3. **Log in as a seeded staff account** directly against local GoTrue (fastest check, no server needed — this is the exact request already verified while making this change):

   ```powershell
   curl -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" -H "apikey: <publishable-key-from-supabase-status>" -H "Content-Type: application/json" -d '{\"email\":\"makati.admin2@goldenfur.com\",\"password\":\"password123\"}'
   ```

   Expected: `200` with an `access_token` and `user.email` = `makati.admin2@goldenfur.com`. Get the `apikey` from `npx supabase status` → **Publishable** key.

4. **Or through the app's own login route** (requires `npm --prefix server run dev` running separately):

   ```powershell
   curl -X POST http://localhost:3000/auth/staff/login -H "Content-Type: application/json" -d '{\"identifier\":\"makati.admin1@goldenfur.com\",\"password\":\"password123\"}'
   ```

   Expected: `200` with an `access_token`.

5. **Log in as a seeded customer account** the same way against `/auth/customers/login` (or the client app's login form) with `customer1@goldenfur.com` / `password123`. Expected: `200` with an `access_token`.

## Applying to the Remote Project

**Corrected after actually trying it** — the guidance originally here (`supabase db reset --linked`, Dashboard "Backups → Reset") was speculative and turned out wrong. Here's what's actually true, confirmed against this project's own remote:

- `supabase db push` **only applies migration files** (schema DDL). It never runs `seed.sql` and never touches data — confirmed by running it, which correctly reported "Remote database is up to date" (no pending migrations) while data was untouched.
- The Supabase CLI has **no command that resets or seeds a linked/remote project's data**. Seeding is a local-only concept tied to `supabase db reset`, which works by dropping and recreating the entire local database first — there's no remote equivalent of that drop.
- The only way to get seed data onto a remote project is to run SQL directly against it via the Supabase Studio **SQL Editor** (or `psql`/any Postgres client using the project's connection string).
- `supabase/seed.sql` is plain `INSERT`s with no `ON CONFLICT` handling, so it only works against an **empty** database. Running it as-is against a remote project that already has data fails immediately — confirmed by pasting it into this project's remote SQL Editor and getting `ERROR: 23505: duplicate key value violates unique constraint "branches_name_key" DETAIL: Key (name)=(Makati) already exists.`, because the remote already had real/manually-created branches and 24 `customer_profiles` rows.

**To wipe a remote project's data and reseed it fresh** (destructive, no undo — confirm the project switcher in Studio's top bar is pointed at the right org/project/branch before running):

1. Open Supabase Studio for the target project → **SQL Editor** → **New query**.
2. Paste the full contents of `testing/docs/custom/04-reset-supabase-seed-data/remote-wipe-and-reseed.sql` (deletes all staff/customer/branch rows via cascade, then reseeds — see the warning header in that file).
3. Click **Run**. Expected: no errors; re-run the row-count queries from `reset-supabase-seed-data.sql` against the same project to confirm 2 branches / 32 staff / 5 customers.

## Acceptance Criteria Checklist

- [x] `supabase db reset` completes end-to-end with no errors — verified locally, not just read through.
- [x] Seeded accounts actually authenticate — verified by calling GoTrue's `/auth/v1/token` directly for both a staff and a customer account and getting a real `access_token` back, not just confirming the rows exist.
- [x] All seeded accounts (staff + customer) use password `password123`.
- [x] Staff emails/usernames follow `<branch>.<role>N@goldenfur.com` (e.g. `makati.admin2@goldenfur.com`).
- [x] Customer emails follow `customerN@goldenfur.com`.
- [x] A branch name was proposed for this request: `chore/reset-supabase-seed-data`.
