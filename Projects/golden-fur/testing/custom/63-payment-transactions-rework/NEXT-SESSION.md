---
title: "Payment/transactions rework — next-session handoff"
date: 2026-09-01
tags: [golden-fur, handoff, payments]
project: golden-fur
status: in-progress
---

# Payment/transactions rework — next-session handoff

## 2026-09-01 follow-up session — gaps A–D + N3/N5 done

PR #135 merged to `dev` (squash, `a2b6759`). The fixes below landed on a fresh
branch **`fix/payment-rework-followups`** (off `dev`):

- **A (done)** — `CreditBalanceProvider`: `Number()`-coerce the PG-numeric
  `balance` at the `credits.api.ts` boundary + defensive coerce in the `total`
  reduce; added a `window` `focus` / `visibilitychange` refetch. New
  `CreditBalanceProvider.spec.tsx`.
- **B (done)** — customer-chosen partial balance payments. New
  `POST /bookings/:id/balance-payment` (jwt-only) →
  `addCustomerBalancePayment` (ownership + `payment_status === 'Partially Paid'`
  + no-pending-charge guard) → existing `add_booking_payment` RPC with
  `p_processed_by: null`. `payForBooking` now pays an existing `balance` charge
  for its own amount instead of recomputing to the full remainder. Customer
  Transaction History page gained a "Pay part of … balance" affordance + amount
  modal; eligibility/remaining via new `reports/utils/payableBalances.ts`.
  **N1 still deferred** (RPC `v_remaining` nets settled-only; the one-pending-
  charge guard covers it for now).
- **C (done)** — re-added the "Transactions" tile to the `supervisor` dashboard
  and the `admin` dashboard's "Supervisor" section
  (`staffDashboard.config.ts`); `Supervisor` is in
  `TRANSACTION_HISTORY_READ_ROLES`. Dropped the dead `'Transaction History'`
  `TILE_ICONS` key.
- **D (done)** — deleted `features/billing/pages/TransactionsPage/` + its route;
  ported the add-balance-payment form into the live `TransactionHistoryTable`
  (staff, via existing `addBookingPayment`). Removed the now-dead client
  `COUNTER_PAYMENT_METHODS` + `PaymentMethodForm` `methods` prop (server
  `COUNTER_PAYMENT_METHODS` kept — validator uses it).
- **N3 (done)** — "Due payments only" toggle on both transaction pages.
- **N5 (done)** — `CustomerBookingsPage` comment verified accurate, no change.
- **Still open**: N1, N2 (needs `transactions.cash_tendered/change_given`
  column), N4 (compliance sign-off), and Part 2 (customer credit-expiry
  visibility) — see the plan file.

No new migration. Server `vitest` 931/931, client `vitest` 739/739, tsc + lint
clean. `format:check` not runnable locally (working tree is CRLF via
`core.autocrlf`); CI validates on LF.

---

Branch: **`feat/payment-transactions-rework`** (golden-fur), pushed through
`1a50f76`. Vault docs branch: **`docs/configurable-credit-conversion-rate`**,
PR **#17**. All 9 migrations (`20260901150`–`158`) are **applied to the linked
DB** (`supabase migration list --linked` confirms).

## State: shippable, but with known gaps (below)

Server `npx vitest run` was 928/928 green as of the blocker-fix commit
(`1efc552`); the two commits after it (`57a6519` client redesign, `1a50f76`
cashier consolidation) were **not** followed by a full re-run — the user asked
to skip test/agent runs to conserve session budget. tsc + targeted lint are
clean on every changed file. Client full suite last ran green at `57a6519`
(735/736; the 1 failure is the pre-existing `AdminPromoConfigPage` date flake).

## What was delivered

1. **Model**: `bookings.payment_stage` dropped → `bookings.payment_status`
   (Pending / Partially Paid / Fully Paid), a stored rollup of settled
   `booking_payment` transactions vs `netTotal = total_price - discount_amount
   - promo_amount`. Kept current by `settle_transaction`/`add_booking_payment`/`pay_transaction_with_credit`RPCs and the app-side`recomputeBookingPaymentStatus` (webhook path).
