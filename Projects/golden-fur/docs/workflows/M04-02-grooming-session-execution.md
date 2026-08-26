---
id: M04-02-grooming-session-execution
module: M04
title: Grooming Session Execution & Billing Handoff
actors: [Groomer, Admin, Supervisor, Superadmin]
trigger: Staff clicks Start or Complete on a queued grooming session (PATCH /grooming/sessions/:id/status)
outcome_success: Underlying booking.status advances (Pending -> In Progress, or In Progress -> Completed); a Completed booking becomes billing-ready for M08 checkout
outcome_failure:
  [
    unauthorized,
    forbidden,
    invalid_payload,
    session_not_found,
    invalid_transition,
  ]
related_modules: [M03, M08]
source:
  - server/src/features/grooming/services/grooming.service.ts
  - server/src/features/grooming/grooming.controller.ts
  - server/src/features/grooming/grooming.routes.ts
  - server/src/features/grooming/modules/validators/grooming.validator.ts
  - server/src/features/grooming/services/grooming.service.spec.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/billing/services/lineItemSources.service.ts
  - supabase/migrations/20260719038_m04_create_grooming_schema.sql
  - supabase/migrations/20260728059_m04_drop_grooming_session_status.sql
steps:
  - id: start
    type: start
    label: Staff clicks Start or Complete on a queued session (PATCH /grooming/sessions/:id/status)
    next: check_role_branch
  - id: check_role_branch
    type: decision
    label: Role in Groomer/Admin/Supervisor/Superadmin, and branch resolved?
    branches:
      - condition: "no"
        next: end_blocked_auth
      - condition: "yes"
        next: check_payload
  - id: end_blocked_auth
    type: end
    result: blocked
    label: Forbidden or unauthorized (401/403)
  - id: check_payload
    type: decision
    label: Payload status is 'In Progress' or 'Completed'?
    branches:
      - condition: "no"
        next: end_blocked_payload
      - condition: "yes"
        next: load_session
  - id: end_blocked_payload
    type: end
    result: blocked
    label: Invalid payload (400)
  - id: load_session
    type: action
    label: Load grooming_sessions row by id
    next: check_session_exists
  - id: check_session_exists
    type: decision
    label: Session exists?
    branches:
      - condition: "no"
        next: end_blocked_not_found
      - condition: "yes"
        next: check_ownership
  - id: end_blocked_not_found
    type: end
    result: blocked
    label: Session not found (404)
  - id: check_ownership
    type: decision
    label: Requester is the assigned_groomer_id, or Admin/Supervisor/Superadmin?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_target_status
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_target_status
    type: decision
    label: Target status?
    branches:
      - condition: In Progress
        next: check_pending
      - condition: Completed
        next: check_in_progress
  - id: check_pending
    type: decision
    label: booking.status = Pending?
    branches:
      - condition: "no"
        next: end_blocked_invalid_transition
      - condition: "yes"
        next: start_booking
  - id: check_in_progress
    type: decision
    label: booking.status = In Progress?
    branches:
      - condition: "no"
        next: end_blocked_invalid_transition
      - condition: "yes"
        next: check_online_prepaid
  - id: end_blocked_invalid_transition
    type: end
    result: blocked
    label: Invalid transition (409), propagated from startBooking/completeBooking
  - id: start_booking
    type: action
    label: "startBooking: status -> In Progress, started_at = now"
    next: end_success_started
  - id: end_success_started
    type: end
    result: success
    label: Session shows In Progress (booking.status = In Progress)
  - id: check_online_prepaid
    type: decision
    label: "Already paid online? (payment_method is GCash/Maya, payment_confirmed = true, payment_stage <> Paid in Advance)"
    branches:
      - condition: "yes"
        next: advance_payment_stage
      - condition: "no"
        next: leave_payment_stage
  - id: advance_payment_stage
    type: action
    label: "Auto-advance payment_stage -> Paid, paid_at = now"
    next: complete_booking
  - id: leave_payment_stage
    type: action
    label: Leave payment_stage as-is (pay-at-counter, or already Paid in Advance)
    next: complete_booking
  - id: complete_booking
    type: action
    label: "completeBooking: status -> Completed, completed_at = now"
    next: end_success_completed
  - id: end_success_completed
    type: end
    result: success
    label: Booking Completed - billing-ready for checkout (M08)
---

# M04 · Grooming Session Execution & Billing Handoff

Machine-readable companion to
[[M04-02-grooming-session-execution|the human-readable version]] in
`Library/golden-fur/workflows/`.
