# Issue #52 Verification: Staff Picker filtering logic + admin toggle (policy_configurations stub)

**Issue:** #52 — feat(booking): Staff Picker filtering logic + admin toggle (policy_configurations stub)
**Owner:** Matthew
**Branch:** `feat/staff-picker-backend`
**Base:** `dev`
**Depends on:** #49, #51 merged
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

Adds the `policy_configurations` **stub** table (only the columns this epic reads: notice period trio + the two Staff Picker toggles) and `staffPicker.service.ts`, the single resolution point for "should the Staff Picker step render for this branch + service type?". When disabled, the flow behaves exactly as though "No preference" were selected — the backend auto-assigns the next `get_staff_availability()`-eligible staff member at confirmation, and the client is never handed a staff list.

## What Changed

- **Added** `supabase/migrations/20260718037_m03_policy_configurations_stub.sql` — `enforcement_mode` enum (`Strict`/`Soft`), the stub table, two unique indexes (one row per branch, exactly one system-wide default row), the seeded default row (3 days / Strict / enabled / both toggles on), and RLS (all-staff read, Admin/Superadmin write). Sprint 5's full M09 epic will `ALTER TABLE` onto this table — flagged in the migration header so the reviewer doesn't re-create it.
- **Added** `server/src/features/booking/services/staffPicker.service.ts` (+spec):
  - `resolveEffectivePolicy(branchId)` — branch row overrides the default row (whole-row override; the stub has no per-column semantics), degrading to the documented defaults if the seeded row was deleted out-of-band;
  - `isStaffPickerEnabled(branchId, category)` — Hotel/Daycare always false; Grooming/Veterinary follow the toggle;
  - `getStaffPickerOptions(...)` — `{ staff_picker_enabled, options }` with "No preference" always first; disabled ⇒ `options: []`, RPC never called;
  - `listAvailableStaff(...)` / `autoAssignStaff(...)` — #49 RPC wrappers (Grooming → Groomer, Veterinary → Veterinarian);
  - `updatePolicyConfiguration(...)` — PATCH semantics; creates a branch override row seeded from the effective policy when none exists (a partial PATCH never silently resets other settings).
- **Modified** `booking.routes.ts` / `booking.controller.ts` — `GET /bookings/staff-picker` (customer+staff, jwt only — customers need it mid-booking-flow), `GET /bookings/policy` (all staff), `PATCH /bookings/policy` (Admin/Superadmin only).

## Acceptance Criteria Map

| AC                                                                | Automated                                          | Manual                  |
| ----------------------------------------------------------------- | -------------------------------------------------- | ----------------------- |
| AC-1 stub table + seeded default row                              | —                                                  | SQL script              |
| AC-2 Admin PATCH per-branch toggle, override row auto-created     | `staffPicker.service.spec.ts`, integration spec    | Postman 3–4, SQL re-run |
| AC-3 disabled toggle ⇒ auto-assign, no staff list exposed         | spec ("RPC not called"), `booking.service.spec.ts` | Postman 5–6             |
| AC-4 enabled ⇒ role-filtered staff via RPC, "No preference" first | spec + integration spec                            | Postman 8               |
| AC-5 non-Admin gets 403 on the write endpoint                     | integration spec                                   | Postman 9               |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Database Verification (Supabase)

1. `supabase db push` (if not already done for the epic).
2. Supabase Studio → **SQL Editor** → paste all of `staff-picker-backend.sql` → **Run**. Every row must show `pass = true` (enum, columns, unique indexes, seeded default row values, RLS policies).

## Postman Verification

Needs one **Admin** (or Superadmin) staff account, one **non-Admin** staff account (e.g. Receptionist), one **customer** account, plus `branch_makati_id` (from Studio → Table Editor → `branches`).

1. Import `staff-picker-backend.postman_collection.json` → collection **Variables** → fill `base_url`, `admin_identifier`/`admin_password`, `staff_identifier`/`staff_password` (the non-Admin), `customer_account_email`/`customer_password`, `branch_makati_id`. Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom; every request's **Test Results** must be green:
   1. **Login Admin** → 200, token captured.
   2. **Login customer** → 200, token captured.
   3. **GET /bookings/policy (Admin)** → 200; a row with `branch_id: null` and the seeded defaults exists (AC-1).
   4. **PATCH disable Grooming picker for Makati (Admin)** → 200; response row has `branch_id = branch_makati_id`, `staff_picker_enabled_grooming = false` — the override row was created by the PATCH (AC-2).
   5. **GET /bookings/staff-picker (customer, Grooming @ Makati)** → 200 with exactly `{ "staff_picker_enabled": false, "options": [] }` — no staff list leaks (AC-3).
   6. **Create a Grooming booking with NO staff_preference (customer)** → 201 and `assigned_staff_id` is non-null — auto-assignment happened server-side while the picker was disabled (AC-3). Fill `pet_id`/`grooming_service_id` variables first (Studio → `pets`, `services`).
   7. **PATCH re-enable Grooming picker for Makati (Admin)** → 200, `staff_picker_enabled_grooming = true`.
   8. **GET /bookings/staff-picker (customer)** again → 200, `staff_picker_enabled: true`, `options[0]` is `{ "type": "no_preference" }`, and every other option has `staff_id`/`display_name`/`profile_photo_url` (the #49 RPC row shape, Groomers only) (AC-4).
   9. **Login non-Admin + PATCH policy** → **403** (AC-5).
4. Cleanup: request 7 already restored the toggle. Delete the request-6 booking (Studio → `bookings`, filter `special_instructions = issue52-postman`).

## Notes

- The read endpoint returns the raw rows (default + overrides) rather than one merged object, so the future Admin panel can show which branches deviate — resolution to an _effective_ policy happens in `resolveEffectivePolicy()`.
- Customers can hit `GET /bookings/staff-picker` (jwt only) but never `GET/PATCH /bookings/policy` — the policy surface is staff-gated at the route level.
