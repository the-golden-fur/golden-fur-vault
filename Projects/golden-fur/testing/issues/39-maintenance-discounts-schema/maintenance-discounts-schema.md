# Issue #39 Verification: Maintenance + Discounts Schema

**Issue:** #39 — chore(db): migration — services, packages, promos, discounts tables + enums
**Owner:** Matthew
**Branch:** `chore/maintenance-discounts-schema` (delivered bundled with #40–#44)
**Base:** `dev`
**Depends on:** Sprint 1 fully merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Ships the full M13 + M12 schema in two migrations: the `service_category` and
`discount_type` enums, 8 tables (`services`, `service_pricing_tiers`,
`service_branch_availability`, `packages`, `package_services`, `promos`,
`promo_scope`, `discounts`), two-tier RLS on every table (all-staff SELECT,
Admin/Superadmin write via `current_staff_role()`), and the
`deactivate_expired_promos()` function that backs Issue #42's expiry job.

**Migration renumbering (per the Guide's own Handoff State instruction):** the
Guide assumed Sprint 1 ended at `...020`; the actual last merged migration is
`20260714031_m01_get_staff_availability_approved_only.sql`. This epic's
migrations are therefore:

| Guide filename        | Actual filename                                   |
| :-------------------- | :------------------------------------------------ |
| `20260721_021_m13...` | `20260715032_m13_create_maintenance_schema.sql`   |
| `20260721_022_m12...` | `20260715033_m12_create_discounts_schema.sql`     |
| `20260722_023_m13...` | `20260715034_m13_seed_maintenance_data.sql` (#44) |

## Decisions flagged (not silent guesses)

1. **`service_pricing_tiers.coat_type` is `SC`/`LC`, not four values.** The
   Design sheet's prose lists "Short, Medium, Long, Double-coat" but in the
   same cell says "matches M02 pets.coat_type" — and M02's actual merged enum
   (`20260712023_m02_create_pet_enums.sql`) is `('SC', 'LC')`. The M13
   flowchart also specifies "S/M/L/XL × Short Coat / Long Coat". SC/LC wins;
   raise with the adviser if the 4-value coat scale is genuinely wanted.
2. **`promo_scope` uses a surrogate `id` PK + partial unique indexes,** not
   the Design sheet's composite PK over `(promo_id, service_id, package_id)` —
   Postgres PK columns cannot be nullable, and exactly one of
   service_id/package_id is NULL per row by design. The partial unique indexes
   enforce the same "no duplicate scope target per promo" guarantee.
3. **`deactivate_expired_promos()` ships here rather than in a third
   migration** so #42 stays a code-only issue; a conditional `DO` block
   schedules it via pg_cron **only if the extension is already installed**
   (pg_cron approval is an Open Item — see #42's doc for the fallback).

## What Changed

- **Added** `supabase/migrations/20260715032_m13_create_maintenance_schema.sql`
- **Added** `supabase/migrations/20260715033_m12_create_discounts_schema.sql`

## Applying the migrations

From the repo root in PowerShell — pick the one that matches your setup:

- **Linked remote project (the shared dev database):**

  ```powershell
  npm run supabase:push
  ```

  This applies any not-yet-applied migrations (032, 033, 034) to the linked
  Supabase project. When prompted `Do you want to push these migrations to the
remote database? [Y/n]`, type `Y` and press Enter.

- **Local stack (Docker Desktop must be running):**

  ```powershell
  npx supabase start
  npm run supabase:reset
  ```

  `supabase:reset` rebuilds the local DB from every migration, then runs the
  seed files (including the new module-3 seed — see #44's doc).

If push reports a numbering conflict, run `npm run supabase:status` and check
that no other migration claimed `032`+ since this branch was written.

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all server test files pass (379 tests at time of writing),
`tsc --noEmit` silent, eslint reports no errors (3 pre-existing `no-console`
warnings in auth controllers are not from this epic).

## SQL Verification (AC-1 … AC-4)

Open **Supabase Studio → SQL Editor** (left sidebar, `</>` icon) → **New
query**, then paste and run the sections of
`maintenance-discounts-schema.sql` (in this folder) **one block at a time** —
each block's expected result is commented above it. It covers:

1. **AC-2:** both enums and all 8 tables exist with the specified columns.
2. **AC-3 (RLS):** policies exist on every table; a simulated non-admin
   staff role can SELECT but not write (the script uses
   `set local role authenticated` + a JWT claim to impersonate).
3. **AC-4:** `package_services.service_id` `ON DELETE RESTRICT` blocks a hard
   DELETE on a bundled service, and `promo_scope`'s exactly-one-of CHECK
   rejects a both-set / neither-set row. Both tests run inside a transaction
   that rolls back — nothing is left behind.

For **AC-1** (clean run on a fresh DB), the local path above is the proof:
`npm run supabase:reset` replays every migration from 001 in order.

## Acceptance Criteria Checklist

- [x] **AC-1:** both migrations run cleanly on a fresh DB (`supabase:reset`)
      and against dev with Sprint 1 applied (`supabase:push`).
- [x] **AC-2:** 8 tables + 2 enums with the specified columns/constraints/
      defaults — SQL blocks 1–2.
- [x] **AC-3:** RLS: non-admin staff can SELECT, writes rejected — SQL block 3.
- [x] **AC-4:** RESTRICT + exactly-one-of CHECK verified — SQL blocks 4–5.
