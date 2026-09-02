---
id: M08-04-recording-a-counter-payment
module: M08
title: Recording a Counter Payment
actors: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
trigger: A money-handling staff member on the Transactions page (/staff/billing/transactions) either records a payment against a Pending booking_payment transaction, or adds a new balance charge to a booking
outcome_success: "settle_transaction RPC flips the transaction to Fully Paid with its real method/bank/reference/processed_by and atomically recomputes bookings.payment_status (net = total_price - discount_amount - promo_amount; paid = sum of non-Pending booking_payment total_amount; Pending / Partially Paid / Fully Paid, + paid_at when Fully Paid). Add-a-payment inserts a new Pending booking_payment transaction (payment_choice='balance') for the cashier to then settle."
outcome_failure:
  [
    forbidden_role,
    not_a_booking_payment,
    transaction_not_pending,
    cash_tendered_short,
    add_amount_not_positive,
    add_amount_exceeds_remaining,
    transaction_already_fully_paid,
  ]
related_modules: [M03, M10, M14]
source:
  - server/src/features/billing/services/transactionPayment.service.ts
  - server/src/features/billing/services/paymentMethod.service.ts
  - server/src/features/billing/billing.controller.ts
  - server/src/features/billing/billing.routes.ts
  - server/src/features/billing/billing.types.ts
  - server/src/features/billing/modules/validators/billing.validator.ts
  - client/src/features/billing/pages/TransactionsPage/TransactionsPage.tsx
  - supabase/migrations/20260901150_m08_bookings_replace_payment_stage_with_payment_status.sql
  - supabase/migrations/20260901151_m08_transactions_payment_choice_free_label.sql
  - supabase/migrations/20260901152_m08_payment_method_add_credit.sql
  - supabase/migrations/20260901153_m08_settle_transaction_rpc.sql
  - supabase/migrations/20260901154_m08_add_booking_payment_rpc.sql
