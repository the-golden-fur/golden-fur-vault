---
title: Booking Queue — separate the online-booking notice period and stop future dates from hiding early time slots
date: 2026-09-02
tags: [session-plan, golden-fur]
project: golden-fur
session: 67-booking-queue-notice-and-slot-reset
branch: fix/booking-notice-and-slot-reset
---

# 67 — Booking Queue: separate the online-booking notice period, and reset time slots for future dates

## What you asked for

Fix two problems on the **Bookings Queue → New Booking** screen, and confirm the
staff picker only shows staff who are actually free.

> Fix how date and time picker in bookings queue > new booking: Currently, when
> it's 1 PM today and I set a booking for tomorrow, it only shows booking time
> slots 2 PM and beyond (AS IF IT'S TREATING TODAY'S AVAILABLE BOOKING SLOTS FOR
> TOMORROW AND LATER DATES). Later dates should reset and show all available
> booking time slots based on branch operating hours and break times. Staff
> should not appear in staff picker when they're not available. Confirm if
> availability time is computed properly (monthly schedule the supervisor set,
> staff on vacation leave, etc.). Right now, monthly schedule is not configured
> by admin role, so all staff should be available EXCEPT when they're chosen by
> a customer at X date/time.

> Fix not being able to book the next day or today in booking queue. I think the
> 3 day notice period FOR RESCHEDULING ONLY is ALSO applying to future online
> bookings. You may add a separate config (for the online booking notice period)
> in admin settings > config > policies.

Decisions taken during planning (asked and answered):

- **Staff picker, unpaid conflict:** leave current behaviour — a groomer/vet
  another customer picked but hasn't paid the downpayment for stays selectable
  until that booking pays (or auto-cancels). No change.
- **New "online booking notice period" default:** **0 days** (same-day and
  next-day bookings allowed out of the box).
- **The old 3-day notice:** unchanged, keeps applying to reschedules only.

## What this part of the app does today

- **Bookings Queue** — the page a **Receptionist** (front-desk staff role) uses
  to see and create appointments. Its "New booking" button opens the same
  step-by-step **booking wizard** a customer uses: branch → pet → service type →
  **date & time** → staff → services → payment.
- **SlotPicker** — the date & time step. It asks the server "what times are open
  on date X?" and shows a row of buttons. The candidate times come from the
  **branch operating hours** (e.g. Makati Mon–Fri 08:00–18:00) minus a fixed
  **lunch break** (default 12:00–13:00, stored in the policy table).
- **Policy table** — one database table, `policy_configurations`, holds every
  booking rule (notice period, lunch break, downpayment %, credit expiry…). One
  system-wide default row plus optional per-branch override rows. Admins edit it
  on **Settings → Config → Policies**.
- **notice_period_days** — a single number in that table (default 3). It was
  meant as the "give us N days' warning to move/cancel an appointment" rule. A
  past change (`_legacy/custom/59`) also started using it as a floor on
  brand-new bookings — that is the bug.
- **Staff picker** — the step that lists which groomer/vet you can request.
  The list already comes fully filtered from a database function
  (`get_staff_availability`): it removes staff who are outside branch hours, on
  an **approved** unavailability block (rest day / vacation / sick leave, all
  written by the Monthly Schedule page), or already assigned to a
  slot-holding booking at that time. There is no "positive shift roster" table,
  so "schedule not configured" already means "everyone available by default" —
  which is exactly what you wanted. **No code change was needed here** beyond
  confirming it; see `testing/testing.md`.

## What's wrong / what's missing

1. **Future dates showed a shifted slot list.** The slot list had a filter
   "drop any time earlier than _now + notice period_" that ran for **every**
   date, not just today. At 1 PM, picking tomorrow dropped every morning slot
   (and picking a day inside the 3-day window returned nothing at all).
2. **Could not book today or tomorrow.** Because `notice_period_days` (3) was
   used as the new-booking floor, the earliest bookable date was "today + 3".

## What we changed

1. **New policy column `booking_notice_period_days`** (default **0**) — the
   notice period for brand-new online bookings, separate from the reschedule
   one. — _Files:_ new migration
   `supabase/migrations/20260902166_m09_policy_configurations_booking_notice_period.sql`;
   both `booking.types.ts` files; `staffPicker.service.ts` (`DOCUMENTED_DEFAULTS`,
   the new-row baseline); `booking.validator.ts`. — _Why:_ so admins can dial the
   new-booking lead time independently, and it defaults to "same-day allowed".

2. **New helpers `bookingLeadDays` / `assertMeetsBookingLeadTime`** next to the
   existing `noticeLeadDays` / `assertMeetsNoticeLeadTime`. — _Files:_
   `server/src/features/booking/services/staffPicker.service.ts`. — _Why:_ new
   bookings read the new column; reschedules keep reading `notice_period_days`.
   `assertMeetsBookingLeadTime` compares **calendar dates in the branch's
   timezone** ("2 days notice" = "the day after tomorrow onwards"), not a
   rolling 48-hour instant.

3. **`getDaySlots` (the slot-list builder) now takes an `intent`** —
   `'new_booking'` (default) or `'reschedule'` — and picks the matching notice
   column. The "time already in the past" filter now runs **only when the
   selected date is today**; any future date returns the branch's full
   operating-hours-minus-lunch list. — _Files:_
   `server/src/features/booking/services/availability.service.ts`,
   `server/src/features/booking/booking.controller.ts`.

4. **`createBooking`** now, for Online bookings, (a) rejects a `scheduled_start`
   already in the past (15-minute grace for clock skew — a backstop the old
   always-on notice gate used to provide for free), then (b) calls
   `assertMeetsBookingLeadTime` for the configurable floor. Walk-ins still skip
   both. Reschedule (`reschedule.service.ts`) is untouched. — _Files:_
   `server/src/features/booking/services/booking.service.ts`.

5. **Client:** `SlotPicker` gains an `intent` prop (default `'new_booking'`);
   the two **reschedule** call sites (`ReceptionistBookingsQueuePage`,
   `CustomerBookingsPage`) pass `intent="reschedule"`. The availability API
   wrapper forwards it. — _Files:_ `client/src/features/booking/api/booking.api.ts`,
   `components/SlotPicker/SlotPicker.tsx`, the two page files.

6. **Policies page** gains a "New online booking notice period" section (one
   number field, 0 = same-day allowed). — _Files:_
   `client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`,
   `client/src/pages/SettingsPage/configTiles.config.ts`.

## Words you might not know

- **migration** — a numbered `.sql` file that changes the database shape; they
  run in order, once each.
- **policy override row** — a `policy_configurations` row tied to one branch;
  when present it replaces the system default for that branch, whole-row.
- **branch timezone** — every branch stores its own IANA zone (all
  `Asia/Manila` today); "today" and "N days out" are computed in that zone.
- **intent (here)** — a hint the client sends the availability endpoint so it
  knows whether to apply the new-booking floor or the stricter reschedule floor
  (the same endpoint serves both pickers).
- **walk-in** — a booking made on the spot for right now; it bypasses the notice
  period and the browsable calendar entirely.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks and the test-suite
counts.
