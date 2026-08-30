---
title: Transactions page & booking-queue "confirmation" status
date: 2026-08-30
tags: [decision, booking, payment, transactions, queue, status]
project: golden-fur
---

Source request: the **"Not Started"** row assigned to Matthew in
`Inbox/Architectural-Change-History.docx` (which supersedes the now-removed
`Projects/golden-fur/context/Architectural-Change-Suggestions.docx`). Verbatim:

1. Add a dedicated transactions page (_"I think it's already there"_) to search, filter and
   sort all customer transactions (e.g. downpayment, full, etc.), where each transaction is
   linked to a booking.
2. Online bookings of status pending payment will appear here for cashiers to mark as paid.
3. Make other queues pull bookings from the payments queue (fully paid or partially paid),
   instead of relying on the bookings queue (`status IS NOT pending`).
4. Or perhaps just add an extra status in the bookings queue before pending (e.g.
   `unconfirmed`) that specifies an online booking is still not paid.
5. Perhaps revamp the entire bookings-queue status to something like:
   `unconfirmed > confirmed > no show > cancelled`.
6. While all the other queues use the standard status: `pending > in progress > completed`.

**Clarification (Matthew, on bullets 4/5):** `unconfirmed` is _not_ a manual step. An online
booking that hasn't been paid is not secure, holds no slot, and shouldn't really register in
the queue as a real appointment — hence `unconfirmed`. It becomes `confirmed` once paid, then
`completed` once its counterpart in a module queue (vet / grooming / hotel / daycare) is also
completed. The point is to make the **receptionist** bookings-queue view legible.

