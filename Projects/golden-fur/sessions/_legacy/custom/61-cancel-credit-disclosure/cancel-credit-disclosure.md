# Cancel dialog now discloses that a paid amount becomes account credit

Branch: `feat/cancel-credit-disclosure` (golden-fur); PR #132 → `dev`,
rebased to a single commit (`5573608`, "feat(booking): disclose the
non-refundable-to-credit policy on cancel"). Stacked on
`feat/cancel-confirmation-dialog` (PR #130, already on `dev`).

## The request, verbatim

The original ask had two parts. Part 1 — the explicit "Are you sure you
want to cancel this booking?" confirm modal — shipped separately as PR #130
and is documented in
`Projects/golden-fur/testing/custom/60-cancel-confirmation-dialog/`. This
record covers **only** part 2: surfacing the cancellation payment policy in
that dialog.

> The cancellation dialog and the customer's post-cancel banner now disclose
> that a payment already made (down payment or full) isn't refunded but, with
> enough notice, becomes account credit at that branch for a future visit — a
> late cancellation forfeits it.

Advisor basis (Aug-27 demo, `Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`),
as characterised in the PR: _"your payment, full or down, will not be
refunded … it will be converted into credits."_ Nothing in the cancel UI
mentioned money before this — the credit-conversion policy lived only in the
M09 server logic and the booking-cancelled notification.

### Scope note

Client-only. No server, schema, migration, or API change — the server's
cancel endpoint already returns `credit_issued` in `CancellationResult`
(see [[M09-01-cancellation-notice-credit-decision]] end node); the client
type simply was not capturing it. No Postman collection or `.sql` reference
copy accompanies this record for that reason.

## Root cause / Context

`cancellation.service.ts` decides, per the branch's effective
`policy_configurations`, whether a cancelled booking's `downpayment_amount`
snapshot converts to a `credit_balances` increment (notice met, a positive
downpayment) or is forfeited (notice missed). That outcome came back to the
client as `notice_period_met` / `policy_violation` and, unread until now,
`credit_issued`.

The UI gave the customer none of this before they confirmed. The customer
cancel dialog only warned "may forfeit your downpayment depending on notice
given" when a `downpayment_amount` was set; the receptionist dialog said
nothing about money at all. The post-cancel banner on `CustomerBookingsPage`
only distinguished "cancelled without meeting the configured notice period"
from a plain "Booking cancelled." — it never told the customer their money
had become usable credit.

## What changed

### Client

- **`client/src/features/booking/booking.types.ts`** — `CancellationResult`
  gains `credit_issued: boolean` (documented as #91/#93: true only when a
  qualifying downpayment was actually converted for this cancellation).
  Server already sends it; this makes it typed and readable.

- **`client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`**
  - Cancel `ConfirmDialog` body: the first paragraph is trimmed to "Are you
    sure you want to cancel this booking? This can't be undone." A second
    paragraph is rendered **only when `cancelTarget.payment_stage` is `Paid`
    or `Paid in Advance`** (an unpaid pencil booking shows nothing new). It
    states the payment "won't be refunded", becomes **account credit** at
    this branch with enough notice, and that a late cancellation forfeits it.
    The old downpayment-conditional forfeiture clause on the first paragraph
    is removed.
  - Post-cancel banner (`setActionMessage`) now has three branches: if
    `result.data.credit_issued`, "Booking cancelled. Your payment has been
    converted into account credit at `{branchName}` for a future visit."
    (`branchName` resolved via the existing `branchNameById` map, falling
    back to "this branch"); else if `policy_violation`, "Booking cancelled.
    This did not meet the required notice period, so any payment was
    forfeited."; else plain "Booking cancelled."

- **`client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`**
  - Same disclosure paragraph in the cancel `ConfirmDialog`, gated on the
    same `payment_stage` check, with staff-facing wording ("Any payment the
    customer has made …", "meets the required notice"). First paragraph's
    "This cannot be undone." tightened to "This can't be undone."
  - This page has **no** post-cancel status banner (`confirmCancel` just
    calls `replaceBooking` and closes the dialog), so nothing changed there.

- **Specs** — `credit_issued` added to the existing `cancelBooking` mock
  results in both `CustomerBookingsPage.spec.ts` (two mocks) and
  `ReceptionistBookingsQueuePage.spec.ts` (one mock). The customer spec's
  existing notice-violation assertion was updated to the new banner wording
  (`/did not meet the required notice period, so any payment was forfeited/i`).
  One new customer test, "discloses the non-refundable-becomes-credit policy
  and reports the credit conversion": a `Paid in Advance` booking with
  `downpayment_amount: 200` → open dialog → assert the dialog shows
  `/won't be refunded/i` and `/account credit/i` → confirm with
  `credit_issued: true` → assert the status banner reads
  `/converted into account credit at Makati for a future visit/i`.

## Verification

1. **Customer portal → My bookings.** Pick a booking whose `payment_stage`
   is `Paid in Advance` or `Paid` → **Cancel**.
   - The modal's body now has a second paragraph: payment "won't be
     refunded", becomes **account credit** at this branch with enough
     notice, late cancellation forfeits it.
   - Confirm. If the branch policy's notice period is met (and the booking
     carried a downpayment), the status banner names the branch: "…
     converted into account credit at `<branch>` for a future visit."
     Cross-check against the customer's credit balance
     ([[M10-credit-balance-management]] views) — it should have increased by
     the downpayment amount.
2. **Customer portal**, a booking cancelled **without** meeting the notice
   period → banner reads "… did not meet the required notice period, so any
   payment was forfeited." Credit balance unchanged.
3. **Customer portal**, an **Unpaid** booking → **Cancel**: the dialog shows
   only the "Are you sure … can't be undone." line, no payment paragraph;
   banner is plain "Booking cancelled."
4. **Receptionist → Bookings Queue.** Cancel a paid booking on the
   customer's behalf → the dialog shows the staff-worded payment paragraph
   ("Any payment the customer has made …"). Unpaid booking → no payment
   paragraph. (No post-cancel banner on this page by design.)

## Test suites

- `client`:
  - Targeted — `npx vitest run` on `CustomerBookingsPage.spec.ts` +
    `ReceptionistBookingsQueuePage.spec.ts` → **2 files, 32/32 passing**.
  - Full suite — `npx vitest run` → **736 passed / 1 failed, 737 tests,
    142 files**. The one failure is a 5000 ms `testTimeout` exceeded under
    full-suite parallel load in `CustomerBookingFlowPage.spec.ts` (the
    "switching category tabs clears the previous tab's selection" case), a
    file this change does not touch. Re-run in isolation:
    `npx vitest run src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.spec.ts`
    → **29/29 passing**. Environmental flake, not a regression (matches the
    known client test-timeout note).
  - `npx tsc -b` → exit 0.
  - `npx eslint` on the five changed files → exit 0.
  - `npx prettier --check` on the changed files → reports all five as
    style-warned **locally only**: this repo is checked out with
    `core.autocrlf=true`, so working-tree files have CRLF while Prettier
    expects LF. An untouched sibling (`CustomerBookingFlowPage.tsx`) fails
    `--check` identically. CI runs on Linux/LF and is unaffected. Not a real
    failure.
- `server`: no changes, not run.

## Open items

- The dialog copy says "a down payment or the full amount" won't be
  refunded, but `cancellation.service.ts` currently only converts the
  snapshotted `downpayment_amount` to credit — a paid-in-full booking would
  convert only that portion. Closing the gap (convert the full paid amount)
  is a separate server change, flagged in the PR.
- Credit redemption at checkout is still a stub
  ([[M10-credit-balance-management]] is issuance-only), so the "use on a
  future visit" promise is not yet fully wired.
- **Workflow docs:** [[M09-01-cancellation-notice-credit-decision]] and
  [[M10-01-cancellation-to-credit-conversion]] both describe the server
  decision and the notification, but neither mentions that the cancel
  **dialog** now pre-discloses the policy or that `CustomerBookingsPage`'s
  post-cancel banner reports the credit/forfeit outcome. Both are
  server-flow docs, so a refresh is optional — a one-line "the client also
  surfaces this at cancel time and in the post-cancel banner" pointer in
  each would be accurate. No dedicated cancellation-flow _UI_ workflow doc
  exists to update.