2. **Booking flow**: no payment method collected; a `payment_scheme`
   (`full` | `downpayment`) radio shows only when the branch down-payment
   policy is enabled. `createBooking` emits one `Pending` `booking_payment`
   charge (`createInitialBookingCharge`); skipped for Veterinary; a
   zero-net booking (100% discount/promo) is born `Fully Paid`.
3. **Cashier**: the filterable **Transaction History** table is now the single
   **"Transactions"** page (title + nav renamed, grouped `TransactionsPage`
   unlinked, duplicate "Transaction History" nav removed). Each Pending
   `booking_payment` row has a `...` menu (View booking / Pay). **Pay** opens
   a modal offering every method (Cash/GCash/Maya/Card/Bank Transfer/Grabmart/
   Pickaroo) plus a **Pay from account credit** button; the amount is locked
   to the transaction's own total. GCash/Maya entered by a cashier settle
   immediately (`resolvePaymentConfirmation` — cashier-confirmed walk-in QR).
4. **Customer**: My Bookings has **no Pay** — Reschedule/Cancel moved behind a
   `...` menu. The customer **Transaction History** page (`/portal/transactions`)
   is where paying happens: "Pay" on a Pending charge → mode modal
   (Account credit / GCash / Maya). Credit settles now; GCash/Maya redirect to
   PayMongo via `payForBooking`, which now **settles the existing Pending
   charge in place** (no second row) and bills `netTotal - alreadySettled`.
5. **Payments Queue deleted**; its Misc-category Start/Complete + pet-assessment
   modal + Admin status-override folded into `ReceptionistBookingsQueuePage`.
6. **Credit redemption real**: `creditStub.service.ts` → `redeem_credit`;
   `payTransactionWithCredit` → the atomic `pay_transaction_with_credit` RPC
   (migration `20260901158`) — one Postgres txn, no redeem-then-settle race.
7. `checkoutBooking` **supersedes** the booking-time estimate charge (deletes
   still-Pending rows + line items) instead of 409ing on it; keeps the 409 for
   a genuinely settled row; rolls `payment_status` up afterward.

## MUST-FIX before this is really done

### A. Navbar credit pill shows ₱0.00 after cancelling a paid booking

- Repro: book → cashier marks the charge paid → cancel with notice met. The
  cancellation notification correctly says "credit of ₱X issued"
  (`issue_credit` ran, `credit_balances` incremented — `customer_profiles.id
== auth.users.id`, so no ID mismatch), but the navbar pill stays ₱0.00.
- `CustomerBookingsPage.confirmCancel` still calls `refreshCreditBalance()`
  when `result.data.credit_issued`. `CreditBalanceProvider` refetches on
  `accessToken` change + a `reloadKey` bump only — **it never refetches on
  navigation or window focus**, so any server-side credit change from a flow
  that isn't the cancel button (or a stale render) leaves it stale.
- **Likely fix**: add a `window` `focus` / `visibilitychange` listener (and/or
  a refetch on route change within the customer shell) to
  `CreditBalanceProvider`. Also coerce `Number(b.balance)` in the `total`
  reduce (PostgREST can return `numeric` as a string). If it's still 0 after
  that, check `GET /credits/balances` directly — `listCreditBalances` service
  uses the **service-role** client so RLS isn't the cause; verify
  `resolveTargetCustomerId` returns the right id for this customer (it returns
  `requesterId` = JWT `sub`; confirm that equals `credit_balances.customer_id`
  for the affected row).

### B. Customer-chosen PARTIAL balance payments

The user's rule: paying a `downpayment` or `full` charge is **amount-locked**
(done). But a **`balance`** payment (only possible when the parent booking's
scheme was `downpayment`, not `full`) must let the customer **enter any amount
≤ remaining**, creating a fresh `Pending` `balance` transaction; if that's less
than the full remaining, they can do it again (2+ balance instances).

