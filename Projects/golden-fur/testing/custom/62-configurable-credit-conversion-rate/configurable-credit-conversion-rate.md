# Configurable cancellation-to-credit conversion rate + credit-not-issued bug fix + navbar credit indicator

Branch: `feat/configurable-credit-conversion-rate`

## The request, verbatim

> - Add a configurable cancellation-to-credit conversion rate (default 100%,
>   admin-adjustable, e.g. down to 50%) instead of a hardcoded full
>   conversion.
> - Fix the bug where credits were not generated after a cancellation during
>   testing — verify the down-payment-to-credit pipeline end-to-end.
> - Re-verify that the reschedule flow correctly reflects updated booking
>   status and resulting credit balance after a cancellation.
> - On the navbar, show how much credits a customer has (only applies to
>   customers), include an icon

Source: advisor session `MsMayuga-Aug27` ("Cancellations & Credits" items
10 and 11) via `Inbox/Architectural-Change-History.docx`.

## Root cause / Context

**Conversion rate.** `cancellation.service.ts` converted `booking.downpayment_amount`
straight into credit — no percentage, and only for bookings that carried a
configured down payment. The advisor asked for an admin-adjustable rate so a
cancellation can keep part of the payment as a charge.

**Credits not generated (GitHub #117).** Credit issuance was gated on
`if (qualifies && log)`, where `log` is the `cancellation_logs` row. That
write is deliberately best-effort and returns `null` on failure, which
silently skipped the credit the customer was owed. `credit_transactions.cancellation_log_id`
is nullable, so the two never needed to be chained.

**Second gap found while fixing.** The old logic keyed off `downpayment_amount`,
so a booking **paid in full** got credit for only the down-payment slice (or
nothing, if no down payment was configured). The rate now applies to what
the customer actually paid.

**Third gap — live testing, the one that actually matters.** Basing the
paid amount on `bookings.payment_stage` was still wrong: a customer
self-service Online booking that requires **no** down payment lands at
`payment_stage = 'Paid'` at creation (see the `paymentStage` ternary in
`booking.service.ts` — the `downpaymentRequired ? 'Unpaid' : undefined`
branch, where `undefined` → column default, but these rows still read
`'Paid'`), so cancelling one minted credit for money that was never
collected. Reported: Customer 1's balance jumped `0 → 1386` from cancelling
two never-paid ₱693 Grooming bookings. **Fix:** `confirmedAmountPaid()` now
sums the booking's `booking_payment` `transactions` whose `payment_status`
is not `'Pending'` (a cashier / the PayMongo webhook actually settled them —
`'Partially Paid'` for a downpayment, `'Fully Paid'` for a full/remaining
payment). No confirmed transaction → no credit.

**Fourth gap — why "I marked it paid and still no credit".** After the third
fix, the user marked a booking paid via the Payments Queue and _still_ got
no credit, because **the cashier "Mark as Paid" path had never written a
`transactions` row**: `recordBookingPaymentTransaction` set `payment_choice`
on a `initiated_by='staff'` row, violating the CHECK
`transactions_payment_choice_requires_customer_initiated` (migration
`20260809118`); `advancePaymentStage` swallows the throw. The `transactions`
table had **zero rows** since Aug 9. Fixed by dropping `payment_choice` from
that insert (commit `fix(billing): record booking-payment transactions on
cashier mark-as-paid`).

_(The `payment_stage = 'Paid'`-without-payment booking-flow bug and the
whole "payment method at booking time" model are being reworked — see the
approved plan: payment method moves to per-transaction pay time, the
Payments Queue is deleted, `bookings.payment_stage` is dropped in favour of
a `bookings.payment_status` rollup, and credit redemption is wired up.)_

**Decision (from clarifying questions + live feedback):** the rate applies
to the confirmed-paid amount, not the configured down payment. Navbar shows
one summed peso total across branches with a wallet icon, linking to
`/portal`, **always shown, including at a ₱0.00 balance** (changed from an
initial "hidden at zero" design so customers discover the feature).

## What changed

### Database

- `supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql`
  — adds `policy_configurations.cancellation_credit_conversion_rate`
  `numeric(5,2) NOT NULL DEFAULT 100 CHECK (0–100)`. The `NOT NULL DEFAULT`
  backfills the seeded system-default row and any branch-override rows to
  `100`, so behaviour is unchanged until an admin lowers it.

### Server

- `booking.types.ts` — `cancellation_credit_conversion_rate` added to
  `PolicyConfiguration` and to the `EffectivePolicy` pick list.
- `services/staffPicker.service.ts` — field added to `DOCUMENTED_DEFAULTS`
  (fallback = 100) and to the `baseline` object in
  `updatePolicyConfiguration()` so a partial PATCH doesn't reset it.
- `modules/validators/booking.validator.ts` — `updatePolicyValidator` gains
  `cancellation_credit_conversion_rate: z.number().min(0).max(100).optional()`
  (the object is `.strict()`, so the field must be declared).
- `services/booking.service.ts` — `recordBookingPaymentTransaction` (the
  cashier "Mark as Paid" path) set `payment_choice` on a staff-initiated
  row, which the CHECK
  `transactions_payment_choice_requires_customer_initiated` (migration
  `20260809118`) rejects. `advancePaymentStage` swallows the throw as
  best-effort, so `payment_stage` advanced to `Paid` but **no `transactions`
  row was ever persisted** — the table had zero rows since Aug 9, and
  `confirmedAmountPaid` (below) therefore always saw 0. Fix: drop
  `payment_choice` from the staff insert (the line-item `description` +
  `payment_status` carry the same meaning). Verified against the linked DB.
- `services/cancellation.service.ts` — core change:
  - new `confirmedAmountPaid(bookingId)` helper: `SUM(total_amount)` of the
    booking's `transactions` where `transaction_type = 'booking_payment'`
    AND `payment_status != 'Pending'`. Skipped (→ 0) when notice wasn't met.
  - `creditAmount = round2(confirmedAmountPaid × rate / 100)`;
    `qualifies = notice.met && creditAmount > 0`.
  - credit issuance block no longer gated on `log`; `issueCredit` is called
    with `cancellationLogId: log?.id ?? null`; the log patch runs only when a
    log row exists.
  - notification now reports the real `creditAmount`.
- `services/creditIssuance.service.ts` — `IssueCreditParams.cancellationLogId`
  is now `string | null`.

### Client

- `booking.types.ts` — `cancellation_credit_conversion_rate` added to
  `PolicyConfiguration`, `EffectivePolicy`, `UpdatePolicyPayload`.
- `pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx` — new
  "Cancellation credit" section (number input, 0–100) with a system-default
  of 100; wired through `FormState`, `formStateFromPolicy`, the page
  `DOCUMENTED_DEFAULTS`, and the `handleSubmit` payload.
- `shared/utils/formatCurrency.ts` (new) — shared `₱1,234.00` formatter;
  `CreditBalanceCard` now imports it instead of its own copy.
- `features/credits/providers/` (new) — `CreditBalanceContext`,
  `CreditBalanceProvider` (self-reads `listCreditBalances`, exposes
  `{ balances, total, isLoading, refresh }`), `useCreditBalance`.
- `features/credits/components/CreditBalanceIndicator/` (new) — navbar pill:
  `<Wallet>` icon + summed total, always rendered (shows `₱0.00` at a zero
  balance), links to `/portal`.
- `shared/components/AppShell/AppShell.tsx` + `shared/components/Navbar/Navbar.tsx`
  — new optional `creditIndicator` prop, threaded through like
  `notificationBell` / `composeButton`.
- `features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx` —
  wraps the customer `AppShell` in `CreditBalanceProvider` and passes
  `creditIndicator={<CreditBalanceIndicator />}`. `StaffAuthGuard` untouched.
- `pages/CustomerBookingsPage/CustomerBookingsPage.tsx` — `confirmCancel`
  calls `refreshCreditBalance()` after a `credit_issued` cancellation so the
  navbar pill / portal home update without a reload.

## Verification

### API (see `configurable-credit-conversion-rate.postman_collection.json`)

1. `1. Login as Admin` → captures the token.
2. `2. GET /bookings/policy` → confirm the default row now has
   `cancellation_credit_conversion_rate: 100`.
3. `3. PATCH /bookings/policy` `{ "cancellation_credit_conversion_rate": 50 }`
   → 200, response echoes `50`.
4. `4. PATCH /bookings/policy` `{ "cancellation_credit_conversion_rate": 150 }`
   → 400 (validator: 0–100).
5. Cancel flow is environment-dependent (needs a booking with a confirmed
   `booking_payment` transaction) — steps `6`–`8` are templated; fill
   `booking_id` / `expected_paid_amount` and run against a booking a cashier
   has marked paid.

### Manual — full pipeline (dev servers up; migration pushed to the linked non-prod Supabase)

1. **Admin** → Settings → Config → Policies. Confirm the new "Cancellation
   credit" field shows `100`. Set notice enforcement to **Soft** (so you can
   test without waiting days), set the rate to **50**, save.
