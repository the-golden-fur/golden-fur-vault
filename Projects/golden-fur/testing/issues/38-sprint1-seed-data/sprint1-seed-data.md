# Issue #38 Verification: Seed SQL for Sprint 1 Reference Data

**Issue:** #38 — chore(db): seed SQL for Sprint 1 reference data
**Owner:** Matthew
**Branch:** `chore/sprint1-seed-data`
**Base:** `dev`
**Depends on:** Epics A, A-1, B merged (staff schema final); Epic C merged
(customer/pet schema final)
**Sprint:** Sprint 1 — Epic D — `supabase/`

## Overview

Seeds Sprint 1 reference data: `branches`, `staff_profiles`, `customer_profiles`,
and `pets`. `staff_profiles` and `customer_profiles` rows have a 1:1 foreign
key to `auth.users`, which plain SQL cannot populate directly through the
Admin API path — `branches` has no such dependency.

**Revision note (this pass):** by direct instruction, the seed data volume
was reverted back to the original dev-convenience shape — **2 staff accounts
per role per branch (32 total)** and **5 bare-ish customer accounts** — instead
of the smaller, formally-AC-exact set (8 staff / 3 customers) from the
previous pass. **This means AC-2 and AC-3's literal wording ("exactly one...
per staff_role", "3 customer_profiles rows") are no longer met on purpose** —
see the Acceptance Criteria Checklist below for what's actually true now. The
module-grouped file layout from the previous pass is unchanged; only the data
volume inside each module's seed files changed.

**Bug fix (found by running `supabase:reset:remote` for real):** both `.sql`
files called `crypt('password123', gen_salt('bf'))` unqualified. Migration
`20260625001_m01_create_branches.sql` installs `pgcrypto` `with schema
extensions`, not `public`. A local `supabase start` instance's default
`search_path` happens to include `extensions`, so this resolved fine there —
but a linked **remote** project's `db reset` session does not, and failed
with `function gen_salt(unknown) does not exist (SQLSTATE 42883)` partway
through module-1's seed. Both files now call `extensions.crypt(...)` /
`extensions.gen_salt(...)` explicitly. The failure was clean: the CLI batches
each seed file's statements together, so the failed run rolled back module-1's
seed entirely and never reached module-2 — migrations still applied
successfully, the remote database was just left unseeded, not corrupted.
Simply re-run `supabase:reset:remote` (or `supabase:reset` locally) after
this fix.

## Module Layout

Modules mirror the `mNN_` prefixes on the migration filenames in
`supabase/migrations/`:

| Module                            | Tables seeded                | Folder                                    |
| :-------------------------------- | :--------------------------- | :---------------------------------------- |
| M01 — Staff Auth & Access Control | `branches`, `staff_profiles` | `supabase/seeds/module-1-staff-auth/`     |
| M02 — Customer Portal & Pets      | `customer_profiles`, `pets`  | `supabase/seeds/module-2-customers-pets/` |

**Tables intentionally left unseeded** (confirmed against every table visible
in Table Editor / `supabase/migrations/`):

- `staff_unavailability_blocks`, `pet_vaccination_records`,
  `pet_medical_notes` — deliberately empty per the original Epic D design, so
  QA can exercise those create/approve workflows from a clean state.
- `mfa_lockouts` (`shared`, not module-owned) — tracks runtime failed-MFA-attempt
  state; there's no meaningful "reference data" to seed here. Stays empty by
  not having a seed file at all.

## What Changed (This Pass)

- **Rewrote** `module-1-staff-auth.seed.sql` — back to the exact original
  dev-convenience content: branches (unchanged) + a nested `do $$ ... $$`
  loop generating 2 staff accounts per role per branch (8 roles × 2 branches
  × 2 = **32 staff**), `<branch>.<role>N@goldenfur.com` (e.g.
  `makati.admin2@goldenfur.com`). **Not idempotent** — like the original, this
  is meant to run once against a freshly-reset database; re-running against a
  database that already has these rows will hit the unique constraints on
  `branches.name` / `staff_profiles.registered_email`.
- **Rewrote** `module-1-staff-auth.seed.ts` — same 32-account shape, generated
  with the same loop logic in TypeScript instead of `jsonb_to_recordset`.
  Still idempotent (unlike the `.sql` file) — safe to re-run against a
  database that already has these rows.
