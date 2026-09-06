# Renaming the seed folders to match the module numbers

Branches: `chore/seeds-module-dirs` (golden-fur),
`docs/seeds-module-dirs-session-74` (golden-fur-vault)

## The request, verbatim

> make supabase\seeds reflect
> Projects\golden-fur\shared\context\architecture\Modules-Features.docx …
> M-dirs, seeded modules only … also remove the other seed tasks, only keep
> seed all

Scope note: the `supabase/functions/` & `schemas/` question from the same
thread was answered (both correctly empty — see `plan.md`); nothing was
added there.

## What changed

### Renames (git-tracked as renames, no content change beyond header comments)

- `supabase/seeds/module-1-staff-auth/` → `m01-staff-auth/`
- `supabase/seeds/module-2-customers-pets/` → `m02-customers-pets/`
- `supabase/seeds/module-4-hotel/` → `m05-hotel/`

### Splits

- `module-3-maintenance/` → `m13-maintenance/` (keeps
  `seedServiceBranchAvailability` + `seedGoldenPackage`) and new
  `m12-discounts/` (`seedMandatedDiscounts` — Senior Citizen / PWD).
- `module-5-promos-vet-catalog/` → `m07-veterinary/` (keeps
  `seedVetMedicationCatalog` + `seedVetProcedureCatalog`); its `seedPromos`
  moved into `m13-maintenance/`.
- Each new folder got its own `.seed.ts` + `.seed.sql` + `.seed.spec.ts`
  trio. Shared helpers (`getClient`, `getBranches`) are duplicated per
  folder, matching the existing convention.

### Wiring

- `package.json`: removed `seed:module-1..4`; `seed:all` now chains
  `tsx supabase/seeds/mNN-<slug>/mNN-<slug>.seed.ts` for all six folders in
  module-number order.
- `.vscode/tasks.json`: removed the four `🌱 Seed: Module N` tasks; only
  `🌱 Seed: All Modules` remains.
- `supabase/config.toml` `[db.seed].sql_paths`: six new paths, `m01` first.
- `.agent/skills/supabase-seed-maintenance.md` coverage map rewritten
  (folder column instead of `module-N`); `.agent/agents/seed-sync-agent.md`,
  `.agent/agents/db-schema-agent.md`, `docs/setup.md`,
  `docs/architecture.md` updated to the `mNN` convention.

### Left untouched deliberately

Applied migrations (`supabase/migrations/*.sql`) that mention
`module-3-maintenance/` etc. in comments — you never edit an applied
migration; the comments are historical.

## Manual test — step by step

This change is developer tooling (the `supabase/seeds/` scripts are run by
hand, never imported by the client or server app), so there is no in-app
click-through. To re-verify locally:

1. Open a terminal in the `golden-fur` repo root.
2. Run `npm run test:seed`. Expect: `Test Files 6 passed (6)`,
   `Tests 25 passed (25)`.
3. Run `npm run format:check`. Expect: `All matched files use Prettier code
style!`.
4. (Against a throwaway / dev database only) `npm run supabase:reset` then
   `npm run seed:all` — each of the six `mNN` scripts should print its
   "ensured N …" line and exit 0. Do **not** run this against production
   (`gtqncxqsofqtzrlgxdfm`); confirm `supabase/.temp/project-ref` first.

## Test suites

`npm run test:seed` — **6 files, 25 tests passing** (run 2026-09-06,
in-session). `npm run format:check` — clean.

Note: CI (`.github/workflows/ci.yml`) does **not** run `test:seed` — it runs
the client/server Vitest suites, both lints, `format:check`, and the
builds, none of which import `supabase/seeds/`. So the CI checks on the PR
will pass trivially, and the `test:seed` run above is the authoritative
verification for this change.

## Open items

None.
