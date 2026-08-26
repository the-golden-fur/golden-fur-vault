---
id: M08-02-customer-self-service-online-payment
module: M08
title: Customer Self-Service Online Payment
actors: [Customer]
trigger: Customer taps Pay (full or downpayment) on their own booking in the customer portal
outcome_success: transactions row Fully Paid via webhook confirmation; bookings.payment_stage advanced when initiated_by = customer and booking_id is present
outcome_failure:
  [
    not_own_booking,
    already_fully_paid,
    no_downpayment_required,
    nothing_left_to_pay,
    online_payments_disabled,
    paymongo_initiation_failed,
    invalid_webhook_signature,
  ]
related_modules: [M03, M09]
source:
  - server/src/features/billing/services/customerBookingPayment.service.ts
  - server/src/features/billing/services/webhookConfirmation.service.ts
  - server/src/features/billing/services/paymongo.service.ts
  - server/src/features/billing/routes/paymongoWebhook.routes.ts
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - server/src/features/booking/services/booking.service.ts
  - supabase/migrations/20260803082_m08_booking_payment_stage.sql
  - supabase/migrations/20260803083_m03_m08_remove_paid_booking_status.sql
  - supabase/migrations/20260809118_custom_transactions_customer_initiated_payment.sql
steps:
  - id: start
    type: start
    label: Customer taps Pay on their own booking
    next: check_ownership
  - id: check_ownership
    type: decision
    label: booking.customer_id = requester?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_already_paid
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Not this customer's booking (403)
  - id: check_already_paid
    type: decision
    label: payment_stage = 'Paid'?
    branches:
      - condition: "yes"
        next: end_blocked_already_paid
      - condition: "no"
        next: check_paid_in_advance
  - id: end_blocked_already_paid
    type: end
    result: blocked
    label: Booking already fully paid (409)
  - id: check_paid_in_advance
    type: decision
    label: payment_stage = 'Paid in Advance'?
    branches:
      - condition: "yes"
        next: amount_remaining_balance
      - condition: "no"
        next: check_pay_choice
  - id: amount_remaining_balance
    type: action
    label: amount = total_price - downpayment_amount; payment_choice = 'full' (forced regardless of client input)
    next: check_amount_positive
  - id: check_pay_choice
    type: decision
    label: Customer chose Pay in Full?
    branches:
      - condition: "yes"
        next: amount_full
      - condition: "no"
        next: check_downpayment_available
  - id: amount_full
    type: action
    label: amount = total_price; payment_choice = 'full'
    next: check_amount_positive
  - id: check_downpayment_available
    type: decision
    label: Booking requires a downpayment and downpayment_amount is set?
    branches:
      - condition: "no"
        next: end_blocked_no_downpayment
      - condition: "yes"
        next: amount_downpayment
  - id: end_blocked_no_downpayment
    type: end
    result: blocked
    label: This booking does not require a downpayment (400)
  - id: amount_downpayment
    type: action
    label: amount = downpayment_amount; payment_choice = 'downpayment'
    next: check_amount_positive
  - id: check_amount_positive
    type: decision
    label: amount > 0?
    branches:
      - condition: "no"
        next: end_blocked_nothing_due
      - condition: "yes"
        next: check_online_enabled
  - id: end_blocked_nothing_due
    type: end
    result: blocked
    label: Nothing left to pay on this booking (409)
  - id: check_online_enabled
    type: decision
    label: online_payments_enabled policy toggle ON for this branch?
    branches:
      - condition: "no"
        next: end_blocked_online_disabled
      - condition: "yes"
        next: initiate_paymongo
  - id: end_blocked_online_disabled
    type: end
    result: blocked
    label: Online payments unavailable for this branch (403)
  - id: initiate_paymongo
    type: action
    label: Create PayMongo e-wallet Source (GCash/Maya) for amount
    next: check_paymongo_ok
  - id: check_paymongo_ok
    type: decision
    label: PayMongo Source created successfully?
    branches:
      - condition: "no"
        next: end_blocked_paymongo_error
      - condition: "yes"
        next: insert_pending_transaction
  - id: end_blocked_paymongo_error
    type: end
    result: blocked
    label: Payment service unavailable, try again later (502)
  - id: insert_pending_transaction
    type: action
    label: Insert transactions row (payment_status=Pending, initiated_by='customer', payment_choice, payment_reference=Source id)
    next: redirect_customer
  - id: redirect_customer
    type: action
    label: Customer is redirected to PayMongo-hosted checkout URL and completes GCash/Maya payment
    next: paymongo_webhook
  - id: paymongo_webhook
    type: action
    label: PayMongo calls POST /billing/paymongo/webhook
    next: check_signature
  - id: check_signature
    type: decision
    label: paymongo-signature HMAC valid against raw body?
    branches:
      - condition: "no"
        next: end_error_invalid_signature
      - condition: "yes"
        next: parse_event
  - id: end_error_invalid_signature
    type: end
    result: error
    label: Invalid webhook signature (401), no state change
  - id: parse_event
    type: action
    label: Parse event (id, source id, status)
    next: check_event_status
  - id: check_event_status
    type: decision
    label: event.status = paid (PayMongo 'chargeable' or 'paid')?
    branches:
      - condition: "no"
        next: end_blocked_failed_event
      - condition: "yes"
        next: conditional_update
  - id: end_blocked_failed_event
    type: end
    result: blocked
    label: Non-paid event logged; transaction stays Pending, customer may retry
  - id: conditional_update
    type: action
    label: "Conditional UPDATE: transactions SET payment_status=Fully Paid, webhook_confirmed_at=now() WHERE payment_reference=sourceId AND payment_status='Pending'"
    next: check_update_matched
  - id: check_update_matched
    type: decision
    label: Did a row match (was still Pending)?
    branches:
      - condition: "no"
        next: end_success_noop
      - condition: "yes"
        next: check_customer_initiated
  - id: end_success_noop
    type: end
    result: success
    label: No matching Pending transaction - already confirmed or unknown source; webhook acks 200 with no further action
  - id: check_customer_initiated
    type: decision
    label: initiated_by = 'customer' AND booking_id present?
    branches:
      - condition: "no"
        next: end_success_no_stage
      - condition: "yes"
        next: advance_payment_stage
  - id: end_success_no_stage
    type: end
    result: success
    label: Transaction Fully Paid (not a customer-initiated booking payment, e.g. cashier-portal or misc-sale)
  - id: advance_payment_stage
    type: action
    label: "Best-effort: advancePaymentStage(bookingId, choice = payment_choice=='downpayment' ? 'advance' : 'onsite') - failure logged, not thrown"
    next: end_success_stage_advanced
  - id: end_success_stage_advanced
    type: end
    result: success
    label: Transaction Fully Paid; booking.payment_stage advanced
---

# M08 · Customer Self-Service Online Payment

Machine-readable companion to
[[M08-02-customer-self-service-online-payment|the human-readable version]] in
`Library/golden-fur/workflows/`.
