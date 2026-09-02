# Transactions page polish + receptionist "confirmation" status on the bookings queue

Branch: `feat/receptionist-confirmation-status` (off `dev`, not yet committed — all
changes staged, working tree otherwise clean).

## The request, verbatim

From the **"Not Started"** task row assigned to Matthew in
`Inbox/Architectural-Change-History.docx`:

> - Add a dedicated transactions page (I think it's already there) to search, filter and
>   sort all customer transactions (e.g. downpayment, full, etc.), where each transaction is
>   linked to a booking
> - Online bookings of status pending payment will appear here for cashiers to mark as paid
> - Make other queues pull bookings from payments queue (fully paid or partially paid),
>   instead of relying on bookings queue (status IS NOT pending)
> - Or perhaps just add an extra status in bookings queue before pending (e.g. unconfirmed),
>   that specifies that an online booking is still not paid
> - Perhaps revamp entire bookings queue status to something like:
>   unconfirmed > confirmed > no show > cancelled
> - While all the other queues will use the standard status: pending > in progress > completed

Then, after a ranked advisory: _"implement all your recommendations to the golden-fur repo"_.

**Clarification the user gave on the `unconfirmed` idea:** it is NOT a manual step — an
online booking that hasn't been paid isn't secure, holds no slot, shouldn't register in the
queue as a real appointment, so it's `unconfirmed`; becomes `confirmed` once paid, then
`completed` when its module-queue counterpart completes; the point is to make the
receptionist bookings-queue view legible.

## Root cause / Context

The advisory (`Projects/golden-fur/decisions/2026-08-30-transactions-page-and-confirmation-status.md`)
concluded:

- The three booking axes (`status`, `payment_stage`, `booking_source`) already carry the
  `unconfirmed → confirmed` transition in the data — an unpaid, down-payment-required Online
  booking is a "pencil booking" (`status = Pending`, `payment_stage = Unpaid`) that holds no
  slot (`SLOT_HOLD_PAID_OR_FILTER` excludes it from capacity and all four module queues) and
  auto-cancels at `downpayment_due_at`. It just wasn't surfaced as one legible label.
- Bullets 3 and 6 are already implemented — every module queue already excludes
  unpaid-downpayment rows and already shares the `Pending → In Progress → Completed`
  vocabulary.
- A staff transactions page already exists (`/staff/reports/transaction-history`, Issue
  #105/#102) and a customer one (`/portal/transactions`).
- **Real gap:** `startBooking` only checked `status === 'Pending'` — a receptionist could
  hit "Check In" on an unpaid pencil booking, moving it to `In Progress`, where it is
  excluded from the module queues (payment filter) _and_ no longer swept by down-payment
  expiry (which only targets `Pending`). Dead-end state.

Decision: implement bullets 4/5 as a **derived display label**, NOT a `booking_status` enum
migration (that reverses `20260728058`, which retired `Confirmed` precisely because there is
no confirm step, and ripples through `payment_stage`-coupled billing / DSR / checkout, the
`get_staff_availability()` RPC, every queue, badges and notification triggers). Plus close
the Check In hole with a server guard, and do the transaction-page polish.

**No migration was added** — no `booking_status` enum change, no DB change at all.

## What changed

### Server

- `features/booking/booking.types.ts` — new `DOWNPAYMENT_EXPIRED_CANCELLATION_REASON`
  constant (was a bare string literal inside `applyDownpaymentExpiry`). Exported so the
  client can tell an expiry-swept cancellation apart from a real one.
- `features/booking/services/booking.service.ts`:
  - `applyDownpaymentExpiry` now writes the new constant instead of the inline string.
  - `startBooking` now throws **409** when `booking.downpayment_required && booking.payment_stage === 'Unpaid'`
    ("This booking's down payment hasn't been paid yet, so it can't be checked in."), before
    the status update — closing the dead-end. Also safe for the internal Hotel/Daycare
    check-in callers (they already filter these rows out upstream).
- `features/booking/services/booking.service.spec.ts` — +2 `startBooking` tests (rejects an
  unpaid down-payment booking with 409 and writes nothing; allows it once `payment_stage`
  is past `Unpaid`).
- `features/reports/reports.types.ts` — `TransactionHistoryFilters` gains `transactionType`
  and `paymentChoice`.
- `features/reports/reports.controller.ts` — both `transactionHistoryController` and
  `customerTransactionHistoryController` now read `transaction_type` / `payment_choice`
  query params.
- `features/reports/services/transactionHistory.service.ts` — applies
  `.eq('transaction_type', …)` / `.eq('payment_choice', …)` when set.
- `features/reports/services/transactionHistory.service.spec.ts` — **new** (the feature had
  no specs): 4 tests covering the left vs `!inner` bookings join, the two new filters, and
  the 400-on-query-error path.

### Client — confirmation status

- `features/booking/booking.types.ts` — new `BookingConfirmationState` union
  (`Unconfirmed | Confirmed | In service | Completed | Expired | Cancelled | No-show`),
  `BOOKING_CONFIRMATION_STATES`, and a mirrored
  `DOWNPAYMENT_EXPIRED_CANCELLATION_REASON`.
- `features/booking/bookingConfirmation.ts` — **new**: pure
  `deriveBookingConfirmationState(booking)` over
  `status` + `payment_stage` + `downpayment_required` + `cancellation_reason`, plus a
  per-state `BOOKING_CONFIRMATION_HINT` map. `.spec.ts` alongside (7 cases).
- `features/booking/components/shared/BookingConfirmationBadge/` — **new** pill component,
  reuses the existing `--color-booking-*` tokens (Unconfirmed borrows Pending's amber,
  Confirmed borrows Paid's green).
- `features/booking/pages/ReceptionistBookingsQueuePage/`:
  - badge swapped from `BookingStatusBadge` to `BookingConfirmationBadge`;
  - the "Status" filter now offers the confirmation vocabulary. It maps to a coarser server
    `status` param via `confirmationToStatusParam` (Unconfirmed/Confirmed → `Pending`,
    In service → `In Progress`, Expired/Cancelled → `Cancelled`, …); the fine split
    (Unconfirmed vs Confirmed, Expired vs Cancelled) is then done client-side in a new
    `confirmationFilteredBookings` memo before search/sort;
  - "Check In" button is now gated on `confirmationState === 'Confirmed'` (was
    `booking.status === 'Pending'`);
  - an amber `unconfirmedHint` row renders under an `Unconfirmed` booking, appending
    `Due <downpayment_due_at>` when present.
  - `.spec.ts` — +new `describe('confirmation status')` (3 tests); `.module.css` gains
    `.unconfirmedHint`.
- `features/booking/pages/CustomerBookingsPage/` — same badge swap (one vocabulary for both
  audiences). `.spec.ts` assertions updated `Pending` → `Confirmed`.

### Client — transactions page

- `features/reports/reports.types.ts` — `payment_choice: string | null` on
  `TransactionRecord`.
- `features/reports/api/reports.api.ts` — `transactionType` / `paymentChoice` on
  `TransactionHistoryFilters`, serialized to `transaction_type` / `payment_choice`;
  `getMyTransactionHistory` accepts `paymentChoice`.
- `features/reports/components/TransactionHistoryTable/`:
  - "Transaction type" and "Payment" filter selects (server-side params);
  - a `SearchSortBar` (shared `useSearchAndSort`) — free-text search over
    method/status/service/misc-description, plus Date/Amount sort;
  - a "Payment" column (Down payment / Full payment / `-`);
  - a per-row "View booking" `<Link>` to `/staff/bookings/:booking_id` (omitted for
    booking-less misc sales);
  - amount label changed from `₱` to `PHP `.
  - `.spec.ts` — **new** (3 tests: filters passed to the API, booking link present/omitted,
    amount sort).
- `features/reports/pages/CustomerTransactionHistoryPage/` — mirrors the payment-choice
  filter, the search+sort bar, the "Payment" column, and the `PHP ` label.

### Client — per-booking payments panel

- `features/billing/components/BookingPaymentsPanel/` — **new**: the "View payments" panel
  extracted out of `PaymentsQueuePage`'s inline JSX into a self-fetching component
  (`listBookingTransactions` on mount, own loading / error / empty states). `.spec.ts`
  alongside (3 tests). `.module.css` moved here.
- `features/billing/pages/PaymentsQueuePage/` — now renders `<BookingPaymentsPanel>`; drops
  ~60 lines of `transactionsByBooking` / `transactionsLoadingId` / `transactionsError`
  state and its now-dead CSS. `togglePayments` is now synchronous (just tracks the open
  row).
- `features/booking/pages/BookingDetailsPage/` — renders `<BookingPaymentsPanel>` in its
  Payment section, making the booking ↔ transaction link bidirectional. `.spec.ts` adds one
  assertion (panel mounted with the booking id; the panel itself is mocked there).

## Verification

### 1. Receptionist bookings queue — Unconfirmed vs Confirmed

As a Receptionist, open `/staff/bookings` (the receptionist bookings queue). With the
down-payment policy enabled for the branch:

1. An Online booking whose down payment is still `Unpaid` shows the **Unconfirmed** pill
   (amber), an amber hint row ("Down payment not paid — this slot isn't reserved and the
   booking expires if it stays unpaid." + "Due <date/time>." when `downpayment_due_at` is
   set), and **no "Check In" button**.
2. After that down payment is marked paid (Payments Queue → Mark as Paid, or the customer
   pays online), the same booking flips to **Confirmed** (green) and the "Check In" button
   appears.
3. A walk-in / no-down-payment `Pending` booking shows **Confirmed** immediately.
4. Set the "Status" filter to **Unconfirmed** — the network call goes out with
   `status=Pending`, and the visible list is then narrowed client-side to just the
   unconfirmed rows. Repeat with **Confirmed**, **In service**, **Expired**, **Cancelled**.
5. A booking auto-cancelled by the down-payment expiry sweep shows **Expired**, not
   **Cancelled**; a manually cancelled one still shows **Cancelled**.

### 2. Check In gate (server)

See the Postman collection — `POST /bookings/:id/start` against an unpaid,
down-payment-required booking must return **409** and leave the row untouched; the same call
succeeds once `payment_stage` is past `Unpaid`.

### 3. Customer bookings list

As a customer, open `/portal/bookings` — a paid / no-down-payment `Pending` booking reads as
**Confirmed** (was "Pending"); an unpaid down-payment one reads as **Unconfirmed**.

### 4. Staff transactions page

As a Cashier (or Admin/Supervisor/Superadmin), open `/staff/reports/transaction-history`:

1. "Transaction type" = Booking payment, "Payment" = Down payment — the table narrows to
   down-payment booking rows (see Postman for the API-level assertion).
2. Type in the search box (e.g. a payment method or service) — rows filter client-side.
3. Switch the sort to "Amount (high to low)" — rows reorder by `total_amount`.
4. Each booking-payment row has a "View booking" link to `/staff/bookings/:id`; misc-sale
   rows show `-`.

### 5. Customer transactions page

As a customer, open `/portal/transactions` — the "Payment" filter, search box, sort, and
"Payment" column behave the same (no customer/pet picker, no "View booking" link).

### 6. Per-booking payments panel

- `/staff/billing/payments-queue` → a row's "View payments" still shows the same payment
  history (now via the extracted component).
- `/staff/bookings/:id` → the Payment section now also lists every payment recorded against
  that booking (date, amount, full vs down payment, method, status, reference).

## Test suites

Run from the repo on this branch:

- `server`: `npm run test` — **902/902 passing (86 files)**. `npx tsc --noEmit` clean.
  `npx eslint .` — **0 errors** (33 pre-existing `no-console` warnings, none in the changed
  files).
- `client`: `npx vitest run --testTimeout=30000` — **720/720 passing (140 files)** for this
  change set; **724/724 (141 files)** once `56-booking-flow-walkin-and-downpayment-ux`
  landed on the same branch/PR. (This machine times out heavier specs at the default
  5000 ms — same note as `Down-payment slot gate` memory.) `npx tsc -b` clean.
  `npx eslint .` — 0 errors (after the fix below).

## Resolved during review

- **`react-hooks/set-state-in-effect` error in `BookingPaymentsPanel`** (initially reported
  by this doc's own pass): the extracted component's `useEffect` reset state synchronously
  (`setTransactions(null); setError(null);`) — the inline `PaymentsQueuePage` version hadn't
  hit the rule because it reset in an event handler. Fixed by collapsing to a single `state`
  object carrying `loadedFor` (the booking the rows belong to); `isLoading` is derived as
  `state.loadedFor !== bookingId`, so a `bookingId` change re-shows the loading state with
  no synchronous reset. `npx eslint .` on the client is now clean; the 3 affected specs
  (`BookingPaymentsPanel`, `PaymentsQueuePage`, `BookingDetailsPage`) stay green.

## Revision — "Unconfirmed" broadened + notifications gated + cashier nav (after the first live test)

The first pass scoped "Unconfirmed" to down-payment-required bookings only (the open item
flagged below). Live testing showed the user's intent is broader — **any unpaid online
booking is Unconfirmed**, whether or not a down-payment policy is configured — and surfaced
three related gaps:

- **`bookingConfirmation.ts` `deriveBookingConfirmationState`** — a `Pending` booking is now
  `Unconfirmed` iff `booking_source === 'Online' && service_category !== 'Veterinary' &&
payment_stage === 'Unpaid'`. `downpayment_required` no longer participates. Veterinary is
  exempt (priced during the visit); walk-ins are `Confirmed` (customer is present). Badge
  prop + spec updated.
- **`booking.service.ts` `createBooking`** — `payment_stage` is now set to `'Paid'` (or
  `'Paid in Advance'`) whenever `payment_confirmed`, not only for down-payment bookings; an
  unpaid online booking falls through to the column default `'Unpaid'` → reads as
  Unconfirmed.
- **Notifications gated** — `sendBookingConfirmedNotification` + `sendStaffAssignedNotification`
  now fire from `createBooking` only when the booking is confirmed at creation (walk-in /
  Veterinary / `payment_confirmed`). For an Unconfirmed booking they fire later, from
  `advancePaymentStage`, the first time a payment moves it off `Unpaid` while still Pending.
  (Fixes: "the assigned groomer received a notif — it should only notify when confirmed".)
- **`startBooking` (Check In) gate broadened** to the same condition (Online + non-Vet +
  Unpaid → 409). Client already hides Check In for a non-`Confirmed` row.
- **Cashier sidebar** — `staffDashboard.config.ts` gained a **Transaction History** tile for
  the Cashier role (route + `TRANSACTION_HISTORY_READ_ROLES` already allowed Cashier; it was
  just missing from nav).
- **Payments Queue "Mark as Paid"** — a booking with no down payment now goes straight to
  Paid (no modal); a down-payment booking's modal is retitled "Record payment", shows the
  down-payment amount, and its two actions are **"Down payment only (Partially Paid)"** /
  **"Full amount (Fully Paid)"**. (Fixes: "no option to mark the downpayment as partially
  paid or the whole as fully paid".)

## Revision 2 — Payments Queue is now a real payment ledger (second live test)

- **500 on the first "Mark as Paid"** — the notification block added in revision 1 called
  `.some()` on `updated.staff_picker_preferences`, which PostgREST returns as a single
  object (not an array) for a one-per-booking relation → `TypeError` → 500 (after the
  `payment_stage` update had already committed). Fixed: normalise to an array, and wrap the
  whole post-update block (transaction write + notifications) in a `try/catch` — none of it
  should ever undo a payment the cashier just took.
- **One status pill per row** — the Payments Queue row dropped `BookingStatusBadge`; the
  single `PaymentStageBadge` gained a `context="billing"` variant reading **"Due payment"
  / "Partially Paid" / "Fully Paid"** (no "Payment:" prefix).
- **"Mark as Paid" now writes `transactions` rows** — `advancePaymentStage` (staff path
  only, keyed on `processedByStaffId` from the controller) inserts one `booking_payment`
  transaction + a matching line item per payment: the **down payment** (`payment_choice`
  `downpayment`, Partially Paid), the **remaining balance** (Fully Paid), or a **full
  payment** (Fully Paid). Each links to the booking, so it shows in Transaction History
  (with the "View booking" link) and the per-booking payments panel. The webhook path is
  unchanged (it already has a row from `payForBooking`). `checkoutAggregation`'s
  single-transaction guard was loosened from `.maybeSingle()` to a `.limit(1)` list check
  so a booking with two payment rows doesn't crash checkout.
- **Modal flow** — Unpaid + down payment required → "Record payment" modal (Down payment /
  Full amount). Unpaid + no down payment → straight to Fully Paid. **Partially Paid → a
  "Record remaining balance (PHP X)" confirmation modal** (was a silent one-click advance).
- **Transaction History** shows `payment_status` `Pending` as **"Due payment"**.

Server **906/906**, client **730/730 (142 files)**, both `tsc` clean, `eslint` 0 errors.

### Still open

- **Cashier sees "Unknown pet / Unknown owner"** on the Payments Queue — `getPet` /
  `getCustomerProfile` 403 for the Cashier role. Pre-existing (visible before any of this
  work); a permissions question, not touched here.
- The per-booking "View payments" panel doesn't live-refresh after "Mark as Paid" in the
  same row — reopen it to see the new transaction. Minor.

### Not changed (by design, explained to the user)

- An Unconfirmed booking still **holds its time slot** (it's still `Pending` and counts for
  capacity when no down-payment policy applies). Making unpaid online bookings hold no slot
  at all is the deferred "require payment on every online booking" work (advisor A1) — a
  bigger, separate change.
- A `Confirmed` (paid, `Pending`) grooming booking does **not** appear in the Grooming Queue
  until it is checked in — the module queues only show `In Progress`. Flow:
  Unconfirmed → (record payment) → Confirmed → (Check In) → In service → shows in the
  Grooming Queue.

## Open items

- No `booking_status` enum migration (bullet 5's literal reading) — deliberately not done,
  per the advisory. The derived label carries the full receptionist-legibility benefit.
- "Unconfirmed" only exists while the branch down-payment policy is enabled. Treating
  _every_ unpaid Online booking as Unconfirmed reopens the deferred "require payment on
  every online booking" work — deliberately out of scope here.
- Bullets 2, 3 and 6 needed no code — cashiers already mark paid on the Payments Queue
  (`payment_stage = Unpaid` filter), and the module queues already exclude unpaid-downpayment
  rows and already share the standard status vocabulary.
