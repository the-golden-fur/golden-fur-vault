# Issue #62 Verification: daycare_sessions table

**Issue:** #62 — chore(db): daycare_sessions table
**Owner:** Matthew
**Branch:** `chore/daycare-schema`
**Base:** `dev`
**Depends on:** Sprint 2 Epic B merged (`bookings` table); Issue #61 merged (sequential numbering, no functional dependency)
**Sprint:** Sprint 3 Epic A — M06 Daycare Management

## Overview

Creates `daycare_sessions` (a single/partial-day supervision session record) so #65 has a real table and RLS to build against. `booking_id` is **nullable** — unlike `grooming_sessions.booking_id` — because a walk-in session legitimately has no booking to reference; a partial `UNIQUE` index still prevents duplicate sessions for the same advance booking.

**Also adds** `branches.daycare_checkin_cutoff` — a column the Guide's #65 dev notes assume already exists ("Southwoods reads from its own branch-config value... confirm the exact column name against the merged M01 schema"), but no such column exists anywhere in the merged M01 schema. It's added here, in the same migration, since #65's cutoff check has nothing to read otherwise. See the "Decision flagged for the reviewer" note below.

**Numbering note:** same renumbering as #61 — this migration is `20260719039` (Guide assumed `...027`).

## What Changed

- **Added** `supabase/migrations/20260719039_m06_create_daycare_schema.sql`:
  - `alter table public.branches add column daycare_checkin_cutoff time not null default '16:00:00'` — both branches get the same seeded default.
  - `daycare_sessions` with the exact DB Design column set: `booking_id` (nullable, FK), `pet_id` (FK), `branch_id` (FK, stored directly so the cutoff-enforcement query stays a single-table read with no join), `created_by_staff_id` (FK), `status` (plain text, `'Active'` default, `CHECK IN ('Active','Completed')`), `check_in_at` (default `now()`), `check_out_at`, `computed_charge`.
  - Partial `UNIQUE` index on `booking_id` `WHERE booking_id IS NOT NULL`.
  - Index on `(branch_id, status)`.
  - **RLS:** Receptionist/Admin/Supervisor may SELECT/INSERT/UPDATE rows at their own branch (`current_staff_role()` + a `staff_profiles.branch_id` match); Superadmin unrestricted (`for all`, mirroring the branch-scope pattern from #61's `grooming_sessions`). **No customer-facing policy exists at all** — Daycare check-in/checkout is staff-only, unlike M03 bookings.

### Decision flagged for the reviewer

The Guide's dev notes for #65 say "Makati is a fixed 4:00 PM per Modules-Features; Southwoods reads from its own branch-config value (M01 branches table) — confirm the exact column name against the merged M01 schema before writing the check." No such column exists in any merged M01 migration (`branches` has `operating_hours`, `timezone`, `is_vet_branch` — no daycare-specific cutoff). Rather than block #65 on a missing column, `daycare_checkin_cutoff` is added here as part of the daycare schema migration, seeded to `16:00:00` for both branches. **Only Southwoods' value is ever actually read** (see #65's `daycareCheckIn.service.ts`) — Makati's cutoff stays hardcoded in application code per "fixed", not sourced from this column, even though the column's default happens to match. **Raise with Alarie if a different Southwoods default was intended** — `16:00:00` was chosen defensively (matches Makati) since no other value was specified anywhere in the source docs.

## Acceptance Criteria Map

| AC                                                                                 | Where verified                                          |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with #61 applied)                      | `supabase db push` below                                |
| AC-2 columns/constraints/defaults per DB Design; `booking_id` nullable             | SQL script section 1                                    |
| AC-3 partial-unique: two rows cannot both reference the same non-null `booking_id` | SQL script's expected-error test                        |
| AC-4 RLS: no customer-role query can read/write this table at all                  | SQL script section 2 + manual customer-token test below |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Database Verification (Supabase)

1. **Apply migrations**:

   ```powershell
   supabase db push
   ```

   Expected: `20260719039` (and `038`/`040` if verifying the whole epic) apply cleanly. `supabase db reset` locally replays everything from scratch with zero errors. **Do not run `db reset` against the hosted project.**

2. **Open Supabase Studio → SQL Editor → New query**, paste all of `daycare-schema.sql` (this folder) and **Run**. Expected: every row `pass = true`.

3. **AC-3 negative test** — run the commented `-- EXPECTED-ERROR TEST` statement individually: inserting a second `daycare_sessions` row with the same non-null `booking_id` must fail with `violates unique constraint "daycare_sessions_booking_id_key"`.

4. **AC-4 customer RLS test** (needs one seeded customer account):
   1. In Studio → **Authentication → Users**, note a customer user's UUID.
   2. Run the `-- RLS IMPERSONATION TEST` block at the bottom of the SQL file (uncomment it first). It seeds a `daycare_sessions` row (as service role), then impersonates the customer — the select must return **0 rows**, and an insert attempt as that customer must **fail** (no policy grants it).

## Notes

- `daycare_sessions.status` is plain `text`, not an enum, matching the Design sheet's convention for small binary-ish states scoped to a single epic (promoted to a real enum only if a third state emerges).
- No `ON DELETE CASCADE` on `booking_id` — bookings are never hard-deleted (cancellation is a status change), so a plain FK is sufficient.
