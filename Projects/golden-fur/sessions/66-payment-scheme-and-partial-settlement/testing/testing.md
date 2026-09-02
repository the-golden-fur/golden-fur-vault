# Booking payment scheme + two-transaction downpayment + partial settlement

Branch: `feat/booking-payment-scheme-and-partial-settlement` (off `dev`)

## The request, verbatim

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

Follow-ups during the work:

> - make cash tendered autofill the full amount of the transaction
> - add credit as a payment option [on the staff Record-payment modal]
> - combine 2 pay buttons into just Pay / mark the transaction as paid

> [the Review step] is only supposed to be a choice of payment scheme
> (downpayment or full), not actual pay on the counter ... only show
> [the downpayment / balance breakdown] when selected payment scheme is
> downpayment ... use accounting terms (downpayment amount, remaining, etc.)

Decisions (see `plan.md`): downpayment policy seeded **on by default** (50%
Percentage); the two transactions are both created **up front**; partial
settlement spawns a leftover for **every** scheme (a "full" charge that is
underpaid also spawns). The Online/Walk-in booking-type step was **not**
touched — it is a receptionist-flow feature (`/staff/bookings/new`) and works
as before; the customer portal never had it.

## Root cause / Context

The booking Review step already had a downpayment-vs-full radio, but it only
renders when `policy_configurations.downpayment_enabled` is true — and that
column shipped `false` (migration `20260828143`), so no customer ever saw the
choice and `createBooking` forced `payment_scheme = 'full'`.

The old `createInitialBookingCharge` (app-side, in `booking.service.ts`)
emitted exactly one `Pending` `booking_payment` transaction — the down payment
_or_ the full net total. The remaining balance was implicit
(`netTotal − Σ settled`) and only became a row when a cashier used "Add a
payment". `settle_transaction` (migration `20260901153`) only ever flipped a
row straight to `Fully Paid`; `pay_transaction_with_credit` refused any
partial-cover. Several code paths assumed "at most one Pending charge per
booking".

Per-service/package downpayment columns were already dropped by migration
`20260828144` — verified, nothing to change there.

## What changed

### Database

- `20260902161_m09_policy_configurations_downpayment_default_on.sql` —
  `downpayment_enabled` column default → `true`; the seeded system-default row
  is UPDATEd to `enabled / Percentage / 50` (guarded so it won't overwrite an
  admin-set type/amount on a shared DB).
- `20260902162_m08_create_initial_booking_charge_rpc.sql` — new SECURITY
  DEFINER `create_initial_booking_charge(p_booking_id, p_scheme, p_net_total,
p_downpayment_amount)`. `downpayment` scheme → two `Pending` `booking_payment`
  rows (`payment_choice` `downpayment` + `balance`, each with one line item);
  `full` → one row.
- `20260902163_m08_settle_transaction_partial.sql` — drops the old 6-arg
  `settle_transaction`, recreates it with a trailing `p_amount_applied numeric
default null`. When the applied amount is less than the transaction total the
  row + its line item are shrunk to the applied amount, flipped `Fully Paid`,
  and a new `Pending` `balance` transaction is inserted for the leftover.
- `20260902164_m10_pay_transaction_with_credit_partial.sql` — `create or
replace`; same shrink-and-spawn when the applied credit is less than the
  charge. Removes the "full-cover only" behaviour.
- `20260902165_m08_add_booking_payment_pending_aware.sql` — `create or
replace`; `remaining = net − Σ settled − Σ pending`, so the RPC alone stops
  the outstanding charges exceeding the bill and the app-side "one Pending
  charge" guards could be deleted.

Reference copies: `testing/payment-scheme-and-partial-settlement.sql`.

### Server

- `booking.service.ts` — `createBooking` calls the new RPC (best-effort,
  same try/catch) instead of the now-deleted `createInitialBookingCharge`;
  guard is `requiresUpfrontCharge && !nothingOwed && netTotal > 0`.
- `staffPicker.service.ts` — `DOCUMENTED_DEFAULTS` (the no-policy-row fallback)
  flipped to downpayment-on to match the seeded row.
