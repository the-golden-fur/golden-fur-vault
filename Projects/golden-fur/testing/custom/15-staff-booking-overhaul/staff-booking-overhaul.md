# Staff Booking Overhaul

Type: Custom cross-cutting batch spanning the staff/customer booking flow, staff scheduling, and a new Superadmin config surface.
Branch: `15-staff-booking-overhaul` (suggested; based off `dev`).

## Scope

1. **Merged Date/Time + Staff step.** The Slot Picker's fixed grid of time-slot buttons is replaced by a hybrid time input (`TimeSlotInput`) - a native `<input type="time">` (typeable, bounded by that date's branch operating hours) plus a dropdown of the day's real slots. For Grooming/Veterinary bookings, the Staff Picker no longer gets its own stepper page - it renders inline, directly beneath the time input, refetching automatically once a time is committed. Applies to both `/portal/book` and `/staff/bookings/new` (they share `CustomerBookingFlowPage`).
2. **Staff "days off" rename + Entire Day option.** User-facing copy only (button/page text) - "unavailability" reads as "day(s) off" everywhere a staff member or reviewer sees it; no table/column/function/route was renamed. New: an "Entire day" checkbox when requesting a day off (self or on-behalf-of another staff member), which resolves to that date's full branch operating-hours window server-side (`is_full_day` column) instead of a manually-picked start/end range. Goes through the exact same pending-vs-auto-approved rule as any other custom-range request.
3. **Superadmin System Configuration.** New page for editing branch name/address/contact number/timezone/operating hours - the same `operating_hours` column the Slot Picker and days-off shift-end resolution already read, but nothing could write to it before this. Deliberately Superadmin-only (narrower than every other maintenance config page, which are all Admin+Superadmin).
4. **Care Instructions catalog wiring (staff view only).** The Hotel booking flow's feeding/medication rows go from plain freetext to a searchable catalog dropdown (reusing `CatalogComboBox`, already built for Hotel Check-in), a two-option "Owner will bring it / Staff will purchase it" radio, and a price x quantity cost estimate when staff-supplied. Staff-view-only because the underlying catalog endpoints are staff-gated - the customer portal is unaffected. Hotel Check-in's own pre-fill now carries this data through instead of discarding it.
5. **Bookings queue search + sort.** `ReceptionistBookingsQueuePage` gets a search box (pet/owner name) and a sort dropdown (soonest/latest/pet name/owner name), matching `HotelBookingPicker`'s existing pattern. See "Investigation finding" below for why this is scoped down from the original bug report.

## Investigation finding: the reported "status filter is failing" and "GET query doesn't work" were not code defects

