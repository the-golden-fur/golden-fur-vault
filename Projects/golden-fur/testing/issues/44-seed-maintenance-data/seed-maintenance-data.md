# Issue #44 Verification: Seed Data — Golden Package + Base Service List

**Issue:** #44 — chore(db): seed data — Golden Package + base service list
**Owner:** Matthew
**Branch:** `chore/seed-maintenance-data` (delivered bundled with #39–#43)
**Base:** `dev`
**Depends on:** #39, #40, #41, #43 merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Seeds the base service catalog (21 services: 10 Grooming with full 4×2
pricing matrices, 1 Daycare, 4 Hotel by cage size, 6 Veterinary), the Golden
Package as **two per-branch rows**, both-branch availability for every
service, and the mandated Senior Citizen/PWD discounts — all idempotent
(fixed `a1300000-…` service ids + `ON CONFLICT DO NOTHING` / `NOT EXISTS`
guards). Promos are deliberately not seeded. **All names and prices are
first-draft placeholders pending adviser confirmation (sprint task 2-A).**

## Decisions flagged (the Guide says: do not guess silently)

1. **SC/PWD scope — the Guide's open question, resolved as 16 rows.** The
   Guide's draft said 4 rows (`2 types × 2 branches`) with
   `scope_type = 'category'` but named no category, and the schema CHECK
   requires exactly one concrete scope per row. Since RA 9994/RA 10754 apply
   the 20% discount across offerings, the seed creates **one row per type ×
   branch × category (2 × 2 × 4 = 16)** so each is independently toggleable
   (exactly MA29's Veterinary concern). If the client wants a single
   per-branch switch instead, delete the extra rows or add an `'all'` scope
   value — raise at the 2-A confirmation.
2. **`Brushing` added beyond the Modules-Features example list.** The Golden
   Package is specified as "Shampoo, Blow-dry, Brush", but the example
   service list has no brush service; `Bath` stands in for Shampoo and a
   `Brushing` service was added so the package really bundles three services.
3. **Bundled price ₱600 vs. a ₱700 sum** — deliberate, demonstrating that a
   package price is independent (#41 AC-2).
4. **Seed-ordering fix (not in the Guide), resolved as two self-contained
   files — not a migration-defined function.** On a fresh `supabase db
reset`, seeds (which create the branches) run **after** migrations, so
   migration `...034` cannot insert branch-dependent rows (availability,
   Golden Package, mandated discounts) on a fresh DB. An earlier pass of
   this seed defined a `public.seed_m13_branch_data()` Postgres function in
   the migration and called it from both the migration and a seed file —
   that coupled a seed file to migration-defined SQL, breaking the
   module-1/module-2 convention where every seed file is self-contained.
   This pass removes that function entirely: migration `...034` now seeds
   **only** the branch-independent base catalog (services + pricing tiers),
   and all branch-dependent seeding lives as plain, self-contained SQL in
   `supabase/seeds/module-3-maintenance/module-3-maintenance.seed.sql` (run
   automatically by `supabase db reset`, ordered after module-1 in
   `supabase/config.toml`) — matching module-1/module-2 exactly, including
   an idempotent `.ts` counterpart (`module-3-maintenance.seed.ts`, run via
   `npm run seed:module-3`) with its own `.seed.spec.ts` unit tests, for
   seeding a linked remote database the same way Issues #38's module-1/
   module-2 scripts do.

## What Changed

- **Added** `supabase/migrations/20260715034_m13_seed_maintenance_data.sql`
  — branch-independent base service catalog + pricing tiers only.
- **Added** `supabase/seeds/module-3-maintenance/module-3-maintenance.seed.sql`
  — self-contained branch-dependent seed (availability, Golden Package,
  mandated discounts); no dependency on any migration-defined function.
- **Added** `supabase/seeds/module-3-maintenance/module-3-maintenance.seed.ts`
  — idempotent Node counterpart, run via `npm run seed:module-3`.
- **Added** `supabase/seeds/module-3-maintenance/module-3-maintenance.seed.spec.ts`
  — 6 unit tests (creation + idempotency for each of the three seed
  functions), run via `npm run test:seed`.
- **Modified** `package.json` (root) — adds the `seed:module-3` script and
  includes it in `seed:all`.
- **Modified** `.vscode/tasks.json` — adds a "🌱 Seed: Module 3 -
  Maintenance" task alongside the other two seed-module tasks.
- **Modified** `supabase/config.toml` — registers the module-3 seed path
  (must stay ordered after module-1).

## Fresh reset vs. linked database

- **Local fresh reset:** `npm run supabase:reset` — migrations run first
  (base catalog seeded), then seeds run in order (module-1 creates
  branches, then module-3's `.sql` fills in availability/Golden Package/
  discounts using those branches).
- **Linked remote database:** `npm run supabase:push` applies the
  migration (base catalog only) — it does **not** run any seed. Follow up
  with `npm run seed:module-3` (requires `SUPABASE_URL` /
  `SUPABASE_SERVICE_ROLE_KEY` in `server/.env`, and that module-1's staff
  seed — or equivalent branch data — already exists there).

If Block 3 of the SQL verification returns zero availability rows, the
module-3 seed hasn't run yet against that database: run
`npm run seed:module-3`, or re-paste `module-3-maintenance.seed.sql`'s
contents into the SQL Editor.

## SQL Verification (all ACs)

Open **Supabase Studio → SQL Editor** (left sidebar `</>` icon) → **New
query** → paste blocks from `seed-maintenance-data.sql` (this folder) one at
a time → **Run** (Ctrl+Enter):

| Block | Checks                                      | Expected                                  |
| :---- | :------------------------------------------ | :---------------------------------------- |
| 1     | AC-1: services per category                 | Grooming 10 / Daycare 1 / Hotel 4 / Vet 6 |
| 2     | AC-1: full matrix on every Grooming service | 10 rows, `tier_count = 8`                 |
| 3     | AC-1: both-branch availability              | 21 rows, `branch_count = 2`, all `true`   |
| 4     | AC-2: Golden Package per branch             | 2 rows, 3 services each, price 600        |
| 5     | AC-3: mandated discounts                    | 4 groups, `category_count = 4`, inactive  |
| 6     | no promos seeded                            | 0                                         |
| 7     | AC-4: idempotent re-run                     | same counts (42 availability / 16 rows)   |

For AC-4 on the migration itself: `supabase migration` tracking never re-runs
an applied file, and its own inserts are additionally guarded by `ON
CONFLICT DO NOTHING`. Block 7 proves the module-3 seed's own idempotency by
re-running its statements and re-checking the same counts.

You can also eyeball the data in **Table Editor** (left sidebar grid icon):
`services`, `service_pricing_tiers`, `packages`, `package_services`,
`discounts`.

## Automated Verification (module-3 seed script)

```powershell
npm run test:seed
```

Expected: 3 test files pass (module-1, module-2, module-3), 13 tests total
— module-3 contributes 6: creation + idempotency for
`seedServiceBranchAvailability`, `seedGoldenPackage`, and
`seedMandatedDiscounts`.

## Acceptance Criteria Checklist

- [x] **AC-1:** base list at both branches, Grooming with full size×coat
      tiers — SQL Blocks 1–3.
- [x] **AC-2:** Golden Package as two per-branch rows bundling the three
      Grooming services — SQL Block 4.
- [x] **AC-3:** SC + PWD exist, `is_active = false`, scope question resolved
      and documented (16-row decision above) — SQL Block 5.
- [x] **AC-4:** idempotent re-run creates no duplicates — SQL Block 7.
