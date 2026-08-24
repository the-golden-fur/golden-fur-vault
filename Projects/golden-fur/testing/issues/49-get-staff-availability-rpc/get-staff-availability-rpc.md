# Issue #49 Verification: get_staff_availability() Postgres RPC

**Issue:** #49 — feat(db): get_staff_availability() Postgres RPC (ports Sprint 1 #27)
**Owner:** Matthew
**Branch:** `feat/get-staff-availability-rpc`
**Base:** `dev` (must include #50's migration — see Sequencing Note below)
**Depends on:** #50 merged
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

Replaces the Epic A-1 (#12) per-staff boolean `get_staff_availability()` with the real set-returning RPC: given a role + branch + time window (and optionally one specific staff member), it returns every eligible staff member `(staff_id, display_name, profile_photo_url)` after the 3-condition check — branch operating hours, no overlapping **Confirmed** booking, no overlapping **approved** Unavailability Block. This ports Sprint 1 Epic B's `staffAvailability.service.ts` (#27) TS reference implementation into SQL, and finally makes the booking-overlap condition real (the `...014`/`...031` versions only had a `to_regclass` placeholder because no `bookings` table existed).

**Sequencing note (Guide):** although #49 is numbered before #50, its migration is numbered **after** #50's (`...036` vs `...035`) and must merge after it — the booking-overlap condition needs the `bookings` table. Say this in the PR description so the reviewer isn't confused by the apparent inversion.

**Numbering note:** the Guide assumed Epic A ended at `...023`; the actual last merged migration on `dev` is `20260715034`, so this epic is renumbered per the Guide's own Handoff State instruction: #50 → `...035`, #49 → `...036`, #52 → `...037`.

## What Changed

- **Added** `supabase/migrations/20260718036_m03_get_staff_availability_rpc.sql`:
  - **Drops** the old boolean overload `get_staff_availability(uuid, timestamptz, timestamptz)`. The Guide asks for `CREATE OR REPLACE` "so no caller needs to change", but Postgres cannot change a function's return type in place — and no production caller ever invoked the boolean version (Sprint 1's read path is the TS service), so the drop is safe. Flag this in the PR.
  - **Creates** `get_staff_availability(p_role staff_role, p_branch_id uuid, p_requested_start timestamptz, p_requested_end timestamptz, p_staff_id uuid default null, p_exclude_booking_id uuid default null) returns table(staff_id, display_name, profile_photo_url)`.
  - `p_staff_id` narrows the set to one staff member (the confirmation-time re-verification call shape, AC-5); NULL lists all eligible staff (the Slot/Staff Picker shape).
  - `p_exclude_booking_id` is a small **addition beyond the Design sheet's param list**: #54's reschedule capacity re-check needs it so a booking doesn't collide with itself when moved within its own window. Documented in the migration header; mention in the PR.
  - Only `status = 'approved'` unavailability rows exclude staff — pending/denied are ignored (Jul 11, 2026 redesign, AC-3). Only `status = 'Confirmed'` bookings conflict (AC-2). Inactive staff (`is_active = false`) never appear.
  - `SECURITY DEFINER` + `search_path = public` (same rationale as `deactivate_expired_promos`): the result exposes only the three fields the customer-facing Staff Picker is specified to show, and customer sessions have no `staff_profiles` read policy of their own.

## Acceptance Criteria Map

| AC                                                                | Where verified            |
| ----------------------------------------------------------------- | ------------------------- |
| AC-1 no-conflict window returns every eligible staff member       | SQL script check `ac1_*`  |
| AC-2 Confirmed-booking overlap excludes the staff member          | SQL script checks `ac2_*` |
| AC-3 approved block excludes; pending/denied do NOT               | SQL script checks `ac3_*` |
| AC-4 outside operating hours → empty set                          | SQL script check `ac4_*`  |
| AC-5 specific staff_id returns them only if all 3 conditions pass | SQL script checks `ac5_*` |

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all test files pass (the RPC's server-side consumers are covered in `staffPicker.service.spec.ts` / `capacity.service.spec.ts`), typecheck silent, lint 0 errors (3 pre-existing `no-console` warnings in auth controllers are expected and unchanged).

## Database Verification (Supabase)

1. **Push the migrations.** In PowerShell at the repo root:

   ```powershell
   supabase db push
   ```

   Expected: `20260718035`, `20260718036`, `20260718037` all apply cleanly. If you get "migration history does not match", run `supabase migration list` and confirm nothing after `20260715034` was already applied.

2. **Open Supabase Studio → your project → SQL Editor** (left sidebar, the `>_` icon) → **New query**.

3. Open this folder's `get-staff-availability-rpc.sql` in your editor, copy **the whole file**, paste it into the SQL Editor, and click **Run** (or Ctrl+Enter).

   The script is self-contained: it creates two clearly-named test staff members (`issue49-groomer-a/b`) at your first branch, a Confirmed booking overlapping the test window for groomer B, and three unavailability blocks (approved / pending / denied), then runs the RPC once per acceptance criterion.

   **Expected output:** one result table with a `check_name` and `pass` column — **every row must show `pass = true`**:

   | check_name                                   | pass |
   | -------------------------------------------- | ---- |
   | ac1_both_groomers_eligible_in_clear_window   | true |
   | ac2_groomer_b_excluded_by_confirmed_booking  | true |
   | ac2_cancelled_booking_does_not_exclude       | true |
   | ac3_approved_block_excludes_groomer_a        | true |
   | ac3_pending_or_denied_block_does_not_exclude | true |
   | ac4_outside_operating_hours_empty_set        | true |
   | ac5_specific_staff_pass_returns_exactly_one  | true |
   | ac5_specific_staff_fail_returns_empty        | true |
   | old_boolean_overload_dropped                 | true |

4. **Clean up:** the bottom of the SQL file has a `-- CLEANUP` section that is commented out. After you've screenshotted/confirmed the results, select just those lines, uncomment them (Ctrl+/), and run them to remove the `issue49-*` test rows.

## Notes / Decisions for the Reviewer

- The old boolean overload had to be dropped (return-type change) — see What Changed.
- `p_exclude_booking_id` added beyond the Design sheet for #54's reschedule re-check.
- Multi-day windows behave like the Sprint 1 version: the operating-hours check evaluates the window against `p_requested_start`'s day; a window crossing midnight fails the hours check by design (bookings are same-day).
