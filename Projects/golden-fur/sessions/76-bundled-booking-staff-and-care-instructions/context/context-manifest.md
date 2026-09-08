# Context — 76-bundled-booking-staff-and-care-instructions

## Copied into ./context/

- `architectural-change-history-in-progress.md` — the two "In Progress"
  backlog items this session closes (configurable staff concurrency +
  bundled-booking double-booking; Hotel step 8 Care Instructions crash),
  quoted verbatim, plus a note on the `service_branch_availability` backfill
  found while verifying. Origin:
  `Projects/golden-fur/shared/context/Architectural-Change-History.docx`
  (section Tasks → Development → In Progress; docx last modified
  2026-09-08).

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx` —
  full project backlog / change log. Canonical, project-wide; only the two
  In-Progress items above are session-specific.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.sql` — seed
  staff logins used in the manual test (`<branch>.<role>N@goldenfur.com`,
  e.g. `makati.admin1`, password `password123`).
- `golden-fur/supabase/seeds/m02-customers-pets/` — seed customers
  (`customer1@goldenfur.com` … `customer5@goldenfur.com`, password
  `password123`) and their pets (`customer1` owns the assessed pets **Max**
  and **Luna**).
- `golden-fur/.env` / `golden-fur/server/.env` — Supabase dev connection
  string used to apply migration `20260908180` directly to the dev DB. A
  secrets file; never copied.

## Vault branch for this session's PR

`docs/golden-fur-session-76-bundled-booking-staff-and-care-instructions`
(also recorded in `testing/testing.md` so the vault `pr-guard` can locate
this folder).
