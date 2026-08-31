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
nothing, if no down payment was configured), and a still-`Unpaid`
down-payment reservation could be issued credit for money never received.
The fix bases the credit on what was actually paid, derived from
`bookings.payment_stage`.

**Decision (from clarifying questions):** the rate applies to the _actual
amount paid_ (`Paid` → net total, `Paid in Advance` → down payment, `Unpaid`
→ 0), not just the configured down payment. Navbar shows one summed peso
total across branches with a wallet icon, hidden at zero, linking to
`/portal`.

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
- `services/cancellation.service.ts` — core change:
  - new `amountPaidOnBooking(booking)` helper derives the paid amount from
    `payment_stage` (`Paid` → `total_price − discount_amount − promo_amount`;
    `Paid in Advance` → `downpayment_amount`; else `0`).
  - `creditAmount = round2(amountPaidOnBooking(booking) × rate / 100)`;
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
  `<Wallet>` + summed total, renders nothing while first-loading or at a
  zero total, links to `/portal`.
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
5. Cancel flow is environment-dependent (needs a paid booking id) — steps
   `5`–`7` are templated; fill `booking_id` and run against a booking whose
   `payment_stage` is `Paid in Advance`.

### Manual — full pipeline (dev servers up; migration pushed to the linked non-prod Supabase)

1. **Admin** → Settings → Config → Policies. Confirm the new "Cancellation
   credit" field shows `100`. Set notice enforcement to **Soft** (so you can
   test without waiting days), set the rate to **50**, save.
2. **Customer** → create an online booking that requires a down payment; pay
   the down payment (PayMongo sandbox). Confirm the navbar shows **no**
   credit pill yet.
3. Cancel that booking (My Bookings → Cancel → confirm modal).
   - Success banner: "converted into account credit…".
   - Navbar pill appears showing **50% of what was paid**.
   - `/portal` branch card shows the same figure.
   - SQL: `select amount, cancellation_log_id from credit_transactions order by created_at desc limit 1;`
     → one `issuance` row, `amount` = 50% of paid, `cancellation_log_id` set.
4. Set the rate back to **100**, cancel a **fully-paid** booking with notice
   → credit = the full discounted net total (not just a down-payment slice).
5. Cancel an **unpaid** down-payment reservation with notice → `credit_issued: false`,
   no `credit_transactions` row, pill unchanged.
6. Cancel a booking with notice **not met** under Strict → `credit_issued: false`,
   payment forfeited (unchanged behaviour).
7. #117: covered by the new unit test — a failing `cancellation_logs`
   insert still issues credit (`p_cancellation_log_id: null`).
8. **Reschedule re-verify:** reschedule a _different_ still-`Pending`
   booking → new date/time shows, status stays `Pending` (reschedule never
   changes `status`), credit pill unaffected by the reschedule itself.

## Test suites

- `server`: `npx vitest run` — 917/917 passing (86 files); `npx tsc --noEmit` clean.
  `cancellation.service.spec.ts` gains 4 cases (rate scaling, fully-paid
  conversion, unpaid → no credit, #117 log-failure still issues).
- `client`: `npx vitest run` — 740/740 passing (143 files); `npx tsc --noEmit` clean.
  New `CreditBalanceIndicator.spec.ts` (3 cases); `CustomerBookingsPage.spec.ts`
  and `CustomerAuthGuard.spec.ts` updated for the provider.
- Root: `npm run format:check` clean; `npm --prefix client run lint` clean;
  `npm --prefix server run lint` clean (0 errors, pre-existing `no-console`
  warnings only); `npm --prefix client run build` succeeds.

## Open items

- **Checkout redemption is still a stub** (unchanged) — issued credit still
  can't be spent at checkout; DSR credit-usage still reads zero. Out of
  scope here.
- `CustomerPortalPage` keeps its own `listCreditBalances` fetch rather than
  reading the new context — a harmless second call on the portal home;
  deduping it was deliberately left out to keep the diff focused.
- The cancelled-booking **email** still reports only the notice outcome, not
  the credited amount (the in-app notification already includes it). Not
  changed here.
