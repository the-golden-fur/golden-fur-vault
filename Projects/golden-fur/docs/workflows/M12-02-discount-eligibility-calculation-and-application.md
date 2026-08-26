---
id: M12-02-discount-eligibility-calculation-and-application
module: M12
title: Discount Eligibility Calculation & Application
actors: [Receptionist, Cashier, Supervisor, Admin, Superadmin]
trigger: A staff member selects a discount while creating a booking, or a completed booking with no discount pre-selected reaches the cashier checkout preview
outcome_success: A discount amount is computed and reflected in the booking's discount_amount / the transaction's discount line items
outcome_failure:
  [
    not_money_handling_staff,
    non_cash_payment_method,
    discount_not_available_at_branch,
    discount_scope_mismatch,
  ]
related_modules: [M03, M08]
source:
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/billing/services/discountPromoEvaluation.service.ts
  - server/src/features/billing/services/checkoutAggregation.service.ts
  - server/src/features/billing/services/lineItemSources.service.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/billing/modules/validators/billing.validator.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - server/src/features/billing/billing.routes.ts
  - server/src/features/discounts/discounts.routes.ts
  - server/src/shared/app.routes.ts
  - client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx
  - client/src/features/billing/pages/CashierCheckoutPage/CashierCheckoutPage.tsx
steps:
  - id: start_booking
    type: start
    label: Staff creates a booking and selects a discount_id (payment step)
    next: role_check
  - id: role_check
    type: decision
    actor: [Receptionist, Cashier, Supervisor, Admin, Superadmin]
    label: Requester role in BOOKING_MARK_PAID_ROLES?
    branches:
      - condition: "No"
        next: end_blocked_role
      - condition: "Yes"
        next: cash_check
  - id: end_blocked_role
    type: end
    label: "Blocked — 403, only money-handling staff may apply a discount"
    result: blocked
  - id: cash_check
    type: decision
    label: payment_method = Cash?
    branches:
      - condition: "No"
        next: end_blocked_cash
      - condition: "Yes"
        next: load_discount
  - id: end_blocked_cash
    type: end
    label: "Blocked — 400, discounts are Cash-only (ID verified in person)"
    result: blocked
  - id: load_discount
    type: action
    label: Load the discount by id
    next: branch_check
  - id: branch_check
    type: decision
    label: Available at the booking's branch?
    branches:
      - condition: "No"
        next: end_blocked_branch
      - condition: "Yes"
        next: scope_check
  - id: end_blocked_branch
    type: end
    label: "Blocked — 400, not available at this branch"
    result: blocked
  - id: scope_check
    type: decision
    label: Scope matches a selected item or the booking's service category?
    branches:
      - condition: "No"
        next: end_blocked_scope
      - condition: "Yes"
        next: compute_booking_amount
  - id: end_blocked_scope
    type: end
    label: "Blocked — 400, doesn't apply to selected items"
    result: blocked
  - id: compute_booking_amount
    type: action
    label: Compute discount_amount (Percentage of total_price, or Flat capped at total_price)
    next: store_selection
  - id: store_selection
    type: action
    label: Store selected_discount_id and discount_amount on the booking row
    next: booking_completed
  - id: booking_completed
    type: action
    label: Booking runs its service and reaches status = Completed
    next: preview_stored
  - id: start_checkout
    type: start
    label: Booking reaches Completed with no discount pre-selected; cashier opens checkout preview
    next: checkout_cash_check
  - id: checkout_cash_check
    type: decision
    label: payment_method = Cash?
    branches:
      - condition: "No"
        next: end_no_discount_lines
      - condition: "Yes"
        next: attest_eligibility
  - id: end_no_discount_lines
    type: end
    label: No discount lines (non-Cash checkout)
    result: success
  - id: attest_eligibility
    type: action
    actor: [Cashier]
    label: Cashier attests eligibility via senior_citizen_eligible / pwd_eligible checkboxes
    next: evaluate_discounts
  - id: evaluate_discounts
    type: action
    label: >-
      evaluateDiscounts fetches every is_active discount and keeps only
      those available at this branch, scope-matching an item/category, and
      -- if mandated (Senior/PWD by exact name) -- matching the attested
      eligibility flag
    next: compute_checkout_amounts
  - id: compute_checkout_amounts
    type: action
    label: Compute each kept discount's amount (Percentage of subtotal, or Flat) as a negative discount line
    next: preview_shown
  - id: preview_stored
    type: action
    label: Checkout preview renders the stored booking-time discount as-is (no re-evaluation)
    next: preview_shown
  - id: preview_shown
    type: action
    label: Preview shown to cashier
    next: confirm_checkout
  - id: confirm_checkout
    type: action
    actor: [Cashier]
    label: Cashier confirms payment method and tender; checkoutBooking persists the transaction
    next: end_transaction_persisted
  - id: end_transaction_persisted
    type: end
    label: Transaction and line items persisted; discount reflected in transactions.discount_amount
    result: success
---

# M12 · Discount Eligibility Calculation & Application

Machine-readable companion to
[[M12-02-discount-eligibility-calculation-and-application|the human-readable version]] in `Library/golden-fur/workflows/`.
