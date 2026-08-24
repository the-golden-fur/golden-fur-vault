# Fix Grooming Availability - Stale 'Paid' Status Bug

Type: Bug fix - one-migration regression, no application code changes.
Branch: `dev` (suggested feature branch: `fix/grooming-availability-paid-status`).

## Bug report

Selecting **Grooming** as the service type in the staff booking flow (`/staff/bookings/new`), after picking a staff member and date, fails the slot-picker's availability call:

```
GET /bookings/availability?branch_id=...&service_category=Grooming&date=2026-08-08&slot_duration_minutes=60
400 (Bad Request)
```

UI shows: `invalid input value for enum booking_status: "Paid"`.

## Root cause

Two migrations redefined `public.get_staff_availability()` one day apart, both branching off the same earlier version (`20260728062`) without knowing about each other:

- **`20260803083_m03_m08_remove_paid_booking_status.sql`** dropped `'Paid'` from the `booking_status` enum entirely (payment tracking moved to the independent `payment_stage` column - see `[[booking-status-automation]]`/`21-staff-queue-overhaul`) and correctly redefined the function's Check 2 to read `status in ('Pending', 'In Progress', 'Completed')`.
- **`20260804092_m03_get_staff_availability_lunch_break.sql`** (one day later, adding the lunch-break check) redefined the _same_ function again, but branched off the pre-083 body - so its Check 2 reverted to `status in ('Pending', 'In Progress', 'Completed', 'Paid')`, silently undoing 083's fix and reintroducing a reference to a status value that no longer exists in the enum.

Since 092 is the last migration to touch this function, every call to `get_staff_availability()` since then has thrown `invalid input value for enum booking_status: "Paid"` at the `status in (...)` predicate. This RPC backs the staff-availability portion of `GET /bookings/availability` (`getDaySlots`), so picking any service category in the Slot Picker that resolves to a staff-role check hits the error - the report reproduced it via Grooming, but Veterinary/Daycare/Pet Assistant-staffed categories are equally affected.

The application (TypeScript) layer was never wrong - `'Paid'` is correctly confined to `PaymentStage` (`payment_stage` column) in both `server/src/features/booking/booking.types.ts` and `client/src/features/booking/booking.types.ts`. This was a pure SQL-migration merge collision.

## Fix

New migration `20260808109_m03_get_staff_availability_fix_paid_status.sql` - `CREATE OR REPLACE` of `get_staff_availability()`, body identical to `20260804092` (operating hours + lunch break + unavailability-block checks) except Check 2 drops `'Paid'` again, matching `20260803083`. No signature change, no caller changes, no application code touched.

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, existing suite still green (this fix is SQL-only; no test files changed).

## Manual Verification

1. Apply the migration: from the repo root, `npm run supabase:push` (or `npm run supabase:reset` for a fresh local database, which also re-runs the seeds and all prior migrations in order).
2. Confirm the function no longer references `'Paid'` - see Section 1 of `fix-grooming-availability-paid-status.sql`.
3. Start the dev servers (`npm run dev` from the repo root).
4. Log in as staff, go to `/staff/bookings/new`.
5. Fill Customer -> Pet -> Branch, pick **Grooming** as Service Type, proceed to Staff & Date.
6. Confirm the Staff & Date step loads normally: no red error banner, no `400` in the Network tab for `GET /bookings/availability`, and staff/slot options render.
7. Repeat step 5-6 for **Veterinary**, **Daycare**, and **Hotel** to confirm the fix isn't Grooming-specific (all four route through the same RPC).
8. Optional regression check: with **Lunch Break** enabled for the branch (Settings -> Policy Configuration), confirm a slot inside the lunch window is still correctly excluded from the staff list - the lunch-break check added by `092` must still work after this fix.
