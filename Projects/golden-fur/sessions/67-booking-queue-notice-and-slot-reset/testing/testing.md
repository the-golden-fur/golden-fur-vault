# Booking Queue — separate online-booking notice period; future dates show the full slot list

Branch: `fix/booking-notice-and-slot-reset` (golden-fur) · `docs/session-67-booking-notice` (golden-fur-vault)

## The request, verbatim

> Fix how date and time picker in bookings queue > new booking: when it's 1 PM
> today and I set a booking for tomorrow, it only shows time slots 2 PM and
> beyond. Later dates should reset and show all available slots based on branch
> operating hours and break times. Staff should not appear in staff picker when
> they're not available. Confirm availability time is computed properly (monthly
> schedule, vacation leave). Right now monthly schedule is not configured, so all
> staff should be available EXCEPT when chosen by a customer at X date/time.

> Fix not being able to book the next day or today in booking queue — the 3-day
> notice period FOR RESCHEDULING ONLY is also applying to future online bookings.
> You may add a separate config (online booking notice period) in admin
> settings → config → policies.

## Root cause / Context

`policy_configurations.notice_period_days` (default 3, enforcement default on)
was doing two jobs: the reschedule/cancellation notice **and** — since
`_legacy/custom/59` — a lead-time floor on brand-new bookings. Two symptoms:

- `getDaySlots` (`availability.service.ts`) filtered out any candidate earlier
  than `now + notice_period_days` **for every date**, so a future date's list
  was shifted by the current time of day (and a date inside the 3-day window
  returned `[]`).
- `createBooking` rejected any Online booking inside `now + notice_period_days`,
  so today/tomorrow were unbookable.

Staff picker: investigated, already correct. `get_staff_availability`
(`supabase/migrations/20260901156_...`) already filters by branch hours + lunch,
**approved** `staff_unavailability_blocks` (the Monthly Schedule page's rest
day / vacation / sick leave), and slot-holding overlapping bookings. There is no
positive shift-roster table, so an unconfigured monthly schedule already means
"all staff available". Left unchanged per the planning decision (unpaid-conflict
staff stay selectable until the conflicting booking pays).

## What changed

### Database

- `supabase/migrations/20260902166_m09_policy_configurations_booking_notice_period.sql`
  — adds `booking_notice_period_days integer not null default 0 check (>= 0)`.

### Server

- `booking.types.ts` — `booking_notice_period_days` on `PolicyConfiguration` +
  `EffectivePolicy`.
- `modules/validators/booking.validator.ts` — `booking_notice_period_days` on
  `updatePolicyValidator`; `intent` (`new_booking` | `reschedule`) on
  `availabilityQueryValidator` and `nextAvailableSlotQueryValidator`.
- `services/staffPicker.service.ts` — new `bookingLeadDays`,
  `resolveBookingLeadDays`, and `assertMeetsBookingLeadTime` (async; resolves
  branch timezone; compares calendar dates, not a rolling instant). Docs on
  `noticeLeadDays`/`assertMeetsNoticeLeadTime` clarified as reschedule-only.
  `DOCUMENTED_DEFAULTS` and the new-row baseline carry the new field.
- `services/availability.service.ts` — `getDaySlots` takes `intent`
  (default `new_booking`); chooses `bookingLeadDays` vs `noticeLeadDays`
  accordingly. The "start already in the past" filter now runs only when
  `date === todayInBranchTz`; future dates return the full
  operating-hours-minus-lunch set. `findNextAvailableSlot` uses
  `resolveBookingLeadDays`.
- `booking.controller.ts` — `availabilityController` reads `intent`, passes it
  through, and returns the matching `min_notice_days`.
- `services/booking.service.ts` — `createBooking` (Online path) now (a) rejects
  a `scheduled_start` more than 15 min in the past — `PAST_SLOT_GRACE_MS`, a
  new backstop the old always-on `notice_period_days` gate used to provide
  incidentally (code-review blocking finding #1) — then (b) calls
  `assertMeetsBookingLeadTime` for the configurable floor. Walk-ins still
  exempt; reschedule path unchanged.
- `modules/validators/booking.validator.ts` — `intent` is on
  `availabilityQueryValidator` only; dropped from `nextAvailableSlotQueryValidator`
  (nothing consumes it there — review nit N1).

### Client

- `api/booking.api.ts` — `AvailabilityQuery.intent`, forwarded as `&intent=`.
- `components/SlotPicker/SlotPicker.tsx` — `intent` prop (default
  `new_booking`), forwarded to the availability call and in the effect deps.
- `pages/ReceptionistBookingsQueuePage/...tsx` and
  `pages/CustomerBookingsPage/...tsx` — reschedule `SlotPicker` gets
  `intent="reschedule"`.
- `booking.types.ts` — `booking_notice_period_days` on `PolicyConfiguration`,
  `EffectivePolicy`, `UpdatePolicyPayload`.
- `pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx` — new
  "New online booking notice period" section (number field, default 0), wired
  into `FormState`, `formStateFromPolicy`, `DOCUMENTED_DEFAULTS`, and the PATCH
  payload.
- `pages/SettingsPage/configTiles.config.ts` — tile description updated.

## Manual test — step by step

Prereqs: dev servers up — client `http://localhost:5173`, server
`http://localhost:3000` (`npm run dev` from the repo root). Migration applied
(`npm run supabase:push`).

### A. The new config appears

1. Browser → `http://localhost:5173`. Click **Staff Login** (top-right). Sign in
   as an **Admin** account. You land on **Dashboard**.
2. Open **Settings** (gear / sidebar) → **Config** → **Policies**.
3. Confirm a section **"New online booking notice period"** with a number field
   showing **0**. The existing **"Reschedule notice period"** section is still
   there, unchanged (Minimum notice 3, enforcement on). Failure: no new section,
   or a console/red error.

### B. Future date shows the full slot list (was the bug)

4. Sidebar → **Bookings Queue** (list of appointments). Click **New booking**.
5. Step through: pick a **branch** (e.g. Makati), a **pet**, service type
   **Grooming**.
6. On the date step, use the date field / **Next day** to select **tomorrow**.
   The time buttons must span the branch's whole open window (e.g. 8:00 AM →
   5:00 PM) with **12:00–1:00 PM missing** (lunch). They must **not** start
   near the current clock time. Failure = list starts around "now".
