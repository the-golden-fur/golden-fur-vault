# Payment / transactions rework — booking payment_status is a transactions rollup, per-transaction payment on a Transactions page

Branch: `feat/payment-transactions-rework` (compared against `dev`)

Commits in scope (all since `4462451`):

- `2004e9c` wip(payments): rework payment/transactions model — server + migrations
- `19d9da0` wip(payments): server specs green for the new payment model
- `40d3131` wip(payments): client — TransactionsPage, sweep, booking-flow payment step
- `57023bb` wip(payments): fold Misc controls into bookings queue, TransactionsPage tests

## The request, verbatim

> Write the verification record for the payment/transactions rework on branch
> `feat/payment-transactions-rework` (golden-fur). Compare against `dev`.
> Relevant commits: 2004e9c, 19d9da0, 40d3131, 57023bb (all since `4462451`).
>
> The 8 migrations `supabase/migrations/20260901150..157` HAVE NOW BEEN PUSHED
> to the linked Supabase project (confirmed via `supabase migration list
> --linked`). The local Docker stack was down, so they were applied straight
> to the linked DB without a local dry-run — note that.
>
> What changed (a planned 4-phase rework):
>
> 1. Dropped `bookings.payment_stage` (Unpaid/Paid in Advance/Paid enum +
>    column + index). Replaced by `bookings.payment_status` which REUSES the
>    `transactions.payment_status` enum (Pending / Partially Paid / Fully
>    Paid) — a stored rollup of the booking's settled `booking_payment`
>    transactions vs `netTotal = total_price - discount_amount -
>    promo_amount`. Backfill: Unpaid→Pending, Paid in Advance→Partially Paid,
>    Paid→Fully Paid.
> 2. Booking flow no longer collects a payment method. The booking step asks
>    only a "payment scheme" (pay in full vs down payment) when a downpayment
>    policy is active. `createBooking` emits ONE `Pending` `booking_payment`
>    transaction (full net total, or the down-payment amount for
>    `payment_scheme: 'downpayment'`) via `createInitialBookingCharge` —
>    best-effort, skipped for Veterinary. New export
>    `recomputeBookingPaymentStatus(bookingId)` for the webhook path.
> 3. Per-transaction payment on a new Transactions page
>    (`client/src/features/billing/pages/TransactionsPage/`). 3 new server
>    endpoints (billing feature): `POST /billing/transactions/:id/pay`
>    (recordTransactionPayment → `settle_transaction` RPC), `POST
>    /billing/bookings/:id/payments` (addBookingPayment → `add_booking_payment`
>    RPC, unlimited balance payments), `POST
>    /billing/transactions/:id/pay-with-credit` (payTransactionWithCredit,
>    full-cover only, sets `payment_method='Credit'`). New
>    `server/src/features/billing/services/transactionPayment.service.ts`.
> 4. Payments Queue deleted. Its Misc-category Start/Complete + pet-assessment
>    capture modal + Admin status-override folded into
>    `ReceptionistBookingsQueuePage`.
> 5. Real credit redemption — `creditStub.service.ts` now calls the
>    `redeem_credit` RPC; `applyCredit` gained an optional `transactionId` arg.
>
> [migration list + test status as given — reproduced under "Test suites"]
>
> Follow the testing-documentation skill. File under
> `Projects/golden-fur/testing/custom/` … Include a Postman collection for the
> 3 new billing endpoints and a migration reference SQL section.

## Root cause / Context

Before this rework a booking carried **two independent payment concepts**:

- `bookings.payment_stage` (`payment_stage` enum: `Unpaid` / `Paid in
  Advance` / `Paid`, added 20260803082) — a bespoke, manually-advanced track.
  A cashier moved it forward with the Payments Queue's "Mark as Paid" action
  (`advancePaymentStage`), and Admin/Superadmin could override it
  (`overridePaymentStage`). `completeBooking` also auto-advanced it to `Paid`
  when an online payment had been pre-confirmed.
- `transactions.payment_status` (`payment_status` enum: `Pending` /
  `Partially Paid` / `Fully Paid`, from 20260731068) — the real per-payment
  record.

