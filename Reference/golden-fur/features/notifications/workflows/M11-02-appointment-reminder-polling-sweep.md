---
id: M11-02-appointment-reminder-polling-sweep
module: M11
title: Appointment-Reminder Polling Sweep
actors: [System]
trigger: The in-process scheduler's 15-minute timer fires (startAppointmentReminderScheduler)
outcome_success: Every booking due for a reminder within the lookahead window is claimed exactly once via reminder_sent_at and its appointment_reminder notification dispatched
outcome_failure: [query_failed, dispatch_failed_per_booking]
related_modules: [M02, M03]
source:
  - server/src/features/notifications/services/appointmentReminder.job.ts
  - server/src/features/notifications/services/notification.service.ts
  - server/src/features/notifications/notifications.types.ts
  - server/src/shared/email/appointmentReminderEmail.ts
  - server/src/shared/email/resend.client.ts
  - supabase/migrations/20260809119_custom_bookings_reminder_sent_at.sql
  - supabase/migrations/20260806103_shared_replace_notification_booleans_with_preferences_jsonb.sql
steps:
  - id: start
    type: start
    label: 15-minute scheduler tick fires (startAppointmentReminderScheduler)
    next: query_candidates
  - id: query_candidates
    type: action
    label: "Query bookings: status in (Pending, In Progress), reminder_sent_at IS NULL, scheduled_start within [now, now + 3-day lookahead]"
    next: check_query_result
  - id: check_query_result
    type: decision
    label: Query succeeded?
    branches:
      - condition: "no"
        next: end_error_query
      - condition: "yes"
        next: check_any_candidates
  - id: end_error_query
    type: end
    result: error
    label: Query error logged; process not crashed; next tick retries
  - id: check_any_candidates
    type: decision
    label: Any candidate bookings returned?
    branches:
      - condition: "no"
        next: end_noop
      - condition: "yes"
        next: resolve_offsets
  - id: end_noop
    type: end
    result: success
    label: No-op this tick - reschedule for +15 minutes
  - id: resolve_offsets
    type: action
    label: Batch-resolve each distinct customer's appointment_reminder.reminder_offset_minutes preference (default 1440 = 1 day) from customer_profiles.notification_preferences
    next: compute_fire_time
  - id: compute_fire_time
    type: action
    label: "For each candidate booking: compute fire time = scheduled_start - customer's offset minutes"
    next: check_due
  - id: check_due
    type: decision
    label: now >= fire time?
    branches:
      - condition: "no"
        next: check_more_bookings
      - condition: "yes"
        next: claim_reminder
  - id: claim_reminder
    type: action
    label: "Conditional UPDATE: set reminder_sent_at = now() WHERE id = booking.id AND reminder_sent_at IS NULL (single-writer claim)"
    next: check_claim_won
  - id: check_claim_won
    type: decision
    label: Claim won (row returned)?
    branches:
      - condition: "no"
        next: check_more_bookings
      - condition: "yes"
        next: dispatch_reminder
  - id: dispatch_reminder
    type: action
    label: Look up customer email + branch name, build message, call createNotification() with eventType=appointment_reminder and a sendEmail thunk (gated by recipient's own preferences, same as generic dispatch workflow)
    next: check_dispatch_error
  - id: check_dispatch_error
    type: decision
    label: Dispatch threw an error?
    branches:
      - condition: "yes"
        next: log_dispatch_error
      - condition: "no"
        next: check_more_bookings
  - id: log_dispatch_error
    type: action
    label: Catch and log - booking stays claimed (reminder_sent_at already set), not retried this poll
    next: check_more_bookings
  - id: check_more_bookings
    type: decision
    label: More candidate bookings remain in this tick?
    branches:
      - condition: "yes"
        next: compute_fire_time
      - condition: "no"
        next: end_tick_complete
  - id: end_tick_complete
    type: end
    result: success
    label: Tick complete - every due booking claimed exactly once; job reschedules itself for +15 minutes regardless of outcome
---

# M11 · Appointment-Reminder Polling Sweep

Machine-readable companion to
[[M11-02-appointment-reminder-polling-sweep|the human-readable version]] in
`Library/golden-fur/features/notifications/workflows/`.