steps:
  - id: start
    type: start
    label: Staff opens the Transactions page
    next: decision_role
  - id: decision_role
    type: decision
    actor: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
    label: Viewer role in BILLING_STAFF_ROLES (Superadmin/Admin/Supervisor/Receptionist/Cashier)?
    branches:
      - condition: "no"
        next: end_forbidden
      - condition: "yes"
        next: input_view
  - id: end_forbidden
    type: end
    result: blocked
    label: Not a money-handling role - client redirects to Settings; routes return 403
  - id: input_view
    type: input
    actor: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
    label: Transactions page loads, grouped by booking (plus standalone misc sales)
    next: decision_action
  - id: decision_action
    type: decision
    label: Which action does the staff member take?
    branches:
      - condition: "Add a payment (booking has no Pending row)"
        next: action_add_post
      - condition: "Record payment (on a Pending booking_payment row)"
        next: input_payment_method
  - id: action_add_post
    type: action
    label: "POST /billing/bookings/:id/payments { amount } -> addBookingPayment -> add_booking_payment RPC"
    next: decision_add_positive
  - id: decision_add_positive
    type: decision
    label: amount is a positive number?
    branches:
      - condition: "no"
        next: end_add_not_positive
      - condition: "yes"
        next: action_add_remaining
  - id: end_add_not_positive
    type: end
    result: blocked
    label: add_booking_payment - amount must be positive (400)
  - id: action_add_remaining
    type: action
    label: "Lock booking FOR UPDATE; remaining = (total_price - discount_amount - promo_amount) - SUM(total_amount over non-Pending booking_payment rows)"
    next: decision_add_fits
  - id: decision_add_fits
    type: decision
    label: amount <= remaining?
    branches:
      - condition: "no"
        next: end_add_exceeds
      - condition: "yes"
        next: action_add_insert
  - id: end_add_exceeds
    type: end
    result: blocked
    label: add_booking_payment - amount exceeds remaining balance (400)
  - id: action_add_insert
    type: action
    label: "Insert new Pending booking_payment transaction (payment_choice='balance', payment_method 'Cash' placeholder, processed_by_staff_id) + 'Additional payment' transaction_line_items row, in one transaction. Returns the new Pending row."
    next: end_added
  - id: end_added
    type: end
    result: success
    label: New Pending booking_payment transaction created - now settled via the Record payment path
  - id: input_payment_method
    type: input
    actor: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
    label: "In the modal, pick a COUNTER_PAYMENT_METHOD (Cash / Card / Bank Transfer / Grabmart / Pickaroo) + bank_name (Bank Transfer only) / payment_reference / cash_tendered (Cash only). GCash/Maya and Credit are not offered here."
    next: action_record_post
  - id: action_record_post
    type: action
    label: "POST /billing/transactions/:id/pay -> recordTransactionPayment -> loadTransaction"
    next: decision_is_booking_payment
  - id: decision_is_booking_payment
    type: decision
    label: transaction_type = 'booking_payment'?
    branches:
      - condition: "no"
        next: end_not_booking_payment
      - condition: "yes"
        next: decision_txn_pending
  - id: end_not_booking_payment
    type: end
    result: blocked
    label: Only booking payments can be settled here (400)
  - id: decision_txn_pending
    type: decision
    label: transaction.payment_status = 'Pending'?
    branches:
      - condition: "no"
        next: end_txn_not_pending
      - condition: "yes"
        next: decision_cash
  - id: end_txn_not_pending
    type: end
    result: blocked
    label: This transaction is already Partially/Fully Paid (409)
  - id: decision_cash
    type: decision
    label: payment_method = 'Cash'?
    branches:
      - condition: "yes"
        next: decision_cash_covers
      - condition: "no"
        next: action_settle_rpc
  - id: decision_cash_covers
    type: decision
    label: cash_tendered >= total_amount (amount due)?
    branches:
      - condition: "no"
        next: end_cash_short
      - condition: "yes"
        next: action_compute_change
  - id: end_cash_short
    type: end
    result: blocked
    label: Cash tendered is less than the amount due (400)
  - id: action_compute_change
    type: action
    label: "changeAmount = round(cash_tendered - total_amount) - returned in the HTTP response only, never persisted (transactions has no tendered/change column)"
    next: action_settle_rpc
  - id: action_settle_rpc
    type: action
    label: "settle_transaction RPC (SECURITY DEFINER, single Postgres transaction): lock the transaction FOR UPDATE"
    next: decision_already_paid
  - id: decision_already_paid
    type: decision
    label: transaction already Fully Paid (lost race)?
    branches:
      - condition: "yes"
        next: end_already_fully_paid
      - condition: "no"
        next: action_flip_txn
  - id: end_already_fully_paid
    type: end
    result: error
    label: settle_transaction - transaction is already Fully Paid (surfaced as 400)
  - id: action_flip_txn
    type: action
    label: "UPDATE transaction -> payment_status='Fully Paid', payment_method, bank_name, payment_reference (coalesced), processed_by_staff_id = requester, updated_at=now()"
    next: action_rollup
  - id: action_rollup
    type: action
    label: "Lock the parent booking FOR UPDATE; net = total_price - discount_amount - promo_amount; paid = SUM(total_amount) over this booking's non-Pending booking_payment transactions; new_status = paid<=0 ? Pending : paid>=net ? Fully Paid : Partially Paid"
    next: action_write_booking
  - id: action_write_booking
    type: action
    label: "UPDATE bookings SET payment_status = new_status, paid_at = now() when Fully Paid (else unchanged), updated_at = now(). Return the booking row."
    next: action_first_payment_side_effects
  - id: action_first_payment_side_effects
    type: action
    label: "applyFirstBookingPaymentSideEffects (shared with the M08-02 webhook path): if this was the first payment (Pending -> settled), re-verify the down-payment slot gate and fire the held-back booking_confirmed / staff_assigned alerts. revertOnCapacityConflict=false here - a capacity conflict keeps the payment and leaves the booking overbooked for staff to reschedule (the webhook path passes true and hard-rejects with 409)."
    next: end_settled
  - id: end_settled
    type: end
    result: success
    label: "Transaction Fully Paid; bookings.payment_status rolled up atomically; first-payment side-effects applied; cashier sees change due for Cash."
---

# M08 · Recording a Counter Payment

Machine-readable companion to
[[M08-04-recording-a-counter-payment|the human-readable version]] in
`Library/golden-fur/features/billing/workflows/`.
