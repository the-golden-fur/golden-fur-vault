---
id: M09-02-reschedule-notice-fee-decision
module: M09
title: Reschedule Notice-Period Enforcement & Fee Calculation
actors: [Customer, Staff]
trigger: Customer or staff member reschedules a Pending booking to a new time/branch/staff (PATCH /bookings/:id/reschedule)
outcome_success: booking's scheduled_start/end (and optionally branch/staff) updated in place; reschedule_count incremented; pending_reschedule_fee_amount set or cleared; a cancellation_logs row is always written
outcome_failure:
  [
    forbidden,
    booking_not_reschedulable,
    already_past,
    veterinary_branch_ineligible,
    notice_period_violation_strict,
    no_capacity_or_staff,
  ]
related_modules: [M03, M08]
source:
  - server/src/features/booking/services/reschedule.service.ts
  - server/src/features/booking/services/rescheduleFee.service.ts
  - server/src/features/booking/services/cancellationLog.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/services/veterinaryEligibility.service.ts
  - server/src/features/booking/services/capacity.service.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/booking.routes.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - supabase/migrations/20260718037_m03_policy_configurations_stub.sql
  - supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql
  - supabase/migrations/20260804091_m09_policy_configurations_lunch_break.sql
  - supabase/migrations/20260804092_m03_get_staff_availability_lunch_break.sql
steps:
  - id: start
    type: start
    label: Customer or staff member requests a reschedule (new scheduled_start/end, optional branch_id, optional staff_preference)
    next: check_ownership
  - id: check_ownership
    type: decision
    label: Is requester the owning customer, or an authenticated staff member? (loadBookingForChange)
    branches:
      - condition: "no"
        next: end_forbidden
      - condition: "yes"
        next: check_status
  - id: end_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_status
    type: decision
    label: Is booking.status Pending? (RESCHEDULABLE_BOOKING_STATUSES — only Pending, unlike cancellation's two statuses)
    branches:
      - condition: "no"
        next: end_not_reschedulable
      - condition: "yes"
        next: check_not_past
  - id: end_not_reschedulable
    type: end
    result: blocked
    label: "A <status> booking cannot be rescheduled (409)"
  - id: check_not_past
    type: decision
    label: Has the booking's current scheduled_start already passed?
    branches:
      - condition: "yes"
        next: end_already_past
      - condition: "no"
        next: check_vet_eligibility
  - id: end_already_past
    type: end
    result: blocked
    label: Scheduled time already passed — effectively a pending no-show (409)
  - id: check_vet_eligibility
    type: decision
    label: "If target branch differs and service_category=Veterinary: is the new branch eligible? (assertVeterinaryBranchEligibility, no-op otherwise)"
    branches:
      - condition: "no"
        next: end_vet_ineligible
      - condition: "yes / not applicable"
        next: check_enforcement_enabled
  - id: end_vet_ineligible
    type: end
    result: blocked
    label: Target branch not eligible for this Veterinary booking
  - id: check_enforcement_enabled
    type: decision
    label: Is the branch's effective policy.notice_enforcement_enabled true? (resolveEffectivePolicy, evaluateNoticePeriod against CURRENT scheduled_start)
    branches:
      - condition: "no"
        next: check_capacity
      - condition: "yes"
        next: check_notice_period
  - id: check_notice_period
    type: decision
    label: "scheduled_start minus now >= notice_period_days?"
    branches:
      - condition: "yes (met)"
        next: check_capacity
      - condition: "no (not met)"
        next: check_enforcement_mode
  - id: check_enforcement_mode
    type: decision
    label: notice_enforcement_mode for this branch?
    branches:
      - condition: Strict
        next: end_strict_blocked
      - condition: Soft
        next: check_capacity
  - id: end_strict_blocked
    type: end
    result: blocked
    label: "Reschedule requires at least N day(s) notice (422) — unlike cancellation, Strict mode blocks a reschedule outright"
  - id: check_capacity
    type: action
    label: "Re-verify capacity/staff availability for the new slot, excluding this booking (Grooming/Veterinary via listAvailableStaff -> get_staff_availability RPC, which also enforces the branch lunch-break window as a hard filter; Hotel/Daycare via checkCapacity) — see M03 for full detail"
    next: check_slot_available
  - id: check_slot_available
    type: decision
    label: Is the new slot available (staff or capacity found)?
    branches:
      - condition: "no"
        next: end_no_capacity
      - condition: "yes"
        next: calc_fee_enabled
  - id: end_no_capacity
    type: end
    result: blocked
    label: No eligible staff / no capacity for the new slot (409)
  - id: calc_fee_enabled
    type: decision
    label: Is policy.reschedule_fee_enabled?
    branches:
      - condition: "no"
        next: update_booking
      - condition: "yes"
        next: calc_fee_allowance
  - id: calc_fee_allowance
    type: decision
    label: "reschedule_free_allowance IS NULL (unlimited), OR booking.reschedule_count < allowance?"
    branches:
      - condition: "yes (still free)"
        next: update_booking
      - condition: "no (allowance exhausted)"
        next: calc_fee_config
  - id: calc_fee_config
    type: decision
    label: Are both reschedule_fee_type and reschedule_fee_value configured?
    branches:
      - condition: "no"
        next: update_booking
      - condition: "yes"
        next: compute_fee
  - id: compute_fee
    type: action
    label: "Compute fee: Flat = reschedule_fee_value; Percentage = booking.total_price * reschedule_fee_value / 100 (rounded to 2 dp)"
    next: update_booking
  - id: update_booking
    type: action
    label: Update scheduled_start/end, branch_id, assigned_staff_id, reschedule_count+1, pending_reschedule_fee_amount (fee amount or null, overwriting any earlier pending amount)
    next: write_log
  - id: write_log
    type: action
    label: Write cancellation_logs row (event_type=reschedule, notice_period_met, enforcement_mode_applied, policy_violation, reschedule_fee_charged=fee amount) — best-effort
    next: send_notification
  - id: send_notification
    type: action
    label: Send booking_rescheduled notification (in-app + email, best-effort), reporting old and new schedule
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Booking rescheduled in place; notice_period_met and policy_violation returned; any fee sits in pending_reschedule_fee_amount, not yet posted as a billable line item
---

# M09 · Reschedule Notice-Period Enforcement & Fee Calculation

Machine-readable companion to
[[M09-02-reschedule-notice-fee-decision|the human-readable version]] in
`Library/golden-fur/workflows/`.
