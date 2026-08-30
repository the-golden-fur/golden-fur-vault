# The N-day minimum-notice policy now floors booking/reschedule dates

Branch: `feat/booking-notice-lead-time` (golden-fur);
`filing/booking-notice-lead-time-verification` (this vault doc).

## The request, verbatim

> Investigate and fix the 3-day-minimum (or N-day) booking filter/configuration
> — verify it correctly applies date ranges instead of appearing to lock/pin
> schedules.

Traced to the Aug-27 advisor demo (`Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`,
reschedule walk-through): _"3 days. Ay, pwede ring configure. … May filter na
tayo. At least 3 days."_ then, trying to move the date to Sep 4:
_"Baka hindi gumagana. … Naka-pin pa nga yata kasi lahat ng schedule. … Kaya 3
schedule."_

## Root cause / Context

`policy_configurations.notice_period_days` (default 3, the Settings →
"Reschedule notice period → Minimum notice (days)" field) was only ever read
by two places:

- `reschedule.service.ts` `evaluateNoticePeriod` — measured against the
  booking's **current** `scheduled_start` ("how far ahead of the appointment
  is the customer making this change"); Strict blocks, Soft flags.
- `cancellation.service.ts` — decides credit-vs-forfeit.

It was **never** applied to _which dates you can pick_. `SlotPicker`'s
`minDate` was just `todayIso()`; `createBooking` had no lead-time check at
all; the reschedule Slot Picker also floored at "today". So setting
"minimum notice = 3 days" changed nothing visible for a new booking, and in
the reschedule flow the near-term days showed as unbookable (past-time
filter, no staff, or the Strict block on confirm) — reading as a pinned,
non-functional calendar rather than a date range that starts 3 days out.

Decision (asked and answered): make `notice_period_days` a **booking
lead-time floor** for both new bookings and reschedules, enforced client
**and** server side.

## What changed

### Server

- `server/src/features/booking/services/staffPicker.service.ts`
  - `noticeLeadDays(policy)` — pure: `notice_period_days` when
    `notice_enforcement_enabled`, else `0`.
  - `assertMeetsNoticeLeadTime(policy, scheduledStart, action)` — throws 422
    (`"<action> requires at least N day(s) notice — please choose a later
date"`) when the slot is inside `now + N*24h`. No-op when enforcement is
    off.
  - `resolveNoticeLeadDays(branchId)` — one-resolve convenience for callers
    that don't otherwise hold the policy.
- `server/src/features/booking/services/availability.service.ts`
  `getDaySlots`
  - Resolves the effective policy **once** now (was one resolve for the
    lunch break); uses it for a day-granular early return (`[]` for any day
    before `today + N` in the branch tz, exactly like a closed day) **and**
    tightens the existing past-time candidate filter to `now + N*24h`, so
    the first bookable day's earlier slots drop out rather than being
    offered and then 422'd on submit. `findNextAvailableSlot` extends its
    look-ahead by `N` so the notice window doesn't eat into the caller's
    requested bookable-day count.
- `server/src/features/booking/booking.controller.ts` `availabilityController`
  - Response gains `min_notice_days` so the Slot Picker can floor its own
    calendar to the same range.
- `server/src/features/booking/services/booking.service.ts` `createBooking`
  - The `bookingSource === 'Online'` block now does one
    `resolveEffectivePolicy` (feeding both down-payment config and the
    notice check) and calls `assertMeetsNoticeLeadTime`. **Walk-ins are
    exempt** (the block is skipped entirely). Net Supabase call count
    unchanged.
- `server/src/features/booking/services/reschedule.service.ts`
  `rescheduleBooking`
  - After `evaluateNoticePeriod`, `assertMeetsNoticeLeadTime(notice.policy,
input.scheduled_start, 'Reschedule')` — reuses the policy
    `evaluateNoticePeriod` already resolved (no extra query). This is
    **in addition to** the existing current-appointment Strict/Soft check,
    which is unchanged.

### Client