- **Rewrote** `module-2-customers-pets.seed.sql` / `.seed.ts` — back to the
  original 5-customer loop (`customer1@goldenfur.com` …
  `customer5@goldenfur.com`), with two additions on top of the original
  (which predates both): a placeholder `facebook_id` on `customer1`, and a
  `pets` block giving each customer 1-2 pets (8 pets total), since `pets`
  didn't exist when the original `seed.sql` was written. The `.sql` variant
  is **not idempotent** for the customer loop (matches the original); the
  `.ts` variant remains idempotent for both customers and pets.
- **Added** `supabase:reset:remote` script to root `package.json`:
  `supabase db reset --linked` — resets the **linked remote** project
  (destructive; only touches whatever project `supabase link` currently
  points at, not local).
- **Added** VS Code task **⚠️ Supabase: Reset REMOTE DB (destructive)** in
  the "Supabase" group of `.vscode/tasks.json`, next to the existing local
  reset task, with a `detail` warning about what it actually does.
- Updated both `.seed.spec.ts` files for the new counts (32 staff / 5
  customers / 8 pets).

### Seed data produced

**Staff (32 total — 2 accounts per role, per branch):**

| Branch     | Roles (×2 each)                                                                            | Email pattern                      |
| :--------- | :----------------------------------------------------------------------------------------- | :--------------------------------- |
| Makati     | Superadmin, Admin, Supervisor, Receptionist, Groomer, Veterinarian, Cashier, Pet Assistant | `makati.<role>N@goldenfur.com`     |
| Southwoods | (same 8 roles)                                                                             | `southwoods.<role>N@goldenfur.com` |

e.g. `makati.admin1@goldenfur.com`, `makati.admin2@goldenfur.com`,
`southwoods.superadmin1@goldenfur.com`, … Role slugs: `superadmin`, `admin`,
`supervisor`, `receptionist`, `groomer`, `veterinarian`, `cashier`,
`petassistant`.

**Customers (5 total, `customer1@goldenfur.com` … `customer5@goldenfur.com`):**

| Email                     | Pets                                    | Notes                           |
| :------------------------ | :-------------------------------------- | :------------------------------ |
| `customer1@goldenfur.com` | Max (Dog, M, SC), Luna (Cat, S, LC)     | has a placeholder `facebook_id` |
| `customer2@goldenfur.com` | Rex (Dog, L, LC)                        |                                 |
| `customer3@goldenfur.com` | Bruno (Dog, XL, SC), Mimi (Cat, M, LC)  |                                 |
| `customer4@goldenfur.com` | Coco (Cat, L, SC)                       |                                 |
| `customer5@goldenfur.com` | Bella (Dog, S, LC), Simba (Cat, XL, SC) |                                 |