7. Select **today**. Now only times later than the current clock time appear.
8. Finish the booking (pick a time, staff = No preference, a service, submit).
   It should succeed. Failure = 422 "requires N days notice".

### C. The new floor still works when an admin sets it

9. Back in **Policies**, set **New online booking notice period** = **2**, click
   save.
10. New booking again (branch → pet → Grooming): **today, tomorrow, day after**
    show "No availability"; the day after that shows the full slot list.
11. Reset it to **0** and save.

### D. Reschedule still uses the 3-day rule (unchanged)

12. With the new field at 0, in **Bookings Queue** open an existing future
    booking → **⋯** → **Reschedule**.
13. The reschedule date picker still refuses dates within **3 days** (the
    "needs at least 3 days notice" hint shows; **Previous day** is disabled at
    the floor). Failure = it lets you pick tomorrow.

### E. Staff picker (confirmation only — no behaviour change)

14. Create a Grooming booking with a **specific groomer** at tomorrow 2:00 PM
    and pay its downpayment (Transactions → mark paid).
15. Start another New Booking for tomorrow 2:00 PM, same branch → at the staff
    step that groomer is **absent**; other groomers are listed.
16. A groomer with an **approved** Vacation/Sick leave block over that window
    (Monthly Schedule page) is also absent.

## Test suites

Run from the repo root on branch `fix/booking-notice-and-slot-reset`:

- **server**: `npm --prefix server test` — **964/964 passing** (88 files).
  `npx tsc --noEmit` (server) — clean. `npx eslint src/features/booking` — 0
  errors (8 pre-existing `no-console` warnings, unrelated files).
- **client**: `npm --prefix client test` — **767/767 passing** (149 files).
  `npm --prefix client run build` (`tsc -b && vite build`) — clean.
  `npx eslint src/features/booking src/pages/SettingsPage` — clean.
- `ci-verifier` subagent: golden-fur fully green; vault `format:check` fixed
  (session-doc markdown).

New/changed tests:

- `services/availability.service.spec.ts` — rewrote the "minimum-notice lead
  time" block: new-booking uses `booking_notice_period_days`, reschedule keeps
  `notice_period_days`, a future date is never shifted by the time of day, today
  still drops past starts.
- `services/booking.service.spec.ts` — create-time gate keys off the new column;
  added "accepts a booking for tomorrow at the default floor (0)" and "rejects a
  past-dated Online booking … even at the default floor (0)". Shared `BASE_INPUT`
  fixture date is now relative-future.
- `services/staffPicker.service.spec.ts` — added a branch-tz midnight-boundary
  case for `assertMeetsBookingLeadTime` (review test-gap).
- `services/staffPicker.service.spec.ts` — `noticeLeadDays` vs `bookingLeadDays`,
  `assertMeetsBookingLeadTime` (no-op at 0, 422 inside window, accepts past it).
- `modules/validators/booking.validator.spec.ts` — `booking_notice_period_days`
  accepted / negative rejected; `availabilityQueryValidator` `intent`.
- `components/SlotPicker/SlotPicker.spec.ts` — `intent` defaults to
  `new_booking`, forwards `reschedule`.

## Code review

`reviews/2026-09-02-1906-pre-pr.md` — CHANGES REQUESTED, 1 blocking + 4 nits.

- **Blocking (fixed):** past-dated Online bookings were no longer rejected at
  the default `booking_notice_period_days = 0` (the old always-on
  `notice_period_days` gate had blocked them incidentally). Added the
  `PAST_SLOT_GRACE_MS` guard in `createBooking` + a test.
- **N1 (fixed):** dropped the unused `intent` from `nextAvailableSlotQueryValidator`.
- **N2 / N3 (won't-fix):** `shiftDateString` duplicates `addDaysToDateString`
  across two service files — kept, to avoid the documented service↔service
  import cycle; the double `resolveEffectivePolicy` per availability request is
  a pre-existing pattern.
- **N4 (deferred):** `PolicyConfigurationPage` still has no spec file
  (pre-existing); the new field is type-checked and covered server-side.

## Open items

- No pgTAP test added for `get_staff_availability` — the repo has no pgTAP
  harness wired into CI (`supabase/tests/` is empty), so an isolated file would
  not be run. The RPC is unchanged by this session.
- `ScheduleFollowUpModal` (vet follow-up) creates an Online booking and so now
  follows the new 0-day floor — which is the desired relief from
  `_legacy/custom/59`'s "Open items".
- `PolicyConfigurationPage` client spec (review N4) — the whole page is
  untested; worth a dedicated session.
