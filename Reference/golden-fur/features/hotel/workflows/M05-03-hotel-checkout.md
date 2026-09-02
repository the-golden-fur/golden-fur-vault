---
id: M05-03-hotel-checkout
module: M05
title: Hotel Checkout
actors: [Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin]
trigger: Staff opens Checkout for an In Progress Hotel stay
outcome_success: booking Completed, stays row Completed with actual_check_out_at set, cage released to Available, remainingBalance computed for M08 billing
outcome_failure:
  [
    stay_not_found,
    wrong_branch,
    already_checked_out,
    checklist_incomplete,
    checkout_race_lost,
  ]
related_modules: [M03, M08, M09]
source:
  - server/src/features/hotel/services/checkout.service.ts
  - server/src/features/hotel/services/careLogCompletion.service.ts
  - server/src/features/hotel/services/activityLog.service.ts
  - server/src/features/hotel/hotel.controller.ts
  - server/src/features/hotel/hotel.routes.ts
  - server/src/features/hotel/hotel.types.ts
  - server/src/features/booking/services/booking.service.ts
steps:
  - id: start
    type: start
    label: Staff opens Checkout for a Hotel stay
    next: check_stay_found
  - id: check_stay_found
    type: decision
    label: Stay found (stay_type = Hotel)?
    branches:
      - condition: "no"
        next: end_blocked_not_found
      - condition: "yes"
        next: check_branch
  - id: end_blocked_not_found
    type: end
    result: blocked
    label: Hotel stay not found (404)
  - id: check_branch
    type: decision
    label: Cage's branch = requester's branch?
    branches:
      - condition: "no"
        next: end_blocked_branch
      - condition: "yes"
        next: check_in_progress
  - id: end_blocked_branch
    type: end
    result: blocked
    label: Stay does not belong to this branch (403)
  - id: check_in_progress
    type: decision
    label: Joined booking's status = In Progress?
    branches:
      - condition: "no"
        next: end_blocked_already_checked_out
      - condition: "yes"
        next: reapply_missed
  - id: end_blocked_already_checked_out
    type: end
    result: blocked
    label: Already checked out (409)
  - id: reapply_missed
    type: action
    label: Re-apply lazy Missed transition, then check Boarding Checklist
    next: check_outstanding
  - id: check_outstanding
    type: decision
    label: Any Pending or In Progress care_log_entries remain? (Missed and Backlog excluded)
    branches:
      - condition: "yes"
        next: end_blocked_checklist_incomplete
      - condition: "no"
        next: compute_extension_days
  - id: end_blocked_checklist_incomplete
    type: end
    result: blocked
    label: Checklist has incomplete tasks (409)
  - id: compute_extension_days
    type: action
    label: Compute extension days - whole calendar days past scheduled_check_out_date, partial day rounds up
    next: check_extension_positive
  - id: check_extension_positive
    type: decision
    label: extension days > 0?
    branches:
      - condition: "yes"
        next: compute_fee
      - condition: "no"
        next: fee_null
  - id: compute_fee
    type: action
    label: extension_fee = days x flat per-day rate (placeholder, no M09 rate config yet)
    next: compute_balance
  - id: fee_null
    type: action
    label: "extension_fee = NULL (never zero - distinguishes 'no fee' from 'a ₱0 fee')"
    next: compute_balance
  - id: compute_balance
    type: action
    label: remainingBalance = booking.total_price - downpayment_amount + (extension_fee or 0)
    next: advance_booking
  - id: advance_booking
    type: action
    label: Advance booking - In Progress -> Completed (also -> Paid if already online-prepaid)
    next: race_guard_update
  - id: race_guard_update
    type: decision
    label: "Conditional update: stays.actual_check_out_at still NULL? (race guard)"
    branches:
      - condition: "no (lost the race)"
        next: end_blocked_race_lost
      - condition: "yes"
        next: set_stay_completed
  - id: end_blocked_race_lost
    type: end
    result: blocked
    label: Already checked out (409)
  - id: set_stay_completed
    type: action
    label: Set stays.status = Completed, actual_check_out_at = now, extension_fee
    next: release_cage
  - id: release_cage
    type: action
    label: Release cage back to Available
    next: record_activity
  - id: record_activity
    type: action
    label: Record check_out activity (best-effort)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Stay Completed, cage Available, remainingBalance passed to M08 billing
---

# M05 · Hotel Checkout

Machine-readable companion to
[[M05-03-hotel-checkout|the human-readable version]] in
`Library/golden-fur/features/hotel/workflows/`.
