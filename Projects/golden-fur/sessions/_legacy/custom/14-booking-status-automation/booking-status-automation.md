# Booking Status Automation

Type: Custom cross-cutting refactor - a fully automated booking lifecycle replacing the old payment-gated `Confirmed` status, plus a second pass on date/time picker accuracy on top of [13-session-and-hotel-booking-fixes](../13-session-and-hotel-booking-fixes/session-and-hotel-booking-fixes.md).
Branch: `dev` (suggested feature branch: `feat/booking-status-automation`).

## Scope

1. **No more manual "staff confirms a booking."** There never actually was a manual confirm step (status was always set automatically) - the `Confirmed` label just read as if one existed, sitting confusingly next to `Completed`. It's retired outright.
2. **New unified lifecycle**, replacing `Pending → Confirmed → Completed` (plus `Cancelled`/`No-show`) with: **Pending** (booked, appointment hasn't started) → **In Progress** (a manual **Start** action, or physical check-in for Hotel/Daycare) → **Completed** (a manual **Complete** action or checkout) → **Paid** (automatic on Complete for an already-confirmed online payment, otherwise a manual **Mark as Paid** action). **No-show** is now a lazy, automatic transition: a Pending booking whose own scheduled time has passed and was never Started flips to No-show the next time it's read - there is no cron/scheduled-job infrastructure in this app, so this happens on read (`GET /bookings`, `GET /bookings/:id`), not on a timer.
3. **Every booking now holds its capacity/staff-time slot from the moment it's created** (`Pending` onward), not just once "Confirmed" - closing a latent double-booking gap where two pay-at-counter customers could both land a `Pending` booking for the same slot, since only `Confirmed` rows used to count against capacity.
4. **Unavailability is caught at the booking steps themselves** - the Slot Picker (`GET /bookings/availability`) and the submission-time capacity check both already run against branch operating hours, staff availability, and cage/session capacity; this batch doesn't change that contract, but the status unification is what makes "occupies capacity" consistent everywhere (see `ACTIVE_BOOKING_STATUSES` below) instead of only ever meaning `Confirmed`.
5. **Bookings queue (`/staff/bookings/queue`)** - can no longer Reschedule or Cancel a booking whose own scheduled time has already passed (previously any `Confirmed`/`Pending` booking showed both actions regardless of how overdue it was). New **Start**/**Complete**/**Mark as Paid** buttons per row, matching the booking's current status.
6. **Date/time picker accuracy, round 2** - a genuine regression in [batch 13](../13-session-and-hotel-booking-fixes/session-and-hotel-booking-fixes.md)'s own past-time fix: Hotel was fully exempt from the past-time filter (by design, for its single day-level slot), but that exemption never checked whether the _entire requested date_ had already passed - so navigating the Slot Picker back to a date days ago still showed a bookable Hotel slot. Fixed. The Slot Picker (client) also now refuses to navigate to a past date at all (`min` on the date input, "Previous day" disabled at today), and Hotel's slot now shows live cage-availability numbers instead of just an enabled/disabled button with no explanation.

## Corrections / decisions

- **Full unification, not a thin relabeling.** The request asked to unify Grooming (`grooming_sessions.status`), Veterinary (`consultations.status`), and Hotel (`hotel_stays.status`) onto `bookings.status` as the single source of truth. All three per-module status columns (and `started_at`/`completed_at` where they existed) are **dropped** by migration - every read/write for those categories now goes through `bookings.status`/`started_at`/`completed_at`/`paid_at` directly, closing three pre-existing gaps where a module's own completion action (Daycare checkout, Hotel checkout, Veterinary consultation completion) never synced back to `bookings.status` at all.
- **Daycare is the one deliberate exception.** `daycare_sessions.booking_id` is nullable - a walk-in Daycare session legitimately has no booking to defer to. `daycare_sessions.status` is kept exactly as-is (still `Active`/`Completed`, unchanged) for every session, walk-in or booked. What's new: check-in/checkout for a booking-linked session now _also_ calls `startBooking`/`completeBooking` to keep `bookings.status` in sync, closing that specific gap without touching the column that has to keep working for walk-ins.
- **Paid has two triggers, both landing on the same transition.** `completeBooking()` (In Progress → Completed) checks the booking's own `payment_method`/`payment_confirmed`: if it was an online method (GCash/Maya) already confirmed at booking time, it skips straight to **Paid** in the same call (the money was already collected before the service even started). Every pay-at-counter booking - Cash/Card/Bank Transfer/Grabmart/Pickaroo, or Veterinary, which never had a payment gate at all - lands on **Completed** and waits for a manual **Mark as Paid**, which is restricted server-side to money-handling roles (Cashier/Receptionist/Admin/Supervisor/Superadmin - not Groomer/Veterinarian/Pet Assistant, who can Start/Complete but never touch payment).
- **No cron infrastructure exists in this app**, so No-show is a _lazy_ transition: `listBookings`/`getBookingById` check, on every read, whether any `Pending` row's `scheduled_start` has passed, and bulk-update those to `No-show` before returning - not a background job. A row that flips mid-request is also re-filtered out of an explicit `status=Pending` query result, so a caller never sees a stale match.
- **`bookings_staff_confirmed_idx` (the old partial index keyed to `status = 'Confirmed'`) is replaced**, not left dangling - the new `bookings_staff_active_idx` keys off the full `ACTIVE_BOOKING_STATUSES` set (`Pending`/`In Progress`/`Completed`/`Paid`), matching what `get_staff_availability()`'s booking-conflict check and every capacity query now use instead of the retired `'Confirmed'` literal.
- **Hotel's single day-level Slot Picker candidate stays exempt from the past-_time_ filter** (same-day Hotel booking must keep working all day, exactly as batch 13 established) - what changed this round is that it's no longer exempt from the past-_date_ check. A fully past date (any category) now returns no slots at all, computed once in branch-local time before any per-category logic runs.
- **Every existing `Confirmed` row in the database is backfilled to `Pending`** by the enum-migration itself (a `Completed` row becomes `Paid` if it was already payment-confirmed or Veterinary, otherwise stays `Completed`) - a one-time, best-effort heuristic for this dev/seed database, not a production data-migration concern.

## Migrations (apply in order, after `20260728057`)

1. `20260728058_m03_unify_booking_status.sql` - replaces the `booking_status` enum (`Pending`/`In Progress`/`Completed`/`Paid`/`Cancelled`/`No-show`), backfills existing rows, adds `bookings.started_at`/`completed_at`/`paid_at`, replaces the capacity partial index.
2. `20260728059_m04_drop_grooming_session_status.sql` - drops `grooming_sessions.status`/`started_at`/`completed_at` + the `grooming_status` enum.
3. `20260728060_m07_drop_consultation_status.sql` - drops `consultations.status`/`completed_at`.
4. `20260728061_m05_drop_hotel_stay_status.sql` - drops `hotel_stays.status`.
5. `20260728062_m03_get_staff_availability_unified_status.sql` - updates the `get_staff_availability()` RPC's booking-conflict check to the new status set.

## New API surface

- `POST /bookings/:id/start` - Pending → In Progress. Any staff role.
- `POST /bookings/:id/complete` - In Progress → Completed (or → Paid automatically for an already-confirmed online payment). Any staff role.
- `POST /bookings/:id/mark-paid` - Completed → Paid. Restricted to Cashier/Receptionist/Admin/Supervisor/Superadmin.

## Files changed (high level)

**Migrations**: the 5 listed above.

**Server** (shared substrate): `features/booking/booking.types.ts` (new enum, `ACTIVE_BOOKING_STATUSES`/`FINISHED_BOOKING_STATUSES`/`CANCELLABLE_BOOKING_STATUSES`/`RESCHEDULABLE_BOOKING_STATUSES`/`ONLINE_PAYMENT_METHODS`/role lists), `services/booking.service.ts` (`startBooking`/`completeBooking`/`markBookingPaid`, `applyNoShowTransition`, removed the Confirmed payment gate), `services/capacity.service.ts` (status-set queries, renamed `listOverlappingConfirmedBookings` → `listOverlappingActiveBookings`), `services/availability.service.ts` (past-date guard + `cage_capacity_remaining`/`cage_capacity_total`), `services/reschedule.service.ts`/`cancellation.service.ts` (new status sets + past-due guard on reschedule), `modules/validators/booking.validator.ts`, `booking.controller.ts`/`booking.routes.ts` (3 new endpoints).

**Server** (per-module rewiring): `features/grooming/{grooming.types,services/grooming.service,modules/validators/grooming.validator,grooming.controller}.ts`, `features/veterinary/{veterinary.types,services/consultation.service,services/currentPrescription.service,services/followUp.service}.ts`, `features/daycare/services/{daycareCheckIn.service,daycareBilling.service}.ts`, `features/hotel/{hotel.types,hotel.controller,services/careInstructions.service,services/checkout.service,services/careLogFlagging.service,services/careLogCompletion.service,services/hotelStay.service}.ts`.

**Client** (shared substrate): `features/booking/booking.types.ts`, `components/shared/BookingStatusBadge/*`, `api/booking.api.ts` (`startBooking`/`completeBooking`/`markBookingPaid`), `styles/tokens.css` (new `--color-booking-paid-*`/`--color-booking-in-progress-*` tokens), `pages/ReceptionistBookingsQueuePage/*` (Start/Complete/Mark as Paid buttons, past-due reschedule guard), `pages/CustomerBookingsPage/*` (same guard, no advance buttons), `components/SlotPicker/*` (min-date guard, cage-availability line).

**Client** (per-module rewiring): `features/grooming/{grooming.types,api/grooming.api,components/AppointmentCard/*,pages/GroomerDashboardPage/*}.ts(x)` (+ deleted `GroomingStatusBadge`), `features/veterinary/{veterinary.types,api/veterinary.api,components/PetHistoryTab/*,pages/VeterinaryConsolePage/*}.ts(x)` (+ deleted `ConsultationStatusBadge`), `features/daycare/pages/DaycareCheckInPage/*`, `features/hotel/{hotel.types,api/hotel.api,components/HotelStayPicker/*,components/HotelBookingPicker/*,pages/HotelCheckInPage/*}.ts(x)`.

**Removed**: `client/src/features/grooming/components/GroomingStatusBadge/*`, `client/src/features/veterinary/components/ConsultationStatusBadge/*` - both fully superseded by the shared `BookingStatusBadge`.

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **627/627 tests pass** (69 files).

From `client/`:

```powershell
npx tsc --noEmit -p .
npx vitest run
```

Expected: typecheck clean, **432/432 tests pass** (102 files).

Both confirmed clean as of this revision.

## Manual Verification

You'll need: the `server/` and `client/` dev servers running (`npm run dev` from the repo root), a Supabase project with migrations `20260728058`-`20260728062` applied (in order, after `20260728057`), and Postman for the API-level checks.

### 0. Apply the migrations

1. From the repo root: `npm run supabase:push` (or `npm run supabase:reset` for a fresh local database, which also re-runs the seeds).
2. If you reset, re-run the seed scripts so login credentials, pets, branches, and services exist.

### 1. Schema checks - `booking-status-automation.sql`

Open the SQL file in this folder in Supabase Studio's SQL Editor. Run Sections 1-5 (read-only) - confirm the new 6-value enum, the 3 new timestamp columns, the 4 dropped per-module status columns (and that `daycare_sessions.status` is _not_ among them), the renamed partial index, and that `get_staff_availability()`'s definition no longer mentions `'Confirmed'` anywhere. Run Section 6 (wrapped in `begin`/`rollback`) - confirm the single returned row shows the full Pending → In Progress → Completed → Paid progression, then confirm the follow-up `select count(*)` shows `0` leftover rows.

### 2. API checks - `booking-status-automation.postman_collection.json`

Fill in `staff_identifier`/`staff_password`, `customer_email`/`customer_password`, `branch_id`, `pet_id` (a real pet belonging to that customer), and `grooming_service_id` (a real Grooming-category service at that branch). **Run** items 1-13 top-to-bottom, during the branch's normal operating hours (see the collection's own description for why).

