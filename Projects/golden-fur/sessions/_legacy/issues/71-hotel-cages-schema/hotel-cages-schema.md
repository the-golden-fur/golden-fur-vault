# Issue #71 Verification: cages table + cage_size / cage_status enums

**Issue:** #71 — chore(db): cages table + cage_size + cage_status enums
**Owner:** Matthew
**Branch:** `chore/hotel-cages-schema`
**Base:** `dev`
**Depends on:** Sprint 1 `branches` table merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

Creates the M05 cage inventory schema so #75 (check-in) and #78 (cage status/checkout) have real tables and RLS to build against: the `cage_size` (`S`/`M`/`L`/`XL`) and `cage_status` (`Available`/`Occupied`/`Reserved`/`Under Maintenance`) enums, and `cages` — a per-branch inventory table.

**Numbering note:** the Guide assumed Sprint 3's last migration was `...028`; the actual last merged migration on `dev` is `20260726049` (M13 promo cap), so this epic's migrations are renumbered `050–053`, matching how #61 (Sprint 3) already renumbered against the same kind of drift.

## What Changed

- **Added** `supabase/migrations/20260727050_m05_create_cages_schema.sql`:
  - `cage_size` enum: `S / M / L / XL` — redeclared rather than reusing `pets.weight_class`, since a cage's size category and a pet's weight class are conceptually distinct fields on different tables that happen to share allowed values.
  - `cage_status` enum: `Available / Occupied / Reserved / Under Maintenance`.
  - `cages` with the exact DB Design column set: `branch_id` (FK to `branches`), `cage_label` (free text, e.g. `M-S-03`), `size`, `status` (default `Available`), `created_at`/`updated_at`.
  - Index on `(branch_id, size, status)` for the cage grid and availability-count queries.
  - **RLS:** Receptionist/Admin/Supervisor may SELECT all cages at their own branch; only Admin (and Superadmin via the catch-all policy) may UPDATE status — this covers the manual Under Maintenance toggle only. The Occupied/Available transitions driven by check-in (#75) and checkout (#78) go through the server's service-role client, bypassing RLS entirely, so they are never gated by this policy.
- **Added** `supabase/seeds/module-4-hotel/module-4-hotel.seed.sql` (+ `.seed.ts`/`.seed.spec.ts`, mirroring `module-3-maintenance`'s convention) — 7 cages per branch (2×S, 2×M, 2×L, 1×XL), idempotent. Registered in `supabase/config.toml`'s `[db.seed] sql_paths` and as `npm run seed:module-4` / the "🌱 Seed: Module 4 - Hotel" VS Code task. Named `module-4`, not `module-5`, to stay consistent with the existing seed folders' creation-order numbering (`module-3-maintenance` already covers M13/M12, not M03) rather than the Modules-Features module number.

## Acceptance Criteria Map

| AC                                                                                      | Where verified                           |
| --------------------------------------------------------------------------------------- | ---------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with Sprint 3 applied)                      | `supabase db push` below                 |
| AC-2 `cages` columns/constraints/defaults; enums have exactly the specified values      | SQL script section 1–2                   |
| AC-3 RLS: any staff role reads own-branch cages; non-Admin cannot set Under Maintenance | SQL script section 3 + manual test below |
| AC-4 seed data (a handful of cages per size category, per branch) inserts cleanly       | `supabase db reset` / seed run below     |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
npm run test:seed
```

(The schema alone has no server code of its own; the first three commands confirm nothing regressed — #75/#78's specs exercise the table's shape indirectly through mocks. `npm run test:seed` runs `module-4-hotel.seed.spec.ts`, which exercises the seed script's idempotency against a mocked Supabase client.)

## Database Verification (Supabase)

1. **Apply migrations** (PowerShell, repo root):

   ```powershell
   supabase db push
   ```

   Expected: `20260727050` (and `051`–`053` if verifying the whole epic) apply with no errors. `supabase db reset` on a local/staging project replays every migration **and runs the seed files** — expect zero errors and 7×2=14 rows in `cages` afterward. **Do not run `db reset` against the hosted project** (it wipes data).

2. **Open Supabase Studio → SQL Editor → New query**, paste all of `hotel-cages-schema.sql` (this folder) and **Run**.

   Expected: one result table where **every row shows `pass = true`**.

3. **AC-4 seed check** — Table Editor → `cages` → confirm 7 rows per branch (`cage_label` like `Makati-S-01`, `Southwoods-XL-01`, etc.), all `status = 'Available'`. If you didn't use `db reset` (e.g. against a hosted project), run the seed explicitly instead: `npm run seed:module-4` (equivalent to pasting `module-4-hotel.seed.sql` into the SQL Editor) — both are idempotent, safe to re-run. A matching "🌱 Seed: Module 4 - Hotel" task is also available in VS Code's Run Task menu.

4. **AC-3 manual RLS test** — the bottom of the SQL file has an `RLS IMPERSONATION TEST` block, commented out. Fill in one Receptionist UUID and one Admin UUID (Authentication → Users) at the same branch, uncomment, and run the whole block: Receptionist's attempt to set a cage to `Under Maintenance` must be rejected (0 rows updated); Admin's must succeed (1 row updated).

## Notes

- Seed data is provided both ways, matching `module-3-maintenance`'s convention: `module-4-hotel.seed.sql` (paste into Studio, or picked up automatically by `supabase db reset`) and `module-4-hotel.seed.ts` (`npm run seed:module-4`, idempotent via per-row existence checks, safe to run against a hosted project without a full reset) with its own `module-4-hotel.seed.spec.ts`.
- **Folder numbering:** named `module-4-hotel`, not `module-5-hotel` — `module-1`/`module-2`/`module-3` are numbered by seed-folder creation order, not the Modules-Features module number (`module-3-maintenance` covers M13/M12, not M03), so this one continues that sequence (4th seed folder) even though the underlying feature is M05.
- `cages` carries no direct FK from `hotel_stays` back to `branches` — branch scoping for every downstream M05 table is resolved by joining through `cages.branch_id`, since only `cages` needs to know its branch directly.
