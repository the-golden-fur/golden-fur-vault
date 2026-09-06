---
title: Renaming the seed folders so they match the module numbers
date: 2026-09-06
tags: [session-plan, golden-fur, supabase, seeds]
project: golden-fur
session: 74-seeds-module-dirs
branch: chore/seeds-module-dirs
---

# 74 — Renaming the seed folders so they match the module numbers

## What you asked for

Make `supabase/seeds/` reflect the 14 modules from `Modules-Features.docx`,
keep only `seed:all` (drop the per-module tasks/scripts), and (from the same
thread) confirm what `supabase/functions/` and `supabase/schemas/` are for.

> also there are multiple modules / make supabase\seeds reflect
> Projects\golden-fur\shared\context\architecture\Modules-Features.docx …
> so there should be 4 dirs in seeds/ … you can push the seeds/ req from
> earlier (all 14 modules) … M-dirs, seeded modules only

## Words you might not know

- **seed data** — rows inserted into the database _after_ the schema is
  built, so the app has something to show on a fresh install (branches,
  sample staff, the Golden Package, the Senior Citizen discount…). Distinct
  from **migrations**, which build the tables/functions themselves.
- **module (M01–M14)** — the 14 feature areas the capstone is divided into
  in `Modules-Features.docx` (M01 Staff Auth, M05 Pet Hotel, M13
  Maintenance, …).
- **idempotent** — safe to run more than once; running the seed twice
  doesn't create duplicate rows.
- **the trio** — every seed folder has three files: `*.seed.ts` (the Node
  runner), `*.seed.sql` (a plain-SQL mirror that `supabase db reset` runs),
  and `*.seed.spec.ts` (a Vitest test against a fake database).

## What was wrong

The seed folders were named by the order they were _added_
(`module-1-staff-auth` … `module-5-promos-vet-catalog`), which stopped
matching the module numbers in the docs. Two of them also bundled more than
one module: `module-3-maintenance` held M13 (services, packages) **and** M12
(Senior Citizen / PWD discounts); `module-5-promos-vet-catalog` held M13
(promos) **and** M07 (the vet medication / procedure catalog).

There were also four `seed:module-1..4` npm scripts and four
`🌱 Seed: Module N` VS Code tasks that duplicated what `seed:all` does.

## What we changed

Renamed to `mNN-<slug>/`, one folder per module that actually has seed data
(most of the 14 modules are transactional and seed nothing):

| now                  | was                                 | holds                                               |
| -------------------- | ----------------------------------- | --------------------------------------------------- |
| `m01-staff-auth`     | `module-1-staff-auth`               | branches, staff_profiles                            |
| `m02-customers-pets` | `module-2-customers-pets`           | customer_profiles, pets                             |
| `m05-hotel`          | `module-4-hotel`                    | cages, food/medication product catalog              |
| `m07-veterinary`     | split from `module-5`               | vet medication + procedure catalog                  |
| `m12-discounts`      | split from `module-3`               | Senior Citizen + PWD discount rows                  |
| `m13-maintenance`    | `module-3` + promos from `module-5` | service branch availability, Golden Package, promos |

- Dropped `seed:module-1..4` and their VS Code tasks. `seed:all` now calls
  each `m*/*.seed.ts` directly, in module-number order (`m01` first because
  everything else needs its branches/staff). `🌱 Seed: All Modules` is the
  only seed task left.
- `supabase/config.toml` `[db.seed].sql_paths` updated to the new names.
- Updated `supabase-seed-maintenance` (the coverage map), `seed-sync-agent`,
  `db-schema-agent`, `docs/setup.md`, `docs/architecture.md`.

**No seed data changed** — the same rows are produced, just reorganised.

### On `supabase/functions/` and `supabase/schemas/` (the same thread)

Both are **correctly empty** and nothing was added:

- `functions/` is for **Supabase Edge Functions** (Deno HTTP). This project
  has none. The "Database Functions" in the Supabase dashboard
  (`add_booking_payment`, `settle_transaction`, the `enforce_*` triggers)
  are **Postgres** functions and already live in `supabase/migrations/`.
- `schemas/` is the declarative-schema feature; `config.toml` has
  `schema_paths = []` (off) — this repo hand-writes migrations. Same for
  `tests/` (pgTAP, unused).
- Mirroring the dashboard nav (`indexes/`, `enums/`) would duplicate DDL
  that already lives in the creating migration — don't.

## How you'll know it worked

See `testing/testing.md`. `npm run test:seed` passes (6 files, 25 tests),
`npm run format:check` is clean, and `npm run seed:all` names six real
files.
