---
title: Online payment gate & unpaid-downpayment slot holds
date: 2026-08-29
tags: [decision, booking, payment, downpayment, capacity, policy]
project: golden-fur
---

Source request: `Projects/golden-fur/context/Architectural-Change-Suggestions.docx`
— the "In Progress" task row assigned to Matthew, which is verbatim the
seven bullets below. Backed by that doc's advisory-session addendum
("Claude Missed" → _Part 1 §A — Down Payment & Slot Reservation, flagged as
critical_, items A1–A5), from `Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`.
Builds directly on golden-fur #121 (down payment moved to a per-transaction
`policy_configurations` policy) and #122 (walk-in booking flow — see
[[2026-08-28-walk-in-booking-flow]]).

The addendum's exact wording:

> A1. Online bookings can currently reserve a slot with zero payment … an
> online booking must never be allowed to hold a slot without some form of
> payment — either full payment or a down payment.
> A2. Down payment … configurable two ways: percentage or flat fee.
> A3. An unpaid down payment should NOT lock the booking into the queue —
> the slot must stay bookable by others … sit in a 'Pending' /
> pencil-booking state … Only an actual payment … should move it into a
> real, locked slot.
> A4. Unpaid down-payment reservations need an expiration window … a
> same-day deadline (e.g., pay by 11:59 PM) after which the reservation
> auto-resets and the slot becomes available again the next day.
> A5. No 'advance payment' option — book online now, pay in person on the
> day … with the cashier able to manually mark it as paid on arrival.

A5 ("advance payment / pay on arrival") is **not** in Matthew's seven-item
row and is a separate backlog line, but it's the natural answer to what a
non-online-paid online booking _does_ under this design — see §1 and Open
question 2. This doc scopes the seven items; A5 is noted where it touches
them.

> **Status: implemented** on branch `feat/downpayment-slot-gate-and-expiry`
> (golden-fur), 2026-08-29. See the "What shipped" section at the end for
> what was built vs. this plan, and which open questions were settled how.
> #121 and #122 shipped the per-transaction config and the Online/Walk-in
> split; this change makes the down payment an actual _reservation gate_
> rather than an after-the-fact optional payment.

## Problem

