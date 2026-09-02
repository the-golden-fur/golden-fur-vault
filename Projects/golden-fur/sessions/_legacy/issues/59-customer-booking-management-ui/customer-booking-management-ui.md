# Issue #59 Verification: customer booking management (reschedule/cancel UI)

**Issue:** #59 — feat(booking): customer booking management (reschedule/cancel UI)
**Owner:** James
**Branch:** `feat/customer-booking-management-ui`
**Base:** `dev`
**Depends on:** #54, #55 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds `CustomerBookingsPage` at `/portal/bookings` — a list of the caller's
own bookings with `BookingStatusBadge` (from #55), a reschedule action that
re-enters the Slot Picker (#56) and Staff Picker (#57) scoped to the
existing booking (not the full 8-step flow), and a cancel action behind an
explicit confirm step (AC-5).

### Supporting server endpoint (new in this issue)

The merged `#51`-`#54` backend never exposed a way to list a customer's own
bookings — only `POST /bookings` and `GET /bookings/:id` existed. Added
`GET /bookings`, a thin list read: a customer caller is always scoped to
their own rows (`customer_id = requesterId`) regardless of which filters
they pass; a staff caller may filter by `branch_id`/`date`/
`service_category`/`status`. This same endpoint is also #60's Receptionist
Bookings Queue data source — see
`testing/docs/issues/60-receptionist-bookings-queue-ui/` for the
staff-scoped side of its verification; this doc covers the customer scope.

## What Changed

- **Added** `server/src/features/booking/services/booking.service.ts` —
  `listBookings()` (customer-scoped or staff-filtered, see above), +
  `booking.service.spec.ts` cases.
- **Modified**
  `server/src/features/booking/modules/validators/booking.validator.ts` —
  added `listBookingsQueryValidator`.
- **Modified** `server/src/features/booking/booking.controller.ts` /
  `booking.routes.ts` — registers `GET /bookings` (`jwtMiddleware` only;
  ownership scoping happens in the service, matching the create/reschedule/
  cancel routes' existing pattern).
- **Added**
  `client/src/features/booking/pages/CustomerBookingsPage/` (`.tsx`,
  `.module.css`, `.spec.ts`).
- **Modified** `client/src/features/booking/booking.routes.tsx` — registers
  `/portal/bookings` (`CustomerAuthGuard`).

### Follow-up fix — the reschedule panel's Staff Picker gate was staff-only

Same root cause as #55/#57: this page originally decided whether to show
`StaffPickerList` during a reschedule by reading `GET /bookings/policy`
(staff-only, 403 for a customer). Removed that fetch entirely; the
reschedule panel now always attempts to mount `StaffPickerList` for
Grooming/Veterinary bookings once a new slot is picked, and lets the
component's own `onUnavailable` callback (reading the customer-accessible
`GET /bookings/staff-picker` response) hide itself and flip a local
`staffPickerUnavailable` flag when the toggle turns out to be disabled. See
`testing/docs/issues/55-booking-flow-shell/`'s "Follow-up fix" section for
the full writeup.

## Acceptance Criteria Map

| AC                                                             | Automated                                                 | Manual/Postman                   |
| -------------------------------------------------------------- | --------------------------------------------------------- | -------------------------------- |
| AC-1 Own bookings only, correct status badges                  | `CustomerBookingsPage.spec.ts`, `booking.service.spec.ts` | Manual Step 2, Postman request 3 |
| AC-2 Reschedule reuses Slot/Staff Picker scoped to the booking | manual (component composition)                            | Manual Step 3                    |
| AC-3 Blocked reschedule names the required notice period       | covered by #54's own tests                                | Manual Step 4                    |
| AC-4 Soft-mode violation visibly flagged                       | `CustomerBookingsPage.spec.ts`                            | Manual Step 4                    |
| AC-5 Cancel requires an explicit confirm step                  | `CustomerBookingsPage.spec.ts`                            | Manual Step 5                    |

## Automated Verification

```powershell
npm --prefix server test -- --run src/features/booking/services/booking.service.spec.ts
npm --prefix server run typecheck
npm --prefix server run lint
npm --prefix client test -- --run src/features/booking/pages/CustomerBookingsPage
npm --prefix client run lint
```

## Postman Verification

Needs one **customer** account with at least one existing booking (create
one first via `testing/docs/issues/51-booking-creation-capacity/`'s
collection, or the browser flow, if none exists yet) and a **second**
customer account.

1. Import `customer-booking-management-ui.postman_collection.json` → fill
   collection variables → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login customer** → 200.
   2. **Login other customer** → 200.
   3. **AC-1 List my bookings** → 200; `{ bookings: [...] }`; every row's
      `customer_id` equals the logged-in customer's own id.
   4. **AC-1 Other customer lists their bookings** → 200; the first
      customer's booking id from request 3 does **not** appear anywhere in
      this response.
   5. **Filter by status=Cancelled (still customer-scoped)** → 200; even
      though a `status` filter is passed, the response never includes
      another customer's rows (branch/status filters are staff-only in
      effect — see `listBookings()`'s dev note).
4. No cleanup needed — this endpoint is read-only.

## Manual Browser Verification

Same startup steps as `testing/docs/issues/55-booking-flow-shell/`.

**Seeded accounts** (all passwords `password123`): `customer1@goldenfur.com`
(pets Max, Luna) and `customer2@goldenfur.com` (pet Rex).

### Step 1 — Create a booking to manage

1. Log in as `customer1@goldenfur.com`, create a Daycare booking for pet
   **Max** roughly 10 days from now (Daycare has no Staff step, keeping this
   quick), any payment method, **Confirm booking**.

### Step 2 — List shows only your own bookings, with status badges (AC-1)

1. Navigate to `http://localhost:5173/portal/bookings`.

Expected: the booking just created appears with a **Confirmed** (or
**Pending**, if pay-at-counter was chosen) status badge, the pet's name,
branch, and scheduled time. — **AC-1**

2. Log out, log in as `customer2@goldenfur.com`, go to `/portal/bookings`.

Expected: `customer1`'s booking does **not** appear here — this account has
no bookings yet (or only its own, if you've created any). — **AC-1**

### Step 3 — Reschedule reuses Slot/Staff Picker (AC-2)

1. Log back in as `customer1@goldenfur.com`, go to `/portal/bookings`, and
   click **Reschedule** on the Daycare booking.

Expected: an inline panel opens showing the **same SlotPicker component**
used in the booking flow (#56), scoped to this booking's branch/category —
not the full 8-step flow (no pet/branch/service re-selection). — **AC-2**

2. Pick a new date/time and click **Confirm new time**.

Expected: a "Booking rescheduled." message, and the list updates in place
(new time shown) without a full page reload. — **AC-2**

### Step 4 — Blocked reschedule + Soft-mode flag (AC-3, AC-4)

1. Try to reschedule the same booking again, this time to **tomorrow**.

Expected (default policy is Strict, 3-day notice): an error banner inside
the reschedule panel naming the required notice period (the server's exact
error text, e.g. "Reschedule requires at least 3 day(s) notice..."). —
**AC-3**

2. As an Admin (`makati.admin1@goldenfur.com`, separate session), switch the
   enforcement mode to Soft via `#54`'s Postman collection's "PATCH policy
   → Soft mode" request (or the DevTools `fetch` snippet in
   `testing/docs/issues/57-staff-picker-ui/`'s doc, adapted to
   `notice_enforcement_mode: "Soft"`).
3. Retry the tomorrow-reschedule as `customer1`.

Expected: it now succeeds, but a message reading "Rescheduled, but this
change did not meet the configured notice period." is visibly shown. —
**AC-4**

4. Cleanup: restore Strict mode via the same PATCH.

### Step 5 — Cancel requires explicit confirmation (AC-5)

1. Click **Cancel** on the booking.

Expected: nothing is cancelled yet — an inline confirm panel appears
("Are you sure you want to cancel this booking?...") with an optional reason
field and two buttons: **Yes, cancel booking** / **Keep booking**. — **AC-5**

2. Click **Keep booking**.

Expected: the panel closes, booking is untouched.

3. Click **Cancel** again, then **Yes, cancel booking**.

Expected: a "Booking cancelled." message, the status badge flips to
**Cancelled**, and the Reschedule/Cancel buttons disappear for this row
(only Confirmed/Pending bookings are actionable). — **AC-5**

## Acceptance Criteria Checklist

- [x] **AC-1:** Customer sees a list of their own bookings only, with
      correct status badges — `booking.service.spec.ts`,
      `CustomerBookingsPage.spec.ts`; manual Step 2; Postman requests 3-4.
- [x] **AC-2:** Reschedule flow reuses the Slot/Staff Picker components
      scoped to the existing booking, not a full re-entry of the 8-step
      flow — manual Step 3.
- [x] **AC-3:** A blocked reschedule (Strict mode, notice not met) shows a
      clear error naming the required notice period — manual Step 4.
- [x] **AC-4:** A Soft-mode reschedule/cancellation that violates notice
      period completes but visibly flags the violation —
      `CustomerBookingsPage.spec.ts`; manual Step 4.
- [x] **AC-5:** Cancel requires an explicit confirm step before the booking
      is cancelled — `CustomerBookingsPage.spec.ts`; manual Step 5.