- `client/src/features/booking/api/booking.api.ts` — `DayAvailability` gains
  `minNoticeDays` (maps `min_notice_days`, defaults 0).
- `client/src/features/booking/components/SlotPicker/SlotPicker.tsx`
  - Reads `minNoticeDays`; `minDate = today + N`; auto-advances the viewed
    date past the notice window on first load (one corrective re-fetch);
    `min` attribute, "Previous day" disable, and the typed-date clamp all
    use the floored date. Shows a one-line explanation when `N > 0`.
  - Walk-in (`lockToNow`) path is untouched — no fetch, no floor.

No schema change, no new migration.

## Verification

Prereq: Settings → Reschedule notice period → enforcement **on**, Minimum
notice = **3**.

1. **Customer portal → Book**, assessed pet, any branch, Grooming.
   - Slot Picker opens on **today + 3 days**, not today. "Previous day" is
     disabled; the date input won't accept an earlier typed date; a
     one-line "needs at least 3 days notice" hint shows.
   - "Next day" navigates forward freely (a real range, not 3 pinned days).
2. `POST /bookings` (Postman) with `scheduled_start` = tomorrow →
   **422**, message names the 3-day requirement. With `scheduled_start` =
   10 days out → **201**.
3. Set Minimum notice = **0** (or enforcement off) → Slot Picker opens on
   today again; same-day `POST /bookings` succeeds.
4. **Reschedule** (customer My Bookings, and the receptionist queue): the
   reschedule Slot Picker floors to today + 3 the same way; moving to a
   date ≥ 3 days out works, a nearer one is rejected 422.
5. **Walk-in** (receptionist): booking flow still locks to "now" and
   succeeds — the notice floor does not apply.
6. Vet follow-up (`ScheduleFollowUpModal`) goes through `createBooking` as
   `Online`, so it is subject to the floor too — see Open items.

Postman collection: `booking-notice-lead-time.postman_collection.json`
(login → policy PATCH → too-soon booking 422 → far-enough booking 201 →
availability endpoint shows `min_notice_days`).

## Test suites

- `server`: `npx vitest run` — **913/913 passing (86 files)**. New:
  3 `availability.service.spec.ts` (day inside/outside window, enforcement
  off), 3 `booking.service.spec.ts` (Online rejected / accepted / walk-in
  exempt), 1 `reschedule.service.spec.ts` (new slot inside window → 422).
  `npx tsc --noEmit` clean. Fixture updates: `booking.service.spec` and
  `availability.service.spec` default policies set
  `notice_enforcement_enabled: false` (those suites don't exercise the
  floor); `booking.integration.spec`'s `CREATE_PAYLOAD` and one
  DOCUMENTED_DEFAULTS test now use a `daysFromNow(30)` slot.
- `client`: `npx vitest run` — **731/731 passing (142 files)**. New:
  1 `SlotPicker.spec.ts` (floors N days out, auto-advances, hint shown).
  `npx tsc --noEmit`, `npx eslint`, `npx prettier --check`, `vite build`
  all clean.

## Open items

- **`assertMeetsNoticeLeadTime` is instant-based** (`now + N*24h`), and
  `getDaySlots`'s slot filter matches it. The whole-day early return is a
  day-granular fast path that is a strict subset of the instant filter, so
  the two never disagree — but the effective floor is "72 hours", not
  "the calendar day 3 days out". If the client wants pure calendar-day
  semantics, the server assert needs the branch timezone (an extra lookup
  in `createBooking`/`reschedule`).
- **Vet follow-ups are subject to the floor** (they call `createBooking`
  with the default `Online` source). A clinician-ordered "recheck in 2
  days" would be blocked under a 3-day policy. Left uniform for now — the
  alternative (picker floors, server doesn't, or a new `booking_source`)
  is worse. Flag if the vet module owner disagrees.
- The pre-existing reschedule **Strict block on the _current_ appointment**
  is unchanged, so a same-day booking still can't be rescheduled at all
  under Strict enforcement (this was not in scope).