The two duplicated the same idea and could disagree. This rework collapses
them (consistent with the user's standing preference for merging overlapping
status concepts): a booking's payment state becomes a **stored rollup** of its
`booking_payment` transactions, reusing the `payment_status` enum on
`bookings`, kept current by two SECURITY DEFINER RPCs. The Payments Queue —
whose only remaining job was advancing `payment_stage` — is deleted; payment
now happens per transaction on a new Transactions page, and a booking can
carry several payments (a down payment plus one or more balance payments).

Also folded in: the real credit-redemption path (Epic B `credit_balances` /
`credit_transactions` has shipped, so `creditStub.service.ts` stops being a
no-op stub), and the Misc-category Start/Complete + pet-assessment-capture
controls that lived on the Payments Queue move to the receptionist bookings
queue (Misc/assessment bookings have no dedicated queue of their own).

## What changed

### Database — 8 migrations, `supabase/migrations/`

All applied to the **linked** Supabase project via `supabase db push`
(`supabase migration list --linked` shows remote through `20260901157`).
**The local Docker stack was down at push time**, so there was no local
`supabase db reset` / local-apply dry-run before pushing — the migrations
went straight to the linked DB. Reference copies (verbatim) are in
`payment-transactions-rework.sql`.

- `20260901150_m08_bookings_replace_payment_stage_with_payment_status.sql` —
  adds `bookings.payment_status public.payment_status not null default
  'Pending'`; backfills from `payment_stage` (Unpaid→Pending, Paid in
  Advance→Partially Paid, Paid→Fully Paid); drops
  `bookings_payment_stage_idx` and `bookings_downpayment_gate_idx`, then the
  `payment_stage` column, then the `payment_stage` type; creates
  `bookings_payment_status_idx` and rebuilds
  `bookings_downpayment_gate_idx` as a partial index on
  `(downpayment_required, payment_status) where downpayment_required = true`.
- `20260901151_m08_transactions_payment_choice_free_label.sql` — drops
  `transactions_payment_choice_requires_customer_initiated` (the
  `initiated_by = 'customer'` coupling) and widens the value CHECK to
  `payment_choice in ('full', 'downpayment', 'balance')` (still NULL-able).
- `20260901152_m08_payment_method_add_credit.sql` — `alter type
  public.payment_method add value if not exists 'Credit'` (own file, no
  consumer in the same transaction).
