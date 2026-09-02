---
id: M10-04-paying-a-transaction-with-credit
module: M10
title: Paying a Transaction with Credit
actors: [Customer, Cashier, Receptionist, Supervisor, Admin, Superadmin]
trigger: A customer taps "Pay with credit" on a Pending booking_payment transaction on the portal Transaction History page (or a BILLING_STAFF_ROLES staff member does it on the customer's behalf) - POST /billing/transactions/:id/pay-with-credit
outcome_success: "redeem_credit RPC decrements the branch-locked credit_balances row and writes a signed-negative 'redemption' credit_transactions row linked to the transaction; settle_transaction flips the transaction to Fully Paid with payment_method='Credit' (processed_by = staff requester or null for a customer) and rolls up bookings.payment_status; transactions.credit_applied_amount is stamped with the redeemed amount."
outcome_failure:
  [
    forbidden_not_owner,
    transaction_not_pending,
    no_credit_available,
    credit_does_not_cover_charge,
    no_balance_row_or_insufficient,
  ]
related_modules: [M03, M08, M14]
source:
  - server/src/features/billing/services/transactionPayment.service.ts
  - server/src/features/billing/services/creditStub.service.ts
  - server/src/features/billing/billing.controller.ts
  - server/src/features/billing/billing.routes.ts
  - client/src/features/reports/pages/CustomerTransactionHistoryPage/CustomerTransactionHistoryPage.tsx
  - supabase/migrations/20260901152_m08_payment_method_add_credit.sql
  - supabase/migrations/20260901153_m08_settle_transaction_rpc.sql
  - supabase/migrations/20260901155_m10_redeem_credit_rpc.sql
  - supabase/migrations/20260805096_m10_create_credit_balances_schema.sql
  - supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql
steps:
  - id: start
    type: start
    label: "Pay with credit tapped on a Pending booking_payment transaction (customer portal, or staff on behalf)"
    next: action_resolve_staff
  - id: action_resolve_staff
    type: action
    label: "Controller resolves isStaff = (staff role is set AND in BILLING_STAFF_ROLES); loads the transaction"
    next: decision_owner
  - id: decision_owner
    type: decision
    label: isStaff, OR transaction.customer_id = requester?
    branches:
      - condition: "no"
        next: end_forbidden
      - condition: "yes"
        next: decision_booking_payment
  - id: end_forbidden
    type: end
    result: blocked
    label: You can only pay for your own transactions (403)
  - id: decision_booking_payment
    type: decision
    label: transaction.transaction_type = 'booking_payment'?
    branches:
      - condition: "no"
        next: end_not_booking_payment
      - condition: "yes"
        next: decision_pending
  - id: end_not_booking_payment
    type: end
    result: blocked
    label: Only booking payments can be paid with credit (400)
  - id: decision_pending
    type: decision
    label: transaction.payment_status = 'Pending'?
    branches:
      - condition: "no"
        next: end_not_pending
      - condition: "yes"
        next: action_compute_amount
  - id: end_not_pending
    type: end
    result: blocked
    label: This transaction is already Partially/Fully Paid (409)
  - id: action_compute_amount
    type: action
    label: "available = credit_balances.balance for (transaction.customer_id, transaction.branch_id), else 0; amount = min(available, transaction.total_amount)"
    next: decision_amount_positive
  - id: decision_amount_positive
    type: decision
    label: amount > 0?
    branches:
      - condition: "no"
        next: end_no_credit
      - condition: "yes"
        next: decision_full_cover
  - id: end_no_credit
    type: end
    result: blocked
    label: No credit available to apply (400)
  - id: decision_full_cover
    type: decision
    label: amount >= transaction.total_amount (credit covers the whole charge)?
    branches:
      - condition: "no"
        next: end_not_covered
      - condition: "yes"
        next: action_redeem
  - id: end_not_covered
    type: end
    result: blocked
    label: "Credit does not cover this charge - split it first (400). Partial application is not supported on this path (unlike checkout's applyCredit)."
  - id: action_redeem
    type: action
    label: "redeem_credit RPC (SECURITY DEFINER, one Postgres txn): lock credit_balances row FOR UPDATE"
    next: decision_balance_ok
  - id: decision_balance_ok
    type: decision
    label: Balance row exists AND balance >= amount (re-checked under the lock)?
    branches:
      - condition: "no"
        next: end_balance_error
      - condition: "yes"
        next: action_decrement
  - id: end_balance_error
    type: end
    result: error
    label: "redeem_credit - no credit balance for this (customer, branch), or balance is less than requested (surfaced as 400)"
  - id: action_decrement
    type: action
    label: "balance -= amount; insert credit_transactions (transaction_type='redemption', amount = -amount, transaction_id = this transaction)"
    next: action_settle
  - id: action_settle
    type: action
    label: "settle_transaction RPC: transaction -> Fully Paid, payment_method='Credit', processed_by = requester (staff) or null (customer); recompute bookings.payment_status (net = total_price - discount_amount - promo_amount; paid = sum of non-Pending booking_payment total_amount)"
    next: action_stamp
  - id: action_stamp
    type: action
    label: "UPDATE transactions SET credit_applied_amount = amount"
    next: action_first_payment_side_effects
  - id: action_first_payment_side_effects
    type: action
    label: "applyFirstBookingPaymentSideEffects (revertOnCapacityConflict=false), same as M08-04: a first payment on a pencil booking re-verifies the slot gate and fires the held-back booking_confirmed / staff_assigned alerts."
    next: end_paid
  - id: end_paid
    type: end
    result: success
    label: "Transaction Fully Paid from credit; credit_balances decremented; a linked redemption row written; bookings.payment_status rolled up; first-payment side-effects applied."
---

# M10 · Paying a Transaction with Credit

Machine-readable companion to
[[M10-04-paying-a-transaction-with-credit|the human-readable version]] in
`Library/golden-fur/features/credits/workflows/`.