2. **Customer** → create an online booking that requires a down payment. The
   navbar credit pill shows **₱0.00** (always visible).
3. **Cancel it now, before paying** → `credit_issued: false`, no
   `credit_transactions` row, pill still ₱0.00 (this is the reported bug — an
   uncollected booking must not mint credit, even if its `payment_stage`
   reads `Paid`).
4. Create another, **pay the down payment** (PayMongo sandbox, or a cashier
   marks the `booking_payment` transaction paid). Then cancel it.
   - Success banner: "converted into account credit…".
   - Navbar pill updates to **50% of what was paid**.
   - `/portal` branch card shows the same figure.
   - SQL: `select amount, cancellation_log_id from credit_transactions order by created_at desc limit 1;`
     → one `issuance` row, `amount` = 50% of the settled down payment.
5. Set the rate back to **100**, cancel a **fully-paid** booking with notice
   → credit = the full settled amount (down payment + remaining balance).
6. Cancel a booking with notice **not met** under Strict → `credit_issued: false`,
   payment forfeited (unchanged behaviour).
7. #117: covered by the new unit test — a failing `cancellation_logs`
   insert still issues credit (`p_cancellation_log_id: null`).
8. **Reschedule re-verify:** reschedule a _different_ still-`Pending`
   booking → new date/time shows, status stays `Pending` (reschedule never
   changes `status`), credit pill unaffected by the reschedule itself.

