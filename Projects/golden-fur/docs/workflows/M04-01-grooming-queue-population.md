---
id: M04-01-grooming-queue-population
module: M04
title: Grooming Queue Population & Visibility
actors: [Groomer, Admin, Supervisor, Superadmin]
trigger: Staff member opens the Grooming Queue (GET /grooming/queue)
outcome_success: Ordered list of visible grooming sessions returned, with grooming_sessions rows lazily vivified for any matching booking that didn't have one yet
outcome_failure: [unauthorized, forbidden]
related_modules: [M01, M03]
source:
  - server/src/features/grooming/services/grooming.service.ts
  - server/src/features/grooming/grooming.controller.ts
  - server/src/features/grooming/grooming.routes.ts
  - server/src/features/grooming/grooming.types.ts
  - server/src/features/grooming/services/grooming.service.spec.ts
  - server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts
  - server/src/features/booking/booking.types.ts
  - supabase/migrations/20260719038_m04_create_grooming_schema.sql
  - supabase/migrations/20260728059_m04_drop_grooming_session_status.sql
steps:
  - id: start
    type: start
    label: Staff member opens the Grooming Queue (GET /grooming/queue)
    next: check_role_branch
  - id: check_role_branch
    type: decision
    label: Role in Groomer/Admin/Supervisor/Superadmin, and branch resolved?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: resolve_date_range
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden or unauthorized (401/403)
  - id: resolve_date_range
    type: action
    label: Resolve date range (date_from/date_to query params, default today, UTC)
    next: query_bookings
  - id: query_bookings
    type: action
    label: Query bookings (service_category=Grooming, status IN Pending/In Progress, scheduled_start within range)
    next: apply_downpayment_gate
  - id: apply_downpayment_gate
    type: action
    label: Exclude bookings still needing an unpaid downpayment (downpayment_required=true AND payment_stage=Unpaid)
    next: check_role_scope
  - id: check_role_scope
    type: decision
    label: Requester role?
    branches:
      - condition: Groomer
        next: filter_own
      - condition: Admin/Supervisor
        next: filter_branch
      - condition: Superadmin
        next: no_filter
  - id: filter_own
    type: action
    actor: [Groomer]
    label: Filter to bookings where assigned_staff_id = requester
    next: lookup_existing_sessions
  - id: filter_branch
    type: action
    actor: [Admin, Supervisor]
    label: Filter to bookings where branch_id = requester's branch
    next: lookup_existing_sessions
  - id: no_filter
    type: action
    actor: [Superadmin]
    label: No filter applied - all branches visible
    next: lookup_existing_sessions
  - id: lookup_existing_sessions
    type: action
    label: Look up existing grooming_sessions rows for these booking IDs
    next: check_missing_sessions
  - id: check_missing_sessions
    type: decision
    label: Any matching booking without a session row yet?
    branches:
      - condition: "yes"
        next: insert_missing_sessions
      - condition: "no"
        next: fetch_full_sessions
  - id: insert_missing_sessions
    type: action
    label: Insert a grooming_sessions row for each missing booking (booking_id, assigned_groomer_id = bookings.assigned_staff_id)
    next: fetch_full_sessions
  - id: fetch_full_sessions
    type: action
    label: Fetch full session rows (joined booking + booking_items)
    next: sort_queue
  - id: sort_queue
    type: decision
    label: queue_position set on both rows being compared?
    branches:
      - condition: "yes"
        next: sort_by_queue_position
      - condition: "no"
        next: sort_by_scheduled_start
  - id: sort_by_queue_position
    type: action
    label: Sort by queue_position
    next: end_success
  - id: sort_by_scheduled_start
    type: action
    label: Fall back to booking.scheduled_start (chronological)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Ordered queue returned (possibly empty)
---

# M04 · Grooming Queue Population & Visibility

Machine-readable companion to
[[M04-01-grooming-queue-population|the human-readable version]] in
`Library/golden-fur/workflows/`.