Today an **online** booking is created at `status = 'Pending'` and
**immediately holds its capacity/staff-time slot regardless of payment** —
`createBooking` (`booking.service.ts`) has no payment gate at all (the
in-code comment is explicit: _"there is no more payment gate on the initial
status - every booking starts 'Pending' and holds its ... slot immediately
... regardless of category or payment method"_). Online payment is a
**separate, later, optional** step: the customer clicks **Pay** on
`CustomerBookingsPage`, which calls `payForBooking`
(`customerBookingPayment.service.ts`) → a real PayMongo checkout →
`confirmPaymongoWebhookEvent` advances `payment_stage`. Nothing forces that
step, and nothing releases the slot if it never happens.

Concretely, against the seven requirements:

| #   | Requirement                                                                                                                          | Current state                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Require full or down payment on every online booking; no zero-payment slot                                                           | **Gap.** `createBooking` takes `payment_confirmed` as advisory data; a customer can pick "Cash" (or GCash with no real checkout) and the booking holds the slot Unpaid.                                                                                                                                                                                                                                                                                                                                                                                      |
| 2   | Down payment configurable as % or flat, admin-set                                                                                    | **Done** (#121). `policy_configurations.downpayment_enabled` / `downpayment_type` (`Flat`/`Percentage`) / `downpayment_amount`, edited on the Policies page, resolved by `resolveDownpaymentPolicy`.                                                                                                                                                                                                                                                                                                                                                         |
| 3   | While unpaid: keep `Pending`, leave the slot bookable — don't lock queue/schedule                                                    | **Partial.** The Grooming/Vet **queues** already exclude unpaid-downpayment rows (`.or('downpayment_required.eq.false,payment_stage.neq.Unpaid')`). But the **schedule** still counts them: `checkCapacity` / `listOverlappingActiveBookings` / `confirmCapacityAfterInsert` filter on `ACTIVE_BOOKING_STATUSES` (`Pending`/`In Progress`/`Completed`) with no payment filter, and the `get_staff_availability()` RPC hardcodes the same status list in its "Check 2". So an unpaid-downpayment `Pending` booking blocks the slot for everyone else.         |
| 4   | Expiration timer on unpaid down-payment holds; auto-release the slot                                                                 | **Gap.** No such logic. `applyNoShowTransition` is a lazy read-time flip but it only fires at `scheduled_start`, not at an end-of-day payment deadline. `policy_configurations` has `credit_expiry_*` (for credits) but nothing for reservation holds.                                                                                                                                                                                                                                                                                                       |
| 5   | Payment phase: choose full or down payment (online only; walk-ins auto-full)                                                         | **Done** (#121/#122). `payment_choice` (`'full'`/`'downpayment'`) on the booking flow's payment step and on the `transactions` row; walk-ins skip the choice and the whole down-payment path.                                                                                                                                                                                                                                                                                                                                                                |
| 6   | Payments Queue: cashier marks paid; down payment → "partially paid" not "fully paid"; per-transaction payment details (date, amount) | **Partial.** "Mark as Paid" exists (`advancePaymentStage`, advance-vs-onsite modal). `payment_stage = 'Paid in Advance'` is the "partially paid" state (label differs from the request's "partially paid"). `transactions` rows carry `payment_status` (`Pending`/`Fully Paid`/`Partially Paid`), `total_amount`, `payment_method`, `payment_reference`, `webhook_confirmed_at`, `created_at`, `processed_by_staff_id` — but **no UI surfaces the per-transaction list on a booking row** anywhere (not on the Payments Queue, not on `BookingDetailsPage`). |
| 7   | Discounts and promos apply _before_ the down payment is calculated                                                                   | **Gap.** `createBooking` computes `downpaymentAmount` from `totalPrice` (gross sum of `booking_items`) _before_ `resolveDiscountAndPromo` runs. `CustomerBookingFlowPage` has the same bug in its preview (`downpaymentAmount` off `subtotal`, while `estimatedTotal` subtracts discount+promo). In practice discounts are Cash-only so this bites **promos** on online bookings, but the fix should cover both.                                                                                                                                             |

## Decision

### 1. Payment gate in `createBooking` for `booking_source = 'Online'`

An online booking must be created with a **confirmed payment** covering at
least the resolved down payment (or the full total if the payer chose
full). No confirmed payment → the booking is **not created** and no slot is
held. Walk-ins are unaffected (they already skip the whole block, #122).

- The booking flow's **payment step becomes mandatory and blocking** for an
  online booking: the customer/receptionist must complete payment before
  the `POST /bookings` call, not after.
  - **GCash/Maya:** the flow initiates the PayMongo checkout _first_
    (reuse `initiatePaymongoPayment`), and only creates the booking once
    the payment is confirmed. Two sub-options, pick one in build (Open
    question 1):
    - **(a) Create-then-confirm with a short TTL** — create the booking
      `Pending`/`Unpaid` _without holding the slot_ (see §3), redirect to
      PayMongo, let the webhook confirm. This is the "reservation with
      expiry" model and pairs naturally with §4.
    - **(b) Confirm-then-create** — hold nothing until the webhook says
      paid, then create the booking already `Pending`/`Paid`(or `Paid in
Advance`). Simpler slot semantics, but the customer can lose the slot
      between choosing it and paying, and it doesn't match "keep it Pending
      while unpaid" in the request.
    - **Recommended: (a)** — it's the only reading consistent with
      requirements 3 and 4, which presuppose a real "Pending + unpaid +
      slot released" state.
  - **Cash / counter (receptionist booking on behalf, or customer electing
    to pay at the branch):** this is effectively _not an online reservation_
    — treat it like a walk-in for slot purposes, **or** require the
    receptionist to record the counter payment at creation
    (`payment_confirmed = true`, `payment_method = 'Cash'`,
    `payment_stage` set). Do **not** allow a customer-self-service Cash
    online booking to hold a slot Unpaid.
- **When `online_payments_enabled = false` for the branch** (the PayMongo
  KYC fallback): there is no online payment instrument, so a customer
  cannot make an online reservation at all — the flow should fall back to
  "request a booking the branch confirms" or disable online self-service
  booking for that branch. Flag for the owner (Open question 2).
- `payment_confirmed` stops being a free-text advisory field on
  `POST /bookings` for online bookings — the server should derive it from a
  real confirmed `transactions` row, not trust the client. (Today
  `CustomerBookingFlowPage` literally sends `payment_confirmed: true` the
  moment GCash is _selected_, before any checkout.)

### 2. Down payment config — no change

`policy_configurations.downpayment_enabled` / `downpayment_type` /
`downpayment_amount` already do exactly what requirement 2 asks (#121).
The only adjustment is the calculation base — see §7.

### 3. Unpaid-downpayment `Pending` bookings must not hold the slot

Introduce a single predicate — _"this booking currently holds a real
slot"_ — and apply it everywhere slot-holding is evaluated:

```text
holds_slot(booking) :=
  status IN ('Pending','In Progress','Completed')
  AND NOT (downpayment_required AND payment_stage = 'Unpaid')
```

i.e. an online booking that requires a down payment and hasn't paved any of
it yet is **transparent** to capacity — exactly the rule the Grooming/Vet
queues already use, lifted to the schedule layer.

Touch points (all must change together or the pre-insert check and the
Slot Picker will disagree):

- `capacity.service.ts` — `listOverlappingActiveBookings`,
  `checkCapacity`'s Hotel/Daycare counts, and `confirmCapacityAfterInsert`
  (both the Grooming/Vet `assigned_staff_id` query and the Hotel/Daycare
  re-count).
- `availability.service.ts` — it calls the same `listOverlappingActiveBookings`
  and `getHotelCageCapacity`/`getDaycareSessionCapacity`, so it inherits
  the fix, but confirm the Slot Picker's day-grid reflects it.
- **`get_staff_availability()` RPC** — new migration redefining the
  function; its "Check 2" hardcodes `bk.status in ('Pending','In
Progress','Completed')` and must add
  `and not (bk.downpayment_required and bk.payment_stage = 'Unpaid')`.
  (Cautionary precedent: this function has been clobbered by parallel
  same-day migrations before — `20260808109` — so base the new one on the
  current definition and check the migration order.)
- The `bookings_staff_active_idx` partial index predicate should match the
  new rule so the RPC/query stays index-covered.
- `booking.service.ts` `UNRESOLVED_BOOKING_STATUSES` (duplicate-booking
  guard) — decide whether an unpaid-downpayment hold still blocks the same
  pet re-booking (probably yes — it's the same customer's in-flight
  attempt; don't want them double-holding).

Once the down payment is paid (`payment_stage` leaves `Unpaid` → `Paid in
Advance` or `Paid`), the booking starts holding the slot normally on the
next capacity read — but note this creates a **race**: two customers can
each have an unpaid hold on the last slot, and whoever pays first wins.
The paying booking's `advancePaymentStage` (or the webhook path) must
re-run `confirmCapacityAfterInsert`-style verification and, if the slot is
now genuinely full of _paid_ bookings, **fail the payment / refund** rather
than silently overbook. Spell this out in build (Open question 3).

### 4. Expiration + auto-release of unpaid holds

New nullable policy field:
`policy_configurations.downpayment_hold_expiry` — a small enum or minutes
value. Requirement text says _"e.g., due by end of day"_, so the default
is **end of the booking's branch-local day of creation**; allow an admin
to pick `end-of-day` / `1 hour` / `2 hours` / `24 hours` (final list TBD).

Mechanism — **follow the No-show precedent** (`applyNoShowTransition`):
lazy, read-time, no cron. There is no scheduled-job infra in this app; the
credit-expiry sweep (`creditExpiry.job.ts` / migration `098`) is the
closest thing and it's a manually-triggered RPC because pg_cron
availability is an open item.

- A `Pending` booking with `downpayment_required AND payment_stage =
'Unpaid' AND now() > downpayment_due_at` is flipped to **`Cancelled`**
  (reason: `downpayment_expired`) the next time it's read through
  `getBookingById` / `listBookings` — same bulk-update shape as
  `applyNoShowTransition`.
- Store the deadline on the row at creation:
  `bookings.downpayment_due_at timestamptz` (null for walk-ins and
  no-down-payment bookings), computed from the policy at `createBooking`
  time so a later policy change doesn't move existing deadlines.
- Because the slot was **already released** in §3 while unpaid, expiry is
  really just tidying up the dead row + notifying the customer
  (`booking_cancelled` / a new `downpayment_expired` notification — see
  [[M11-notification]]). No capacity is "returned" because none was held.
- The customer's **Pay** button must refuse a booking past its deadline
  (or one already swept to `Cancelled`), with a clear "this reservation
  expired, please re-book" message.
- Provide a manual sweep endpoint too (mirror `creditExpiry.job.ts`) so a
  staging environment without pg_cron can force it, and so the count is
  observable.

### 5. Full-vs-downpayment choice — no change

Done in #121/#122. Confirm during build that the choice is **hidden and
forced to full** for: walk-ins (already), and any category where down
payment doesn't apply. Veterinary is `payment_confirmed = false` always
(price is TBD until the vet finalizes it) — decide whether Vet online
bookings are exempt from the §1 gate entirely (Open question 4).

### 6. Payments Queue — mark paid, partial state, per-transaction detail

- **Mark as Paid** already exists. Keep the advance-vs-onsite modal.
- **"Partially paid" wording.** The underlying state is `payment_stage =
'Paid in Advance'` and `transactions.payment_status = 'Partially Paid'`.
  Rather than rename the enum (it's load-bearing across billing, DSR,
  checkout), add a **display mapping** in the Payments Queue / badges:
  show `Paid in Advance` as **"Partially Paid"** with the balance-due
  amount (`total_price − downpayment_amount`). One `PaymentStageBadge`
  change, no schema churn. (Note if the client would rather the DB enum
  actually read "Partially Paid" — that's a bigger migration, Open
  question 5.)
- **Marking a down-payment booking paid.** From `Paid in Advance`, "Mark as
  Paid" settles the balance → `Paid` / `transactions.payment_status =
'Fully Paid'`. From `Unpaid` with a down-payment booking, the
  advance-vs-onsite modal already handles "they're paying the down payment
  now" (`advance`) vs "they're paying in full now" (`onsite`).
- **Per-transaction payment details.** New read: `GET
/bookings/:id/transactions` (money-handling roles + the owning customer —
  RLS already allows both to `SELECT transactions`). Returns each
  `transactions` row for the booking: `created_at`, `payment_method`,
  `total_amount`, `payment_status`, `payment_choice`, `payment_reference`,
  `webhook_confirmed_at`, `processed_by_staff_id`. Surface it as an
  expandable panel / "View payments" affordance on each Payments Queue
  row (and reuse on `BookingDetailsPage`). This is display-only — no new
  write path.
  - **Overlaps with a separate backlog line** — _"Add a dedicated
    transactions page … to search, filter and sort all customer
    transactions (e.g. downpayment, full, etc.), where each transaction is
    linked to a booking"_ (also Matthew's, also In Progress). That's a
    _global_ transactions browser; `transactionHistory.service.ts` /
    M14-03 (Transaction History Search) already exists and likely covers
    most of it. Build the per-booking `GET /bookings/:id/transactions`
    view here; reconcile with / reuse the M14-03 endpoint rather than
    duplicating a second transactions list.

### 7. Discounts/promos before the down payment

In `createBooking`, **reorder**: run `resolveDiscountAndPromo` first, then
compute the down payment against the **net** total:

```text
netTotal = round2(totalPrice - discountAmount - promoAmount)
downpaymentAmount =
  downpayment_type = 'Percentage'
    ? round2(netTotal * downpayment_amount / 100)
    : min(downpayment_amount, netTotal)          // flat, never exceed the bill
```

- `resolveDiscountAndPromo` doesn't depend on the down payment, so moving
  it earlier is safe. `payment_stage` derivation and the `transactions`
  amount already flow from `downpaymentAmount`, so nothing downstream
  changes shape.
- Mirror the same `netTotal` base in `CustomerBookingFlowPage`'s preview
  (`downpaymentAmount` should come off `estimatedTotal`, not `subtotal`).
- `customerBookingPayment.service.ts` computes the remaining balance as
  `total_price − downpayment_amount`; keep that identity by having the
  stored `downpayment_amount` already be the net-based figure. Balance =
  `netTotal − downpaymentAmount` — audit every `total_price −
downpayment_amount` site (`payForBooking`, checkout preview) for the
  discount/promo/credit interaction.

## Schema changes (summary)

- `bookings.downpayment_due_at timestamptz` (nullable).
- `bookings` cancellation reason vocabulary gains `downpayment_expired`
  (check how cancellation reasons are stored — free text vs enum).
- `policy_configurations.downpayment_hold_expiry` (enum/int, nullable or
  defaulted).
- `get_staff_availability()` redefinition migration.
- `bookings_staff_active_idx` predicate update migration.
- Possibly a new `booking_cancelled` / `downpayment_expired` notification
  event (M11) — or reuse `booking_cancelled`.

## Non-goals

- Not touching the cashier's own `checkoutBooking` /
  `checkoutAggregation.service.ts` path — that always settles the full
  remaining balance in a staff-witnessed interaction and is out of scope.
- Not renaming the `payment_stage` / `payment_status` enums (§6 uses a
  display mapping instead) unless the client explicitly wants the DB value
  changed.
- Not adding real pg_cron infra — §4 uses the established lazy read-time
  pattern.
- Not solving the pre-existing "GCash selected ⇒ `payment_confirmed: true`
  with no actual checkout" behavior beyond what §1 already forces.
- Not changing walk-in behavior at all (auto-full, no down payment, no
  gate — #122).

## Open questions

1. **§1:** create-then-confirm-with-TTL (a) vs confirm-then-create (b) for
   GCash/Maya. Recommendation: (a).
2. **§1 + addendum A5:** the "advance payment" path — book online now, pay
   in person on the day, cashier marks it paid on arrival. Is this simply
   _the_ behaviour of every online booking that hasn't paid online yet
   (Pending, slot not held, expires end of day per §4, cashier can settle
   it via §6's Mark as Paid), or a distinct opt-in the customer chooses at
   the payment step? And what does it do when `online_payments_enabled =
false` for the branch — is "advance payment" then the _only_ online
   option?
3. **§3:** two unpaid holds on the last slot, both pay — the second
   payment must fail gracefully (refund / credit). Exact UX + refund
   mechanism?
4. **§5:** are Veterinary online bookings exempt from the §1 payment gate
   (price is TBD until the vet finalizes it, so there's nothing definite to
   take a down payment on)?
5. **§6:** display-only "Partially Paid" mapping, or actually migrate the
   `payment_status` enum value?
6. **§4:** exact expiry options offered to the admin (`end-of-day` only, or
   a set of durations?), and the branch-timezone handling for "end of
   day".

## What shipped

Branch `feat/downpayment-slot-gate-and-expiry`. The core realisation that
shaped the build: **§3 + §4 together _are_ the implementation of §1.**
"Never reserve a slot with zero payment" = "an unpaid down-payment booking
holds no slot and expires." No booking-flow restructuring or hard
pay-before-create redirect was needed (and PayMongo isn't live anyway —
addendum E11). So the booking is still created immediately; it just
reserves nothing until it pays.

**Scope decision:** the whole gate is keyed on `downpayment_enabled`. When
an Admin turns the down payment on, the slot-gate + expiry + release
behaviour activates; when it's off (today's default) nothing changes.
Requirements 3/4/5 only make sense with a down payment configured, so this
is the coherent reading.

### Migrations

- `20260829146_m09_policy_configurations_downpayment_hold_hours.sql` —
  `downpayment_hold_hours integer NOT NULL DEFAULT 24 CHECK (> 0)`.
- `20260829147_m03_bookings_downpayment_due_at.sql` —
  `downpayment_due_at timestamptz` (nullable).
- `20260829148_m03_get_staff_availability_downpayment_hold.sql` — Check 2
  now also excludes `downpayment_required AND payment_stage = 'Unpaid'`.
  (The `bookings_staff_active_idx` predicate was left status-only — the
  query predicate still implies it, so the index is still used; tightening
  it was pure micro-optimisation and skipped.)

### Server

- `booking.service.ts` `createBooking`: `resolveDiscountAndPromo` now runs
  **before** the down-payment block; down payment is `%`-of / capped-at
  the discounted `netTotal` (§7). `payment_confirmed` is honoured **only
  for a staff-created booking** — a customer's self-service booking is
  never created pre-paid (this is the §1 enforcement point). A
  `holdsSlot` flag (`!(downpayment_required && payment_stage === 'Unpaid')`)
  gates the pre-insert `checkCapacity` and post-insert
  `confirmCapacityAfterInsert` — a pencil booking skips both.
  `downpayment_due_at = now + downpayment_hold_hours` is stamped for the
  unpaid case.
- `applyDownpaymentExpiry(bookings)` — lazy read-time sweep (No-show
  precedent), run before `applyNoShowTransition` in `getBookingById` /
  `listBookings`; flips an unpaid past-deadline booking to `Cancelled`
  (reason: "Down payment not received before the reservation deadline").
- `advancePaymentStage`: when a down-payment booking leaves `Unpaid` it
  starts holding a slot, so it re-runs `confirmCapacityAfterInsert` and,
  if the slot filled while it sat unpaid, reverts to `Unpaid` + `409`
  ("reschedule to an open slot"). The webhook path already swallows/logs a
  thrown `advancePaymentStage` (Q3 — this is the "graceful fail", no
  auto-refund built since PayMongo is stubbed).
- `capacity.service.ts` — `listOverlappingActiveBookings` and
  `confirmCapacityAfterInsert` add `.or(SLOT_HOLD_PAID_OR_FILTER)` (new
  exported constant in `booking.types.ts`, same string the grooming/vet
  queues already used).
- `staffPicker.service.ts` — `EffectivePolicy` / `DOCUMENTED_DEFAULTS` /
  `updatePolicyConfiguration` baseline / `resolveDownpaymentPolicy` /
  `DownpaymentPolicy` all gain `downpayment_hold_hours`.
- `booking.validator.ts` — `updatePolicyValidator` gains
  `downpayment_hold_hours` (positive int).
- New `billing/services/bookingTransactions.service.ts` +
  `GET /billing/booking/:bookingId/transactions` (staff-only) — §6's
  per-booking payment list.

### Client

- `PolicyConfigurationPage` — new "Reservation hold (hours)" field in the
  Downpayment section; copy updated ("after any discount or promo").
- `PaymentStageBadge` — display-map only: `'Paid in Advance'` →
  **"Partially Paid"** everywhere the badge renders (DB enum unchanged —
  Q5 answered "display-only").
- `PaymentsQueuePage` — "View payments" / "Hide payments" in the row's
  `…` menu opens an inline panel listing each `transactions` row (amount,
  Down payment vs Full payment, method, status, date, reference), lazily
  fetched via `listBookingTransactions`.
- `CustomerBookingFlowPage` — down-payment preview now computed off the
  discounted `estimatedTotal` (§7); confirmation screen shows a
  "this slot is not reserved yet — pay by &lt;deadline&gt; or it's
  cancelled" banner for an unpaid pencil booking.
- `Booking` type gains `downpayment_due_at`; `PolicyConfiguration` /
  `EffectivePolicy` / `UpdatePolicyPayload` gain `downpayment_hold_hours`;
  `Transaction` gains `payment_choice`.

### Open-question resolutions

| Q   | Resolution                                                                                                                                                                                                                    |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Moot — no create-then-confirm _or_ confirm-then-create restructuring. The booking is created as a pencil booking; payment is a separate later step (existing Pay flow / cashier).                                             |
| 2   | "Advance payment" is simply the behaviour of every unpaid online down-payment booking — not a separate opt-in. `online_payments_enabled = false` was **not** specially handled in this pass (still an open item — see below). |
| 3   | `advancePaymentStage` reverts + 409s on a lost race; the webhook path logs it. No auto-refund/credit (PayMongo stubbed) — revisit when payments go live.                                                                      |
| 4   | Veterinary is naturally exempt: no `downpayment_required` (price TBD), so `holdsSlot` stays true and the §3/§4 behaviour never engages. `payment_confirmed` is already forced false for Vet.                                  |
| 5   | Display-only "Partially Paid" mapping.                                                                                                                                                                                        |
| 6   | Plain `downpayment_hold_hours` (default 24), not a calendar "end of day" — no timezone math, and since the slot is already free while unpaid, "24h from creation" and "end of day" are operationally equivalent.              |

### Still open / follow-up

- `online_payments_enabled = false` (PayMongo KYC fallback): an online
  customer booking that requires a down payment then has no way to pay
  online and will always expire. Needs a "branch confirms" path or a
  block on online self-service booking for that branch.
- No auto-refund/credit on the §3 lost-payment race (fine while PayMongo
  is a stub).
- `bookingNotifications` — no dedicated `downpayment_expired` /
  "pay your down payment" email yet; the in-app booking list + the
  confirmation-screen banner are the only nudges.
- The separate "dedicated transactions page" backlog line (global
  search/filter over all transactions) is untouched — M14-03 already
  covers most of it.