- `20260901153_m08_settle_transaction_rpc.sql` —
  `settle_transaction(p_transaction_id, p_payment_method, p_bank_name,
  p_payment_reference, p_cash_tendered, p_processed_by) returns
  public.bookings`. SECURITY DEFINER, `service_role`-only. Row-locks the
  transaction, raises if not found / already `Fully Paid`, flips it to `Fully
  Paid` with the real method + `processed_by_staff_id`, then recomputes the
  parent booking's rollup: `net = total_price - discount_amount -
  promo_amount`; `paid = sum(total_amount)` over that booking's non-`Pending`
  `booking_payment` rows; status = `Pending` (paid ≤ 0) / `Fully Paid` (paid
  ≥ net) / `Partially Paid` otherwise; sets `bookings.paid_at` when it
  reaches `Fully Paid`. `p_cash_tendered` is accepted but **not persisted**
  (no column for it).
- `20260901154_m08_add_booking_payment_rpc.sql` —
  `add_booking_payment(p_booking_id, p_amount, p_processed_by) returns
  public.transactions`. SECURITY DEFINER, `service_role`-only. Validates
  `p_amount > 0` and `p_amount <= net - already-settled`, then inserts one
  `Pending` `booking_payment` transaction (`payment_method 'Cash'`
  placeholder, `payment_choice 'balance'`) plus a matching `'service'` line
  item ("Additional payment").
- `20260901155_m10_redeem_credit_rpc.sql` —
  `redeem_credit(p_customer_id, p_branch_id, p_amount, p_transaction_id)
  returns public.credit_transactions`. Inverse of `issue_credit()`. SECURITY
  DEFINER, `service_role`-only. Row-locks the `credit_balances` row, raises
  if missing or `balance < p_amount`, decrements the balance, inserts a
  `'redemption'` `credit_transactions` row with `amount = -p_amount` and
  `transaction_id = p_transaction_id`.
- `20260901156_m03_get_staff_availability_payment_status.sql` — `CREATE OR
  REPLACE` of `get_staff_availability` (identical signature); Check 2's
  down-payment slot gate changes `bk.payment_stage = 'Unpaid'` →
  `bk.payment_status = 'Pending'`. Body otherwise verbatim from
  `20260829148`.
- `20260901157_m14_reporting_functions_settled_only.sql` — `CREATE OR
  REPLACE` of `get_daily_sales_report` and `get_analytics_summary` from
  `20260805101`; every `from public.transactions t` aggregation gains `and
  t.payment_status = 'Fully Paid'` (a `Pending` charge now exists up front
  and must not inflate gross). `get_cage_occupancy_report` intentionally
  untouched.

### Server

- `features/billing/services/transactionPayment.service.ts` — **new**. Three
  exports:
  - `recordTransactionPayment` — loads the transaction, rejects a
    non-`booking_payment` (400) or non-`Pending` (409), runs
    `resolvePaymentConfirmation` to validate the cash tender / compute
    change, calls `settle_transaction`, returns `{ transaction, booking,
    changeAmount }`.
  - `addBookingPayment` — thin wrapper over `add_booking_payment`.
  - `payTransactionWithCredit` — ownership check (a customer may only pay
    their own transaction → 403; `isStaff` may pay any), `Pending`-only
    (409), **full-cover only** — if available credit `< chargeAmount` it
    rejects 400 ("doesn't cover this … charge — split it first"). Then
    `redeem_credit` → `settle_transaction` with `p_payment_method = 'Credit'`
    (`p_processed_by` = staff id when `isStaff`, else null) →
    `update transactions.credit_applied_amount`.
  - `firstRow` helper normalizes bare-row vs one-element-array RPC returns.
- `features/billing/billing.controller.ts` — new
  `recordTransactionPaymentController`, `addBookingPaymentController`,
  `payTransactionWithCreditController`. The credit one resolves
  `getStaffRoleOrNull` → `isStaff = BILLING_STAFF_ROLES.includes(role)`.
- `features/billing/billing.routes.ts` — `POST
  /billing/transactions/:id/pay` and `POST /billing/bookings/:id/payments`
  are `...staffAccess` (jwt + session + `requireRole(BILLING_STAFF_ROLES)` +
  `requireBranch`); `POST /billing/transactions/:id/pay-with-credit` is
  `jwtMiddleware` only (ownership enforced in the service so a customer can
  call it).
- `features/billing/modules/validators/billing.validator.ts` — new
  `recordTransactionPaymentValidator` (`payment_method` ∈
  `COUNTER_PAYMENT_METHODS`; `bank_name` required iff `Bank Transfer`;
  `cash_tendered` required iff `Cash`; `.strict()`) and
  `addBookingPaymentValidator` (`{ amount: positive }`, `.strict()`).
- `features/billing/billing.types.ts` — new `COUNTER_PAYMENT_METHODS =
  ['Cash','Card','Bank Transfer','Grabmart','Pickaroo']` (GCash/Maya
  excluded — webhook/checkout only; Credit has its own path) +
  `CounterPaymentMethod`. `Transaction.payment_choice` type widened to
  `'full' | 'downpayment' | 'balance' | null`.
- `features/billing/services/creditStub.service.ts` — no longer a stub.
  `getAvailableCredit` reads the real `credit_balances.balance` for
  `(customer, branch)` (0 when no row). `applyCredit` gained an optional
  `transactionId` 4th arg, computes `appliedAmount = max(0, min(requested,
  available))`, and calls `redeem_credit` when positive.
- `features/billing/services/webhookConfirmation.service.ts` — the
  customer-initiated PayMongo confirmation path swaps `advancePaymentStage({
  choice })` for `recomputeBookingPaymentStatus(bookingId)`; stops selecting
  `payment_choice` off the transaction. Still logs-not-throws so the webhook
  acks 200.
- `features/booking/services/booking.service.ts`:
  - `createBooking` no longer accepts/writes `payment_method` /
    `payment_confirmed` / a `payment_stage`. It sizes an initial charge:
    `paymentScheme = 'downpayment'` only when `downpaymentRequired &&
    input.payment_scheme === 'downpayment'`, else `'full'`;
    `initialChargeAmount` = down-payment amount or `netTotal`. After the
    booking row is inserted and capacity re-confirmed, if
    `service_category !== 'Veterinary'` and the amount `> 0`, it calls the
    new private `createInitialBookingCharge` **best-effort** (catches and
    `console.error`s — a charge failure never undoes the booking).
  - `createInitialBookingCharge` (new, private) — inserts one `Pending`
    `booking_payment` transaction (`payment_method 'Cash'` placeholder,
    `payment_choice` = the scheme) plus a matching line item ("Down payment"
    / "Full payment").
  - `recomputeBookingPaymentStatus(bookingId)` (new, exported) — app-side
    equivalent of the RPC rollup for the webhook path and as a safety net:
    recomputes `payment_status` from settled `booking_payment` rows vs
    `netTotal`, and owns the one-time side effects — the down-payment
    slot-gate capacity re-check (reverts + 409 if the slot filled while the
    booking sat unpaid) and the "first payment confirms a still-`Pending`
    Online booking" notifications that `createBooking` held back.
  - `advancePaymentStage` and `overridePaymentStage` **deleted** (+ their
    controllers, routes `POST /bookings/:id/payment-stage/advance` and `PATCH
    /bookings/:id/payment-stage`, validators, `PAYMENT_STAGE_ADVANCE_ROLES`
    usage). `completeBooking` no longer touches payment at all (dropped the
    `onlinePrepaid → payment_stage: 'Paid'` branch).
  - `listBookings` filter renamed `paymentStage` → `paymentStatus`
    (`payment_stage` → `payment_status` query param); the
    `excludeUnpaidDownpayment` OR-filter is now
    `downpayment_required.eq.false,payment_status.neq.Pending`; the
    unpaid-pet-duplicate-booking guard checks `payment_status === 'Pending'`.
- `features/booking/modules/validators/booking.validator.ts` —
  `createBookingValidator` drops `payment_method` / `payment_confirmed` /
  `payment_choice`, adds `payment_scheme: z.enum(['downpayment','full'])
  .optional()`. `listBookingsQueryValidator` `payment_stage` →
  `payment_status` (∈ `PAYMENT_STATUSES`).
- Small ripples: `grooming.service.ts` / `consultation.service.ts` queue
  filters, `cancellation.service.ts`, `lineItemSources.service.ts`,
  `customerBookingPayment.service.ts` — all `payment_stage`/`Unpaid` →
  `payment_status`/`Pending`.

### Client

- `features/billing/pages/TransactionsPage/` — **new** (replaces
  `PaymentsQueuePage/`, ~1130 lines deleted). Route
  `/staff/billing/transactions`. Role-gated client-side to
  Superadmin/Admin/Supervisor/Receptionist/Cashier (mirrors
  `BILLING_STAFF_ROLES`); others `<Navigate to="/staff/settings">`. Reads the
  existing `/reports/transaction-history` feed, groups `booking_payment` rows
  by `booking_id`. Per pending row: a "Record payment" modal (reuses
  `PaymentMethodForm`) → `recordTransactionPayment`. Per fully-settled group
  with no pending rows: an inline "Add a payment" amount field →
  `addBookingPayment`.
- `features/billing/api/billing.api.ts` — new `recordTransactionPayment`,
  `addBookingPayment`, `payTransactionWithCredit`.
- `features/billing/billing.routes.tsx` — route swapped
  `payments-queue` → `transactions`, `PaymentsQueuePage` → `TransactionsPage`.
- `features/staff/config/staffDashboard.config.ts` — the "Payments Queue"
  dashboard tile becomes "Transactions" (new copy + `to`), for both roles
  that had it; `TILE_ICONS` key renamed (keeps the `Receipt` icon).
- `features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
  — payment step no longer picks a method. No `paymentMethod` state, no
  `ONLINE_METHODS`, no `PayMongoFeeNotice` on this step, discounts no longer
  gated on "Cash selected". `showPaymentChoice = downpaymentRequired` (was
  also gated on an online method being picked). Submits `payment_scheme`
  instead of `payment_method` / `payment_confirmed` / `payment_choice`.
  Persisted-draft shape drops `paymentMethod`.