> **Status: implemented** on branch `feat/receptionist-confirmation-status` (golden-fur),
> 2026-08-30. Recommendations #1–#3 (plus the customer-facing carry-over) were built; the
> `booking_status` enum was **not** migrated (#6). See "What shipped" at the end.

Builds on [[2026-08-29-online-payment-gate-and-downpayment-holds]] (#123 — the down-payment
slot gate) and [[2026-08-28-walk-in-booking-flow]] (#122).

## Current state (verified against the code, 2026-08-30)

The recent status unification (migrations `20260728058`, `20260803083`), the walk-in flow
(#122), and the down-payment slot gate (#123) already established **three orthogonal axes**
on a booking:

| Axis             | Values                                                                             | Notes                                                                                                                                                                                                     |
| ---------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `status`         | `Pending → In Progress → Completed`, plus `Cancelled`, `No-show`                   | `Confirmed` **and** `Paid` were deliberately retired. `No-show` is a lazy read-time flip. `completeBooking` is shared — hotel checkout / grooming complete / vet complete all set `status = 'Completed'`. |
| `payment_stage`  | `Unpaid → Paid in Advance → Paid`                                                  | Independent of `status`. `PaymentStageBadge` already display-maps `Paid in Advance → "Partially Paid"`. Cashier advances it via `/staff/billing/payments-queue` "Mark as Paid".                           |
| `booking_source` | `Online` (born `Pending`) / `Walk-in` (born `In Progress`, skips the down payment) | `20260828145`, #122.                                                                                                                                                                                      |

Key facts:

- **The `unconfirmed → confirmed` transition already exists in the data.** An unpaid
  down-payment online booking is a "pencil booking": `status = Pending`,
  `payment_stage = Unpaid`, holds no slot (`SLOT_HOLD_PAID_OR_FILTER` excludes it from
  capacity and from all four module queues), and auto-cancels at `downpayment_due_at` via
  `applyDownpaymentExpiry`. Once paid, `advancePaymentStage` re-checks capacity and it starts
  holding a real slot. It just isn't surfaced as a single lifecycle label.
- **Bullet 3 is already implemented.** All four module queues already exclude
  unpaid-downpayment bookings — Grooming (`grooming.service.ts:104`) and Veterinary
  (`consultation.service.ts:127`) bake in `.or('downpayment_required.eq.false,payment_stage.neq.Unpaid')`;
  the Hotel and Daycare check-in pickers pass the same via `excludeUnpaidDownpayment`
  (`booking.service.ts:1274`). There is **no separate "payments queue" data source** —
  `PaymentsQueuePage` is `listBookings` filtered by `payment_stage`.
- **Bullet 6 is already the model** — every module queue shares one status vocabulary
  (`ACTIVE_BOOKING_STATUSES = Pending/In Progress/Completed`).
- **A staff transactions page already exists**: `/staff/reports/transaction-history`
  (`TransactionHistoryTable`, Issue #105/#102), money-role-gated, filtering
  customer / pet / date range / service category server-side via
  `transactionHistory.service.ts`. Customer counterpart: `/portal/transactions`. `transactions`
  is one row **per payment event** with FK `booking_id` (nullable only for `miscellaneous_sale`),
  `payment_choice` (`full`/`downpayment`), `payment_status`, `payment_method`,
  `payment_reference`, `processed_by_staff_id`.
- **Per-booking payment detail already exists**: `GET /billing/booking/:id/transactions`
  plus the "View payments" panel on `PaymentsQueuePage` (shipped with #123).
- **Real gap:** `ReceptionistBookingsQueuePage` renders a `Check In` button for _any_
  `Pending` booking (line ~1036), and server `startBooking` (`booking.service.ts:1448`) only
  checks `status === 'Pending'` — **no payment gate**. A receptionist can therefore check in
  an unpaid pencil booking, moving it to `In Progress`, where it is excluded from the module
  queues (payment filter) _and_ no longer subject to down-payment expiry (which only targets
  `Pending`). Dead-end state.

## Ranked assessment

### 1. Surface a derived "confirmation" lifecycle on the receptionist bookings queue — recommended

Implement bullets 4/5 as a **display mapping over the fields that already exist**, not a
schema/enum change. The receptionist queue (and its status filter) speaks a 4-stage
vocabulary:

| Shown as                          | Derived from                                                                                                                                               | Check In offered? |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| **Unconfirmed**                   | `status = Pending` AND `downpayment_required` AND `payment_stage = 'Unpaid'` (the pencil booking — no slot held). Show the `downpayment_due_at` countdown. | No                |
| **Confirmed**                     | `status = Pending` AND not the above (paid, walk-in, or no down payment required)                                                                          | Yes               |
| **In service**                    | `status = 'In Progress'` (counterpart is live in a module queue)                                                                                           | —                 |
| **Completed**                     | `status = 'Completed'` (module-queue counterpart finished)                                                                                                 | —                 |
| **No-show / Cancelled / Expired** | `status` in `No-show` / `Cancelled`; relabel the `downpayment_expired` cancellation reason as "Expired" for this view                                      | —                 |

- A `BookingConfirmationBadge` component + a `deriveConfirmationState(booking)` helper —
  mirrors the existing `PaymentStageBadge` display-map precedent. No migration, no RPC
  change, nothing touching `payment_stage` / billing / DSR / capacity.
- **Gate the `Check In` action on `Confirmed`** — client button visibility, and a matching
  server guard in `startBooking` (reject when `downpayment_required && payment_stage === 'Unpaid'`).
  This closes the dead-end above.
- **Scope boundary (open question):** "Unconfirmed" as defined here only exists when the
  down-payment policy is switched on. Treating _every_ unpaid online booking as "Unconfirmed"
  (and not holding its slot) means reopening the deferred "require payment on every online
  booking" work (`online_payments_enabled` fallback, PayMongo KYC — see
  [[2026-08-29-online-payment-gate-and-downpayment-holds]] "still open"). Recommend keeping
  the narrow scope.
- If server-side filter/sort by this vocabulary is wanted later, a Postgres
  `GENERATED ALWAYS AS` column stays consistent automatically — but start with the
  client-derived badge.

### 2. Transactions page (bullet 1) — "already there", minor polish backlog

Add to `TransactionHistoryTable` / `transactionHistory.service.ts`: column sorting (reuse
`useSearchAndSort` + `SearchSortBar`), a `transaction_type` / `payment_choice` filter
("downpayment, full, …"), per-row navigation to `/staff/bookings/:booking_id`, and drop the
`!inner` join so misc-sale rows appear. Client plus a few query params; no schema. Bullet 2
needs nothing — cashiers already mark paid on `/staff/billing/payments-queue` filtered to
`payment_stage = Unpaid`.

### 3. Reuse the per-booking payments panel on `BookingDetailsPage`

`GET /billing/booking/:id/transactions` already exists; dropping the `PaymentsQueuePage`
panel onto `BookingDetailsPage` makes the booking ↔ transaction link bidirectional. Cheap,
self-contained.

### 4. Extend the confirmation vocabulary to the customer's own bookings list — optional

Follow-on to #1. "Confirmed" is reassuring customer-facing language too, and one vocabulary
across both audiences is cleaner.

### 5. Bullets 3 & 6 — no action, already implemented

See "Current state" above.

### 6. Migrating the actual `booking_status` DB enum to `unconfirmed/confirmed/…` — not recommended

The derived label in #1 delivers the full receptionist-legibility benefit. A real enum
migration reverses `20260728058` (which retired `Confirmed` precisely because there is no
confirm step), and ripples through `payment_stage`-coupled billing / DSR / checkout, the
`get_staff_availability()` RPC, every module queue, badges, and notification triggers —
high blast radius for a presentation goal a derived value achieves safely.

## Conclusion

Close the row, keeping only:

- **#1** — derived confirmation status + the Check In gate. Genuinely useful for the
  receptionist and it fixes a real hole. Small: one badge component, one helper, one client
  guard, one server guard.
- **#2** — the transaction-history polish, as a minor backlog line.

Bullets 3 and 6 are done. Bullet 5's literal reading (a status-enum migration) is not worth
the blast radius.

## What shipped

Branch `feat/receptionist-confirmation-status` (golden-fur), off `dev`, 2026-08-30.
Full server suite green (902), full client suite green (720). No migration.

### Server

- `booking.types.ts` — new `DOWNPAYMENT_EXPIRED_CANCELLATION_REASON` constant (was a
  hardcoded string in `applyDownpaymentExpiry`).
- `booking.service.ts` `startBooking` — now 409s when
  `downpayment_required && payment_stage === 'Unpaid'`, closing the hole where a receptionist
  could check in an unpaid pencil booking into a dead-end `In Progress` state. Two spec
  tests added (rejects unpaid; allows once the down payment is in).
- `reports.types.ts` / `transactionHistory.service.ts` / `reports.controller.ts` — the
  transaction-history endpoints (staff + customer) gained `transaction_type` /
  `payment_choice` filters. New `transactionHistory.service.spec.ts` (feature had no specs).

### Client — confirmation status (rec #1)

- `booking.types.ts` — `BookingConfirmationState` type + `BOOKING_CONFIRMATION_STATES` +
  mirrored reason constant.
- `bookingConfirmation.ts` — `deriveBookingConfirmationState(booking)` (pure, unit-tested)
  and a per-state hint map. Purely derived from `status` + `payment_stage` +
  `downpayment_required` + `cancellation_reason`.
- `components/shared/BookingConfirmationBadge/` — new pill, reuses the existing
  booking-status color tokens.
- `ReceptionistBookingsQueuePage` — badge swapped in; the "Status" filter now offers the
  confirmation vocabulary (maps to a coarse server `status`, split client-side); "Check In"
  gated to `Confirmed`; an amber hint row on `Unconfirmed` bookings showing the
  `downpayment_due_at` deadline.
- `CustomerBookingsPage` — same badge (one vocabulary for both audiences).

### Client — transactions page (rec #2)

- `TransactionHistoryTable` — transaction-type + payment-choice filter selects, a
  client-side search + date/amount sort (shared `useSearchAndSort` + `SearchSortBar`), a
  "Payment" column (full vs down payment), and a per-row **View booking** link to
  `/staff/bookings/:id`.
- `CustomerTransactionHistoryPage` — mirrors the payment-choice filter + sort.
- `reports.types.ts` / `reports.api.ts` — `payment_choice` on `TransactionRecord`, new
  filter params. New `TransactionHistoryTable.spec.ts`.

### Client — per-booking payments panel (rec #3)

- `billing/components/BookingPaymentsPanel/` — extracted from `PaymentsQueuePage`'s inline
  "View payments" panel into a self-fetching component (own spec). `PaymentsQueuePage` now
  renders it (dropping ~60 lines of fetch/cache state); `BookingDetailsPage` renders it in
  its Payment section — the booking ↔ transaction link now goes both ways.

### Not done (deliberately)

- No `booking_status` enum migration (#6) — the derived label carries the full benefit.
- "Unconfirmed" only exists while the down-payment policy is on (narrow scope — see the
  open question above).
