---
id: M14-01-daily-sales-report-generation
module: M14
title: Daily Sales Report Generation
actors: [Admin, Supervisor, Superadmin]
trigger: Admin/Supervisor/Superadmin requests the DSR for a single report_date, optionally overriding branch (Superadmin only)
outcome_success: DSR JSON returned - breakdown (service_category x payment_method), totals, credit_usage, misc_sales, misc_sales_total - all transaction aggregations count only payment_status = 'Fully Paid' rows
outcome_failure: [unauthorized, forbidden, missing_report_date, rpc_error]
related_modules: [M08, M10]
source:
  - server/src/features/reports/reports.controller.ts
  - server/src/features/reports/reports.routes.ts
  - server/src/features/reports/reports.types.ts
  - server/src/features/reports/services/dailySalesReport.service.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts
  - supabase/migrations/20260805101_m14_create_reporting_functions.sql
  - supabase/migrations/20260901157_m14_reporting_functions_settled_only.sql
steps:
  - id: start
    type: start
    label: Admin/Supervisor/Superadmin opens the DSR view
    next: check_route_guard
  - id: check_route_guard
    type: decision
    label: "Authenticated, session valid, role in Superadmin/Admin/Supervisor, branch resolved? (route middleware)"
    branches:
      - condition: "no"
        next: end_blocked_auth
      - condition: "yes"
        next: input_report_date
  - id: end_blocked_auth
    type: end
    result: blocked
    label: Unauthorized / forbidden (401 / 403)
  - id: input_report_date
    type: input
    actor: [Admin, Supervisor, Superadmin]
    label: Enter report_date (optional branch_id override)
    next: check_report_date
  - id: check_report_date
    type: decision
    label: report_date provided?
    branches:
      - condition: "no"
        next: error_missing_date
      - condition: "yes"
        next: check_superadmin
  - id: error_missing_date
    type: action
    label: "Show error: report_date is required (400)"
    next: input_report_date
  - id: check_superadmin
    type: decision
    label: Is requester a Superadmin?
    branches:
      - condition: "no"
        next: branch_own
      - condition: "yes"
        next: branch_requested_or_null
  - id: branch_own
    type: action
    label: effective branch = requester's own branch_id (any passed branch_id is ignored)
    next: call_rpc
  - id: branch_requested_or_null
    type: action
    label: effective branch = branch_id passed, or null for combined-branches view
    next: call_rpc
  - id: call_rpc
    type: action
    label: Call get_daily_sales_report(effective_branch, report_date) RPC
    next: check_rpc_error
  - id: check_rpc_error
    type: decision
    label: RPC returned an error (e.g. malformed date)?
    branches:
      - condition: "yes"
        next: end_blocked_rpc
      - condition: "no"
        next: compute_breakdown
  - id: end_blocked_rpc
    type: end
    result: blocked
    label: Report generation failed (400)
  - id: compute_breakdown
    type: action
    label: "DB function aggregates same-day (t.created_at::date = report_date), payment_status = 'Fully Paid' booking_payment transactions into a service_category x payment_method breakdown + totals (migration 20260901157 - Pending charges created up front at booking time are excluded so gross is not inflated)"
    next: compute_credit_usage
  - id: compute_credit_usage
    type: action
    label: "DB function computes credit_usage section from credit_transactions redemption rows (branch-scoped via credit_balances) - now reports real figures since the redeem_credit path shipped (M10-04), no longer always zero"
    next: compute_misc_sales
  - id: compute_misc_sales
    type: action
    label: "DB function computes misc_sales (miscellaneous_sale transactions, payment_status = 'Fully Paid', grouped by payment_method) + misc_sales_total"
    next: end_success
  - id: end_success
    type: end
    result: success
    label: DSR returned - breakdown, totals, credit_usage, misc_sales, misc_sales_total
---

# M14 · Daily Sales Report Generation

Machine-readable companion to
[[M14-01-daily-sales-report-generation|the human-readable version]] in
`Library/golden-fur/workflows/`.
