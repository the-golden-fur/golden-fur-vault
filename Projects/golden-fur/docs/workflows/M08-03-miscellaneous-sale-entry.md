---
id: M08-03-miscellaneous-sale-entry
module: M08
title: Miscellaneous Sale Entry
actors: [Cashier, Receptionist, Supervisor, Admin, Superadmin]
trigger: A money-handling staff member records a sale with no underlying booking (catalog product or freetext item)
outcome_success: transactions row (booking_id NULL, transaction_type = miscellaneous_sale) plus one misc_sale_item line item, Fully Paid or Pending
outcome_failure: [product_not_found]
related_modules: [M10, M08]
source:
  - server/src/features/billing/services/miscSale.service.ts
  - server/src/features/billing/services/creditStub.service.ts
  - server/src/features/billing/services/paymentMethod.service.ts
  - server/src/features/billing/services/paymongo.service.ts
  - server/src/features/billing/modules/validators/billing.validator.ts
  - server/src/features/billing/billing.routes.ts
  - server/src/features/billing/billing.controller.ts
  - server/src/features/billing/billing.types.ts
steps:
  - id: start
    type: start
    label: Staff member records a miscellaneous sale
    next: catalog_check
  - id: catalog_check
    type: decision
    label: product_catalog_id provided?
    branches:
      - condition: "Yes"
        next: fetch_catalog
      - condition: "No"
        next: freetext_item
  - id: fetch_catalog
    type: action
    label: Fetch product_catalog row (name, price)
    next: product_found_check
  - id: product_found_check
    type: decision
    label: Product found?
    branches:
      - condition: "No"
        next: end_product_not_found
      - condition: "Yes"
        next: catalog_item
  - id: end_product_not_found
    type: end
    label: "Blocked — product not found (404)"
    result: blocked
  - id: catalog_item
    type: action
    label: >-
      item = { description: product.name, referenceId: catalog id,
      quantity: input.quantity, unitPrice: product.price (server-snapshotted) }
    next: compute_subtotal
  - id: freetext_item
    type: action
    label: >-
      item = { description: input.description, referenceId: null,
      quantity: 1, unitPrice: input.amount }
    next: compute_subtotal
  - id: compute_subtotal
    type: action
    label: subtotal = unitPrice × quantity
    next: fetch_credit
  - id: fetch_credit
    type: action
    label: >-
      Fetch available credit (creditStub — always ₱0);
      requestedCredit = min(credit_to_apply, available, subtotal)
    next: apply_credit
  - id: apply_credit
    type: action
    label: Apply credit (creditStub — always appliedAmount = 0)
    next: compute_amount_due
  - id: compute_amount_due
    type: action
    label: amountDue = subtotal − creditApplied
    next: online_portal_check
  - id: online_portal_check
    type: decision
    label: Payment method = GCash/Maya AND online_channel = 'portal'?
    branches:
      - condition: "Yes"
        next: create_paymongo_source
      - condition: "No"
        next: cash_check
  - id: create_paymongo_source
    type: action
    label: >-
      Create PayMongo e-wallet Source; payment_status = Pending;
      payment_reference = Source id
    next: insert_transaction
  - id: cash_check
    type: decision
    label: Payment method = Cash?
    branches:
      - condition: "Yes"
        next: confirm_cash
      - condition: "No"
        next: confirm_manual
  - id: confirm_cash
    type: action
    label: Confirm payment_status = Fully Paid; compute change = cash_tendered − amountDue
    next: insert_transaction
  - id: confirm_manual
    type: action
    label: >-
      Confirm payment_status = Fully Paid
      (Card/Bank Transfer/Grabmart/Pickaroo/GCash-Maya walk_in_qr)
    next: insert_transaction
  - id: insert_transaction
    type: action
    label: >-
      Insert transactions row (booking_id = NULL,
      transaction_type = miscellaneous_sale, misc_sale_description,
      credit_applied_amount, total_amount computed server-side)
    next: insert_line_item
  - id: insert_line_item
    type: action
    label: Insert transaction_line_items row (line_item_type = misc_sale_item)
    next: fully_paid_check
  - id: fully_paid_check
    type: decision
    label: payment_status = Fully Paid?
    branches:
      - condition: "Yes"
        next: end_fully_paid
      - condition: "No"
        next: end_pending
  - id: end_fully_paid
    type: end
    label: Transaction Fully Paid — receipt recorded
    result: success
  - id: end_pending
    type: end
    label: >-
      Transaction Pending — staff hands off checkout URL/QR;
      webhook confirms later
    result: success
---

# M08 · Miscellaneous Sale Entry

Machine-readable companion to
[[M08-03-miscellaneous-sale-entry|the human-readable version]] in `Library/golden-fur/workflows/`.