- Today: `add_booking_payment` (creates a `balance` charge, `p_amount <=
remaining`, `payment_choice='balance'`) is **staff-only**
  (`POST /billing/bookings/:id/payments`, `staffAccess`). `payForBooking`
  (customer) with no Pending charge inserts one row for the **full** remaining
  (or `min(downpayment, remaining)`) — no customer-chosen partial.
- **To do**: give the customer a "Pay part of the balance" path. Either
  (a) a customer-accessible `add_booking_payment` (amount param, `<= remaining`
  re-checked in the RPC — it already does) then the normal per-transaction Pay,
  or (b) an optional `amount` on `payForBooking` used only when the booking is
  `Partially Paid` / it's a balance payment, `0 < amount <= remaining`.
  Add the amount field to the customer Transaction History Pay modal, shown
  only for the balance case.
- Nit **N1** from the review is related: `add_booking_payment`'s "remaining"
  only nets **settled** rows, so it doesn't subtract an outstanding Pending
  balance charge. The `addBookingPayment` _service_ now guards against a 2nd
  unsettled charge (409), but the RPC math itself is still loose — fold a
  `- sum(pending booking_payment)` into `v_remaining` in a follow-up migration
  if balance charges ever need to stack.

### C. Nav gap from the consolidation

The perl that removed the duplicate "Transaction History" nav entries also
removed it from **two report-section dashboards** (Supervisor + Admin "Reports"
groups in `client/src/features/staff/config/staffDashboard.config.ts`) that had
_only_ that tile and no "Transactions" tile. Add a `{ title: 'Transactions',
description: '...', to: '/staff/reports/transaction-history' }` tile back to
those two groups.

### D. Dead route / component

`client/src/features/billing/pages/TransactionsPage/` (the grouped-by-booking
page) + its route `/staff/billing/transactions` in `billing.routes.tsx` are now
**unlinked** but still present. Either delete them (and
`TransactionsPage.spec.tsx`) or repoint something at them. The `PaymentMethodForm`
`methods` prop and client `COUNTER_PAYMENT_METHODS` const were added for that
page — still fine to keep, `COUNTER_PAYMENT_METHODS` is now unused.

## Should-fix (review nits, non-blocking)

- **N2**: `settle_transaction` accepts `p_cash_tendered` but never persists it
  — no tender/change audit trail for a cash counter payment. Needs a schema
  column (`transactions.cash_tendered` / `change_given`).
- **N4**: the booking-time Senior/PWD discount is no longer tied to an
  in-person payment (the "Cash only" check was removed). The `discountIdVerified`
  attestation + money-handling-role gate remain — get a conscious compliance
  sign-off that the attestation alone satisfies the ID-logging expectation
  (`.agent/skills/discount-senior-pwd-compliance.md`).
- **N3 (partly done)**: the cashier page still loads the whole ledger
  server-side (no pagination); the old grouped page had a pending-only default.
  The consolidated table has date/customer/type filters but no "pending only"
  quick filter — add one.
- **N5**: `CustomerBookingsPage` — stale comment about `payForBooking` charging
  "the remainder regardless" (it now bills net). Already reworded; double-check.

## Remaining process steps

1. **golden-fur PR → `dev`** (`pr-to-dev` skill, squash). CI-parity via
   `ci-verifier`, then `code-reviewer` on `dev...HEAD` — the 5 original
   blockers are fixed but the review has **not** been re-run against the
   fixes or the two client-redesign commits.
2. **Vault PR #17** is already open (`docs/configurable-credit-conversion-rate`
   → `main`). It needs: this handoff doc committed, and the workflow/module
   docs refreshed for (a) `checkoutBooking` supersede behaviour,
   (b) the cashier one-page consolidation + inline Pay, (c) the customer Pay
   moving off My Bookings onto Transaction History, (d) `payForBooking`
   settle-in-place + net billing, (e) `applyFirstBookingPaymentSideEffects`
   on the counter path. `.agent/` docs were synced at `537b315` but before
   the checkout-supersede + consolidation changes — re-check
   `paymongo-webhook-handling.md` / `daily-sales-report-format.md` /
   `payment-billing-agent.md`.