- `transactionPayment.service.ts` — `recordTransactionPayment` takes
  `amountApplied`, checks the cash tender against the amount being collected
  (not the full total), passes `p_amount_applied`, and returns the spawned
  `leftover`. `payTransactionWithCredit` drops the hard "split it first" 400.
  The `addBookingPayment` one-Pending-charge guard is deleted.
- `customerBookingPayment.service.ts` — `payForBooking` fetches all Pending
  `booking_payment` rows and targets the `downpayment` row first (for "pay
  downpayment") or the oldest non-downpayment row (for "pay in full"), always
  attaching to an existing Pending row before inserting a new one.
  `addCustomerBalancePayment`'s guard is deleted.
- `billing.controller.ts` / `billing.validator.ts` — accept `amount_applied`
  (`z.number().positive().optional()`).
- Shared consts: `PAYMENT_SCHEMES` / `PaymentScheme` in `booking.types.ts`,
  `PAYMENT_CHOICES` / `PaymentChoice` in `billing.types.ts` (server + client);
  the client `payment_choice` type gained the missing `'balance'`.

### Client

- `CustomerBookingFlowPage.tsx` (booking Review step) — legend is now
  **"Payment scheme"**; radios read _"Downpayment — PHP X now, PHP Y remaining
  balance"_ / _"Full payment — PHP Z"_; the **Downpayment amount / Remaining
  balance** rows show only when the downpayment scheme is selected; the helper
  line no longer says payment happens at the counter in that step.
- `TransactionHistoryTable.tsx` (staff Transactions page Record-payment modal)
  — cash tendered prefilled to the transaction total; **Credit** added to the
  method dropdown (routed to the pay-with-credit endpoint); the two buttons
  merged into one **"Mark as paid"**; an editable **"Amount to collect"** with
  a live "a PHP … balance payment will be created" hint drives partial
  settlement.
- `PaymentMethodForm.tsx` — optional `methods` prop; renders no
  bank/reference/cash fields for `Credit`; cash field shows a placeholder of
  the amount due.
- `BookingPaymentsPanel.tsx` — `'balance'` → "Balance payment" label.
- `billing.api.ts` — `amount_applied` on the record-payment payload,
  `leftover` on the two result types.

## Manual test — step by step

Prereqs: `supabase db push` to the linked non-production project, then
`npm run dev` from the repo root (client `http://localhost:5173`, server
`http://localhost:3000`). Log-in values are in `golden-fur/server/.env`
(referenced, not copied — see `context/context-manifest.md`).

### A. Customer picks the downpayment scheme → two transactions

1. Open `http://localhost:5173` and sign in as a **customer** (portal).
2. Click **Book a service**. Pick a pet, a branch, **Grooming**, a staff +
   date, then a service (e.g. the Golden Package). Click **Next** to the
   **Review** step.
3. In the price box you should see **"Downpayment amount"** and **"Remaining
   balance"** rows (each half the total for a 50% policy), and below it a
   fieldset headed **"Payment scheme"** with two radios:
   - _Downpayment — PHP … now, PHP … remaining balance_ (selected by default)
   - _Full payment — PHP …_
     The helper text should say _"No payment is collected in this step…"_ — **not**
     "recorded at the counter".
4. Click **Full payment**. The "Downpayment amount / Remaining balance" rows
   disappear. Click **Downpayment** again — they come back.
5. Leave **Downpayment** selected and click **Confirm booking**. You land on a
   "Booking confirmed" screen.
6. Go to **My Transactions** (`/portal/transactions`). The new booking shows
   **two** rows: one **Down payment** and one **Balance payment**, both
   _Due payment_. Failure: only one row, or a row labelled "Full payment".

### B. Cashier settles the down payment, then the balance partially

7. In another browser/profile, sign in to the **staff console** as a
   **Cashier** and open **Transactions** (`/staff/reports/transaction-history`).
8. Find the booking from step 5. Open the **Down payment** row's **⋯ → Pay**.
   The modal is headed **"Mark as paid — PHP …"**. The **Method** dropdown
   includes **Credit**. **Cash tendered** is pre-filled with the transaction's
   amount. There is **one** button, **"Mark as paid"** (no separate "Pay from
   account credit").
9. Leave "Amount to collect" at the full amount, method **Cash**, click
   **Mark as paid**. The row flips to **Fully Paid**; the booking rollup
   becomes **Partially Paid**; the customer receives the booking-confirmed
   notification (this was the first settled payment).
10. Open the **Balance payment** row → **Pay**. Set **Amount to collect** to
    _less_ than the total (e.g. half). A line appears: _"A PHP … balance
    payment will be created for the rest."_ Click **Mark as paid**.
11. The row flips to **Fully Paid** for the amount you entered, and a **new**
    **Balance payment** row appears (Due payment) for the leftover. The booking
    stays **Partially Paid**. Failure: no new row, or the row settles for the
    full amount.
12. Repeat step 10–11 on the new leftover row, paying it in full this time →
    booking becomes **Fully Paid**.

### C. Credit, partial cover

13. Ensure the test customer has some account credit at this branch but less
    than a Due-payment row's amount (cancel a paid booking in time to generate
    credit if needed).
14. Open that Due-payment row → **Pay**, choose method **Credit** (the
    amount/bank/reference fields hide), click **Mark as paid**. The row settles
    for the available credit and a new **Balance payment** row appears for the
    remainder. Failure: a 400 "credit doesn't cover this charge — split it
    first".

### D. Full scheme, underpaid

15. Book another Grooming service as the customer, choose **Full payment** on
    Review, confirm. My Transactions shows **one** "Full payment" row.
16. As the cashier, open it → **Pay**, set "Amount to collect" below the total,
    **Mark as paid**. It settles partially and spawns a **Balance payment**
    row.

### E. Policy toggle still works

17. Sign in as **Admin**, open **Settings → Config → Policies**. In the
    Downpayment section, untick **enable**. Save.
18. As the customer, start a new booking. On **Review** there is **no**
    "Payment scheme" fieldset and **no** breakdown — just the estimated total.
    My Transactions shows **one** "Full payment" row after confirming.
19. Re-enable the policy in step 17 to restore the default.

### F. Per-service downpayment config is gone

20. As **Admin**, open **Settings → Services & Packages**, create or edit a
    service. Confirm there is **no** downpayment field anywhere on the form.

### G. Receptionist Online/Walk-in step (regression check — unchanged)

21. Sign in as a **Receptionist**, open **Bookings Queue**, click **New
    booking**. After the Customer and Service Type steps there is still a
    **Booking Type** step offering **Online Booking** / **Walk-in**. Pick
    **Walk-in** → the date/time picker locks to "now" and the booking is
    created **In Progress** with no downpayment.

API-level checks (down payment amounts, `amount_applied` validation, the
leftover in the response): `testing/payment-scheme-and-partial-settlement.postman_collection.json`.

## Test suites

Run at HEAD `34f1a08` this session:

- `server`: `npx vitest run` — **950 / 950** passing (88 files);
  `npm run lint` — exit 0.
- `client`: `npx vitest run` — **766 / 766** passing (149 files);
  `npm run lint` — exit 0; `npm run build` — built OK.
- repo root: `npm run format:check` — exit 0.

`.git/ci-verifier-pass` written for `34f1a08`. The `ci-verifier` and
`code-reviewer` subagents both terminated on the account session rate limit;
the verification above and `reviews/2026-09-02-1742-pre-pr.md` are the manual
equivalents.

## Open items

- No direct DB-level test of the three RPCs (shrink-and-spawn, repeat, the
  `SUM(line_total)` invariant after a shrink) — all covered only through
  mocked-Supabase service specs. Flagged in the review as G1.
- No test that the first-payment notification fires exactly once when the
  `balance` row settles before the `downpayment` row (review G2).
- `supabase db push` not yet run — it's the closing step once this merges.
- The customer portal "Pay in full now" button now settles just the down
  payment row and leaves the balance row separately due (correct, but the
  copy may want a rethink — noted in `plan.md`).