Expected: every request's inline test script passes, specifically:

1. Both logins succeed.
2. A booking created ~1 hour in the past starts `Pending`, then reading it back immediately shows `No-show` (the lazy transition), and that same booking can no longer be Started or Rescheduled (`409` both times).
3. A booking created ~24 hours out can be Started (`In Progress`), Completed (`Completed`, not auto-Paid since it's Cash), and Marked Paid (`Paid`) - with each action correctly rejected `409` if attempted a second time or out of order, and a `Paid` booking can no longer be Cancelled.

### 3. Bookings queue - no more Confirmed, Start/Complete/Mark as Paid, past-due guard

1. Go to `/staff/bookings/queue`. Confirm the Status filter dropdown reads Pending/In Progress/Completed/Paid/Cancelled/No-show - no "Confirmed" anywhere.
2. Find (or create, via `/staff/bookings/new`) a `Pending` booking scheduled for later today or a future date. Confirm its row shows a **Start** button (and **Reschedule**/**Cancel**, since both are still valid for Pending).
3. Click **Start** - confirm the status badge updates to `In Progress` in place (no page reload), and the row now shows **Complete** instead of Start, and no longer shows Reschedule (only Pending is reschedulable).
4. Click **Complete** - confirm the badge updates to `Completed` (or straight to `Paid` if this booking happened to be an already-confirmed GCash/Maya one) and the row shows **Mark as Paid** if it stopped at Completed.
5. Click **Mark as Paid** - confirm the badge updates to `Paid` and no further action buttons remain.
6. Create a booking, then (directly via the API or by waiting) let its scheduled time pass without ever clicking Start - reload the queue and confirm it now shows `No-show`, with no Reschedule/Cancel/Start buttons at all.
7. Find any booking whose scheduled time is already in the past but still shows a _different_ status than No-show (e.g. you manually Started it, so it's legitimately In Progress) - confirm it does **not** show a Reschedule button (past-due bookings are never reschedulable regardless of status), but still shows Cancel if its status is Pending or In Progress.

### 4. Date/time picker accuracy, round 2

1. At `/staff/bookings/new` (or `/portal/book`), reach the Date & Time step for a **Hotel** booking. Note the current date, then click "Previous day" repeatedly to go back several days. Confirm "Previous day" becomes disabled once you reach today, and the date `<input>` refuses to go earlier (both by its native `min` and by snapping back if you type/paste an earlier date).
2. With today's date selected for a Hotel booking, confirm a line reads "Cage availability for this size: _N_ of _M_ free" above the single day slot - not just an enabled/disabled button with no explanation.
3. Switch to **Grooming** and confirm the same min-date guard applies - you cannot navigate the picker to a date before today.