All accounts use the password `password123`.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm install
npm run test:seed -- --run
```

Expected: 7/7 tests pass — 4 in `module-1-staff-auth.seed.spec.ts` (branch
idempotency, exact 32-account/4-per-role-per-branch split, the
`branch.roleN@goldenfur.com` email pattern, staff idempotency), 3 in
`module-2-customers-pets.seed.spec.ts` (5 customers / 8 pets with variety,
the placeholder `facebook_id` on exactly `customer1`, idempotency).

This pass did **not** run either script against a real database:
`server/.env`'s `SUPABASE_URL` points at a live hosted Supabase project, not
a local instance. A dry run confirming both `.ts` scripts load, resolve their
imports, and fail gracefully without live credentials was performed:

```powershell
$env:SUPABASE_URL = ""
$env:SUPABASE_SERVICE_ROLE_KEY = ""
npx tsx supabase/seeds/module-1-staff-auth/module-1-staff-auth.seed.ts
npx tsx supabase/seeds/module-2-customers-pets/module-2-customers-pets.seed.ts
```

Expected: both print
`SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set (see server/.env).`

The `.sql` variants were **not** executed against a live Postgres (no local
Docker instance was available in this environment) — please run them via
`npm run supabase:reset` locally as part of your own verification pass.

## Running It For Real (Local Supabase Recommended)

**Do this against a local Supabase instance. `supabase:reset:remote` targets
whatever project `supabase link` currently points at — confirm that before
ever running it; it will wipe and reseed a real, possibly shared, database.**

### Local

```powershell
npm run supabase:reset
```

Applies migrations, then runs both module `.sql` files automatically. Since
neither is idempotent, **do not** run this a second time expecting a clean
re-seed without errors — `supabase db reset` always starts from a dropped/
recreated database, so this is normal and expected, not a bug.

Or use the TS/Admin API variants (idempotent, so safe against a
partially-seeded database):

```powershell
npm run seed:module-1   # branches + staff_profiles (32 accounts)
npm run seed:module-2   # customer_profiles + pets (5 customers, 8 pets)
npm run seed:all        # both, in sequence
```

### Remote (linked project) — use deliberately, not by habit

```powershell
npm run supabase:reset:remote
```

Runs `supabase db reset --linked` — drops and rebuilds the **linked remote**
project from migrations + seeds. Run `npm run supabase:status` first if
you're not sure which project is currently linked. Also available as the
**⚠️ Supabase: Reset REMOTE DB (destructive)** VS Code task.

## VS Code Tasks

Command Palette → **Tasks: Run Task**:

| Task                                       | Group     | Runs                    |
| :----------------------------------------- | :-------- | :---------------------- |
| 🌱 Seed: Module 1 - Staff Auth             | Seed Data | `seed:module-1`         |
| 🌱 Seed: Module 2 - Customers & Pets       | Seed Data | `seed:module-2`         |
| 🌱 Seed: All Modules                       | Seed Data | `seed:all`              |
| 🔧 Supabase: Reset Local DB                | Supabase  | `supabase:reset`        |
| ⚠️ Supabase: Reset REMOTE DB (destructive) | Supabase  | `supabase:reset:remote` |

Confirm they appear:

```powershell
Get-Content .vscode/tasks.json | Select-String "Seed:|Reset REMOTE"
```

## Structural / Database Verification

Confirm the seeded rows via Supabase Studio → **Table Editor**, or the SQL
Editor:

```sql
select role, count(*) from public.staff_profiles group by role order by role;
-- expect: 8 rows, count = 4 each (2 branches x 2 accounts)

select count(*) from public.staff_profiles;
-- expect: 32

select count(*) from public.customer_profiles;
-- expect: 5

select count(*) filter (where facebook_id is not null) from public.customer_profiles;
-- expect: 1

select count(*) from public.pets;
-- expect: 8

select
  (select count(*) from public.staff_unavailability_blocks) as blocks,
  (select count(*) from public.pet_vaccination_records) as vax,
  (select count(*) from public.pet_medical_notes) as notes,
  (select count(*) from public.mfa_lockouts) as lockouts;
-- expect: 0, 0, 0, 0
```

## Acceptance Criteria Checklist

Recorded honestly against the issue's original wording — some no longer hold
literally, by explicit direction this pass (see Revision note above).

- [~] **AC-1:** `module-1-staff-auth.seed.sql` inserts `branches` rows for
  Makati and Southwoods, but is **no longer** "safe to re-run" — the
  restored original content has no `on conflict` clause (matches the
  real historical `seed.sql`, which was also not idempotent). The `.ts`
  variant (`seedBranches`) is still idempotent if that matters for your
  workflow.
- [~] **AC-2:** does **not** create exactly one `staff_profiles` row per
  `staff_role`. Creates 2 per role per branch (32 total) — restored
  dev-convenience volume, by direct instruction.
- [~] **AC-3:** does **not** create exactly 3 `customer_profiles` rows.
  Creates 5, each with 1-2 `pets` rows of varied
  species/weight_class/coat_type — unit test `creates 5 customers, each
with 1-2 pets...`.
- [x] **AC-4:** at least one seed customer (`customer1`) has a placeholder
      `facebook_id` — unit test `sets a placeholder facebook_id...`.
- [x] **AC-5:** no `staff_unavailability_blocks`, `pet_vaccination_records`,
      or `pet_medical_notes` rows are created by any Epic D seed script — by
      construction; confirmed via the SQL verification query above.
- [~] **AC-6:** the `.ts` variants of both modules remain idempotent
  (re-running does not duplicate rows or throw — unit tests `is
idempotent: re-running does not duplicate...`). The `.sql` variants are
  **not** idempotent by design this pass (see AC-1/the Revision note) —
  they mirror the original `seed.sql`, meant for a single run against a
  freshly-reset database.