- `features/booking/components/shared/PaymentStatusBadge/` — **new** (renamed
  from `PaymentStageBadge/`, CSS moved). `Pending` / `Partially Paid` /
  `Fully Paid`; `context="billing"` renders "Due payment" / "Partially Paid"
  / "Fully Paid" with no "Payment:" prefix. Reuses the old stage colour
  tokens.
- `features/booking/booking.types.ts` — `PaymentStage` type + `PAYMENT_STAGES`
  + `OVERRIDABLE_PAYMENT_STAGES` replaced by `PaymentStatus` /
  `PAYMENT_STATUSES`. `Booking.payment_stage` → `payment_status`.
  `CreateBookingPayload` drops `payment_method` / `payment_confirmed` /
  `payment_choice`, adds `payment_scheme`. `ListBookingsFilters.paymentStage`
  → `paymentStatus`.
- `features/booking/api/booking.api.ts` — `advancePaymentStage` /
  `overridePaymentStage` deleted; `listBookings` sends `payment_status`.
- `features/booking/bookingConfirmation.ts` — `deriveBookingConfirmationState`
  reads `payment_status === 'Pending'` for the "Unconfirmed" (awaiting
  payment) case.
- `features/staff/pages/ReceptionistBookingsQueuePage/` — folds in the
  deleted Payments Queue's Misc-only controls: Start / Complete /
  Admin-and-Superadmin status-override for `Misc` bookings (Initial
  Assessment / Reassessment), plus the pet-assessment capture modal
  (weight_class + coat_type saved before Start when the Misc service has
  `captures_pet_assessment`). Adds a `payment_status` filter. Non-Misc rows
  unchanged (still read-only here).
