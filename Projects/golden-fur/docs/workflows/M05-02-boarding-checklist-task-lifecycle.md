---
id: M05-02-boarding-checklist-task-lifecycle
module: M05
title: Boarding Checklist Task Lifecycle
actors:
  [Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin, System]
trigger: A care_log_entries row (generated at Hotel/Daycare check-in) is read on the Boarding Checklist Kanban, or a staff member acts on a card
outcome_success: entry status moves to In Progress, Completed (with notification sent), Pending (reopened), or Missed (lazy, system-driven)
outcome_failure: [not_pending, already_completed, already_pending]
related_modules: [M11]
source:
  - server/src/features/hotel/services/careLogCompletion.service.ts
  - server/src/features/hotel/services/careLogNotifications.service.ts
  - server/src/features/hotel/services/activityLog.service.ts
  - server/src/features/hotel/hotel.types.ts
  - server/src/features/hotel/hotel.controller.ts
  - server/src/features/hotel/hotel.routes.ts
steps:
  - id: start
    type: start
    label: Care log entries exist for an active stay (auto-generated at check-in)
    next: read_board
  - id: read_board
    type: action
    label: Board is read (Boarding Checklist Kanban)
    next: check_stale
  - id: check_stale
    type: decision
    label: Pending/In Progress entry whose scheduled_date is before today?
    branches:
      - condition: "yes"
        next: flip_missed
      - condition: "no"
        next: check_future
  - id: flip_missed
    type: action
    label: Bulk-flip to Missed
    next: record_missed_activity
  - id: record_missed_activity
    type: action
    label: Record task_missed activity (system-driven, no actor)
    next: end_missed
  - id: end_missed
    type: end
    result: success
    label: status = Missed - doesn't block checkout, can still be reopened
  - id: check_future
    type: decision
    label: Pending entry whose scheduled_date is after today?
    branches:
      - condition: "yes"
        next: end_backlog_display
      - condition: "no"
        next: staff_action
  - id: end_backlog_display
    type: end
    result: success
    label: Displayed as Backlog for this read only - never written to the DB; self-resolves to Pending once its date arrives
  - id: staff_action
    type: decision
    label: Staff action on a card
    branches:
      - condition: Start
        next: check_start_pending
      - condition: Complete
        next: check_already_completed
      - condition: Reopen
        next: check_already_pending
  - id: check_start_pending
    type: decision
    label: Entry status = Pending?
    branches:
      - condition: "no"
        next: end_blocked_not_pending
      - condition: "yes"
        next: set_in_progress
  - id: end_blocked_not_pending
    type: end
    result: blocked
    label: Entry is not Pending (409)
  - id: set_in_progress
    type: action
    label: Set status = In Progress
    next: record_started_activity
  - id: record_started_activity
    type: action
    label: Record task_started activity
    next: end_in_progress
  - id: end_in_progress
    type: end
    result: success
    label: status = In Progress
  - id: check_already_completed
    type: decision
    label: completed_at already set?
    branches:
      - condition: "yes"
        next: end_blocked_already_completed
      - condition: "no"
        next: set_completed
  - id: end_blocked_already_completed
    type: end
    result: blocked
    label: Already completed (409)
  - id: set_completed
    type: action
    label: Set completed_at, completed_by, status = Completed
    next: send_notification
  - id: send_notification
    type: action
    label: Send care_log_completed notification (best-effort; gated solely by the customer's own notification_preferences.care_log_completed) + email if account_email on file
    next: record_completed_activity
  - id: record_completed_activity
    type: action
    label: Record task_completed activity
    next: end_completed
  - id: end_completed
    type: end
    result: success
    label: status = Completed
  - id: check_already_pending
    type: decision
    label: Entry status = Pending?
    branches:
      - condition: "yes"
        next: end_blocked_already_pending
      - condition: "no"
        next: clear_and_reopen
  - id: end_blocked_already_pending
    type: end
    result: blocked
    label: Already Pending (409)
  - id: clear_and_reopen
    type: action
    label: Clear completed_at/completed_by, set status = Pending
    next: record_reopened_activity
  - id: record_reopened_activity
    type: action
    label: Record task_reopened activity
    next: end_reopened
  - id: end_reopened
    type: end
    result: success
    label: status = Pending
---

# M05 · Boarding Checklist Task Lifecycle

Machine-readable companion to
[[M05-02-boarding-checklist-task-lifecycle|the human-readable version]] in
`Library/golden-fur/workflows/`.
