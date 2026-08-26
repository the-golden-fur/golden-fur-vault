---
id: M06-02-daycare-checkout-billing
module: M06
title: Daycare Checkout & Billing
actors: [Receptionist, Admin, Supervisor, Superadmin, Groomer, Pet Assistant]
trigger: Staff selects an Active Daycare session to check out
outcome_success: stays row set to Completed with actual_check_out_at + computed_charge stored atomically; cage released; linked booking best-effort synced to Completed
outcome_failure:
  [session_not_found, already_completed, checklist_incomplete, update_failed]
related_modules: [M03, M05, M08]
source:
  - server/src/features/daycare/daycare.controller.ts
  - server/src/features/daycare/services/daycareBilling.service.ts
  - server/src/features/daycare/services/daycareBilling.service.spec.ts
  - server/src/features/hotel/services/careLogCompletion.service.ts
  - server/src/features/booking/services/availability.service.ts
  - server/src/features/booking/services/booking.service.ts
  - supabase/migrations/20260803088_m08_daycare_overnight_pricing.sql
  - supabase/migrations/20260807107_m06_m09_daycare_fee_config.sql
  - supabase/migrations/20260807104_m05_m06_unify_stays.sql
steps:
  - id: start
    type: start
    label: Staff selects an Active Daycare session to check out
    next: fetch_session
  - id: fetch_session
    type: action
    label: Fetch stays row (stay_type Daycare)
    next: check_found
  - id: check_found
    type: decision
    label: Session found?
    branches:
      - condition: "no"
        next: end_blocked_not_found
      - condition: "yes"
        next: check_already_completed
  - id: end_blocked_not_found
    type: end
    result: blocked
    label: Session not found (404)
  - id: check_already_completed
    type: decision
    label: status already Completed?
    branches:
      - condition: "yes"
        next: end_blocked_already_completed
      - condition: "no"
        next: apply_checklist_relabel
  - id: end_blocked_already_completed
    type: end
    result: blocked
    label: Already checked out (409)
  - id: apply_checklist_relabel
    type: action
    label: Apply lazy Missed/Backlog relabeling to this session's Care Log entries
    next: check_outstanding_tasks
  - id: check_outstanding_tasks
    type: decision
    label: Any Pending or In Progress care log tasks?
    branches:
      - condition: "yes"
        next: end_blocked_checklist
      - condition: "no"
        next: resolve_fee_schedule
  - id: end_blocked_checklist
    type: end
    result: blocked
    label: Boarding Checklist has incomplete task(s) (409)
  - id: resolve_fee_schedule
    type: action
    label: Resolve fee schedule from session's own service_id (first_hour_fee, succeeding_hour_fee, daycare_overnight_fee; defaults 100/50/850 if unset)
    next: compute_hourly_charge
  - id: compute_hourly_charge
    type: action
    label: "Compute hourly charge: <=1h -> first_hour_fee flat, else + succeeding_hour_fee * ceil(extra hours)"
    next: count_overnight_nights
  - id: count_overnight_nights
    type: action
    label: Count branch closing-time boundaries crossed between check-in and now
    next: check_nights
  - id: check_nights
    type: decision
    label: Nights > 0?
    branches:
      - condition: "no"
        next: total_hourly_only
      - condition: "yes"
        next: total_with_overnight
  - id: total_hourly_only
    type: action
    label: Total = hourly charge
    next: update_stay
  - id: total_with_overnight
    type: action
    label: Total = hourly charge + nights * daycare_overnight_fee
    next: update_stay
  - id: update_stay
    type: action
    label: "Update stays: status Completed, actual_check_out_at = now, computed_charge = total (single atomic write)"
    next: check_update
  - id: check_update
    type: decision
    label: Update succeeded?
    branches:
      - condition: "no"
        next: end_blocked_update_failed
      - condition: "yes"
        next: release_cage
  - id: end_blocked_update_failed
    type: end
    result: blocked
    label: Failed to check out (400)
  - id: release_cage
    type: action
    label: "Release cage: Occupied -> Available"
    next: check_booking_linked
  - id: check_booking_linked
    type: decision
    label: booking_id present?
    branches:
      - condition: "no"
        next: record_activity
      - condition: "yes"
        next: sync_booking
  - id: sync_booking
    type: action
    label: "Sync booking: In Progress -> Completed"
    next: check_sync_result
  - id: check_sync_result
    type: decision
    label: Booking sync result?
    branches:
      - condition: succeeded
        next: record_activity
      - condition: "failed - 409 (booking was independently cancelled)"
        next: record_activity
      - condition: "failed - other error"
        next: end_error_sync_propagated
  - id: end_error_sync_propagated
    type: end
    result: error
    label: Non-409 booking sync error propagates (stays row is already durably Completed)
  - id: record_activity
    type: action
    label: Record check_out activity (with computed charge)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Session Completed, charge stored, cage freed
---

# M06 · Daycare Checkout & Billing

Machine-readable companion to
[[M06-02-daycare-checkout-billing|the human-readable version]] in
`Library/golden-fur/workflows/`.
