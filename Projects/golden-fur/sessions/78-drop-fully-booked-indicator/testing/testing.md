# Removed the "fully booked" pop-up from the new-booking flow

Branch: `fix/drop-fully-booked-indicator` (base: `dev`)

## The request, verbatim

> Remove the fully booked indicator when starting a new booking:
>
> - I believe this runs when all staff are selected in bookings
> - EVEN THOUGH, they're scheduled on different dates
> - This does not mean that on X date, X staff are unavailable
> - Either drop how fully booked works or rewire its functionality

## Root cause / Context

The availability step of the new-booking wizard
(`CustomerBookingFlowPage`) carried a pre-check on top of the Slot Picker:
`SlotPicker` reported, via an `onAvailabilityChange` callback, whether the
day it just loaded had any candidate slots and whether any were open. When
a day had candidates but zero open, the page showed a blocking **"This
looks fully booked"** modal and fired `GET /bookings/availability/next-slot`
(`findNextAvailableSlot`), which walks `getDaySlots` forward up to 14 days
for the first open slot.

This duplicated the Slot Picker's own, accurate, per-date empty state
("No open slots on this date. Try another date above."). The staff-overlap
math it ultimately depends on (`get_staff_availability` Check 2) is
correctly time-scoped — `bk.scheduled_start < p_requested_end AND
bk.scheduled_end > p_requested_start` — so a staff member booked on a
different date does not count against the viewed date. The complaint is
about the modal's behaviour, not the arithmetic: it reads as a false
"fully booked" alarm for an ordinary busy day or a day the branch's only
eligible staff member is on approved leave, and it interrupts the flow.

Decision (per the request's "either drop … or rewire"): **drop it**, end to
end, rather than keep tuning a redundant heuristic.

## What changed

No database changes.

### Server

- `services/availability.service.ts` — deleted `findNextAvailableSlot`,
  `DEFAULT_LOOKAHEAD_DAYS`, and the `FindNextAvailableSlotParams` /
  `NextAvailableSlot` interfaces. `nextDateString` / `addDaysToDateString`
  stay (still used by `countOvernightNights` and `getDaySlots`). Dropped
  the now-unused `resolveBookingLeadDays` import.
- `booking.controller.ts` — deleted `nextAvailableSlotController` and the
  `findNextAvailableSlot` / `nextAvailableSlotQueryValidator` imports.
- `booking.routes.ts` — deleted the `GET /bookings/availability/next-slot`
  route and its controller import.
- `modules/validators/booking.validator.ts` — deleted
  `nextAvailableSlotQueryValidator`.

### Client

- `pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` — deleted the
  `fullyBookedNotice` / `isCheckingAvailability` state, the
  `handleSlotAvailabilityChange` and `dismissFullyBookedNotice` handlers,
  the `onAvailabilityChange` prop passed to `<SlotPicker>`, the
  "This looks fully booked" / "No availability found" modal, and the
  `isCheckingAvailability` branch of the Next button (it's just **Next**
  now, never "Checking availability…"). Removed the
  `getNextAvailableSlot` / `NextAvailableSlot` imports.
- `pages/CustomerBookingFlowPage/CustomerBookingFlowPage.module.css` —
  deleted the now-orphan `.modalOverlay` / `.modal` / `.modalTitle` rules.
- `components/SlotPicker/SlotPicker.tsx` — deleted the
  `onAvailabilityChange` prop, its ref, and the effect call. Dropped the
  now-unused `useRef` import.
- `api/booking.api.ts` — deleted `getNextAvailableSlot`,
  `NextAvailableSlotQuery`, `NextAvailableSlot`.
- Specs: `SlotPicker.spec.ts` lost its `describe('onAvailabilityChange')`
  block (3 cases); `CustomerBookingFlowPage.spec.ts` lost the two
  "fully-booked modal" cases, the `getNextAvailableSlot` mock, the
  fail-open default mock, and the mock SlotPicker's two "Simulate …"
  buttons.

## Manual test — step by step

Assumes `golden-fur` is running locally: server on
`http://localhost:3000`, client on `http://localhost:5173` (run
`npm run dev` at the repo root, or the "🚀 Dev: Start All" VS Code task).
Staff logins are `<branch>.<role>N` / `password123` (e.g.
`makati.receptionist1`); customer logins are `customerN@goldenfur.com` /
`password123` (from the seed files — see `context/context-manifest.md`).

### A. The pop-up is gone on a fully-booked day (customer)

1. Open `http://localhost:5173`. Click **Log in** (top-right), enter a
   customer login, click **Sign in**. You land on the customer portal
   home.
2. Click **Book an appointment** (or go to `/portal/book`). You're on the
   wizard, first step **Pet**.
3. Pick an already-assessed pet (one that shows a weight class), click
   **Next**. Pick a branch, click **Next**. On **Service Type** pick
   **Grooming**, click **Next**. On **Service** pick any grooming service,
   click **Next**. You land on the **availability step** with a calendar
   and time list.
4. Navigate to a date you know is heavily booked for grooming (or use the
   admin Bookings Queue to fill one first). When the day loads and every
   time shows **Unavailable**:
   - **PASS:** the calendar shows **"No open slots on this date. Try
     another date above."** and nothing else. No pop-up. The **Next**
     button stays as **Next** (never flips to "Checking availability…").
   - **FAIL (regression):** a dialog titled **"This looks fully booked"**
     or **"No availability found"** appears.
5. Use **Next day** / the date input to move to a day with openings, pick a
   time, and finish the booking normally — everything past this step is
   unchanged.

### B. Receptionist new-booking flow

1. Log in as a receptionist, open **Bookings** → **New booking**
   (`/staff/bookings/new`).
2. Repeat A steps 3–4. Same expectation: the inline "No open slots on this
   date" message, no modal.

### C. The dead endpoint is really gone (optional, API level)

`GET http://localhost:3000/bookings/availability/next-slot?branch_id=…` now
returns **404** (route removed). `GET /bookings/availability?...` (the Slot
Picker's own endpoint) still works.

## Test suites

Run this session (no `ci-verifier` available in this environment):

- `client`: `npx vitest run` — **792/792 passing (155 files)**;
  `npx tsc --noEmit` clean; `npx eslint` clean on the changed files;
  `npx vite build` succeeds.
- `server`: `npx vitest run` — **1023/1023 passing (93 files)**;
  `npx tsc --noEmit` clean (after `npm install` restored the
  `@getbrevo/brevo` dep that was missing from the local `server/`
  install — unrelated to this change, and it now imports fine).
- Root `npm run format:check` clean.

## Open items

- None. The removal is self-contained; the Slot Picker's own per-date
  availability display is the remaining, accurate source of "this day is
  full".
