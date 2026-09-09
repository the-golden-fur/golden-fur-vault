# One "Amount paid" field in the mark-as-paid modal

Branch: `feat/simplify-mark-as-paid-modal` (base: `dev`; code uncommitted in
the working tree at the time this record was written — read it with
`git -C ../golden-fur diff`).

## The request, verbatim

> Simplify cashier account > transaction > mark transaction as paid modal:
>
> - Currently there's 2 payment fields
> - What is amount to collect for?
> - What is cash tendered for?
> - Simplify and merge, 1 field only and that's the field how much the
>   cashier/customer is going to pay against the transaction
> - You can omit the change label
>
> (see Projects/golden-fur/shared/context/Architectural-Change-History.docx
> for full task context)
> commit new arch changes file in the end

**Scope note.** Two things were settled with the user during planning:

1. The single field is labelled **"Amount paid (PHP)"** (neutral — reads for
   both "customer sets how much I'm paying" and "receptionist sets how much a
   customer pays").
2. The customer's own Pay modal (`/portal/transactions`, "My Transactions"),
   which had **no** amount field and always paid the full transaction, also
   gets the single "Amount paid" field — **editable for the "Account credit"
   method only**. For GCash / Maya the field is shown disabled and locked to
   the full amount; a true partial there needs PayMongo-webhook work that is
   deliberately out of scope.

## Root cause / Context

Money owed on a booking lives in the `transactions` table, one row per
charge. Two UIs settle a _Pending_ row:

- **Cashier:** `TransactionHistoryTable` (`/staff/reports/transaction-history`).
  Its "Mark as paid" modal had two number inputs — _Amount to collect_ (how
  much to settle now; a smaller value spawns a _Pending_ "balance"
  transaction for the rest) and _Cash tendered_ (Cash method only), which
  drove a computed **"Change: PHP …"** line.
- **Customer:** `CustomerTransactionHistoryPage` (`/portal/transactions`).
  Its "Pay" modal offered Account credit / GCash / Maya and always paid in
  full — no amount field.

The transaction row never stored a tendered or change figure —
`settle_transaction` (the DB function) already ignored its `p_cash_tendered`
parameter, and nothing downstream read `changeAmount`. So the second field
and the change line were pure UI.

The accepted payment methods are **unchanged** from `dev`
(`z.enum(PAYMENT_METHODS)` on `recordTransactionPaymentValidator`, and the
full `PAYMENT_METHODS` + `Credit` in the modal dropdown): an early revision
narrowed both to the 5 counter methods, but code review flagged that as a
scope creep / behaviour change (it would have stopped a cashier recording a
counter GCash/Maya QR payment against an existing Pending row), so it was
reverted. This PR only changes the field count. The validator docblock was
corrected to describe the actual behaviour rather than the aspirational
"GCash/Maya excluded" wording that predated this change.

No schema change — no migration.

## What changed

### Server

- **`modules/validators/billing.validator.ts`** —
  `recordTransactionPaymentValidator` drops the `cash_tendered` field and its
  "required when payment_method is Cash" refinement; `payment_method` stays
  `z.enum(PAYMENT_METHODS)` (docblock corrected). New
  `payTransactionWithCreditValidator` — a `.strict()` object with a single
  optional `amount_applied: z.number().positive()`; an empty body is valid.
- **`billing.controller.ts`** — `recordTransactionPaymentController` stops
  passing `cashTendered`. `payTransactionWithCreditController` now
  `safeParse`s `req.body ?? {}` with the new validator (400 with
  `error.issues` on failure) and passes `amountApplied` to the service.
- **`services/transactionPayment.service.ts`** —
  `recordTransactionPayment` loses the `cashTendered` param, the
  `resolvePaymentConfirmation` call and import, and `changeAmount` from
  `RecordTransactionPaymentResult`. It passes `p_cash_tendered: null` to the
  unchanged `settle_transaction` RPC (kept only for call-site symmetry).
  A shared `resolveAmountApplied(amountApplied, total)` helper does the
  `round2` + `> 0` + `<= total` bounds check (error copy "Amount paid …");
  both `recordTransactionPayment` and `payTransactionWithCredit` call it
  right after the Pending check, before any DB work.
  `payTransactionWithCredit` gains optional `amountApplied`, then
  `amount = round2(min(available, requested))` (was
  `min(available, chargeAmount)`).
- **`services/transactionPayment.service.spec.ts`** — drops the
  `cashTendered` inputs and `changeAmount` assertions; the Cash test now
  asserts `p_cash_tendered: null`. Adds two `payTransactionWithCredit`
  cases: "caps `p_amount` at a caller-supplied `amountApplied` even when
  more credit is available" and "rejects `amountApplied` greater than the
  transaction total".

### Client

- **`billing/api/billing.api.ts`** — `RecordPaymentPayload` drops
  `cash_tendered`; `recordTransactionPayment`'s result type drops
  `changeAmount`; `payTransactionWithCredit(transactionId, accessToken,
amountApplied?)` — new optional third arg, sends
  `JSON.stringify({ amount_applied })` as the body only when it is set
  (otherwise no body, as before).
- **`billing/components/PaymentMethodForm/PaymentMethodForm.tsx`** — new
  `hideCashTendered?: boolean` prop. When true the Cash branch renders
  neither the "Cash tendered (PHP)" input nor the "Change:" line (and, since
  the whole `showCashTendered` block is skipped, no reference field in that
  branch either). Card / Bank / online branches unchanged. Checkout and
  `MiscellaneousSaleForm` keep the default (`false`).
- **`reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`** —
  `PAY_MODAL_METHODS` unchanged (`[...PAYMENT_METHODS, 'Credit']`). `openPay`
  no longer prefills `cash_tendered`. The single input is relabelled **"Amount paid (PHP)"** and
  rendered for every method including Credit. `<PaymentMethodForm
hideCashTendered>`. `confirmPay` sends no `cash_tendered`; a value below
  the total is passed as `amount_applied` to `recordTransactionPayment` and
  as the new third arg to `payTransactionWithCredit`. The
  "balance will be created" preview shows the exact peso figure only for the
  counter path; for Credit it is number-free ("Whatever the available credit
  does not cover will be left as a balance payment"), because the server
  caps the applied amount at available credit.
- **`reports/pages/CustomerTransactionHistoryPage/CustomerTransactionHistoryPage.tsx`** —
  new `payAmount` state, prefilled to the transaction total in `openPay`.
  New single **"Amount paid (PHP)"** input, `disabled` unless
  `payMode === 'credit'`. New `selectPayMode` helper snaps `payAmount` back
  to the full amount whenever a non-credit mode is chosen. `confirmPay`
  validates the amount for the credit path (`> 0`, `<= total`) and passes a
  below-total value as the third arg to `payTransactionWithCredit`.
  Number-free balance hint for credit; a "GCash and Maya must pay the full
  amount" note for the locked modes.
- **Specs** — `PaymentMethodForm.spec.tsx` (+1: `hideCashTendered` drops the
  field, the change line and the reference field for Cash);
  `TransactionHistoryTable.spec.ts` (renamed cases for the single field;
  asserts no "Cash tendered" / no "Change:"; `payTransactionWithCredit`
  called with the new 3rd arg `undefined` for a full pay and `200` for a
  partial; +1 case for the partial-credit route);
  `CustomerTransactionHistoryPage.spec.tsx` (+2: partial "Amount
  paid" sent as the credit amount with the number-free preview; field locked
  and snapped to full for GCash / Maya).

## Manual test — step by step

Assumes `golden-fur` is running locally: server on `http://localhost:3000`,
client on `http://localhost:5173` (`npm run dev` at the repo root, or the
"Dev: Start All" VS Code task). Verified against the dev Supabase database
(see `server/.env` / `client/.env` — secrets, never copied here).

Logins (from the seed data): staff `<branch>.<role>N` / `password123`
(e.g. `makati.cashier1`); customers `customerN@goldenfur.com` /
`password123`.

You need at least one **Pending** transaction. If there isn't one: log in as
a customer, **Book an appointment** → assessed pet → a branch → **Grooming**
→ a service that requires a down-payment → pick a slot → reach the payment
step but **do not** pay. That booking now has a _Pending_ down-payment
transaction visible to the cashier.

### A. Cashier "Mark as paid" — one field, counter method

1. Open `http://localhost:5173`, click **Staff Login**, sign in as
   `makati.cashier1` / `password123`. You land on a page headed
   **Dashboard**. (A red error banner instead = dev server or seed data not
   ready; stop.)
2. In the left sidebar click **Transactions**. You land on
   `/staff/reports/transaction-history`, a table headed with filter tiles
   and a transaction list.
3. Find a row whose status is **Pending** and click its **Mark as paid**
   button.
   - **PASS:** a modal opens titled **Mark as paid — PHP <total>**. There is
     exactly **one** money field, labelled **Amount paid (PHP)**, prefilled
     with the transaction total. Below it a **Method** dropdown.
   - **FAIL:** two number fields, or a field labelled "Amount to collect" or
     "Cash tendered".
4. In **Method** choose **Cash**.
   - **PASS:** no extra "Cash tendered (PHP)" field appears and no "Change:
     PHP …" line appears.
   - **FAIL:** a "Cash tendered" box or a "Change" line shows up.
5. Leave **Amount paid** at the full total, keep **Cash**, click **Mark as
   paid**.
   - **PASS:** the modal closes, the row flips to **Fully Paid**, no error
     banner.

### B. Cashier partial settlement spawns a balance transaction

1. Repeat A1–A3 on another **Pending** row (note its total, call it `T`).
2. Clear **Amount paid** and type a smaller number, e.g. `T` minus 100.
   - **PASS:** a line appears reading "A PHP 100.00 balance payment will be
     created for the rest." Keep **Cash** as the method.
   - **FAIL:** no such line, or the figure is wrong.
3. Click **Mark as paid**.
   - **PASS:** the modal closes; the original row is **Fully Paid**; a new
     **Pending** transaction for PHP 100.00 (type "balance") now appears for
     the same booking.

### C. Cashier settles from account credit

1. You need a customer with a positive credit balance. As `makati.cashier1`,
   or an Admin, you can confirm a customer's credit on
   `/staff/reports/transaction-history` by checking that customer, or issue
   credit by cancelling one of their paid bookings (see the Credits feature).
2. On a **Pending** row belonging to that customer, click **Mark as paid**,
   set **Method** to **Credit**.
   - **PASS:** the **Amount paid (PHP)** field is still shown and editable.
3. Type an amount larger than the customer's available credit but no more
   than the transaction total.
   - **PASS:** the preview line is the number-free "Whatever the available
     credit does not cover will be left as a balance payment." (not a peso
     figure).
   - **FAIL:** a specific "A PHP X balance payment will be created" figure
     shows for the Credit method.
4. Click **Mark as paid**.
   - **PASS:** the row settles for the available credit and a **Pending**
     balance transaction is created for the uncovered remainder.

### D. Customer Pay modal — credit is editable, GCash/Maya locked

1. Sign out. Click **Log in** and sign in as the customer from C
   (`customerN@goldenfur.com` / `password123`).
2. In the sidebar click **Transactions** → `/portal/transactions`.
3. On a payable row click **Pay**. A modal opens titled **Pay PHP <total>**
   with a "How would you like to pay?" group: **Account credit**, **GCash**,
   **Maya**.
   - **PASS:** below the radio group there is an **Amount paid (PHP)** field,
     prefilled to the total, editable while **Account credit** is selected.
4. With **Account credit** selected, lower the amount below the total.
   - **PASS:** a note appears: "Whatever your available credit does not
     cover will be left as a balance payment you can settle later."
5. Click the **GCash** radio.
   - **PASS:** the **Amount paid** field is greyed out (disabled) and snaps
     back to the full total; a note reads "GCash and Maya must pay the full
     amount. Use account credit to pay part of this transaction."
   - **FAIL:** the field stays editable, or keeps the lowered value.
6. Switch back to **Account credit**, set a partial amount, click **Pay with
   credit**.
   - **PASS:** the modal closes; the transaction is settled for that amount
     (bounded by available credit) and a balance transaction is created for
     the rest.

### E. API-level checks

See `testing/simplify-mark-as-paid-modal.postman_collection.json` — it
covers: a Cash mark-as-paid with **no** `cash_tendered` succeeding (was
required before); a `cash_tendered` field now rejected by the `.strict()`
schema (400); `pay-with-credit` with `amount_applied` greater than the total
rejected (400); and `pay-with-credit` with a valid partial `amount_applied`.

## Test suites

Re-run this session (no `ci-verifier` in this environment):

- **server:** `npx tsc --noEmit` clean; `npx vitest run src/features/billing`
  — **61/61 passing (7 files)**.
- **client:** `npx tsc --noEmit` clean;
  `npx vitest run src/features/billing src/features/reports` — **50/50
  passing (8 files)**.
- Repo-root `npm run format:check` — clean.
- Code review: `reviews/2026-09-09-1900-pre-pr.md` (high, pre-PR — supersedes
  the earlier medium pass `2026-09-09-1812-pre-pr.md`). Two findings actioned
  (method-narrowing reverted; bounds check extracted), two recorded as
  intentional no-ops.

## Open items

- **Full-amount credit pay with insufficient credit** spawns a balance
  transaction but shows no post-payment toast surfacing the `leftover`.
  Pre-existing (`pay_transaction_with_credit` has clamped to available
  credit since migration `20260902164`); neither the old nor new UI reads
  the response's `leftover`. Not a regression.
- **A true partial GCash / Maya payment** from the customer modal is out of
  scope — it needs PayMongo-webhook reconciliation work. The field is locked
  to the full amount for those methods on purpose.
- **Board view + an active Status filter tile shows empty columns** — from
  session 78's `TransactionBoard`; untouched here.
