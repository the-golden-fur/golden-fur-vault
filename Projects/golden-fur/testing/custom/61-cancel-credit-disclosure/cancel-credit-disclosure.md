# Cancellation flow discloses the non-refundable → account-credit policy

Branch: `feat/cancel-credit-disclosure` (golden-fur, stacked on
`feat/cancel-confirmation-dialog`); `filing/cancel-credit-disclosure-verification`
(this vault doc, stacked on `filing/cancel-confirmation-dialog-verification`).

## The request, verbatim

> Add on-screen copy in the cancellation flow disclosing that payment (full
> or down) is non-refundable but will be converted into account credit for
> use on a future visit.

From the Aug-27 advisor demo (`Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`):
_"please be reminded that your down payment, or your payment, full or down
payment, will not be refunded. However, it will be converted into credits …
it will be credited to your account, that you can use to pay for any type of
service the next time you visit."_

## Context

Nothing in the cancel UI mentioned money. The credit-conversion policy
lived only in `M09` / the `credit-balance-ledger` skill and in the
post-cancel _notification_ — the customer confirming a cancellation on
screen saw only "This can't be undone".

Actual server rule (`cancellation.service.ts`, unchanged here): a
cancellation converts the booking's snapshotted `downpayment_amount` into
a per-branch account-credit increment **only when the notice period was
met**; a late (Strict) cancellation forfeits it. Credit is branch-specific,
non-transferable, non-refundable as cash, and expires (default 30 days,
per policy).

## What changed

Client only — no server, schema, or API change.

- `client/src/features/booking/booking.types.ts`
  - `CancellationResult` gains `credit_issued: boolean` — the server's
    `cancelBooking` already returns it; the client type just hadn't
    surfaced it.
- `client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`
- `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`
  - The cancel `ConfirmDialog` body adds a paragraph, shown **only when
    the booking has actually been paid** (`payment_stage` is `Paid` or
    `Paid in Advance`):

    > "Any payment you've already made — a down payment or the full amount
    > — won't be refunded. If you cancel with enough notice it becomes
    > **account credit** at this branch that you can use on a future visit;
    > a late cancellation forfeits it."

    (Receptionist wording: "Any payment the customer has made …".)

  - An unpaid pencil booking shows nothing new — there's no payment to
    convert, it just auto-expires.
- `CustomerBookingsPage` post-cancel banner, previously "Booking cancelled"
  / "Booking cancelled without meeting the configured notice period", now:
  - `credit_issued` → "Booking cancelled. Your payment has been converted
    into account credit at **{branch}** for a future visit."
  - `policy_violation` → "Booking cancelled. This did not meet the required
    notice period, so any payment was forfeited."
  - otherwise → "Booking cancelled."

## Verification

1. **Customer → My bookings**, a booking that's been paid (down payment or
   full; `payment_stage` shows Paid / Partially Paid) → **Cancel**.
   - The dialog now has the "won't be refunded … account credit … a late
     cancellation forfeits it" paragraph under the first line.
2. Confirm with enough notice → success banner: "…converted into account
   credit at Makati for a future visit." Confirm too close to the
   appointment under Strict enforcement → "…did not meet the required
   notice period, so any payment was forfeited."
3. An **unpaid** Pending booking → Cancel → the dialog shows only the
   "This can't be undone" line (no payment paragraph).
4. **Receptionist Bookings Queue** → Cancel a paid booking → same
   paragraph with "the customer" wording.

## Test suites

- `client`: `npx vitest run` — **732/732 passing (142 files)**. New
  `CustomerBookingsPage.spec.ts` case: paid booking → dialog shows the
  "won't be refunded" + "account credit" copy → `credit_issued` result →
  banner names the branch. AC-4's banner assertion updated to the new
  forfeiture wording. `credit_issued: false` added to the existing cancel
  mocks. `npx tsc --noEmit`, `npx eslint`, `npx prettier --check`,
  `npx vite build` all clean.
- `server`: no changes.

## Open items

- **Copy vs. ledger for a paid-in-full booking.** The advisor's policy
  ("full or down payment → credit") and this copy both imply the whole
  paid amount converts. `cancellation.service.ts` only converts the
  snapshotted `downpayment_amount` — a booking paid in full above its
  down payment would credit back just the down-payment portion. Wiring
  the ledger to convert the actual amount paid is a separate change
  (server + `creditIssuance.service.ts`), out of scope for on-screen copy.
- Credit **redemption at checkout is still a stub** (`credit-balance-ledger`
  skill) — the copy says the credit is usable "on a future visit", which
  is the intended design but not yet spendable end-to-end.
