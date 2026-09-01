---
id: M14-04-analytics-dashboard-summary
module: M14
title: Analytics Dashboard Summary
actors: [Superadmin]
trigger: Superadmin selects an optional branch and a time_filter (Today/This Week/This Month/This Year/All Time) on the Analytics Dashboard
outcome_success: Analytics summary returned - total_revenue, booking_count, cancelled_count, cancellation_rate
outcome_failure: [unauthorized, forbidden, invalid_time_filter, rpc_error]
related_modules: [M08, M03]
source:
  - server/src/features/reports/reports.controller.ts
  - server/src/features/reports/reports.routes.ts
  - server/src/features/reports/reports.types.ts
  - server/src/features/reports/services/analytics.service.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - supabase/migrations/20260805101_m14_create_reporting_functions.sql
  - supabase/migrations/20260901157_m14_reporting_functions_settled_only.sql
steps:
  - id: start
    type: start
    label: Superadmin opens Analytics Dashboard
    next: check_route_guard
  - id: check_route_guard
    type: decision
    label: "Authenticated, session valid, role = Superadmin? (route middleware, ANALYTICS_READ_ROLES)"
    branches:
      - condition: "no"
        next: end_blocked_auth
      - condition: "yes"
        next: input_filters
  - id: end_blocked_auth
    type: end
    result: blocked
    label: Unauthorized / forbidden (401 / 403)
  - id: input_filters
    type: input
    actor: [Superadmin]
    label: Select branch (optional) and time_filter
    next: check_role_service
  - id: check_role_service
    type: decision
    label: "Service layer re-checks: requesterRole = Superadmin? (defense-in-depth)"
    branches:
      - condition: "no"
        next: end_blocked_service_role
      - condition: "yes"
        next: check_time_filter
  - id: end_blocked_service_role
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_time_filter
    type: decision
    label: "time_filter is one of today/this_week/this_month/this_year/all_time?"
    branches:
      - condition: "no"
        next: end_blocked_invalid_filter
      - condition: "yes"
        next: call_rpc
  - id: end_blocked_invalid_filter
    type: end
    result: blocked
    label: Invalid time_filter (400)
  - id: call_rpc
    type: action
    label: Call get_analytics_summary(branch_id, time_filter) RPC
    next: resolve_range_start
  - id: resolve_range_start
    type: action
    label: "DB function resolves range_start (day/week/month/year trunc of now(), or -infinity for all_time)"
    next: compute_revenue
  - id: compute_revenue
    type: action
    label: "Sum transactions.total_amount WHERE payment_status = 'Fully Paid' AND created_at >= range_start (branch-scoped) -> total_revenue (migration 20260901157 - Pending/Partially Paid charges are no longer counted)"
    next: compute_booking_counts
  - id: compute_booking_counts
    type: action
    label: "Count bookings with scheduled_start >= range_start (branch-scoped) -> booking_count, and where status = Cancelled -> cancelled_count"
    next: check_booking_count_positive
  - id: check_booking_count_positive
    type: decision
    label: booking_count > 0?
    branches:
      - condition: "no"
        next: rate_zero
      - condition: "yes"
        next: rate_computed
  - id: rate_zero
    type: action
    label: cancellation_rate = 0
    next: check_rpc_error
  - id: rate_computed
    type: action
    label: "cancellation_rate = round(cancelled_count / booking_count * 100, 2)"
    next: check_rpc_error
  - id: check_rpc_error
    type: decision
    label: RPC returned an error?
    branches:
      - condition: "yes"
        next: end_blocked_rpc
      - condition: "no"
        next: end_success
  - id: end_blocked_rpc
    type: end
    result: blocked
    label: Report generation failed (400)
  - id: end_success
    type: end
    result: success
    label: Analytics summary returned - revenue, booking_count, cancelled_count, cancellation_rate
---

# M14 · Analytics Dashboard Summary

Machine-readable companion to
[[M14-04-analytics-dashboard-summary|the human-readable version]] in
`Library/golden-fur/workflows/`.
