# Issue #50 Verification: bookings schema (bookings + booking_addons + staff_picker_preferences)

**Issue:** #50 — chore(db): bookings table + booking_status/reused service_category enums + booking_addons + staff_picker_preferences
**Owner:** Matthew
**Branch:** `chore/booking-schema`
**Base:** `dev`
**Depends on:** Epic A #39 merged (imports `service_category`)
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

Creates the full M03 booking schema so #51 has real tables and RLS to build against: the `booking_status` enum, `bookings` (root lifecycle record), `booking_addons` (per-booking add-on junction with a price snapshot), and `staff_picker_preferences` (one preference row per booking, audit flag for the toggle state). `service_category` is **reused** from Epic A's `20260715032` migration, not redeclared.

**Numbering note:** the Guide assumed Epic A ended at `...023`; the actual last merged migration on `dev` is `20260715034`, so this migration is `20260718035` per the Guide's Handoff State instruction.

## What Changed

- **Added** `supabase/migrations/20260718035_m03_create_booking_schema.sql`:
  - `booking_status` enum: `Confirmed / Completed / Cancelled / No-show / Pending`. Per the DB Design sheet, `Pending` is primarily reserved for M07 (Sprint 3); this epic's one use of it is the pay-at-counter stub gate — see the Spec Tension note below.
  - `bookings` with the exact DB Design column set, plus:
    - `CHECK (num_nonnulls(service_id, package_id) = 1)` — the exactly-one-of rule **in SQL** (AC-4), mirroring Epic A's `promo_scope` pattern;
    - `CHECK (scheduled_end > scheduled_start)`, `total_price >= 0`, `payment_method IN (...)` stub vocabulary check;
    - indexes on `(customer_id)`, `(branch_id, scheduled_start)`, and a partial `(assigned_staff_id, scheduled_start) WHERE status = 'Confirmed'` for the RPC's overlap condition.
  - `booking_addons.service_id` → `ON DELETE RESTRICT` (historical add-on references never silently vanish); `booking_id` → `ON DELETE CASCADE`; `price_at_booking` snapshot (AC-4).
  - `staff_picker_preferences.booking_id` `UNIQUE` + `ON DELETE CASCADE`; `CHECK` that `preferred_staff_id` is only set for `preference_type = 'specific'`; `staff_picker_shown` audit flag.
  - **RLS:** staff SELECT-all via `current_staff_role()`; customer-scoped SELECT/INSERT/UPDATE on own `bookings` rows (`customer_id = auth.uid()`), and ownership-subquery policies on the two child tables. No staff write policy — staff writes go through the server's endpoints (service-role client), matching the Guide's "only appropriate write paths can mutate".

### Spec tension flagged for the reviewer

The Design sheet says a booking that fails the payment gate "does not persist at all", while Guide Issue #58 (AC-4) says pay-at-counter **creates** the booking with `payment_confirmed = false` and it "does not reach Confirmed status until a cashier later confirms". These can't both hold with this enum. Implementation follows #58 (persist as `Pending`) because it keeps #51 AC-4 literally true and makes the epic coherent end-to-end; the enum comment documents this. **Raise with Alarie if the "never persists" reading was intended.**

## Acceptance Criteria Map

| AC                                                                                                          | Where verified                                          |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with Epic A)                                                    | `supabase db push` below                                |
| AC-2 tables/columns/constraints/defaults per DB Design; enum exists; service_category reused not redeclared | SQL script sections 1–3                                 |
| AC-3 RLS: customer sees only own rows; staff SELECT-all                                                     | SQL script section 4 + manual cross-customer test below |
| AC-4 exactly-one-of CHECK + booking_addons RESTRICT verified by manual test query                           | SQL script section 5 (expected-error statements)        |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

(The schema has no server code of its own; this confirms nothing regressed.)

## Database Verification (Supabase)

1. **Apply migrations** (PowerShell, repo root):

   ```powershell
   supabase db push
   ```

   Expected: `20260718035` (and 036/037 if you're verifying the whole epic) apply with no errors. AC-1's "fresh database" half: `supabase db reset` on a local/staging project replays all migrations from scratch — expect zero errors. **Do not run `db reset` against the hosted project** (it wipes data).

2. **Open Supabase Studio → SQL Editor → New query**, paste all of `booking-schema.sql` (this folder) and **Run**.

   Expected: one result table where **every row shows `pass = true`** (enum values, reused enum identity, column shapes, FK delete rules, CHECK constraints, RLS enabled, policy counts, indexes).

3. **AC-4 negative tests** — the bottom of the SQL file has two statements commented out under `-- EXPECTED-ERROR TESTS`. Run each **individually** (select the statement, Run):
   - the both-`service_id`-and-`package_id` insert must fail with `violates check constraint "bookings_service_or_package_check"` (name may render as the table's check constraint);
   - the `DELETE FROM services ...` for a service referenced by a `booking_addons` row must fail with `violates foreign key constraint` (RESTRICT). _(This one needs at least one add-on row — create a Grooming booking with an add-on via #51's Postman collection first, or skip until #51 is verified.)_

4. **AC-3 cross-customer RLS test** (needs two seeded customer accounts):
   1. In Studio → **Authentication → Users**, note two customer users' emails.
   2. In the SQL Editor, run the `-- RLS IMPERSONATION TEST` block at the bottom of the SQL file (uncomment it first). It uses `set local role authenticated` + `request.jwt.claims` to impersonate customer A, inserts a booking for customer A (succeeds), then attempts a select/insert as customer B against A's row — the select must return **0 rows** and the insert must **fail**.
   3. Staff SELECT-all: the same block impersonates a staff user and confirms the row **is** visible.

## Notes

- `bookings.status` defaults to `'Confirmed'` per the DB Design sheet; the server sets `Pending` explicitly for the pay-at-counter stub case.
- `booking_addons` has no UNIQUE(booking_id, service_id) — the Design sheet doesn't specify one, so duplicates are allowed (matches "don't invent constraints").
