---
id: M11-01-event-triggered-notification-dispatch
module: M11
title: Event-Triggered Notification Dispatch
actors: [System, Staff, Customer]
trigger: A business event fires in another module (booking confirmed/rescheduled/cancelled, payment recorded, care log completed, staff selected, account created, password reset, message received) and calls createNotification()
outcome_success: In-app notifications row inserted and/or best-effort email sent, each independently gated by the recipient's own notification_preferences for that event type
outcome_failure: [in_app_insert_failed]
related_modules: [M01, M03, M05, M08]
source:
  - server/src/features/notifications/services/notification.service.ts
  - server/src/features/notifications/notifications.types.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/staff/services/staffManagement.service.ts
  - server/src/shared/email/resend.client.ts
  - server/src/shared/email/bookingConfirmedEmail.ts
  - supabase/migrations/20260805100_m11_create_notifications_schema.sql
  - supabase/migrations/20260806103_shared_replace_notification_booleans_with_preferences_jsonb.sql
  - supabase/migrations/20260814124_custom_notification_event_type_add_message_received.sql
  - supabase/migrations/20260814125_custom_notifications_related_thread_id.sql
  - supabase/migrations/20260819137_custom_notification_event_type_add_staff_assigned.sql
steps:
  - id: start
    type: start
    label: Business event fires in an originating module (booking confirmed/rescheduled/cancelled, payment recorded, care log completed, staff selected, account created, password reset, message received)
    next: build_params
  - id: build_params
    type: action
    actor: [System]
    label: Originating module's notification helper resolves recipient id (staff or customer), event_type, title/message, and a sendEmail thunk where a template exists
    next: call_create_notification
  - id: call_create_notification
    type: action
    label: Call createNotification() - the one shared write path for every event type
    next: lookup_preferences
  - id: lookup_preferences
    type: action
    label: Look up recipient's notification_preferences jsonb entry for this event_type from staff_profiles or customer_profiles (whichever recipient id was supplied)
    next: check_pref_entry
  - id: check_pref_entry
    type: decision
    label: Recipient has an explicit preference entry for this event type?
    branches:
      - condition: "no"
        next: default_both_on
      - condition: "yes"
        next: check_inbrowser
  - id: default_both_on
    type: action
    label: Default email = true, in_browser = true (fail open, never silently goes dark)
    next: check_inbrowser
  - id: check_inbrowser
    type: decision
    label: in_browser enabled for this event?
    branches:
      - condition: "no"
        next: skip_insert
      - condition: "yes"
        next: insert_row
  - id: skip_insert
    type: action
    label: Skip notifications row insert (no bell/inbox entry for this event)
    next: check_email
  - id: insert_row
    type: action
    label: Insert notifications row (recipient id, event_type, title, message, related_booking_id/related_thread_id)
    next: check_insert_result
  - id: check_insert_result
    type: decision
    label: Insert succeeded?
    branches:
      - condition: "no"
        next: end_error_insert
      - condition: "yes"
        next: check_email
  - id: end_error_insert
    type: end
    result: error
    label: createNotification throws (400) - propagates to the caller's own try/catch, does not roll back the triggering business action
  - id: check_email
    type: decision
    label: email enabled for this event, AND caller supplied a sendEmail thunk?
    branches:
      - condition: "no"
        next: end_success
      - condition: "yes"
        next: invoke_send_email
  - id: invoke_send_email
    type: action
    label: Invoke the caller-supplied sendEmail() thunk (shared/email/*.ts -> resend.client.ts)
    next: check_send_result
  - id: check_send_result
    type: decision
    label: Email sent successfully?
    branches:
      - condition: "yes"
        next: end_success
      - condition: "no"
        next: log_email_failure
  - id: log_email_failure
    type: action
    label: Catch and log the failure - never rethrown, never rolls back the notification row or the triggering action
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Dispatch complete - in-app row and/or email delivered per the recipient's own preference, independently of each other
---

# M11 · Event-Triggered Notification Dispatch

Machine-readable companion to
[[M11-01-event-triggered-notification-dispatch|the human-readable version]] in
`Library/golden-fur/features/notifications/workflows/`.