- `features/reports/pages/CustomerTransactionHistoryPage/` — adds a "Pay with
  credit" button on the customer's own `Pending` `booking_payment` rows →
  `payTransactionWithCredit`; reloads the feed on success, shows the service
  error (e.g. the full-cover-only 400) inline.

## Verification

### A. Booking flow emits one Pending charge, no payment method

1. As a customer, book a **Grooming** appointment at a branch whose
   down-payment policy is **off**. On the payment step: confirm there is no
   payment-method picker and no "pay in full vs down payment" choice.
2. Complete the booking. As a cashier, open **Transactions**
   (`/staff/billing/transactions`): the new booking appears as a "Grooming
   booking" group with one row — amount = net total, status "Due payment".
3. In the DB (or via `/reports/transaction-history`): the booking has exactly
   one `booking_payment` transaction, `payment_status = 'Pending'`,
   `payment_choice = 'full'`, plus one line item; `bookings.payment_status =
   'Pending'`.
4. Repeat at a branch with the **down-payment policy on**: the payment step
   now shows the scheme choice. Pick "down payment". The initial charge row's
   amount = the down-payment amount and `payment_choice = 'downpayment'`.
5. Book a **Veterinary** consult: no `booking_payment` transaction is created
   at all (priced during the visit).

### B. Record a counter payment (`POST /billing/transactions/:id/pay`)

See `payment-transactions-rework.postman_collection.json` requests 3-9.
Summary of the behaviour to confirm:

6. On the Transactions page, click "Record payment" on a Due row, choose
   **Cash**, enter a tender above the amount → the transaction flips to
   "Fully Paid", the modal reports change due, and (if this covered the whole
   net) `bookings.payment_status` becomes "Fully Paid" with `paid_at` set.
   Partial coverage → "Partially Paid".
7. **Bank Transfer** requires a bank; **Cash** requires a tender — the
   validator rejects each omission with 400. **GCash / Maya** are not offered
   and are rejected 400 server-side.
8. Recording a payment against an already-settled transaction → 409.

### C. Add a balance payment (`POST /billing/bookings/:id/payments`)

9. On a booking group with no pending rows, use "Add a payment", enter an
   amount ≤ the outstanding balance → a new "Due payment" row appears; settle
   it as in B. An amount **above** the remaining balance → 400
   (`add_booking_payment: amount … exceeds remaining balance`). The new row
   is `payment_choice = 'balance'`.

### D. Pay with credit (`POST /billing/transactions/:id/pay-with-credit`)

10. As a customer with branch credit ≥ a `Pending` `booking_payment` charge,
    open **Transaction History** and click "Pay with credit" on that row →
    the row becomes "Fully Paid", `payment_method = 'Credit'`,
    `credit_applied_amount` set, a `redemption` `credit_transactions` row
    (negative `amount`, `transaction_id` linked) is written, the branch
    credit balance drops, and the booking rollup advances.
