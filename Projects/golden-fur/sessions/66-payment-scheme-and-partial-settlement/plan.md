---
title: Let customers choose downpayment or full payment, and split payments into pieces
date: 2026-09-02
tags: [session-plan, golden-fur]
project: golden-fur
session: 66-payment-scheme-and-partial-settlement
branch: feat/booking-payment-scheme-and-partial-settlement
---

# 66 — Let customers choose downpayment or full payment, and split payments into pieces

## What you asked for

Make the last step of booking let the customer (or the receptionist booking on
their behalf) choose **downpayment** or **full payment**, and change how the
money side is recorded. Verbatim:

> - On new booking:
>   - Allow customers/receptionist to choose payment scheme at last step
>   - Either downpayment or full payment
>   - Currently it auto locks full payment
>   - Verify that choosing downpayment scheme should initially create 2
>     transactions (downpayment + remaining balance)
>   - If remaining balance isn't fully paid, it creates another remaining
>     balance transaction instance
> - Verify that downpayment config per service/package is now gone
>   - It should've been moved to admin settings > config a while ago

Follow-up you added while planning, about the **Record payment** popup on the
staff Transactions page:

> - make cash tendered autofill the full amount of the transaction (e.g. 693 >
>   should put 693 as placeholder value)
> - add credit as a payment option
> - combine 2 pay buttons into just Pay or something ... since you're paying for
>   the customer, or making the transaction as paid

And you chose, when asked: seed the downpayment setting **on by default**;
create **both** transactions up front; and allow **partial payments that spawn a
new leftover transaction** — for full-payment bookings too, not just
downpayment ones.

## Some words you need first

- **Golden Fur** has two apps sharing one database: a **customer portal**
  (where a pet owner books online) and a **staff console** (where employees run
  the business). A **role** is the kind of staff account — Receptionist,
  Cashier, Admin, etc.