## Test suites

- `server`: `npx vitest run` — all passing; `npx tsc --noEmit` clean.
  `cancellation.service.spec.ts` (13 cases): rate scaling, full settled-amount
  conversion, **`payment_stage: 'Paid'` with no confirmed transaction → no
  credit**, notice-not-met → no credit, #117 log-failure still issues.
  `booking.service.spec.ts` — asserts `recordBookingPaymentTransaction`'s
  insert carries **no `payment_choice`** (the constraint that was silently
  failing) and the correct line-item description.
- `client`: `npx vitest run` — 740/740 passing (143 files); `npx tsc --noEmit` clean.
  New `CreditBalanceIndicator.spec.ts` (3 cases, incl. renders `₱0.00` at zero);
  `CustomerBookingsPage.spec.ts` and `CustomerAuthGuard.spec.ts` updated for
  the provider. (One unrelated pre-existing failure on `dev`:
  `AdminPromoConfigPage.spec.ts > the timing filter narrows to Ended promos`,
  a date-sensitive flake — not touched by this change.)
- Root: `npm run format:check` clean; `npm --prefix client run lint` clean;
  `npm --prefix server run lint` clean (0 errors, pre-existing `no-console`
  warnings only); `npm --prefix client run build` succeeds.

## Open items

- **Follow-on approved plan — payment/transactions rework.** Payment method
  moves out of the booking step to per-transaction pay time; the Payments
  Queue is deleted (its mark-as-paid moves to the Transactions page, per
  transaction; Misc controls fold into the Bookings Queue);
  `bookings.payment_stage` (and its "Paid in Advance" label) is **dropped**
  in favour of a `bookings.payment_status` rollup reusing the
  `transactions.payment_status` vocabulary; credit redemption ("pay with
  credits") is wired up for real. Phased; Phase 0 (the constraint fix above)
  shipped in this branch.
- **`payment_stage = 'Paid'` on an uncollected Online booking** — the
  receptionist-picks-GCash/Maya path sets `payment_confirmed: true` client
  -side and the server trusts it. Removed by Phase 1 of the rework.
- **Stale test data:** cleaned — Customer 1's bogus `credit_balances` /
  `credit_transactions` rows and the two lying `cancellation_logs` rows were
  deleted / corrected on the linked project.
- **Checkout redemption is still a stub** — issued credit still can't be
  spent; DSR credit-usage still reads zero. Addressed by Phase 3 of the
  rework.
- `CustomerPortalPage` keeps its own `listCreditBalances` fetch rather than
  reading the new context — a harmless second call on the portal home;
  deduping it was deliberately left out to keep the diff focused.
- The cancelled-booking **email** still reports only the notice outcome, not
  the credited amount (the in-app notification already includes it). Not
  changed here.
