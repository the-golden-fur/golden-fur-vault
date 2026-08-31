---
title: "M10 · Cancellation-to-Credit Conversion"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M10
---

# M10 · Cancellation-to-Credit Conversion

**Actors:** Customer, any staff member (whoever is cancelling), Admin/Superadmin (policy configuration)
**Code:** `server/src/features/booking/services/cancellation.service.ts`,
`server/src/features/booking/services/cancellationLog.service.ts`,
`server/src/features/credits/services/creditIssuance.service.ts`
**Part of:** [[M10-credit-balance-management|M10 · Credit Balance Management]]

A customer or staff member cancels a booking. Cancellation itself is never
blocked by an unmet notice period — what the notice outcome decides is
whether the money the customer already paid is converted into branch-locked
credit or simply forfeited. When it is converted, only a configurable
percentage of the paid amount becomes credit
(`cancellation_credit_conversion_rate`, default 100% — the advisor asked for
this to be adjustable, e.g. down to 50%, so a late-ish cancellation can keep
part of the payment as a charge).

```mermaid
flowchart TD
    A(["START: Cancellation requested for a booking"]) --> B{"Booking status is\nPending or In Progress?"}
    B -- "No" --> C(["END: Blocked — booking in this\nstatus cannot be cancelled (409)"])
    B -- "Yes" --> D["Evaluate notice period against\nbranch's effective policy_configurations"]
    D --> E["Update booking:\nstatus = Cancelled, cancelled_at, cancellation_reason"]
    E --> F{"Booking update\nsucceeded?"}
    F -- "No" --> G(["END: Blocked — failed to cancel booking (400)"])
    F -- "Yes" --> H["Write cancellation_logs row\n(credit_issued=false, credit_amount=null by default;\nbest-effort — insert failure returns null, not a throw)"]
    H --> I["Compute amountPaid from payment_stage:\nPaid → net total · Paid in Advance → downpayment · Unpaid → 0"]
    I --> I2["creditAmount = round2(amountPaid ×\ncancellation_credit_conversion_rate / 100)"]
    I2 --> J{"Qualifies for credit?\n(notice period met AND creditAmount > 0)"}
    J -- "No" --> K["No credit attempted\n(notice missed → payment forfeited,\nor nothing was paid,\nor rate is 0%)"]
    J -- "Yes" --> L{"credit_expiry_enabled\non the branch's policy?"}
    L -- "Yes" --> M["expires_at = now() + credit_expiry_days"]
    L -- "No" --> N["expires_at = null (never expires)"]
    M --> O["Call issue_credit() DB function\n(atomic: upsert credit_balances +\ninsert issuance credit_transactions row).\ncancellation_log_id may be null if the log write failed."]
    N --> O
    O --> P{"issue_credit()\nreturned a transaction row?"}
    P -- "No" --> Q["Credit issuance failed\n(cancellation_logs.credit_issued stays false —\nbest-effort, never re-thrown)"]
    P -- "Yes" --> R["Patch cancellation_logs (if a log row exists):\ncredit_issued = true, credit_amount = creditAmount\n(best-effort — ledger is still source of truth if this patch fails)"]
    K --> S["Send booking-cancelled notification\n(reports credit amount if issued, else none)"]
    Q --> S
    R --> S
    S --> T(["END: Booking cancelled —\ncredit issued, forfeited, or not applicable"])
```

## Notes

- Cancellation and credit issuance are **not** one atomic unit: the booking
  status update, the `cancellation_logs` insert, and the `issue_credit()`
  call are three separate steps. Only the balance-increment + issuance-row
  pair inside `issue_credit()` itself is atomic (a single PL/pgSQL function,
  `SECURITY DEFINER`, called via RPC) — see
  `supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql`.
- **What gets converted is the amount actually paid, not the configured
  downpayment.** `amountPaid` is derived from `bookings.payment_stage`:
  `Paid` → the discounted net total (`total_price − discount_amount −
promo_amount`); `Paid in Advance` → `downpayment_amount`; `Unpaid` (or
  unset) → `0`. So a booking paid in full returns its whole net total, a
  booking that only paid the downpayment returns the downpayment, and an
  unpaid booking (e.g. a still-Pending down-payment reservation cancelled
  before its hold expires) returns nothing — no credit for money the
  business never received.
- **The conversion rate** is `policy_configurations.cancellation_credit_conversion_rate`
  — a percentage `0`–`100`, `NOT NULL DEFAULT 100`, branch-scoped and
  resolved by the same `resolveEffectivePolicy()` used for the notice
  period, reschedule fee, and credit expiry. Editable on Settings → Config →
  Policies (Admin/Superadmin). `creditAmount = round2(amountPaid × rate /
100)`; a rate of `0` means a qualifying cancellation converts nothing.
  Migration `supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql`.
- A Strict-mode unmet notice period never blocks cancellation the way it
  blocks a _reschedule_ — it only withholds credit. This mirrors the
  distinction already documented for reschedule's own notice check.
- Any booking that was actually paid can now qualify — including a
  fully-paid Grooming/Daycare/Veterinary booking, which previously could
  never get credit because the old logic keyed off `downpayment_amount`
  alone. The notice period still has to be met.
- **A failed `cancellation_logs` insert no longer skips credit issuance**
  (previously the guard was `qualifies && log`; issue #117).
  `credit_transactions.cancellation_log_id` is nullable, so the credit is
  issued with a null link and only the log-row summary is lost. A failed
  `issue_credit()` RPC still just leaves `credit_issued = false`; a failed
  patch of the log row after a successful issuance leaves the ledger correct
  but the log's summary fields stale. None of these raise an error back to
  the caller — the booking is already cancelled by the time any of them can
  happen.
- `credit_expiry_enabled` / `credit_expiry_days` come from `policy_configurations`
  (default `true` / `30`, see
  `supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql`).

## Relationship to other modules

Triggered from [[M09-policy-enforcement|M09]]'s cancellation flow
(`evaluateNoticePeriod()`), which reads the same `policy_configurations`
table this workflow reads for the conversion-rate/credit-expiry rules. The
paid amount it converts comes from `bookings.payment_stage`, driven by
[[M08-billing-payments|M08]]'s payment flow. Feeds
[[M14-report-management|M14]]'s DSR once redemption is wired up (currently
issuance-only, per [[M10-credit-balance-management|M10]]'s Status section).
The navbar credit indicator (customer portal) reads the resulting
`credit_balances` and refreshes right after this flow issues credit.
