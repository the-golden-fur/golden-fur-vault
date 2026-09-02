---
id: M14-03-transaction-history-search
module: M14
title: Transaction History Search
actors: [Superadmin, Admin, Supervisor, Receptionist, Cashier, Customer]
trigger: Staff or customer submits transaction-history search filters (branch [staff-only], customer_id, pet_id, date_from, date_to, service_category)
outcome_success: Transaction list returned (possibly empty), ordered by created_at descending
outcome_failure: [unauthorized, forbidden, query_error]
related_modules: [M08, M03]
source:
  - server/src/features/reports/reports.controller.ts
  - server/src/features/reports/reports.routes.ts
  - server/src/features/reports/reports.types.ts
  - server/src/features/reports/services/transactionHistory.service.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts
steps:
  - id: start
    type: start
    label: Staff member or customer opens Transaction History
    next: check_caller_type
  - id: check_caller_type
    type: decision
    label: Is the caller a customer (no staff role/branch on the JWT)?
    branches:
      - condition: "yes"
        next: force_customer_scope
      - condition: "no"
        next: check_route_guard
  - id: force_customer_scope
    type: action
    actor: [Customer]
    label: customer_id forced to req.user.sub (cannot be overridden); no branch filter applied
    next: input_filters
  - id: check_route_guard
    type: decision
    label: "Authenticated, session valid, role in Superadmin/Admin/Supervisor/Receptionist/Cashier, branch resolved? (route middleware)"
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
        next: branch_requested_or_omitted
  - id: branch_own
    type: action
    label: branch filter = requester's own branch_id (any passed branch_id is ignored)
    next: input_filters
  - id: branch_requested_or_omitted
    type: action
    label: branch filter = branch_id passed, or omitted entirely for all branches
    next: input_filters
  - id: input_filters
    type: input
    actor: [Superadmin, Admin, Supervisor, Receptionist, Cashier, Customer]
    label: "Enter optional filters: pet_id, date_from, date_to, service_category (+ customer_id, branch_id for staff)"
    next: check_join_type
  - id: check_join_type
    type: decision
    label: pet_id or service_category provided?
    branches:
      - condition: "yes"
        next: inner_join
      - condition: "no"
        next: left_join
  - id: inner_join
    type: action
    label: Join transactions to bookings with INNER join (excludes booking-less misc sales)
    next: apply_filters
  - id: left_join
    type: action
    label: Join transactions to bookings with LEFT join (booking-less misc sales still shown)
    next: apply_filters
  - id: apply_filters
    type: action
    label: "Apply each provided filter: branch_id, customer_id, created_at >= date_from, created_at < date_to + 1 day (exclusive), bookings.pet_id, bookings.service_category"
    next: order_results
  - id: order_results
    type: action
    label: Order by created_at descending
    next: check_query_error
  - id: check_query_error
    type: decision
    label: Query returned an error?
    branches:
      - condition: "yes"
        next: end_blocked_query
      - condition: "no"
        next: end_success
  - id: end_blocked_query
    type: end
    result: blocked
    label: Search failed (400)
  - id: end_success
    type: end
    result: success
    label: Transaction list returned (possibly empty)
---

# M14 · Transaction History Search

Machine-readable companion to
[[M14-03-transaction-history-search|the human-readable version]] in
`Library/golden-fur/features/reports/workflows/`.
