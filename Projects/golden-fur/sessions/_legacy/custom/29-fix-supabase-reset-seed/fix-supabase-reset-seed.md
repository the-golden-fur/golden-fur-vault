# Fix `supabase db reset` (remote) and re-seed the linked project

Branch: `29-fix-supabase-reset-seed`

Follow-up in the same session to `27-daycare-hotel-parity-and-fixed-pricing`
/ `28-fix-pricing-matrix` - the "⚠️ Supabase: Reset REMOTE DB (destructive)"
VSCode task (`npm run supabase:reset:remote` → `supabase db reset --linked`)
failed partway through seeding, right after the migrations added in #27/#28
applied. Both root causes turned out to be **pre-existing bugs**, unrelated
to #27/#28's own content, that a genuinely fresh full reset had apparently
never been run against since they were introduced.

## Why it failed

```
Seeding data from supabase/seeds/module-4-hotel/module-4-hotel.seed.sql...
failed to send batch: ERROR: there is no unique or exclusion constraint
matching the ON CONFLICT specification (SQLSTATE 42P10)
```

`module-4-hotel.seed.sql` seeds `product_catalog` with
`on conflict (name, category) do nothing`. That matched a plain
`unique (name, category)` constraint when it was written - but migration
`20260803085` (customer-owned catalog rows) later replaced that constraint
with **two partial unique indexes** (one scoped to `owner_customer_id IS
NULL` for global/staff rows, one to `IS NOT NULL` for a customer's own
rows), so two different customers - or a customer and the global catalog -
can reuse the same food/medication name. Postgres can only infer a partial
index for `ON CONFLICT` if the same `WHERE` clause is repeated in the
`ON CONFLICT` clause itself; a plain `on conflict (name, category)` with no
predicate matches neither partial index, hence SQLSTATE 42P10. This had
been silently broken since `20260803085` merged - it just needs a truly
fresh reset (not a `db push` onto an already-seeded db) to surface, which
this session's `⚠️ Supabase: Reset REMOTE DB` run apparently was the first
in a while to attempt.

Separately, the pasted output also showed (non-fatal, just noisy):

```
NOTICE (42622): identifier "Front-desk staffcan write medication instructions at their branch"
will be truncated to "Front-desk staffcan write medication instructions at their bra"
```

"Front-desk staff can write medication instructions at their branch" is 66
bytes - 3 over Postgres's 63-byte (`NAMEDATALEN - 1`) identifier limit - so
every `CREATE POLICY` using that exact name gets silently truncated. This
has been true since the original `20260727052` migration created it (a
pre-existing, dormant issue affecting every run, not something #27/#28
introduced) - it only became visible in this session because migration
`20260807104` (from #27) also recreates this same policy (generalizing
`hotel_stays` into the shared `stays` table) and, until this fix, copied
the same over-length name forward.

## What changed

- `supabase/seeds/module-4-hotel/module-4-hotel.seed.sql`: both
  `product_catalog` inserts now use
  `on conflict (name, category) where owner_customer_id is null do nothing`
  (these are global/staff-managed rows - `owner_customer_id` is `NULL` by
  omission - matching `product_catalog_global_name_category_uniq` exactly).
- `supabase/migrations/20260807104_m05_m06_unify_stays.sql`: the recreated
  medication-instructions write policy is now named "...at branch" (60
  bytes) instead of "...at their branch" (66 bytes), so it no longer
  re-triggers the truncation NOTICE. The matching `DROP POLICY` statement
  necessarily still uses the original 66-byte name - it has to resolve to
  whatever name is actually stored (itself already truncated by the
  original 2025-07-27 migration), and a different, already-short string
  there would not match, so the DROP would fail with "policy does not
  exist" instead. That one NOTICE (from the DROP) is expected to keep
  appearing on every reset going forward - it's cosmetic and matches
  pre-existing history, not something this fix could remove.
- Both edits were made in place (not a new migration/seed file) since
  neither had been applied to any shared/remote environment before this
  session's fix.

Both `27-daycare-hotel-parity-and-fixed-pricing/
daycare-hotel-parity-and-fixed-pricing.sql` (the bundled-migrations doc
copy) was re-synced to match the policy-name edit.

## Verification

Already run and confirmed in this session:

1. `npx supabase db reset --linked --yes` (equivalent to the "⚠️ Supabase:
   Reset REMOTE DB" VSCode task, run non-interactively) completed with no
   errors - every migration applied and all four seed modules
   (`module-1-staff-auth` → `module-2-customers-pets` →
   `module-3-maintenance` → `module-4-hotel`) ran to completion.
2. Row counts queried directly against the linked project afterward,
   confirming real data landed (not just "no error printed"):

   | table                       | count                                                                                                                  |
   | --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
   | branches                    | 2                                                                                                                      |
   | staff_profiles              | 32                                                                                                                     |
   | customer_profiles           | 5                                                                                                                      |
   | pets                        | 13                                                                                                                     |
   | services                    | 23                                                                                                                     |
   | packages                    | 2                                                                                                                      |
   | package_services            | 6                                                                                                                      |
   | service_branch_availability | 46                                                                                                                     |
   | discounts                   | 16                                                                                                                     |
   | cages                       | 14                                                                                                                     |
   | product_catalog             | 13 (7 food + 6 medication - confirms the ON CONFLICT fix actually inserted rows, not just silently skipped everything) |
   | stays                       | 0 (expected - empty until a real check-in happens)                                                                     |

To re-verify yourself:

1. Run the "⚠️ Supabase: Reset REMOTE DB (destructive)" VSCode task (or
   `npm run supabase:reset:remote` in a terminal, answering `y` at the
   confirmation prompt) - it should complete with no `ERROR` lines, only
   informational `NOTICE` lines (the one remaining medication-policy
   truncation notice under `20260807104` is expected, see above).
2. Optionally, spot-check `product_catalog` directly in the Supabase
   Dashboard's Table Editor (or SQL Editor:
   `select count(*) from product_catalog;`) - should show 13 rows.

## Test suites

Not applicable - this is a migration/seed-script correctness fix, not
application code. `server`/`client` test suites are unaffected (already
confirmed green in #27/#28's own verification passes, and neither suite
touches seed `.sql` files).
