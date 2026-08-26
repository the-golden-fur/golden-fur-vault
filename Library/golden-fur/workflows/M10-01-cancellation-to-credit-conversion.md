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
blocked by an unmet notice period — what the notice outcome (and whether the
booking actually carried a non-refundable downpayment) decides is whether
that downpayment is converted into branch-locked credit or simply forfeited.

```mermaid
flowchart TD
    A(["START: Cancellation requested for a booking"]) --> B{"Booking status is\nPending or In Progress?"}
    B -- "No" --> C(["END: Blocked — booking in this\nstatus cannot be cancelled (409)"])
    B -- "Yes" --> D["Evaluate notice period against\nbranch's effective policy_configurations"]
    D --> E["Update booking:\nstatus = Cancelled, cancelled_at, cancellation_reason"]
    E --> F{"Booking update\nsucceeded?"}
    F -- "No" --> G(["END: Blocked — failed to cancel booking (400)"])
    F -- "Yes" --> H["Write cancellation_logs row\n(credit_issued=false, credit_amount=null by default;\nbest-effort — insert failure returns null, not a throw)"]
    H --> I{"Qualifies for credit?\n(notice period met AND\ndownpayment_amount > 0 AND\nlog write succeeded)"}
    I -- "No" --> J["No credit attempted\n(notice missed → downpayment forfeited,\nor booking had no downpayment,\nor log write failed)"]
    I -- "Yes" --> K{"credit_expiry_enabled\non the branch's policy?"}
    K -- "Yes" --> L["expires_at = now() + credit_expiry_days"]
    K -- "No" --> M["expires_at = null (never expires)"]
    L --> N["Call issue_credit() DB function\n(atomic: upsert credit_balances +\ninsert issuance credit_transactions row)"]
    M --> N
    N --> O{"issue_credit()\nreturned a transaction row?"}
    O -- "No" --> P["Credit issuance failed\n(cancellation_logs.credit_issued stays false —\nbest-effort, never re-thrown)"]
    O -- "Yes" --> Q["Patch cancellation_logs:\ncredit_issued = true, credit_amount = downpayment\n(best-effort — ledger is still source of truth if this patch fails)"]
    J --> R["Send booking-cancelled notification\n(reports credit amount if issued, else none)"]
    P --> R
    Q --> R
    R --> S(["END: Booking cancelled —\ncredit issued, forfeited, or not applicable"])
```

## Notes

- Cancellation and credit issuance are **not** one atomic unit: the booking
  status update, the `cancellation_logs` insert, and the `issue_credit()`
  call are three separate steps. Only the balance-increment + issuance-row
  pair inside `issue_credit()` itself is atomic (a single PL/pgSQL function,
  `SECURITY DEFINER`, called via RPC) — see
  `supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql`.
- A Strict-mode unmet notice period never blocks cancellation the way it
  blocks a _reschedule_ — it only withholds credit. This mirrors the
  distinction already documented for reschedule's own notice check.
- Grooming/Daycare/Veterinary bookings have no downpayment concept
  (`downpayment_amount` is `0`/`null`), so they can never qualify for credit
  regardless of notice — only a booking whose item required a downpayment
  (Hotel, and now catalog-wide per [[M13-maintenance-packages-services-promos|M13]]) can.
- `credit_expiry_enabled` / `credit_expiry_days` come from `policy_configurations`
  (default `true` / `30`, see
  `supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql`)
  and are branch-scoped, resolved by the same `resolveEffectivePolicy()` used
  for notice-period and reschedule-fee checks.
- Every step past the log write is best-effort with respect to the
  cancellation's own success: a failed `cancellation_logs` insert skips
  credit issuance entirely (no way to link the issuance back to an event);
  a failed `issue_credit()` RPC call just leaves `credit_issued = false`; a
  failed patch of the log row after a successful issuance leaves the ledger
  correct but the log's summary fields stale. None of these failures raise
  an error back to the caller — the booking is already cancelled by the time
  any of them can happen.

## Relationship to other modules

Triggered from [[M09-policy-enforcement|M09]]'s cancellation flow
(`evaluateNoticePeriod()`), which reads the same `policy_configurations`
table this workflow reads for the downpayment/credit-expiry rules. Feeds
[[M14-report-management|M14]]'s DSR once redemption is wired up (currently
issuance-only, per [[M10-credit-balance-management|M10]]'s Status section).
