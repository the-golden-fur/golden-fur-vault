---
title: "M05 · Hotel Checkout"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M05
---

# M05 · Hotel Checkout

**Actors:** Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin
(`HOTEL_ADVANCE_ROLES`)
**Code:** `server/src/features/hotel/services/checkout.service.ts`,
`server/src/features/hotel/services/careLogCompletion.service.ts`
**Part of:** [[M05-pet-hotel-boarding-management|M05 · Pet Hotel (Boarding) Management]]

Staff check a pet out of a Hotel stay once its Boarding Checklist has no
actionable tasks left. The system calculates any late-checkout extension
fee, reconciles the stay's total cost against the downpayment already
collected, advances the booking to Completed, and releases the cage.

```mermaid
flowchart TD
    A(["START: Staff opens Checkout\nfor a Hotel stay"]) --> B{"Stay found\n(stay_type = Hotel)?"}
    B -- "No" --> B1(["END: Blocked — hotel stay\nnot found (404)"])
    B -- "Yes" --> C{"Cage's branch =\nrequester's branch?"}
    C -- "No" --> C1(["END: Blocked — stay does not\nbelong to this branch (403)"])
    C -- "Yes" --> D{"Joined booking's status\n= In Progress?"}
    D -- "No" --> D1(["END: Blocked — already\nchecked out (409)"])
    D -- "Yes" --> E["Re-apply lazy Missed transition,\nthen check Boarding Checklist"]
    E --> F{"Any Pending or In Progress\ncare_log_entries remain?\n(Missed and Backlog excluded)"}
    F -- "Yes" --> F1(["END: Blocked — checklist\nhas incomplete tasks (409)"])
    F -- "No" --> G["Compute extension days:\nwhole calendar days past\nscheduled_check_out_date,\npartial day rounds up"]
    G --> H{"extension days > 0?"}
    H -- "Yes" --> H1["extension_fee = days x flat\nper-day rate (placeholder,\nno M09 rate config yet)"]
    H -- "No" --> H2["extension_fee = NULL\n(never zero — distinguishes\n'no fee' from 'a ₱0 fee')"]
    H1 --> I["remainingBalance = booking.total_price\n- downpayment_amount + (extension_fee or 0)"]
    H2 --> I
    I --> J["Advance booking:\nIn Progress -> Completed\n(also -> Paid if already\nonline-prepaid)"]
    J --> K{"Conditional update:\nstays.actual_check_out_at\nstill NULL?\n(race guard)"}
    K -- "No (lost the race)" --> K1(["END: Blocked — already\nchecked out (409)"])
    K -- "Yes" --> L["Set stays.status = Completed,\nactual_check_out_at = now,\nextension_fee"]
    L --> M["Release cage back to Available"]
    M --> N["Record check_out activity\n(best-effort)"]
    N --> O(["END: Stay Completed, cage Available,\nremainingBalance passed to M08 billing"])
```

## Notes

- The Boarding Checklist gate excludes both terminal-ish statuses deliberately: Missed tasks can't block a stay forever over something nobody can still act on, and Backlog tasks (scheduled for a day after today) were never going to happen before this checkout anyway. Only Pending/In Progress is "outstanding." See [[M05-02-boarding-checklist-task-lifecycle|M05 · Boarding Checklist Task Lifecycle]].
- The extension fee is a flat ₱500-per-day placeholder
  (`EXTENSION_FEE_PER_DAY` in `checkout.service.ts`) — the code comments
  flag this explicitly as standing in for a real
  [[M09-policy-enforcement|M09]] rate configuration that doesn't exist yet.
- `completeBooking()` is called _before_ the conditional `stays` update on
  purpose: an illegal booking-status transition (e.g. a booking that was
  never actually started) fails fast without mutating `stays` at all.
  `completeBooking` itself isn't atomic against a second concurrent
  checkout call for the same stay — the real single-writer guarantee is the
  conditional `UPDATE stays ... WHERE actual_check_out_at IS NULL` that
  follows it; only the request that wins that race goes on to release the
  cage and return a result.
- Reconciliation is billing-ready only — no `transactions` row is created
  here; the computed `remainingBalance` is handed off to
  [[M08-sales-billing|M08]].

## Relationship to other modules

Advances the underlying booking via [[M03-appointment-booking|M03]]'s
booking-status machinery, hands the remaining balance to
[[M08-sales-billing|M08]], and its extension-fee rate is intended to move to
[[M09-policy-enforcement|M09]] configuration.