Careful review of both the bookings queue and Hotel Check-in query paths (client `BOOKING_STATUSES` enum, server validator, `listBookings` service filter, `QueueFilterBar`'s date-range math, the prior status-unification migrations) found no mismatch, no stale literal, and no RLS interference (the service uses the service-role Supabase client). There is also no `bookings` seed data anywhere in `supabase/seeds/` - on a fresh/reset database, both pages showing "no bookings match these filters" is the expected result of zero rows existing, not a query bug. If this still reproduces against a booking you've confirmed exists in Supabase's table editor, that's a genuine new finding - see verification step 6 below, which is designed to catch it if so.

## Migrations (apply in order, after `20260728062`)

1. `20260728063_m01_staff_unavailability_blocks_full_day.sql` - adds `staff_unavailability_blocks.is_full_day boolean not null default false`.
2. `20260728064_m01_branches_config_rls.sql` - adds an UPDATE RLS policy on `branches`, Superadmin-only.

## New API surface

- `GET /branches` - full branch rows (name/address/contact_number/is_vet_branch/operating_hours/timezone). Superadmin-only.
- `GET /branches/:id` - single branch. Superadmin-only.
- `PATCH /branches/:id` - update a branch. Superadmin-only.
- `GET /bookings/availability` - response shape changed from `{ slots }` to `{ slots, window }`, where `window` is `{ open, close } | null` for the requested date.
- `POST /staff/:id/unavailability` - accepts two new optional fields, `is_full_day: boolean` and `date: string` (YYYY-MM-DD), as an alternative to `start_time`/`end_time`.
- `POST /bookings` - `hotel_preferences.feeding[]` items accept optional `food_catalog_id`/`brought_by_customer`; `hotel_preferences.medications[]` items accept optional `medication_catalog_id`/`brought_by_customer`.

## Files changed (high level)

**Migrations**: the 2 listed above.

**Server**: `features/booking/services/availability.service.ts` (`resolveOperatingWindow`), `features/booking/booking.controller.ts` (availabilityController), `features/booking/booking.types.ts` + `modules/validators/booking.validator.ts` (hotel-preferences catalog fields), `features/staff/services/unavailabilityBlock.service.ts` (`resolveDateWindow`, `isFullDay`/`date` params), `features/staff/staff.types.ts` (`is_full_day`), `features/staff/staff.controller.ts` (validator + controller wiring), new `features/branches/` (`branches.types.ts`, `branches.controller.ts`, `branches.routes.ts`, `services/branches.service.ts`, `modules/validators/branches.validator.ts`), `shared/app.routes.ts` (mounts `branchesRoutes`).

**Client**: new `features/booking/components/TimeSlotInput/*`, `features/booking/components/SlotPicker/SlotPicker.tsx` (uses TimeSlotInput), `features/booking/api/booking.api.ts` (`DayAvailability` shape), `features/booking/booking.types.ts` (`OperatingWindow`, hotel-preferences catalog fields), `features/booking/pages/CustomerBookingFlowPage/*` (merged slot+staff step, catalog-aware Care Instructions rows, `SupplierChoice`), `features/booking/pages/ReceptionistBookingsQueuePage/*` (search/sort), `features/staff/components/forms/UnavailabilityBlockForm/*` (copy + Entire Day), `features/staff/components/badges/UnavailabilityBlockBadge/*` + `components/review/UnavailabilityReviewCard/*` (copy + Full day off display), `features/staff/pages/UnavailabilityApprovalQueuePage/*` + `pages/StaffProfilePage/*` + `pages/StaffManagementPage/*` (copy), `features/staff/config/staffDashboard.config.ts` (copy + new tile), `features/staff/staff.types.ts` + `modules/validators/staff.validator.ts` (Entire Day fields), `features/hotel/pages/HotelCheckInPage/HotelCheckInPage.tsx` (prefill now uses catalog fields when present), new `features/maintenance/pages/SystemConfigurationPage/*` + `features/maintenance/api/branches.api.ts` + `features/maintenance/maintenance.types.ts` (`Branch`/`OperatingHours`), `features/maintenance/maintenance.routes.tsx`.

## Automated Verification

From `server/`:

```powershell
npx tsc -b --noEmit
npx vitest run
```

Expected: typecheck clean, **645/645 tests pass** (71 files).

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
```

Expected: typecheck clean, **446/446 tests pass** (104 files).

Both confirmed clean as of this revision. (`npx eslint .` also confirmed clean in both - the client run surfaced and fixed 3 new `react-hooks/set-state-in-effect` errors along the way, all in code this batch added.)

## Manual Verification

You'll need: the `server/` and `client/` dev servers running (`npm run dev` from the repo root), a Supabase project with migrations `20260728063`-`20260728064` applied (in order, after `20260728062`), and Postman for the API-level checks.

### 0. Apply the migrations

1. From the repo root: `npm run supabase:push` (or `npm run supabase:reset` for a fresh local database, which also re-runs the seeds).
2. If you reset, re-run the seed scripts so login credentials, pets, branches, and services exist.

### 1. Schema checks - `staff-booking-overhaul.sql`

Open the SQL file in this folder in Supabase Studio's SQL Editor. Run Sections 1-4 (read-only) - confirm `is_full_day` exists with the right default, the new `branches` UPDATE policy exists and is Superadmin-scoped, `branches` still carries its full config columns, and the days-off status trigger from migration `...019` is untouched. Run Section 5 (wrapped in `begin`/`rollback`) - confirm a self-requested Entire Day lands `pending` and an on-behalf-of one lands `approved`, both `is_full_day = true`, then confirm the follow-up `select count(*)` shows `0` leftover rows.

### 2. API checks - `staff-booking-overhaul.postman_collection.json`

Fill in the collection variables (Superadmin/Admin/Receptionist logins, a real `branch_id`, `pet_id`, `customer_id`, a Hotel-category `hotel_service_id`, a real `food_catalog_id`/`medication_catalog_id` from the Hotel Food/Medication Catalog admin pages, and `target_staff_id` for the days-off request). Run groups 1-3 first (logins), then groups 4-8 in any order.

Expected: every request's inline test script passes, specifically:

1. `GET /branches` succeeds for Superadmin with full config fields, and returns `403` for Admin.
2. `PATCH /branches/:id` updates operating hours and rejects a close time that isn't after open.
3. `GET /bookings/availability` returns both `slots` and `window`.
4. An Entire Day request created by an Admin for another staff member is auto-approved with `is_full_day: true`; a bare `is_full_day: true` with no `date` is rejected `400`.
5. A Hotel booking's `hotel_preferences.feeding[]`/`medications[]` round-trip the catalog fields exactly as sent; `hotel_preferences` is still rejected on a non-Hotel booking.
6. `GET /bookings?status=Pending` returns only `Pending` rows (directly tests whether the originally-reported "status filter is failing" claim reproduces against real data).

### 3. Merged Date/Time + Staff step

1. At `/staff/bookings/new` and `/portal/book`, select a Grooming or Veterinary service for today. Confirm the time input won't accept/commit a time before the current clock time, and the dropdown only offers times inside that branch's operating hours for the selected day.
2. Commit a time - confirm the available-staff list appears immediately beneath the time input on the same step (no separate "Staff" tab in the stepper), and re-fetches if you change the date or time.
3. Switch to Hotel or Daycare - confirm there's no staff list at all, just the hybrid time input, and picking the (single, day-level) Hotel slot still shows the cage-availability line.

### 4. Days off + Entire Day

1. As a plain staff member, open your profile's Days Off section. Confirm the button reads "Take the rest of today off" (not "Unavailable until end of shift") and the submit button reads "Request day(s) off".
2. Check "Entire day", pick a date, and submit. Confirm it's created as `pending` (since it's your own request) and, once an Admin/Supervisor/Superadmin approves it, your profile badge reads "Full day off" (not a time range).
3. As an Admin, open Staff Management, expand another staff member, check "Entire day" for them, and submit - confirm it's auto-approved immediately (not pending), and the Days Off Approval Queue page title reflects the new naming.

### 5. Superadmin System Configuration

1. Log in as Superadmin, open the new "System Configuration" tile from the admin dashboard (`/staff/admin/maintenance/system-configuration`). Edit a branch's operating hours for a day you'll test with, save, and confirm the success message appears.
2. Go create a booking for that branch/day and confirm the Date & Time step's available times reflect the new hours.
3. Log in as a plain Admin (not Superadmin) and confirm navigating to the same URL redirects you to `/staff/profile`.

### 6. Care Instructions catalog wiring

1. At `/staff/bookings/new`, pick a Hotel service, reach Care Instructions. Check a meal time - confirm the food type field is now a searchable dropdown (typing still works for a freetext entry with no catalog match).
2. Pick a real catalog item - confirm a two-option radio appears ("Owner will bring it" / "Staff will purchase it"), defaulting to "Owner will bring it".
3. Select "Staff will purchase it" and change the quantity - confirm the displayed estimate updates to catalog price x quantity.
4. Repeat for a medication row (dropdown + radio + flat catalog price - no quantity concept for medications, since dose isn't a count).
5. Complete the booking, then start Hotel Check-in for that same booking - confirm the catalog selection and supplier choice carried over instead of showing blank/freetext.

### 7. Bookings queue search/sort + the "failing query" claim

1. Create a real booking (any status) at a branch/day you can find easily.
2. On `/staff/bookings/queue`: confirm it appears, confirm filtering by its exact status shows it (and other statuses hide it), and confirm the new search box (by pet/owner name) and sort dropdown (soonest/latest/pet name/owner name) work.
3. Repeat the same real-booking check on `/staff/hotel/check-in` for a Hotel booking specifically.
4. If either still shows nothing for a booking you've confirmed exists in Supabase's table editor, that contradicts this batch's investigation finding above - bring it back as a concrete repro (booking id, exact filters used) for further debugging.
