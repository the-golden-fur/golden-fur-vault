# Booking flow: walk-in starts "now", down-payment split on Review & Pay, Booking Type card icons + ⓘ popover

Branch: `feat/receptionist-confirmation-status` (bundled into that single PR at the
user's request — same branch as `55-transactions-page-and-confirmation-status`, a
distinct concern so it gets its own verification doc per the skill's scope-note
convention).

## The request, verbatim

Across several chat messages while iterating on the receptionist booking wizard
(`/staff/bookings/new`):

> fix the walk in procedure in booking process. at 6 date time step, when walk in is
> selected, it should take in the CURRENT DATE TIME, not next available slot. and based
> from that current date time, show available staff below
>
> also add icon when choosing online booking or walkin. remove the big text below it, move
> it to some sort of info component that looks like the usual i — when you click on i comp,
> you get to see that long explanation text
>
> [Review & Pay, online > grooming] make it so that in the review and pay phase, it should
> show the calculated downpayment since it's an online booking. do this for all online
> bookings

Clarification (AskUserQuestion): the down-payment line already rendered as small grey
helper text — the ask is to **promote it to a prominent breakdown** ("Downpayment due now"

- "Balance due later" as their own rows), for every online booking.

## Context

- **Walk-in slot.** `SlotPicker`'s `lockToNow` mode (walk-in flow, #122) previously ran the
  normal `getDayAvailability` fetch and auto-selected `slots.find(s => s.available)` — the
  _next available_ slot, e.g. 10:00–11:00 when the branch's seeded Sunday hours open at
  10:00 and it's currently 07:51. A walk-in means "the customer is physically here now", so
  the slot should be _now_.
- **Booking Type step** (receptionist-only, step 5): two big text cards (Online Booking /
  Walk-in) with no icon and a paragraph of explanation each.
- **Down payment on Review & Pay**: shown as one dim `<p>` — "Downpayment required now: PHP
  315.00" — under Estimated total. Driven by `getDownpaymentStatus(branchId)` +
  `estimatedTotal` (the discounted net), mirroring `createBooking`'s own server-side math.

## What changed

_Client only — no server change, no migration, no API-route change._

### Walk-in "starting now" — `client/src/features/booking/components/SlotPicker/SlotPicker.tsx`

- `lockToNow` no longer fetches `getDayAvailability` at all (`useEffect` returns early).
- New `nowSlot` memo: `start` = current time with seconds/ms zeroed, `end` = `start +
slotDurationMinutes`. Computed once per lock so it stays stable while the receptionist
  finishes the wizard.
- The auto-select effect now selects `nowSlot` (was `earliestAvailableSlot`, now removed).
- Banner: **"Walk-in — starting now"** + the current `HH:MM – HH:MM today` range (was
  "Walk-in — next available slot today" + the resolved slot, with a "no open slot today"
  fallback that no longer applies — a walk-in always books now).
- **Staff picker is unchanged** and already keys off the selected slot's window, so
  `StaffPickerList` / `get_staff_availability` now report who is free _right now_. If nobody
  is (e.g. before opening hours), `autoAssignStaff` still 409s at submit — correct: a
  Grooming/Vet walk-in genuinely needs a staff member present. (No server carve-out for
  out-of-hours walk-ins was added — that would be a separate, deliberate decision.)

### Booking Type card icons + ⓘ popover

- New shared `client/src/shared/components/InfoPopover/` — a small "ⓘ" button that reveals
  short help text on click; closes on outside-click / Escape; `stopPropagation` on the
  trigger. Same pattern as `MoreOptionsMenu`. (`InfoPopover.spec.ts` — 3 tests.)