3. **Vault format:check CI is already red on `main`** (~122 pre-existing
   files) — unrelated to this work; the files in PR #17 are prettier-clean.

## User's requests, verbatim — the ones not fully finished

Original brief for this task (fully in scope, delivered except where noted):

> - At booking process > payment step, allow customers/receptionist to choose
>   payment scheme, whether to pay in full or downpayment when doing online
>   bookings
>   - This decides the number of transactions made at customer > my
>     transaction or cashier > transactions
>   - Full payment = 1 transaction only
>   - Downpayment = 2 transactions (e.g. downpayment and remaining balance, or
>     perhaps make it flexible? 2+ transactions? Downpayment + multiple
>     remaining balance transaction instances where you can choose how much to
>     pay, creates new instance if remaining balance is not paid in full)
> - Remove payment mode in booking process, move it to customer > my
>   transactions and cashier > transactions
>   - Payment mode only appears when clicking on a transaction > pay
>   - Customers can choose credits, gcash or paymaya
>   - Cashiers can choose cash, bank, card, pickaroo and the aforementioned
>     three

Status: scheme choice ✅ (policy-gated); full=1 txn ✅; downpayment = downpayment
charge + N staff-created balance charges ✅ **at the RPC level**; payment mode
moved off booking flow ✅; per-transaction Pay modal ✅ on both cashier and
customer pages; customer methods (credit/gcash/maya) ✅; cashier methods
(cash/bank/card/pickaroo/grabmart + gcash/maya + credit) ✅.
**NOT done: the customer choosing how much of the balance to pay and spawning
2+ balance instances themselves** — see gap **B** above. Today only staff can
create a partial `balance` charge.

Follow-up UI requests during the session (partly done):

> I cancelled a confirmed booking (marked it as paid with cashier), YET CREDITS
> IN NAVBAR IS STILL NOT UPDATED AND STILL SHOWS 0

→ **NOT fixed** — gap **A** above.

> why is there a separate page for transactions and history as cashier? it
> SHOULD ONLY BE transactions

→ **Done** — the filterable table is now the single "Transactions" page; the
grouped page and the duplicate nav entry are gone (but see gap **C**/**D** for
loose ends: two report dashboards lost the link, and the old grouped
component/route is still in the tree unlinked).

> I should be able to pay here [staff Transaction History]. remove booking
> field, replace with ... (options are view booking and pay). pay opens payment
> modal like in customer (auto default full amount, choose method cash, gcash,
> etc.)

→ **Done** — `...` menu (View booking / Pay), Pay modal with method choice.

> if the Payment [choice] is downpayment (it is LOCKED IN FULL AMOUNT, cannot
> edit). if it's full payment (ALSO LOCKED). if it's remaining balance (derived
> from parent booking if payment scheme is downpayment, NOT FULL payment, then
> ONLY THEN you can put amount that is not the full due)

→ **Partly done**: paying an existing `downpayment` / `full` / `balance`
transaction is amount-locked to that transaction's total ✅. **NOT done**: the
customer-facing "create a partial `balance` charge with a chosen amount" — this
is the same as gap **B**. The `payment_choice` field stays plain text + a CHECK
constraint (`'full' | 'downpayment' | 'balance'`), not a PG enum — matches the
codebase convention for `transaction_type` / `line_item_type` etc.; the user
asked "why is it not an enum" — answer: deliberate house style, documented in
`20260731068_m08_create_transactions_schema.sql` and `...097` header comments.

## Commits on the branch (since `dev` merge-base `044693d4`)

`2004e9c` model+migrations · `19d9da0` server specs · `40d3131` client
TransactionsPage+sweep · `57023bb` Misc fold-in+specs · `537b315` .agent docs ·
`415ced8` first-payment side-effects on counter path · `1efc552` 5 review
blockers · `57a6519` customer payment → Transactions page · `1a50f76` one
cashier Transactions page with inline Pay.