11. If the customer's credit is **less** than the charge → 400 ("doesn't
    cover this … charge — split it first"); nothing is redeemed.
12. A customer calling this for **another** customer's transaction → 403.
    Staff (`BILLING_STAFF_ROLES`) may pay on any customer's behalf
    (`processed_by` recorded).

### E. Down-payment slot gate still works on `payment_status`

13. With the down-payment policy on, create two Online Hotel bookings for the
    same last slot (each holds no slot while `payment_status = 'Pending'`).
    Pay the first (record its down-payment charge, or webhook-confirm it) →
    it passes the capacity re-check and confirms; the second, when paid, gets
    409 "That time slot filled up before this payment".
14. `get_staff_availability` returns a groomer as available even though a
    down-payment-required booking is assigned to them, until that booking's
    `payment_status` leaves `'Pending'`.

### F. Payments Queue is gone; Misc controls moved

15. `/staff/billing/payments-queue` no longer routes. The staff dashboard
    tile now reads "Transactions".
16. In the receptionist bookings queue, a `Misc` (Initial Assessment /
    Reassessment) booking still shows Start / Complete and (Admin/Superadmin)
    the status-override dropdown; starting one whose service captures a pet
    assessment opens the weight-class + coat-type capture modal first.
    Non-Misc rows remain read-only there.

### G. Reporting excludes unsettled charges

17. Create a booking (→ one `Pending` charge) but do **not** settle it. Run
    the daily sales report and analytics summary for today: the unpaid charge
    does **not** appear in gross / revenue. Settle it → it now counts.

## Test suites

Run on this branch (`feat/payment-transactions-rework`, worktree clean) on
2026-09-01:

- `server`: `npx vitest run` — **920/920 passing (87 files)**.
  `npx tsc --noEmit` — clean.
- `client`: `npx vitest run` — **733/734 passing (143 files)**. The one
  failure is
  `src/features/maintenance/pages/AdminPromoConfigPage/AdminPromoConfigPage.spec.ts
  > AdminPromoConfigPage > the timing filter narrows to Ended promos` — a
  pre-existing date-dependent flake (the `buildPromo()` default fixture's
  fixed date range has now elapsed, so it too counts as "Ended" and the
  filter assertion fails). Unrelated to this change; per the implementer it
  fails on `dev` as well. `npx tsc -b` — clean.
- Per the implementer, both repos are also eslint + prettier clean (not
  re-run here).

New/updated tests of note:
`server/.../billing/services/transactionPayment.service.spec.ts` (new, 7
cases — cash settle + change, already-settled 409, add-balance RPC,
full-from-credit happy path, no-balance 400, partial-cover 400, wrong-owner
403); `webhookConfirmation.service.spec.ts` (now asserts
`recomputeBookingPaymentStatus`); `booking.service.spec.ts` /
`booking.validator.spec.ts` rewritten for `payment_scheme` / the initial
charge / `recomputeBookingPaymentStatus`;
`client/.../TransactionsPage/TransactionsPage.spec.tsx` (new, 4 cases);
`ReceptionistBookingsQueuePage.spec.ts` (+Misc Start/Complete/assessment).

## Open items

- **No local migration dry-run.** The 8 migrations were pushed straight to
  the linked Supabase project (`supabase db push`) with the local Docker
  stack down — there was no `supabase db reset` / local apply first.
  `supabase migration list --linked` confirms remote is at `20260901157` and
  matches local. `20260901150` is destructive (drops `bookings.payment_stage`
  and the `payment_stage` type after backfilling); it ran without error but
  was not rehearsed locally. Next `supabase db reset` on a dev machine is the
  first real replay of the full chain — watch `20260901156`'s own carried-over
  warning about `get_staff_availability` being clobbered by parallel same-day
  migrations branching off a stale copy.
- **`payTransactionWithCredit` is full-cover only.** Partial credit
  application against a single transaction is deferred — the caller must
  split the charge (add a balance payment for the remainder) first. The 400
  message says as much.
- **`p_cash_tendered` is not persisted** by `settle_transaction` (no column);
  change-due is computed and returned to the client but not stored on the
  transaction.
- Client-side role gating on the Transactions page is a UX guard only;
  `BILLING_STAFF_ROLES` + `requireBranch` on the routes are the real
  enforcement (consistent with the other cashier pages).