- `CustomerBookingFlowPage` Booking Type step (`case 'bookingType'`): each card now shows a
  lucide icon (`Globe` for Online Booking, `Footprints` for Walk-in) + the label only; the
  paragraph moved into an `InfoPopover` pinned to the card's top-right corner. The card
  stays a real `<button>` — the ⓘ is a sibling inside a `position: relative` wrapper (a
  button can't nest in a button). Walk-in blurb updated: "…the date and time are set to
  now…" (was "…locks to the next available slot today…").

### Down-payment split on Review & Pay — `CustomerBookingFlowPage` `case 'payment'`

- The single grey `<p>Downpayment required now: PHP X</p>` became two rows in the pricing
  box, shown whenever `downpaymentAmount !== null` (i.e. every online / non-walk-in booking
  under a branch whose down-payment policy is enabled — unchanged trigger):
  - **Downpayment due now** — `PHP {downpaymentAmount}` — emphasised (gold, border-top).
  - **Balance due later** — `PHP {max(0, estimatedTotal − downpaymentAmount)}` — muted.
- New CSS: `.downpaymentDueNow`, `.pricingRowMuted`, plus the Booking Type
  `.bookingTypeCardWrap` / `.bookingTypeInfo`.

### Friendlier `POST /bookings` failure message

- New `client/src/features/booking/bookingErrors.ts` — `friendlyBookingError(raw)`
  (+ `bookingErrors.spec.ts`, 4 tests). The submit handler used to append a fixed
  capacity/duration hint to _every_ error, so a raw PostgREST error (e.g.
  `Could not find the 'downpayment_due_at' column of 'bookings' in the schema cache`,
  seen locally when migrations `20260829146-148` haven't been applied) rendered verbatim
  plus a misleading "try a different time". Now: PostgREST/DB leakage (schema-cache,
  column/relation/constraint text) collapses to one generic "something went wrong on our
  end" line; a server-authored domain message passes through; the slot hint is only added
  for an actual slot/staff/capacity conflict.
- **Not a code bug** — the underlying 400 in the screenshot is a stale local schema: run
  `npm run supabase:reset` (repo root) to apply migrations + reseed. The client change
  just stops it from looking scary.

## Verification

All in the staff console as a **Receptionist**, `/staff/bookings/new`.

1. **Walk-in = now.** Customer → Pet → Branch → Grooming → Booking Type: click **Walk-in**
   → Next. The Staff & Date step shows **"Walk-in — starting now"** with the current
   `HH:MM–HH:MM` (not a future slot). The Staff list below reflects who is available at that
   time. Change the system clock / retry at different times to confirm the start tracks
   "now".
2. **Walk-in before opening hours.** With Makati (seeded Sun 10:00–14:00) and the clock at
   ~07:51 Sunday: the banner shows ~07:51, and the staff picker is empty / Confirm returns
   a 409 "no eligible staff" — expected (branch effectively closed).
3. **Booking Type cards.** Step 5 shows an icon + label per card and **no paragraph**.
   Click the **ⓘ** on each → the explanation appears in a small panel; click ⓘ again, press
   Escape, or click elsewhere → it closes. Selecting a card still works (ⓘ click does not
   select the card).
4. **Down-payment breakdown (online).** With the branch down-payment policy enabled
   (Settings → Policies): Booking Type **Online Booking** → Grooming → pick a service →
   Review & Pay. The pricing box shows **Downpayment due now** (gold) and **Balance due
   later** (muted) as their own rows, `due now + balance = Estimated total`. Repeat for
   Hotel / Daycare and for individual services vs a package — the rows appear for all.
5. **Walk-in shows no down-payment.** Booking Type **Walk-in** → Review & Pay: no
   "Downpayment due now" row, no online (GCash/Maya) payment methods — unchanged.

## Test suites

Run on `feat/receptionist-confirmation-status` (this change set + the
`55-transactions-page-and-confirmation-status` work share the branch / PR):

- `client`: `npx vitest run --testTimeout=30000` — **728/728 passing (142 files)**
  (this machine times out heavier specs at the default 5000 ms). `npx tsc -b` clean.
  `npx eslint .` — 0 errors.
- `server`: unaffected by this change set (client-only) — full run on this branch
  902/902, `npx tsc --noEmit` clean, `npx eslint .` 0 errors.

## Open items

- No server carve-out for out-of-hours walk-ins: a Grooming/Vet walk-in booked before the
  branch opens (or with no staff on shift) still 409s at auto-assign. Flagged to the user
  as a separate decision.
- `nowSlot` is captured once when `lockToNow` turns on; if the receptionist leaves the
  wizard open for a long time the start time can drift from the true "now". Acceptable for
  the walk-in flow (booking is created promptly); revisit if it becomes an issue.
- Veterinary online bookings: the client shows the down-payment breakdown whenever the
  branch policy is on (not category-gated), matching the pre-existing trigger and the
  server's own `createBooking` (also not category-gated for `booking_source = 'Online'`).
  If Vet should be exempt (price TBD), that is a pre-existing server question, not
  introduced here.
