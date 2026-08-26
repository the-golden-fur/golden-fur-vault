---
title: "M08 · Cashier Checkout"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M08
---

# M08 · Cashier Checkout

**Actors:** Cashier, Receptionist, Supervisor, Admin, Superadmin
**Code:** `server/src/features/billing/services/checkoutAggregation.service.ts`,
`server/src/features/billing/services/lineItemSources.service.ts`,
`server/src/features/billing/services/discountPromoEvaluation.service.ts`,
`server/src/features/billing/services/paymentMethod.service.ts`,
`server/src/features/billing/services/creditStub.service.ts`,
`server/src/features/billing/services/paymongo.service.ts`
**Part of:** [[M08-sales-billing|M08 · Sales & Billing]]

A money-handling staff member checks out a booking whose underlying service
has already completed: the system assembles service/discount/promo line
items, applies any credit (currently a stub), resolves the payment method,
and persists one `transactions` row plus its `transaction_line_items` —
`total_amount` is always the server-computed `SUM(line_total)`, never a
client-supplied figure.

```mermaid
flowchart TD
    A(["START: Cashier opens checkout\nfor a booking"]) --> B{"Does a transaction\nalready exist for\nthis booking_id?"}
    B -- "Yes" --> C(["END: Blocked — booking already\nhas a transaction (409)"])
    B -- "No" --> D["Fetch booking for billing\n(getBookingForBilling)"]
    D --> E{"Booking status\n= Completed?"}
    E -- "No" --> F(["END: Blocked — service not\ncompleted yet (409)"])
    E -- "Yes" --> G["Build service line items by category\n(Grooming/Misc item-based, Hotel stay\nreconciliation, Daycare session charge,\nVeterinary consultation items) +\n'Downpayment already collected' netting"]
    G --> H{"Discount/promo already\nlocked in at booking time?\n(selected_discount_id /\nselected_promo_id)"}
    H -- "Yes" --> I["Render the stored\nbooking.discount_amount /\npromo_amount snapshot as-is"]
    H -- "No" --> J["Auto-evaluate scope-matching\ndiscounts (Cash-only, mandated\nSenior/PWD gated by eligibility flags)\nand promos (capped by\npromo_cap_configuration)"]
    I --> K["Apply customer credit\n(creditStub.service.ts —\nalways $0 applied)"]
    J --> K
    K --> L{"Payment method = GCash/Maya\nAND online_channel = 'portal'?"}
    L -- "Yes" --> M["Create PayMongo e-wallet Source;\npayment_status = Pending;\npayment_reference = Source id"]
    L -- "No" --> N{"Payment method = Cash?"}
    N -- "Yes" --> O{"cash_tendered\n>= amount due?"}
    O -- "No" --> P(["END: Blocked — cash tendered\nis less than amount due (400)"])
    O -- "Yes" --> Q["Confirm payment_status = Fully Paid;\ncompute change = cash_tendered − amount due"]
    N -- "No" --> R["Confirm payment_status = Fully Paid\n(Card/Bank Transfer/Grabmart/Pickaroo/\nGCash-Maya walk_in_qr)"]
    M --> S["Insert transactions row\n(subtotal/discount/promo/credit/total_amount\ncomputed server-side from line items)"]
    Q --> S
    R --> S
    S --> T["Insert transaction_line_items rows\nfor all service/discount/promo/credit lines"]
    T --> U{"Any promos evaluated\nthis checkout?"}
    U -- "Yes" --> V["Insert transaction_promo_selections\nrows (is_activated = true)"]
    U -- "No" --> W{"payment_status\n= Fully Paid?"}
    V --> W
    W -- "Yes" --> X["Send payment_confirmed notification\n+ email to customer\n(best-effort — logged, not thrown)"]
    W -- "No" --> Y(["END: Transaction Pending —\ncashier hands off checkout URL/QR;\nwebhook confirms later,\nno notification fires here"])
    X --> Z(["END: Transaction Fully Paid —\nreceipt recorded"])
```

## Notes

- `booking.payment_method` (locked in at booking creation) — not the
  checkout-time payment method chosen here — gates whether
  `evaluateDiscounts` runs at all: it returns nothing unless that stored
  value is `'Cash'`, mirroring the same Cash-only-for-discounts rule
  `resolveDiscountAndPromo` enforces at booking time (`discountPromoEvaluation.service.ts`).
  Promos have no such payment-method gate.
- Promo combinability is capped by `promo_cap_configuration` (branch row, or
  the system-wide default): a `percentage`/`flat` cap applies promos
  largest-value-first and trims the last one that would cross the cap; a
  `count` cap instead applies the largest-value N promos in full and drops
  the rest — no partial trimming for a count cap, since a "count" has no
  fractional promo.
- **Credit application is a stub as shipped** — `creditStub.service.ts`
  always returns `appliedAmount: 0` regardless of what the cashier
  requested; `credit_applied_amount` is written to the transaction but
  never actually reduces `total_amount` yet (see [[M10-credit-balance-management|M10]]).
- A Hotel booking nets out its downpayment from the `stays` record
  (`getHotelLineItems`), not the generic `downpaymentNettingLines` helper
  every other category uses — both produce an equivalent negative
  `discount`-typed line, just sourced differently.
- `payment_confirmed` only fires here, at checkout time, when the resulting
  transaction is immediately `Fully Paid`. A checkout that goes `Pending`
  (GCash/Maya portal channel) does **not** get this notification re-fired
  when [[M08-02-customer-self-service-online-payment|the webhook later confirms it]] —
  flagged in the code as a known gap, not yet reflected in the module note's
  Open Items.
- `processed_by_staff_id` is only set when the transaction resolves
  `Fully Paid` immediately — a `Pending` PayMongo-portal transaction is left
  unattributed to a staff member at creation time.

## Relationship to other modules

Reads discounts/promos from [[M12-discount-management|M12]]/[[M13-maintenance-packages-services-promos|M13]] and
credit balances (stub) from [[M10-credit-balance-management|M10]]. Sends the
`payment_confirmed` notification via [[M11-notification|M11]]. Feeds
[[M14-report-management|M14]] reporting. Booking data originates in
[[M03-appointment-booking|M03]] and its category-specific modules
(M04–M07).
