---
title: "M08 · Miscellaneous Sale Entry"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M08
---

# M08 · Miscellaneous Sale Entry

**Actors:** Cashier, Receptionist, Supervisor, Admin, Superadmin (create);
Admin, Superadmin only (update/delete)
**Code:** `server/src/features/billing/services/miscSale.service.ts`,
`server/src/features/billing/services/creditStub.service.ts`,
`server/src/features/billing/services/paymentMethod.service.ts`,
`server/src/features/billing/services/paymongo.service.ts`,
`server/src/features/billing/modules/validators/billing.validator.ts`,
`server/src/features/billing/billing.routes.ts`
**Part of:** [[M08-sales-billing|M08 · Sales & Billing]]

A misc sale records a transaction with no underlying booking
(`booking_id = NULL`, `transaction_type = 'miscellaneous_sale'`) — a
catalog product or a freetext item, sold by a money-handling staff member,
reusing the same credit-application and payment-confirmation logic as a
cashier's [[M08-01-cashier-checkout|counter checkout]] rather than
duplicating it.

```mermaid
flowchart TD
    A(["START: Staff member records\na miscellaneous sale"]) --> B{"product_catalog_id\nprovided?"}
    B -- "Yes" --> C["Fetch product_catalog row\n(name, price)"]
    C --> D{"Product found?"}
    D -- "No" --> E(["END: Blocked — product\nnot found (404)"])
    D -- "Yes" --> F["item = {description: product.name,\nreferenceId: catalog id, quantity: input.quantity,\nunitPrice: product.price (server-snapshotted)}"]
    B -- "No" --> G["item = {description: input.description,\nreferenceId: null, quantity: 1,\nunitPrice: input.amount}"]
    F --> H["subtotal = unitPrice × quantity"]
    G --> H
    H --> I["Fetch available credit\n(creditStub — always ₱0);\nrequestedCredit = min(credit_to_apply,\navailable, subtotal)"]
    I --> J["Apply credit\n(creditStub — always\nappliedAmount = 0)"]
    J --> K["amountDue = subtotal − creditApplied"]
    K --> L{"Payment method = GCash/Maya\nAND online_channel = 'portal'?"}
    L -- "Yes" --> M["Create PayMongo e-wallet Source;\npayment_status = Pending;\npayment_reference = Source id"]
    L -- "No" --> N{"Payment method\n= Cash?"}
    N -- "Yes" --> O["Confirm payment_status = Fully Paid;\ncompute change = cash_tendered − amountDue"]
    N -- "No" --> P["Confirm payment_status = Fully Paid\n(Card/Bank Transfer/Grabmart/Pickaroo/\nGCash-Maya walk_in_qr)"]
    M --> Q["Insert transactions row\n(booking_id = NULL, transaction_type =\nmiscellaneous_sale, misc_sale_description,\ncredit_applied_amount, total_amount\ncomputed server-side)"]
    O --> Q
    P --> Q
    Q --> R["Insert transaction_line_items row\n(line_item_type = misc_sale_item)"]
    R --> S{"payment_status\n= Fully Paid?"}
    S -- "Yes" --> T(["END: Transaction Fully Paid —\nreceipt recorded"])
    S -- "No" --> U(["END: Transaction Pending —\nstaff hands off checkout URL/QR;\nwebhook confirms later"])
```

## Notes

- Exactly one item shape is allowed per sale — `product_catalog_id` (+
  optional `quantity`) or `description` + `amount` — enforced by the
  request validator before this diagram's logic runs; the diagram shows
  only the resulting catalog-lookup vs. freetext branches. The freetext
  branch trusts `input.amount` as-is since there's no catalog row to
  server-snapshot a price from.
- Credit application is the same always-₱0 stub `checkoutAggregation.service.ts`
  uses ([[M08-01-cashier-checkout|Cashier Checkout]]) — `credit_applied_amount`
  is written to the transaction but never actually reduces `total_amount`
  yet (see [[M10-credit-balance-management|M10]]).
- `customer_id` is required (`transactions.customer_id` is `NOT NULL`) even
  though there's no booking to derive it from — every misc sale is tied to
  an existing customer profile, which credit redemption also needs.
- Unlike cashier checkout, no `payment_confirmed` notification fires here,
  whether the sale resolves Fully Paid immediately or later via the
  PayMongo webhook — the webhook confirms a misc sale's `Pending` row the
  same way it confirms any other (see
  [[M08-02-customer-self-service-online-payment|the webhook flow]]), but
  only advances `payment_stage` when a `booking_id` is present, which a
  misc sale never has.
- `processed_by_staff_id` is only set when the sale resolves Fully Paid
  immediately, left unattributed for a Pending PayMongo-portal sale — same
  rule as cashier checkout.
- Update (Admin/Superadmin only) recomputes `line_total`/`total_amount`
  server-side whenever the item shape changes, never trusting a
  client-supplied total; it does not re-run credit or payment-method logic.
  Delete is a hard delete of the transaction row, also Admin/Superadmin
  only. Neither is diagrammed here — both are straightforward field-level
  CRUD with no further branching.

## Relationship to other modules

Shares credit-application (stub) with [[M10-credit-balance-management|M10]]
and the payment-confirmation/webhook mechanism with
[[M08-02-customer-self-service-online-payment|M08's online payment flow]].
Feeds [[M14-report-management|M14]] under its own DSR category.
