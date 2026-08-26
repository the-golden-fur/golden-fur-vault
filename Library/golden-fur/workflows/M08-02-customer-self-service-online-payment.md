---
title: "M08 · Customer Self-Service Online Payment"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M08
---

# M08 · Customer Self-Service Online Payment

**Actors:** Customer, (PayMongo webhook — unauthenticated system caller)
**Code:** `server/src/features/billing/services/customerBookingPayment.service.ts`,
`server/src/features/billing/services/webhookConfirmation.service.ts`,
`server/src/features/billing/services/paymongo.service.ts`,
`server/src/features/billing/routes/paymongoWebhook.routes.ts`
**Part of:** [[M08-sales-billing|M08 · Sales & Billing]]

A customer pays for their own booking from the portal (My Bookings > Pay) —
full price or just the required downpayment — via GCash/Maya. This is a
real PayMongo redirect checkout, distinct from a cashier's
[[M08-01-cashier-checkout|counter checkout]]: it always creates a `Pending`
`transactions` row tagged `initiated_by = 'customer'`, and only the PayMongo
webhook — not any cashier action — later confirms it and advances the
booking's `payment_stage`.

```mermaid
flowchart TD
    A(["START: Customer taps Pay\non their own booking"]) --> B{"booking.customer_id\n= requester?"}
    B -- "No" --> C(["END: Blocked — not this\ncustomer's booking (403)"])
    B -- "Yes" --> D{"payment_stage\n= 'Paid'?"}
    D -- "Yes" --> E(["END: Blocked — booking already\nfully paid (409)"])
    D -- "No" --> F{"payment_stage\n= 'Paid in Advance'?"}
    F -- "Yes" --> G["amount = total_price − downpayment_amount;\npayment_choice = 'full' (forced)"]
    F -- "No" --> H{"Customer chose\n'Pay in Full'?"}
    H -- "Yes" --> I["amount = total_price;\npayment_choice = 'full'"]
    H -- "No" --> J{"Booking requires a downpayment\nand downpayment_amount is set?"}
    J -- "No" --> K(["END: Blocked — this booking does\nnot require a downpayment (400)"])
    J -- "Yes" --> L["amount = downpayment_amount;\npayment_choice = 'downpayment'"]
    G --> M{"amount > 0?"}
    I --> M
    L --> M
    M -- "No" --> N(["END: Blocked — nothing left\nto pay on this booking (409)"])
    M -- "Yes" --> O{"online_payments_enabled\npolicy toggle ON for\nthis branch? (M09)"}
    O -- "No" --> P(["END: Blocked — online payments\nunavailable for this branch (403)"])
    O -- "Yes" --> Q["Create PayMongo e-wallet\nSource for `amount`"]
    Q --> R{"PayMongo Source\ncreated successfully?"}
    R -- "No" --> S(["END: Blocked — payment service\nunavailable, try again later (502)"])
    R -- "Yes" --> T["Insert transactions row\n(payment_status = Pending,\ninitiated_by = 'customer',\npayment_choice, payment_reference = Source id)"]
    T --> U["Customer is redirected to the\nPayMongo-hosted checkout URL\nand completes GCash/Maya payment"]
    U --> V["PayMongo calls\nPOST /billing/paymongo/webhook"]
    V --> W{"paymongo-signature HMAC\nvalid against raw body?"}
    W -- "No" --> X(["END: Error — invalid webhook\nsignature (401), no state change"])
    W -- "Yes" --> Y["Parse event\n(id, source id, status)"]
    Y --> Z{"event.status = paid?\n('chargeable' or 'paid')"}
    Z -- "No" --> AA(["END: Blocked — non-paid event logged;\ntransaction stays Pending,\ncustomer may retry"])
    Z -- "Yes" --> AB["Conditional UPDATE: transactions\nSET payment_status = Fully Paid,\nwebhook_confirmed_at = now()\nWHERE payment_reference = sourceId\nAND payment_status = 'Pending'"]
    AB --> AC{"Did a row match\n(was still Pending)?"}
    AC -- "No" --> AD(["END: No-op — already confirmed or\nunknown source; webhook acks 200"])
    AC -- "Yes" --> AE{"initiated_by = 'customer'\nAND booking_id present?"}
    AE -- "No" --> AF(["END: Transaction Fully Paid\n(not a customer-initiated\nbooking payment)"])
    AE -- "Yes" --> AG["Best-effort: advancePaymentStage\n(choice = 'advance' if payment_choice\nwas 'downpayment', else 'onsite')"]
    AG --> AH(["END: Transaction Fully Paid;\nbooking.payment_stage advanced"])
```

## Notes

- The three "amount" branches (advance-forced full balance, Pay in Full,
  downpayment-only) are mutually exclusive and evaluated in that order —
  `payment_stage = 'Paid in Advance'` overrides whatever `pay_in_full` the
  client sent, since the only thing left to collect is the remaining
  balance.
- `initiated_by`/`payment_choice` default to `'staff'`/`null` for every
  other transaction (including a cashier checkout that also happens to use
  the GCash/Maya `'portal'` channel — see
  [[M08-01-cashier-checkout|Cashier Checkout]]). The webhook confirms
  **any** `Pending` row by `payment_reference` regardless of who initiated
  it, but only advances `payment_stage` when `initiated_by = 'customer'`
  and a `booking_id` is present — a misc-sale's `Pending` row (no
  `booking_id`) or a staff-initiated portal transaction is confirmed the
  same way but never touches `payment_stage`.
- The webhook always responds `200` once the signature is valid, even for a
  `'failed'` event or a no-op re-delivery — a non-2xx here would make
  PayMongo retry redelivery indefinitely for an event this service already
  finished handling.
- The conditional `UPDATE ... WHERE payment_status = 'Pending'` is the sole
  idempotency guard — a second webhook delivery for an already-confirmed
  transaction matches no row and is a safe no-op, with no separate
  event-id dedup table.
- `advancePaymentStage` failures are logged, not rethrown — the webhook
  must still ack `200` for PayMongo even if the booking-side update fails;
  the transaction itself is already `Fully Paid` by that point regardless.

## Relationship to other modules

Reads the `online_payments_enabled` toggle from
[[M09-policy-enforcement|M09]] (per-branch or system-wide). Advances
`bookings.payment_stage` via [[M03-appointment-booking|M03]]'s
`advancePaymentStage`. Shares its webhook confirmation mechanism with any
other `Pending` PayMongo transaction, including a cashier's
[[M08-01-cashier-checkout|counter checkout]] and a
[[M08-03-miscellaneous-sale-entry|miscellaneous sale]].
