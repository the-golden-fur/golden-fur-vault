# Issue #72 Verification: hotel_stays table

**Issue:** #72 — chore(db): hotel_stays table
**Owner:** Matthew
**Branch:** `chore/hotel-stays-schema`
**Base:** `dev`
**Depends on:** #71 merged; Sprint 2 Epic B `bookings` table
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

Creates the M05 hotel-stay execution schema so #75 has a real table and RLS to build against: `hotel_stays` — one row per confirmed Hotel booking, from check-in through checkout.

## What Changed

- **Added** `supabase/migrations/20260727051_m05_create_hotel_stays_schema.sql`:
  - `hotel_stays` with the exact DB Design column set: `booking_id` (`UNIQUE`, FK to `bookings`, mirroring `grooming_sessions.booking_id`'s convention), `pet_id` (denormalized, FK to `pets`), `cage_id` (FK to `cages`), `status` (plain text `Active`/`Completed`, matching `daycare_sessions.status`'s established convention), `check_in_at`/`scheduled_check_out_date`/`actual_check_out_at`, `downpayment_amount` (copied from `bookings.downpayment_amount` at check-in), `extension_fee` (nullable — NULL means "no fee applied", never zero), `notify_opt_in` (default `false`), `created_by_staff_id`, `created_at`/`updated_at`.
  - Indexes on `pet_id` and `status`.
  - **RLS:** Receptionist/Admin/Supervisor may SELECT/INSERT/UPDATE rows at their own branch, resolved via a join through `cages.branch_id` (this table carries no `branch_id` column of its own); Superadmin unrestricted. No customer-facing policy at all — matching `daycare_sessions`' staff-only convention (customers see booking status via M03, not this execution record).

## Acceptance Criteria Map

| AC                                                                    | Where verified                           |
| --------------------------------------------------------------------- | ---------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with #71 applied)         | `supabase db push` below                 |
| AC-2 columns/constraints/defaults per DB Design; `booking_id` UNIQUE  | SQL script section 1                     |
| AC-3 uniqueness test: two rows cannot reference the same `booking_id` | SQL script's expected-error test         |
| AC-4 RLS: no customer-role query can read or write this table         | SQL script section 2 + manual test below |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Database Verification (Supabase)

1. **Apply migrations:**

   ```powershell
   supabase db push
   ```

   Expected: `20260727051` applies cleanly on top of `050`.

2. **Studio → SQL Editor**, paste `hotel-stays-schema.sql` (this folder) and **Run** — every row `pass = true`.

3. **AC-3 negative test** — the SQL file's `EXPECTED-ERROR TEST` block (commented) inserts a second `hotel_stays` row for a `booking_id` that already has one. Run it individually (needs one existing `hotel_stays` row — create one via #75's Postman collection first). Expected: `ERROR ... violates unique constraint "hotel_stays_booking_id_key"`.

4. **AC-4 manual RLS test** — uncomment the `RLS IMPERSONATION TEST` block, fill in one Customer UUID and one Receptionist UUID, run the whole block. The customer's SELECT must return 0 rows even on a `hotel_stays` row that exists; the Receptionist's (same branch) must return 1.

## Notes

- `hotel_stays.downpayment_amount` is copied from `bookings.downpayment_amount` at check-in time (#75), not read live from `bookings` on every query — `bookings.downpayment_amount` already exists from Sprint 2 Epic B (M03 Process 1's 50% Hotel downpayment), so no new booking-side column was needed here.