- **Booking** — one appointment: a pet, a branch, a service, a date/time.
- **Transaction** — one row in the `transactions` database table representing a
  _payment event_ tied to a booking (e.g. "the customer owes ₱150 as a down
  payment"). A booking can have several. Each transaction has a **status**:
  `Pending` (money not collected yet), `Fully Paid`, or `Partially Paid`.
- **`payment_choice`** — a short text label on each transaction saying what kind
  it is: `full`, `downpayment`, or `balance` (a balance is "the rest that's
  still owed").
- **Down payment** — paying only part of the price now to hold the appointment,
  and the rest later.
- **Payment scheme** — the customer's choice at checkout: pay the _down payment_
  now, or pay in _full_ now. (In the code the field is `payment_scheme`.)
- **`policy_configurations`** — a database table with one "default settings" row
  plus optional per-branch override rows. It holds business rules an Admin can
  change on **Settings → Config → Policies** in the staff console: notice
  periods, the lunch break, credit expiry, and the **down-payment** rule
  (on/off, percentage-or-flat, amount).
- **migration** — a numbered `.sql` file under `supabase/migrations/`. Running
  it changes the database structure or data. Migrations run in filename order
  and are never edited after they ship; you add a new one instead.
- **RPC** — a function that lives _inside_ the PostgreSQL database and the
  server calls by name. Golden Fur uses these when several table writes must
  succeed or fail together as one unit (the database guarantees that; two
  separate calls from the server do not).
- **`SECURITY DEFINER`** — a flag on a database function letting it bypass the
  per-row permission rules (**RLS**, row-level security), because the function
  itself already checks who's allowed to do what.
- **spec / test suite** — automated tests (`*.spec.ts`). "CI: Verify All" is the
  one command that runs every test, linter, and build for both apps; it must be
  green before a pull request.

## What this part of the app does today

**The booking wizard.** One React page,
`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`,
is the whole step-by-step booking form. It is used at two URLs: `/portal/book`
(the customer books themselves) and `/staff/bookings/new` (a receptionist books
for someone). The final step is labelled **"Review"**. It already contains a
radio-button choice — "pay the down payment now" vs "pay in full now" — but that
choice **only appears when the branch's down-payment rule is switched on**
(`showPaymentChoice` at line ~1270). The rule ships **off**, so nobody ever sees
the choice, and the server falls back to charging the full amount. That's the
"auto locks full payment" you described.

**What happens after you submit a booking.** The server function `createBooking`
(`server/src/features/booking/services/booking.service.ts`, starts ~line 712)
creates the booking row, then calls `createInitialBookingCharge` (~line 1584),
which inserts **exactly one** `Pending` transaction:

- if the scheme is `downpayment` → one transaction for the down-payment amount
  only;
- otherwise → one transaction for the whole price.

The "remaining balance" after a down payment is **not** stored as a transaction.
It only exists as a calculation (`price − what's been paid`). A cashier turns it
into a real transaction later, by hand, using an "Add a payment" button.

**Recording a payment.** On the staff **Transactions** page
(`/staff/reports/transaction-history`, component
`client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`),
a staff member clicks a row's **⋯ → Pay**. A popup opens with:

- a payment-method dropdown (Cash, GCash, Maya, Card, Bank Transfer, Grabmart,
  Pickaroo) — **no "Credit" option**;
- for Cash, a "Cash tendered" box that starts **empty**;
- **two** buttons: "Pay from account credit" and "Record payment".

Paying always settles the **whole** transaction — the database function
`settle_transaction` (migration `20260901153`) only flips a transaction from
`Pending` to `Fully Paid`, never a partial amount. Paying with store credit
(`pay_transaction_with_credit`, migration `20260901158`) refuses outright if the
customer's credit doesn't cover the entire charge.

**The down-payment setting itself** already lives in the right place —
`policy_configurations`, edited on Settings → Config → Policies. The old
mechanism, where each service or package carried its own `requires_downpayment`
column, was deleted by migration `20260828144`. (Requirement 4 is just asking us
to confirm that, which we did — see below.)

## What's wrong / what's missing

1. A customer or receptionist can never actually pick "down payment" — the
   choice is hidden because the setting is off by default.
2. When someone does pick "down payment", only **one** transaction is created.
   You want **two** immediately: the down payment **and** the remaining balance,
   both visible on the Transactions page and on the customer's "My
   Transactions" list, so nobody has to remember to add the balance by hand.
3. There is no way to pay a transaction _partially_. If a customer owes ₱500 on
   a balance and hands over ₱200, the cashier can't record that cleanly. You
   want: record the ₱200, mark that transaction done, and automatically create a
   **new** ₱300 "remaining balance" transaction. Repeat until it's all paid.
   This should also work if someone chose **full payment** but then only pays
   part of it.
4. The Record-payment popup is clunky: the Cash box makes you retype the amount,
   there's no Credit option even though credit is a real payment method, and two
   buttons is one too many when the job is simply "mark this as paid".

## What we're going to change

There are **five new migrations** (numbered `20260902161` through
`20260902165`, continuing after the last one, `20260902160`) plus server and
client edits. Build it in the order in the last section — each block is safe to
commit on its own.

### 1. Turn the down-payment setting on by default

- **New migration `20260902161_m09_policy_configurations_downpayment_default_on.sql`**
  — set the `downpayment_enabled` column's default to `true`, and update the
  existing default settings row to `enabled = true`, type `Percentage`, amount
  `50` (i.e. 50%). Guards (`where ... is null`) stop it from overwriting a value
  an Admin already set on a shared database.
  _Why 50%:_ it's the example the project advisor gave, it works for a ₱350
  grooming and a multi-night hotel stay alike, and the code already handles
  percentages. An Admin can change it any time on Settings → Config → Policies;
  switching to a flat peso amount is a one-line edit to this migration.
- **`server/src/features/booking/services/staffPicker.service.ts`** (~line 40)
  — there's a hard-coded fallback copy of the default settings used only if the
  settings row is ever missing. Flip its down-payment fields to match (its own
  comment says it should mirror the migration).
- _Why:_ once the setting is on, the "down payment vs full" radio on the Review
  step shows up on its own — no other change needed for requirement 1.

### 2. Create two transactions up front for the down-payment scheme

- **New migration `20260902162_m08_create_initial_booking_charge_rpc.sql`** — a
  database function `create_initial_booking_charge`. Given the booking, the
  scheme, the net price, and the down-payment amount:
  - scheme `downpayment` → insert **two** `Pending` transactions: one labelled
    `downpayment` for the down-payment amount, one labelled `balance` for
    `price − down payment` (skipped if that's zero). Each gets its matching
    line-item row.
  - scheme `full` → one `Pending` transaction labelled `full`, as today.
  - Doing it as one database function (not several separate server inserts)
    matches how every similar write in this codebase already works, so the rows
    can't half-succeed.
- **`server/src/features/booking/services/booking.service.ts`** — at the charge
  call site (~line 1064) call the new function instead of
  `createInitialBookingCharge`; keep the existing "if this fails, log it but
  keep the booking" wrapper. Delete the now-unused `createInitialBookingCharge`
  (~line 1584).
- _Why:_ both new rows are `Pending`, so every existing "how much has actually
  been paid?" calculation still reads zero — the booking still behaves as unpaid
  until a real payment lands. Nothing about slot-holding or notifications
  changes.

### 3. Allow partial payments that spawn a leftover transaction

- **New migration `20260902163_m08_settle_transaction_partial.sql`** — replace
  the `settle_transaction` function (copy the current version from
  `20260901153`, then modify). Add an optional "amount actually applied"
  argument. If it's less than the transaction's total: shrink this transaction
  (and its line item) down to the amount paid, mark it `Fully Paid`, and
  **insert a new `Pending` `balance` transaction** for the leftover. If it
  equals the total, behave exactly as before. Because the leftover is itself a
  normal transaction, paying it partially again just spawns another leftover —
  "repeat until paid" works for free, and a `full` transaction that's underpaid
  spawns a `balance` too.
- **New migration `20260902164_m10_pay_transaction_with_credit_partial.sql`** —
  same idea for the pay-with-credit function: if the available credit is less
  than the charge, apply what there is and spawn the leftover, instead of
  refusing.
- **New migration `20260902165_m08_add_booking_payment_pending_aware.sql`** —
  the "Add a payment" function currently computes "remaining" as
  `price − already-settled`. Now that a booking can start with a `Pending`
  balance row, also subtract `Pending` amounts, so the cashier can't
  accidentally create charges that add up to more than the price.
- **`server/src/features/billing/services/transactionPayment.service.ts`**:
  - `recordTransactionPayment` (~line 80) — accept an "amount applied"; use it
    (not the full total) when checking the cash tendered and computing change;
    pass it to the RPC; return the newly-spawned leftover row so the UI can
    mention it. Delete the guard (~line 161) that blocked "Add a payment"
    whenever any `Pending` charge existed — the RPC now handles the maths.
  - `payTransactionWithCredit` (~line 216) — delete the hard "credit doesn't
    cover this, split it first" error (~line 253); apply what credit is
    available and let the RPC spawn the leftover.
- **`server/src/features/billing/services/customerBookingPayment.service.ts`** —
  `payForBooking` currently assumes a booking has at most one `Pending` charge.
  Make it pick deterministically: the `downpayment` row first, then the oldest
  `balance` row. Remove the matching "one pending charge only" guard in
  `addCustomerBalancePayment` (keep its "booking must be Partially Paid" check).
- **`server/src/features/billing/{billing.controller.ts, modules/validators/billing.validator.ts}`**
  — accept the new optional `amount_applied` field on the record-payment
  request.

### 4. Tidy the Record-payment popup

- **`client/src/features/billing/components/PaymentMethodForm/PaymentMethodForm.tsx`**
  — this form is shared with the checkout and misc-sale screens, so add an
  optional `methods` prop (defaulting to today's list) instead of changing the
  list globally. Pre-fill / show a placeholder of the amount due in the Cash
  box. Add an `isCredit` branch that hides the bank/reference/cash fields.
- **`client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`**
  (popup ~line 526) — pass `methods={[...PAYMENT_METHODS, 'Credit']}`. Add an
  editable "Amount to collect" box (defaults to the transaction total, can't
  exceed it) with a live note "A ₱X balance payment will be created" when it's
  less. Replace the two buttons with one **"Mark as paid"**: if the method is
  `Credit`, call the pay-with-credit endpoint; otherwise call record-payment
  with `amount_applied`.
- **`client/src/features/billing/api/billing.api.ts`** — add `amount_applied?:
number` to the record-payment request type.

### 5. Small shared clean-ups (bundled in so the code stays consistent)

- **`payment_choice` / `payment_scheme` constants.** The strings `'downpayment'
| 'full'` and `'full' | 'downpayment' | 'balance'` are re-typed by hand in
  ~10 files, and the **client** copy is missing `'balance'` — a latent bug the
  new UI would hit. Add `PAYMENT_SCHEMES` and `PAYMENT_CHOICES` constant arrays
  in the server and client `booking.types.ts` / `billing.types.ts` (matching the
  existing `BOOKING_SOURCES` pattern) and point the other files at them. The
  client `'balance'` fix must land here; the rest is a mechanical rename.
- **Display labels.** `BookingPaymentsPanel.tsx` (~line 94) and the Transactions
  filter dropdown gain a `balance → "Balance payment"` label.
- **Comments.** `checkoutAggregation.service.ts` and `payableBalances.ts` keep
  working as-is under the two-row model — add a sentence each explaining why.

### 6. Requirement 4 — already done, nothing to change

We confirmed by reading the code: migration `20260828144` dropped
`requires_downpayment`, `downpayment_amount`, and `downpayment_type` (and their
check constraints) from both the `services` and `packages` tables; the booking
validator only accepts `downpayment_*` on the strict _policy_ form; the server
reads the down-payment rule only from `policy_configurations`; there is no
per-service down-payment field anywhere in the staff UI; and the seed scripts
carry no such columns. The migration in step 1 is the only place the setting is
(re)established, and it's at policy level. `testing/testing.md` will record this
as verified.

## Things we deliberately are NOT doing

- Not touching `get_staff_availability()` (a database function with a history of
  merge accidents) — this work doesn't need it.
- Not renaming the `payment_status` enum values.
- Not redesigning the customer portal "Pay in full now" button. After this
  change it settles the down-payment transaction in one click and leaves the
  balance transaction still due (which is correct — the balance is its own row
  now). Whether that button's wording should change is an open question for the
  client; ship the straightforward version first.

## Build order

Branch `feat/booking-payment-scheme-and-partial-settlement` off `dev`. Commit in
this order (each is independently valid and testable):

1. Setting on by default (migration `…161` + fallback + one test fix).
   **This alone delivers requirement 1.**
2. Shared constants + client `'balance'` fix (no behaviour change).
3. Two transactions up front (migration `…162` + `booking.service.ts` + rework
   the down-payment test mocks).
4. Partial settlement core (migrations `…163`, `…165` + billing services +
   validator/controller + tests).
5. Credit partial-cover (migration `…164` + credit service + tests).
6. Record-payment popup (`PaymentMethodForm` + `TransactionHistoryTable` +
   `billing.api.ts` + tests).

## How you'll know it worked

`testing/testing.md` (written when the code is built) will carry the
click-by-click checks. In short, after `supabase db push` to a non-production
database and `npm run dev`:

- A `/portal/book` grooming booking shows the "down payment or full?" choice on
  the Review step; picking **down payment** creates **two** rows on
  `/staff/reports/transaction-history` — "Down payment" and "Remaining balance".
- Opening a row → **Pay** pre-fills the Cash amount; entering _less_ than the
  total marks that row paid and creates a fresh "Remaining balance" row for the
  difference; the single **Mark as paid** button also offers **Credit** as a
  method.
- Turning the setting **off** on Settings → Config → Policies hides the choice
  again and goes back to one full-price transaction.
- Creating/editing a service shows no down-payment field anywhere.
- "CI: Verify All" is green for both `golden-fur` and `golden-fur-vault`.
