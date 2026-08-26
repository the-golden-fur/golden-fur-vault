---
id: M01-02-unavailability-block-request-review
module: M01
title: Unavailability Block Request & Review
actors: [Staff (self), Admin, Supervisor, Superadmin]
trigger: A staff member requests time off for themselves, or a manager files one on another staff member's behalf
outcome_success: staff_unavailability_blocks row created with status resolved by DB trigger (approved or pending)
outcome_failure:
  [
    forbidden_role,
    forbidden_branch,
    forbidden_rest_day_self_service,
    validation_error,
    overlapping_block,
    cannot_review_own_request,
  ]
related_modules: [M03, M09]
source:
  - server/src/features/staff/services/unavailabilityBlock.service.ts
  - server/src/features/staff/staff.types.ts
  - supabase/migrations/20260711019_m01_staff_unavailability_blocks_add_status.sql
steps:
  - id: start
    type: start
    label: Staff requests unavailability, or a manager files one on their behalf
    next: check_on_behalf
  - id: check_on_behalf
    type: decision
    label: Filing on behalf of another staff member?
    branches:
      - condition: "yes"
        next: check_manager_role
      - condition: "no"
        next: check_rest_day
  - id: check_manager_role
    type: decision
    label: Is requester Admin, Supervisor, or Superadmin?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_same_branch
  - id: check_same_branch
    type: decision
    label: Same branch as target staff member? (Superadmin exempt)
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_rest_day
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_rest_day
    type: decision
    label: leave_type = Rest Day AND self-requested?
    branches:
      - condition: "yes"
        next: end_blocked_rest_day
      - condition: "no"
        next: choose_request_type
  - id: end_blocked_rest_day
    type: end
    result: blocked
    label: Rest Day can only be set by Supervisor/Admin/Superadmin (403)
  - id: choose_request_type
    type: input
    label: "Choose request type: Quick Action / Entire Day / Custom range"
    next: resolve_window
  - id: resolve_window
    type: action
    label: Resolve start/end window (shift-end, branch operating hours, or explicit start_time/end_time)
    next: validate_window
  - id: validate_window
    type: decision
    label: end_time after start_time, and not in the past? (Quick Action exempt from past-check)
    branches:
      - condition: "no"
        next: error_validation
      - condition: "yes"
        next: check_overlap
  - id: error_validation
    type: action
    label: Show validation error (400)
    next: choose_request_type
  - id: check_overlap
    type: decision
    label: Overlaps an existing unavailability block for this staff member?
    branches:
      - condition: "yes"
        next: end_blocked_conflict
      - condition: "no"
        next: insert_block
  - id: end_blocked_conflict
    type: end
    result: blocked
    label: Conflicting block (409)
  - id: insert_block
    type: action
    label: Insert staff_unavailability_blocks row (BEFORE INSERT trigger assigns status)
    next: trigger_status
  - id: trigger_status
    type: decision
    label: "DB trigger: is_quick_action = true, OR filed on someone else's behalf?"
    branches:
      - condition: "yes"
        next: end_success_approved
      - condition: "no"
        next: status_pending
  - id: end_success_approved
    type: end
    result: success
    label: status = approved, counts toward availability immediately
  - id: status_pending
    type: action
    label: status = pending, queued for review
    next: open_queue
  - id: open_queue
    type: action
    actor: [Admin, Supervisor, Superadmin]
    label: Reviewer opens Pending Approval queue (branch-scoped; Superadmin sees all branches)
    next: check_self_review
  - id: check_self_review
    type: decision
    label: Is the reviewer the original requester?
    branches:
      - condition: "yes"
        next: end_blocked_self_review
      - condition: "no"
        next: review_decision
  - id: end_blocked_self_review
    type: end
    result: blocked
    label: Cannot review own request (403)
  - id: review_decision
    type: decision
    label: Reviewer decision
    branches:
      - condition: approve
        next: end_success_reviewed
      - condition: deny
        next: end_denied
  - id: end_success_reviewed
    type: end
    result: success
    label: status = approved, counts toward availability
  - id: end_denied
    type: end
    result: success
    label: status = denied, denial_reason recorded, excluded from availability
---

# M01 · Unavailability Block Request & Review

Machine-readable companion to
[[M01-02-unavailability-block-request-review|the human-readable version]] in
`Library/golden-fur/workflows/`.
