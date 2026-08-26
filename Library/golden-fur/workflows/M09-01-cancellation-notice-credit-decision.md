---
title: "M09 · Cancellation Notice-Period Check & Credit Conversion"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M09
---

# M09 · Cancellation Notice-Period Check & Credit Conversion

**Actors:** Customer, Staff (any authenticated staff role, or the owning customer)
**Code:** `server/src/features/booking/services/cancellation.service.ts`,
`server/src/features/booking/services/cancellationLog.service.ts`,
`server/src/features/booking/services/reschedule.service.ts` (shared `evaluateNoticePeriod`),
`server/src/features/credits/services/creditIssuance.service.ts`
**Part of:** [[M09-policy-enforcement|M09 · Policy Enforcement]]

When a customer or staff member cancels a booking, the system checks how far
ahead of the scheduled appointment the cancellation happens, always logs the
event, and converts the booking's downpayment into a credit only if the
configured notice period was met and a downpayment actually exists to
convert. A cancellation is never blocked by the notice check — only the
financial consequence changes.

```mermaid
flowchart TD
    A(["START: Customer or staff requests cancellation"]) --> B["Submit cancellation_reason (optional)"]
    B --> C{"Is requester the owning\ncustomer or authenticated staff?"}
    C -- "No" --> D(["END: Blocked — forbidden (403)"])
    C -- "Yes" --> E{"Is booking.status\nPending or In Progress?"}
    E -- "No" --> F(["END: Blocked — booking\ncannot be cancelled (409)"])
    E -- "Yes" --> G{"Is notice-period\nenforcement enabled\nfor this branch?"}
    G -- "No" --> I["Set status = Cancelled\n(proceeds regardless of notice outcome)"]
    G -- "Yes" --> H{"scheduled_start − now\n>= notice_period_days?"}
    H -- "Met" --> I
    H -- "Not met" --> I
    I --> J["Write cancellation_logs row\n(notice_period_met, enforcement_mode_applied,\npolicy_violation = enforced AND NOT met)\n— best-effort"]
    J --> K{"Did the log\nrow get written?"}
    K -- "No" --> P
    K -- "Yes" --> L{"notice_period_met = true\nAND downpayment_amount > 0?"}
    L -- "No" --> P["Send booking_cancelled\nnotification (best-effort)"]
    L -- "Yes" --> M["Call issue_credit() RPC\n(atomic balance increment\n+ credit_transactions row)"]
    M --> N{"Credit transaction\nissued successfully?"}
    N -- "No" --> P
    N -- "Yes" --> O["Patch log row:\ncredit_issued = true,\ncredit_amount = downpayment"] --> P
    P --> Q(["END: Booking Cancelled —\nnotice_period_met / policy_violation /\ncredit_issued returned"])
```

## Notes

- **A cancellation is never blocked**, regardless of `Strict` vs `Soft`
  enforcement mode — the mode only decides `policy_violation` on the logged
  row and the credit outcome, unlike a Strict reschedule, which _is_ blocked
  outright (see [[M09-02-reschedule-notice-fee-decision|M09-02]]).
- **Best-effort logging can silently suppress a qualifying credit.** If
  `writeCancellationLog` fails (its own DB write, swallowed rather than
  thrown), `cancelBooking` skips the credit check entirely — `issueCredit`
  is only ever called with a real `cancellation_logs.id` to attach the
  transaction to. The booking still cancels successfully; only the credit
  issuance is silently dropped for that one event.
- **The downpayment check is not Hotel-specific**, despite how the module
  note frames it — see the discrepancy note below.
- `notice_enforcement_enabled = false` short-circuits the whole check to
  "met" (`evaluateNoticePeriod` returns `{ enforced: false, met: true }`),
  so a disabled policy always qualifies for credit if a downpayment exists.
- `issueCredit()` wraps a single atomic Postgres function (`issue_credit`,
  migration `...097`) rather than a separate balance-read + insert, so the
  `credit_balances` increment and the `credit_transactions` issuance row
  can't diverge.
- The `sendBookingCancelledNotification` email/in-app dispatch is
  best-effort and runs last, after the credit decision is fully resolved,
  so its message can state the credited amount (or omit it) correctly.

## Relationship to other modules

Credit issuance posts to [[M10-credit-balance-management|M10]]'s
`credit_balances`/`credit_transactions`. The notice-period policy itself is
configured via `GET`/`PATCH /bookings/policy`, read here through
`resolveEffectivePolicy()` (shared with
[[M09-02-reschedule-notice-fee-decision|M09-02]] and
[[M03-appointment-booking|M03]]). Notification dispatch goes through
[[M11-notification|M11]].
