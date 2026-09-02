# Issue #27 Verification: staffAvailability.service.ts

**Issue:** #27 — feat(staff): staffAvailability.service.ts
**Owner:** Alarie
**Branch:** `feat/staff-availability-service`
**Base:** `dev`
**Depends on:** #24 merged
**Sprint:** Sprint 1 — M01 Staff Auth & Access Control

## Overview

Adds a read-only TypeScript service that, given a `staff_id` and a date range, intersects the staff member's branch `operating_hours` for each day in range with the inverse of that staff member's **approved** `staff_unavailability_blocks`, and returns the resulting available windows. It is explicitly **not** `get_staff_availability()` (the existing Postgres RPC at `supabase/migrations/20260701014_m01_create_get_staff_availability_function.sql`) — it's a TypeScript reference implementation of the same 3-condition shape for Sprint 2's M03 Slot Picker / Staff Picker to consume directly, and for whichever Sprint 2 epic owns M03 to port into SQL later.

**Scope note — schema dependency on Issue #29 (flagged and resolved before implementation):** this issue's own dev notes say to filter on `status = 'approved'` from the start, and to "land #29 first (or coordinate schema availability) so this service isn't written against columns that don't exist yet." At the time of implementation, `staff_unavailability_blocks` had no `status` column — Issue #29 (the full request/approval backend: review endpoint, pending-list endpoint, no-self-review RLS) had not been merged. Rather than block on #29 or write the service against a schema that doesn't exist, migration `20260711019_m01_staff_unavailability_blocks_add_status.sql` lands **only the schema piece #27 hard-depends on** — the `unavailability_block_status` enum, the four new columns (`status`, `is_quick_action`, `reviewed_by`, `reviewed_at`, `denial_reason`), and the `enforce_unavailability_block_status()` `BEFORE INSERT` trigger — copied verbatim from the Epic B Guide's #29 reference SQL. It also drops the now-unsafe "Staff can update their own unavailability blocks" RLS policy (a staff member must never be able to flip their own row's `status` via a direct table update once the column exists). **Issue #29's actual scope — the `PATCH .../review` and `GET .../pending` endpoints, the service-layer review logic, and the "no self-review" RLS tightening (migration `...013` in the Guide) — is unaffected and remains separate, future work.**

This mirrors the precedent already set by Issue #24's verification doc, which found the Guide's Supervisor on-behalf-of claim didn't match the shipped RLS and documented the discrepancy rather than silently building against the aspirational spec.

**Also flagged, not blocking:** the Guide's Handoff State says `get_staff_availability()` "was scoped out of Epic A-1" and would be created fresh in Sprint 2 — but it already exists in `dev` (migration `20260701014`, Issue #12 in this repo's actual numbering). This doesn't affect #27 (which never touches that function), but is worth reconciling in the Guide separately.

## What Changed

- **Added** `supabase/migrations/20260711019_m01_staff_unavailability_blocks_add_status.sql` — prerequisite schema (see above). Not part of #27's originally listed Affected Files; added because #27 cannot function or be verified against a live DB without it.
- **Added** `server/src/features/staff/services/staffAvailability.service.ts`:
  - `getStaffAvailability({ staffId, rangeStart, rangeEnd, bookingOverlap? })` — the main entry point. `rangeStart`/`rangeEnd` are `YYYY-MM-DD` branch-local calendar dates, inclusive.
  - Looks up the staff member's branch (`404` if the staff profile doesn't exist, `400` if the branch can't be resolved), then for each calendar day in range: looks up that weekday's `operating_hours` entry, converts `open`/`close` into real UTC instants for that specific date using the branch's IANA `timezone` (same offset-resolution approach as `unavailabilityBlock.service.ts`'s `resolveShiftEnd`), and subtracts any **approved** unavailability blocks overlapping that window.
  - A day with no `operating_hours` entry (branch closed) returns `availableWindows: []` for that date rather than erroring.
  - `bookingOverlap` is accepted and structured (`{ considerBookings?: boolean }`) but always returns a clearly-labeled placeholder (`{ considered: false, message: '...' }`) — it never throws and never silently pretends to have checked bookings, since the `bookings` table doesn't exist until Sprint 2.
  - The unavailability-block query is filtered with `.eq('status', 'approved')`, so pending/denied rows never reduce availability (AC-5).
