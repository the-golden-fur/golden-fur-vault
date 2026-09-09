---
title: One "Amount paid" field in the mark-as-paid modal
date: 2026-09-09
tags: [session-plan, golden-fur]
project: golden-fur
session: 80-simplify-mark-as-paid-modal
branch: feat/simplify-mark-as-paid-modal
---

# 80 — One "Amount paid" field in the mark-as-paid modal

## What you asked for

Collapse the cashier's "mark this transaction as paid" pop-up down to a
single money field, and give the customer's own pay pop-up the same field.

> Simplify cashier account > transaction > mark transaction as paid modal:
>
> - Currently there's 2 payment fields
> - What is amount to collect for?
> - What is cash tendered for?
> - Simplify and merge, 1 field only and that's the field how much the
>   cashier/customer is going to pay against the transaction
> - You can omit the change label
>
> (full task context: `Projects/golden-fur/shared/context/Architectural-Change-History.docx`)

Two decisions were made while planning:

1. The field is labelled **"Amount paid (PHP)"** — neutral wording that
   reads both ways ("how much I'm paying" for a customer, "how much this
   customer is paying" for a receptionist).
2. Scope grew slightly: the **customer's own** Pay pop-up (the "My
   Transactions" page) never had an amount field at all — it always paid the
   whole transaction. It now gets the same single "Amount paid" field, but
   it is only **editable when paying from account credit**. For GCash / Maya
   the field is shown but locked to the full amount, because a real partial
   card/e-wallet payment needs extra PayMongo (payment-provider) plumbing
   that is deliberately out of scope here.

## What this part of the app does today

**Golden Fur** is a pet-services booking app. Money owed for a booking is
tracked as **transactions** — one row per charge (a down-payment, a balance,
a walk-in sale). A transaction is _Pending_ until it is paid, then _Fully
Paid_.

Two screens let someone settle a _Pending_ transaction:

- **Cashier / receptionist:** the **Transactions** page at
  `/staff/reports/transaction-history` (reached from the staff sidebar item
  **Transactions**). Each _Pending_ row has a **Mark as paid** action that
  opens a small pop-up (a **modal**). Until this change that modal had
  **two** number fields:
  - _Amount to collect (PHP)_ — how much of the transaction to settle now
    (a smaller number settles it partly and creates a new _Pending_
    "balance" transaction for the rest).
  - _Cash tendered (PHP)_ — only for the Cash method: how much cash the
    customer physically handed over, which the modal used to show a
    computed **"Change: PHP …"** line.
- **Customer:** the **Transactions** page at `/portal/transactions`
  (customer sidebar item **Transactions**). Each payable row has a **Pay**
  button opening a modal that asks _"How would you like to pay?"_ — **Account
  credit**, **GCash**, or **Maya** — and always paid the transaction in
  full. No amount field.

## What's wrong / what's missing

- On the cashier modal the **Cash tendered** field and the **Change** line
  are dead weight. The transaction record never stores a "tendered" or
  "change" figure — the drawer/change is a physical-cash concern the app
  doesn't track. Two money boxes side by side (one of which only sometimes
  appears) make a one-second action look complicated.
- The two boxes are also easy to confuse: "amount to collect" vs "cash
  tendered" is not obvious wording.
- On the customer modal there is no way to pay only _part_ of a transaction
  from account credit, even though the server already supports it.

## What we're going to change

1. **Cashier modal: one field, always shown.** — _Which files:_
   `client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`,
   `client/src/features/billing/components/PaymentMethodForm/PaymentMethodForm.tsx`
   — _Why:_ the single box is relabelled **"Amount paid (PHP)"** and shown
   for every method (including Credit). `PaymentMethodForm` gets a new
   `hideCashTendered` flag; when set, its Cash branch renders no tendered
   input and no "Change" line. Checkout and the miscellaneous-sale form do
   not pass the flag, so they are unaffected.

2. **Payment methods: unchanged.** — An early revision narrowed the cashier
   modal + the server validator to the five counter methods (dropping
   GCash/Maya, whose docblock always claimed they didn't belong here). Code
   review judged that a behaviour change beyond this task — a cashier can
   still need to record a counter GCash/Maya QR payment against an existing
   Pending row — so it was reverted. The validator's docblock was corrected
   to match the real (unchanged) behaviour. This session only changes the
   field count, nothing about which methods are accepted.

3. **Customer modal: add the single "Amount paid" field.** — _Which files:_
   `client/src/features/reports/pages/CustomerTransactionHistoryPage/CustomerTransactionHistoryPage.tsx`
   — _Why:_ the field is editable only for **Account credit** (that path can
   spawn a balance transaction); for GCash / Maya it is disabled and snapped
   to the full amount, with a one-line note explaining why.

4. **Thread the partial amount through to the credit endpoint.** — _Which
   files:_ `client/src/features/billing/api/billing.api.ts`,
   `server/src/features/billing/billing.controller.ts`,
   `server/src/features/billing/services/transactionPayment.service.ts`,
   `server/src/features/billing/modules/validators/billing.validator.ts` —
   _Why:_ `payTransactionWithCredit` gained an optional third argument
   `amountApplied` and now sends an `{ amount_applied }` body. A new
   `payTransactionWithCreditValidator` accepts that optional body (an empty
   body still means "pay in full"). The service caps the applied credit at
   `min(available credit, requested amount)`, with `requested` bounded
   above by the transaction total.

5. **Server: stop computing change.** — _Which files:_
   `transactionPayment.service.ts`, `billing.controller.ts` — _Why:_
   `recordTransactionPayment` no longer takes a `cashTendered` argument,
   no longer calls `resolvePaymentConfirmation`, and drops `changeAmount`
   from its result. It passes `p_cash_tendered: null` to the unchanged
   `settle_transaction` database function (which already ignores that
   parameter). No migration.

## Words you might not know

- **transaction** — one row in the `transactions` table representing a
  single charge against a booking (down-payment, balance, or a walk-in
  sale). Paid or not-yet-paid, tracked independently.
- **modal** — a small pop-up window that sits on top of the page and blocks
  the rest of it until you close it.
- **account credit** — a stored balance a customer can spend on future
  charges (issued from cancellations, refunds, etc.).
- **balance transaction** — when a charge is only partly paid, the app
  creates a fresh _Pending_ transaction for the unpaid remainder so it can
  be collected later.
- **PayMongo** — the third-party payment provider that processes GCash /
  Maya / card payments and calls back ("webhook") to confirm them.
- **webhook** — an automatic HTTP call the payment provider makes to our
  server to say "this payment went through".
- **validator** — server-side code (using the `zod` library) that checks an
  incoming request body has the right shape before anything acts on it.
- **RPC / `settle_transaction`** — a function that runs inside the database
  itself, flipping the transaction to _Fully Paid_ and recomputing the
  booking's payment status in one atomic step.
- **migration** — a versioned SQL file that changes the database schema.
  None was needed here.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
