---
id: M10-03-credit-balance-and-history-access
module: M10
title: Credit Balance & History Access
actors: [Customer, Cashier, Admin, Superadmin]
trigger: "A customer or staff member calls GET /credits/balances or GET /credits/history"
outcome_success: returns the caller-authorized customer's credit_balances (all branches) or credit_transactions history (one branch), empty array if none exist
outcome_failure:
  [
    unauthorized,
    invalid_query,
    forbidden_role_or_ownership,
    customer_id_required,
  ]
related_modules: [M02, M08]
source:
  - server/src/features/credits/services/creditBalance.service.ts
  - server/src/features/credits/credits.controller.ts
  - server/src/features/credits/credits.routes.ts
  - server/src/features/credits/credits.types.ts
  - server/src/features/credits/modules/validators/credits.validator.ts
  - supabase/migrations/20260805096_m10_create_credit_balances_schema.sql
  - supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql
steps:
  - id: start
    type: start
    label: "GET /credits/balances or GET /credits/history"
    next: check_auth
  - id: check_auth
    type: decision
    label: Request authenticated? (jwtMiddleware)
    branches:
      - condition: "no"
        next: end_blocked_unauthorized
      - condition: "yes"
        next: check_query
  - id: end_blocked_unauthorized
    type: end
    result: blocked
    label: Unauthorized (401)
  - id: check_query
    type: decision
    label: Query params valid? (customer_id optional; branch_id required for /history)
    branches:
      - condition: "no"
        next: end_blocked_invalid_query
      - condition: "yes"
        next: check_staff_role
  - id: end_blocked_invalid_query
    type: end
    result: blocked
    label: Invalid query (400)
  - id: check_staff_role
    type: decision
    label: Does the requester have a staff role?
    branches:
      - condition: "no (customer)"
        next: check_customer_scope
      - condition: "yes (staff)"
        next: check_credit_role
  - id: check_customer_scope
    type: decision
    label: customer_id provided AND differs from requester?
    branches:
      - condition: "yes"
        next: end_blocked_forbidden
      - condition: "no"
        next: target_is_requester
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: target_is_requester
    type: action
    label: Target customer = requester
    next: check_endpoint
  - id: check_credit_role
    type: decision
    label: Staff role in Superadmin / Admin / Cashier?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_customer_id_provided
  - id: check_customer_id_provided
    type: decision
    label: customer_id provided?
    branches:
      - condition: "no"
        next: end_blocked_customer_id_required
      - condition: "yes"
        next: target_is_param
  - id: end_blocked_customer_id_required
    type: end
    result: blocked
    label: customer_id is required (400)
  - id: target_is_param
    type: action
    label: Target customer = customer_id
    next: check_endpoint
  - id: check_endpoint
    type: decision
    label: Which endpoint?
    branches:
      - condition: /credits/balances
        next: query_balances
      - condition: /credits/history
        next: lookup_balance_row
  - id: query_balances
    type: action
    label: Query credit_balances where customer_id = target, ordered by branch_id
    next: end_success_balances
  - id: end_success_balances
    type: end
    result: success
    label: Returns balances array (one row per branch, may be empty)
  - id: lookup_balance_row
    type: action
    label: Look up credit_balances row for (target, branch_id)
    next: check_balance_row_exists
  - id: check_balance_row_exists
    type: decision
    label: Balance row exists for that branch?
    branches:
      - condition: "no"
        next: end_success_empty_history
      - condition: "yes"
        next: query_transactions
  - id: end_success_empty_history
    type: end
    result: success
    label: Returns empty history array (not a 404)
  - id: query_transactions
    type: action
    label: Query credit_transactions for that credit_balance_id, newest first
    next: end_success_history
  - id: end_success_history
    type: end
    result: success
    label: Returns full issuance/redemption/expiry history for that branch
---

# M10 · Credit Balance & History Access

Machine-readable companion to
[[M10-03-credit-balance-and-history-access|the human-readable version]] in
`Library/golden-fur/workflows/`.