- **Added** `server/src/features/staff/services/staffAvailability.service.spec.ts` — 9 unit tests covering AC-1 through AC-5 plus edge cases (closed day, invalid range, missing staff/branch).

### Why no controller/route/Postman collection

Unlike `unavailabilityBlock.service.ts`, this issue's Affected Files list is just the service + its spec — there's no HTTP endpoint. It's an internal function for Sprint 2's booking flow to import and call directly, not something exposed over the API in this sprint. There's nothing for a Postman collection to exercise.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all server test files pass (9 new tests in `staffAvailability.service.spec.ts`; 172/172 across the whole server test suite as of this branch), `tsc --noEmit` produces no output, `eslint .` reports 0 errors (pre-existing `no-console` warnings in unrelated auth controllers are expected and unchanged).

## Structural Verification

1. Confirm the new files exist:

   ```powershell
   Get-ChildItem server/src/features/staff/services -Filter "staffAvailability*"
   ```

   Expected: `staffAvailability.service.ts`, `staffAvailability.service.spec.ts`.

2. Confirm the service is not wired into any route (by design — see above):

   ```powershell
   Select-String -Path server/src/features/staff/staff.routes.ts -Pattern "staffAvailability|getStaffAvailability"
   ```

   Expected: no matches.

## Database Verification (prerequisite schema migration)

Needed because AC-1, AC-3, and AC-5 depend on real DB behavior (the `status` column existing and being set correctly by the trigger), not just the TypeScript logic.

1. **Push the migration** to your linked Supabase project:

   ```powershell
   supabase db push
   ```

   If the project isn't linked yet, run the Supabase login/link steps first (see your Supabase project's connection string in the dashboard under Project Settings → Database).

2. **Confirm the columns exist** — in Supabase Studio → SQL Editor, run:

   ```sql
   select column_name, data_type, column_default
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'staff_unavailability_blocks'
   order by ordinal_position;
   ```

   Expected: `status`, `is_quick_action`, `reviewed_by`, `reviewed_at`, `denial_reason` are present alongside the original columns.

3. **Run the verification SQL script** — open Supabase Studio → SQL Editor, paste in the contents of:

   ```text
   testing/docs/issues/27-staff-availability-service/staff-availability-service.sql
   ```

   and run it. This script creates a test staff member and three unavailability blocks (one admin-created "on behalf of" block, one self-requested custom-range block, one self-requested block that's then marked denied), then checks the trigger assigned statuses correctly and that a `status = 'approved'` filter (the same filter `staffAvailability.service.ts` uses) includes only the on-behalf-of block.

4. **Confirm the expected results** (shown as a single result row):
   - `approved_block_status` = `approved`
   - `pending_block_status` = `pending`
   - `denied_block_status` = `denied`
   - `approved_rows_in_range` = `1`
   - `pending_or_denied_rows_in_range` = `2`

   The script cleans up its own test data at the end (safe to re-run).

## Acceptance Criteria Checklist

- [x] **AC-1:** No approved blocks → full branch operating-hours window returned for each day in range — unit test `AC-1: returns the full operating-hours window...`.
- [x] **AC-2:** An approved block partially overlapping a day's hours → remaining sub-window(s) returned — unit test `AC-2: returns the remaining sub-windows...`.
- [x] **AC-3:** An approved block covering the entire day's hours → no available windows for that day — unit test `AC-3: returns no available windows...`.
- [x] **AC-4:** The booking-overlap parameter is accepted/structured and returns a clearly-labeled placeholder, never throws or silently mis-succeeds — unit test `AC-4: accepts a booking-overlap param...`.
- [x] **AC-5:** Pending/denied blocks never reduce availability (only `status = 'approved'` is queried) — unit test `AC-5: filters the unavailability-block query to status = approved...`; DB-level check via `staff-availability-service.sql` (`pending_or_denied_rows_in_range` excluded from `approved_rows_in_range`).
