---
id: M08-01-cashier-checkout
module: M08
title: Cashier Checkout
actors: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
trigger: Money-handling staff opens checkout for a booking whose service status is Completed
outcome_success: transactions row + transaction_line_items created with server-computed total_amount; Fully Paid triggers a payment_confirmed notification, Pending returns a PayMongo checkout URL/QR for the customer
outcome_failure:
  [
    duplicate_transaction,
    booking_not_completed,
    insufficient_cash_tendered,
    paymongo_initiation_failed,
  ]
related_modules: [M03, M10, M11, M12, M13, M14]
source:
  - server/src/features/billing/billing.controller.ts
  - server/src/features/billing/billing.routes.ts
  - server/src/features/billing/billing.types.ts
  - server/src/features/billing/modules/validators/billing.validator.ts
  - server/src/features/billing/services/checkoutAggregation.service.ts
  - server/src/features/billing/services/lineItemSources.service.ts
  - server/src/features/billing/services/discountPromoEvaluation.service.ts
  - server/src/features/billing/services/creditStub.service.ts
  - server/src/features/billing/services/paymentMethod.service.ts
  - server/src/features/billing/services/paymongo.service.ts
  - supabase/migrations/20260731068_m08_create_transactions_schema.sql
  - supabase/migrations/20260731069_m08_create_transaction_line_items_schema.sql
  - supabase/migrations/20260726049_m13_promo_cap_and_transaction_promo_selections.sql
  - supabase/migrations/20260818132_custom_promo_cap_count_type.sql
  - supabase/migrations/20260803083_m03_m08_remove_paid_booking_status.sql
  - supabase/migrations/20260803082_m08_booking_payment_stage.sql
  - supabase/migrations/20260803088_m08_daycare_overnight_pricing.sql
steps:
  - id: start
    type: start
    label: Cashier opens checkout for a booking
    next: check_existing_txn
  - id: check_existing_txn
    type: decision
    label: Does a transaction already exist for this booking_id?
    branches:
      - condition: "yes"
        next: end_blocked_duplicate
      - condition: "no"
        next: fetch_booking
  - id: end_blocked_duplicate
    type: end
    result: blocked
    label: Booking already has a transaction (409)
  - id: fetch_booking
    type: action
    label: Fetch booking for billing (getBookingForBilling)
    next: check_completed
  - id: check_completed
    type: decision
    label: Booking status = Completed?
    branches:
      - condition: "no"
        next: end_blocked_not_completed
      - condition: "yes"
        next: build_service_lines
  - id: end_blocked_not_completed
    type: end
    result: blocked
    label: Service not completed yet - checkout unavailable (409)
  - id: build_service_lines
    type: action
    label: Build service line items by category (Grooming/Misc item-based, Hotel stay reconciliation, Daycare session charge, Veterinary consultation items) plus downpayment-already-collected netting
    next: check_locked_discount_promo
  - id: check_locked_discount_promo
    type: decision
    label: Discount/promo already locked in at booking time (selected_discount_id/selected_promo_id)?
    branches:
      - condition: "yes"
        next: use_locked_snapshot
      - condition: "no"
        next: auto_evaluate
  - id: use_locked_snapshot
    type: action
    label: Render the stored booking.discount_amount/promo_amount snapshot as-is (no re-evaluation)
    next: apply_credit
  - id: auto_evaluate
    type: action
    label: Auto-evaluate scope-matching discounts (Cash-only per booking.payment_method, mandated Senior/PWD gated by eligibility flags) and promos (capped by promo_cap_configuration)
    next: apply_credit
  - id: apply_credit
    type: action
    label: Apply customer credit toward preCreditTotal (creditStub.service.ts - always returns $0 applied)
    next: resolve_payment
  - id: resolve_payment
    type: decision
    label: "Payment method = GCash/Maya AND online_channel = 'portal'?"
    branches:
      - condition: "yes"
        next: initiate_paymongo
      - condition: "no"
        next: check_cash
  - id: check_cash
    type: decision
    label: Payment method = Cash?
    branches:
      - condition: "yes"
        next: validate_cash
      - condition: "no"
        next: confirm_manual
  - id: validate_cash
    type: decision
    label: cash_tendered >= amount due?
    branches:
      - condition: "no"
        next: end_blocked_insufficient_cash
      - condition: "yes"
        next: confirm_manual
  - id: end_blocked_insufficient_cash
    type: end
    result: blocked
    label: Cash tendered is less than amount due (400)
  - id: confirm_manual
    type: action
    label: Confirm payment_status = Fully Paid (Cash additionally computes change = cash_tendered - amount due)
    next: insert_transaction
  - id: initiate_paymongo
    type: action
    label: Create PayMongo e-wallet Source; payment_status = Pending; payment_reference = PayMongo Source id
    next: insert_transaction
  - id: insert_transaction
    type: action
    label: Insert transactions row (subtotal/discount/promo/credit/total_amount computed server-side from line items; processed_by_staff_id set only when Fully Paid)
    next: insert_line_items
  - id: insert_line_items
    type: action
    label: Insert transaction_line_items rows for all service/discount/promo/credit lines
    next: check_promos_selected
  - id: check_promos_selected
    type: decision
    label: Any promos evaluated this checkout?
    branches:
      - condition: "yes"
        next: record_promo_selections
      - condition: "no"
        next: check_fully_paid
  - id: record_promo_selections
    type: action
    label: Insert transaction_promo_selections rows (is_activated = true)
    next: check_fully_paid
  - id: check_fully_paid
    type: decision
    label: payment_status = Fully Paid?
    branches:
      - condition: "yes"
        next: send_notification
      - condition: "no"
        next: end_success_pending
  - id: send_notification
    type: action
    label: Send payment_confirmed notification + email to customer (best-effort - failure logged, not thrown)
    next: end_success_paid
  - id: end_success_paid
    type: end
    result: success
    label: Transaction Fully Paid, receipt recorded
  - id: end_success_pending
    type: end
    result: success
    label: Transaction Pending - checkout URL/QR handed to customer; webhook confirms later, no notification fires at this step
---

# M08 · Cashier Checkout

Machine-readable companion to
[[M08-01-cashier-checkout|the human-readable version]] in
`Library/golden-fur/workflows/`.
