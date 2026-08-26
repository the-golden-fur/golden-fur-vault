---
id: M14-02-cage-occupancy-report-generation
module: M14
title: Cage Occupancy Report Generation
actors: [Receptionist, Admin, Supervisor, Superadmin]
trigger: Receptionist/Admin/Supervisor/Superadmin opens the Cage Occupancy report, optionally passing branch_id (Superadmin only)
outcome_success: Rows returned - cage_count grouped by size (S/M/L/XL) x status (Available/Occupied/Reserved/Under Maintenance)
outcome_failure: [unauthorized, forbidden, rpc_error]
related_modules: [M05]
source:
  - server/src/features/reports/reports.controller.ts
  - server/src/features/reports/reports.routes.ts
  - server/src/features/reports/reports.types.ts
  - server/src/features/reports/services/cageOccupancy.service.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts
  - supabase/migrations/20260805101_m14_create_reporting_functions.sql
steps:
  - id: start
    type: start
    label: Receptionist/Admin/Supervisor/Superadmin opens Cage Occupancy report
    next: check_route_guard
  - id: check_route_guard
    type: decision
    label: "Authenticated, session valid, role in Superadmin/Admin/Supervisor/Receptionist, branch resolved? (route middleware)"
    branches:
      - condition: "no"
        next: end_blocked_auth
      - condition: "yes"
        next: check_superadmin
  - id: end_blocked_auth
    type: end
    result: blocked
    label: Unauthorized / forbidden (401 / 403)
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
    label: Call get_cage_occupancy_report(effective_branch) RPC
    next: check_rpc_error
  - id: check_rpc_error
    type: decision
    label: RPC returned an error?
    branches:
      - condition: "yes"
        next: end_blocked_rpc
      - condition: "no"
        next: group_rows
  - id: end_blocked_rpc
    type: end
    result: blocked
    label: Report generation failed (400)
  - id: group_rows
    type: action
    label: "DB function groups current cages rows by size x status and counts each combination"
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Cage occupancy rows returned (possibly empty array)
---

# M14 · Cage Occupancy Report Generation

Machine-readable companion to
[[M14-02-cage-occupancy-report-generation|the human-readable version]] in
`Library/golden-fur/workflows/`.
