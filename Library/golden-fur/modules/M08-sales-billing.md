---
title: "M08 · Sales & Billing"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M08 · Sales & Billing

**Layer:** Back-office
**Code:** `features/billing` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The aggregation/checkout point: payment methods, PayMongo online
payment (available to customers directly, not just cashier-recorded),
credit application, Miscellaneous Sale entries, and discounts/promos.

The line-item builder that used to be Grooming-specific
(`getItemBasedLineItems`) is generalized and reused by Miscellaneous
Sale and any other item-based booking, since bookings carry
`booking_items` rather than a single service/package.

Discounts/promos applied at booking time ([[M03-appointment-booking|M03]]/[[M12-discount-management|M12]]) arrive
at checkout already locked in via `bookings.discount_amount`/
`promo_amount`; the cashier UI still allows applying eligible
discounts/promos not selected earlier. Government-mandated discounts
(Senior Citizen 20%, PWD) apply automatically once the cashier flags
eligibility.

## Payment processing

PayMongo online payment fees are sourced from PayMongo's published
rates and shown as a non-blocking informational step — they don't
change the recorded booking total.

## Payments Queue

`/staff/billing/payments-queue` is the **only** screen that advances
`bookings.status` (Start/Complete), advances/overrides
`bookings.payment_stage`, or performs the Admin/Superadmin status
override — the Receptionist Bookings Queue ([[M03-appointment-booking|M03]]) is read-only for
these. It also owns Start/Complete/override for the Misc category
(Initial Assessment/Reassessment — [[M13-maintenance-packages-services-promos|M13]]), which has no execution
queue of its own. Payment-stage-advance access: Superadmin, Admin,
Supervisor, Receptionist, Cashier. Status override: Admin/Superadmin
only.

## Customer self-service online payment

Customers can pay for their own booking from the portal (My Bookings >
Pay) — full payment, or the downpayment only if still required — via
the same GCash/Maya PayMongo integration. Gated by a policy toggle,
`online_payments_enabled` ([[M09-policy-enforcement|M09]]), per branch or system-wide; when
off, the Pay button stays visible but disabled with a tooltip.
`transactions.initiated_by` (`staff`/`customer`) and
`transactions.payment_choice` (`full`/`downpayment`) distinguish this
path — only a customer-initiated payment auto-advances `payment_stage`
on webhook confirmation.

## Credit application at checkout

The cashier can apply some or all of a customer's branch-locked,
non-transferable credit balance, capped at the lesser of balance or
transaction total, with atomic deduction and partial application — as
_designed_. **As shipped, checkout still reads that balance through a
stub** — credit issuance/balances/history ([[M10-credit-balance-management|M10]]) are fully live, but a
cashier can't yet actually apply credit to reduce a transaction total.

## Downpayment netting

For a booking whose item required a downpayment, checkout automatically
nets out what was already collected: a "Downpayment already collected"
negative line item for Grooming/Misc/Daycare/Veterinary; Hotel has its
own downpayment-netting logic based on the stay record ([[M05-pet-hotel-boarding-management|M05]]).

## Miscellaneous Sale Entry

A transaction type with no booking record (`booking_id` NULL,
`transaction_type = miscellaneous_sale`), used mainly for credit
redemption against non-inventory retail items, under a dedicated DSR
category. Distinct from the _Misc_ `service_category` (Initial
Assessment/Reassessment — [[M13-maintenance-packages-services-promos|M13]]), which does have a booking record and
flows through the Payments Queue normally.

## Relationship to other modules

Receives transaction data from [[M03-appointment-booking|M03]]–[[M07-health-veterinary-management|M07]] (`booking_items`).
Applies credits from [[M10-credit-balance-management|M10]] (issuance side only — see stub above) and
discounts/promos from [[M12-discount-management|M12]]/[[M13-maintenance-packages-services-promos|M13]]. Reads the online-payments toggle and
downpayment rules from [[M09-policy-enforcement|M09]]/M13. Feeds [[M14-report-management|M14]]. Cashier-facing;
also visible to Admins and Supervisors.

## Open items

- Credit redemption at checkout is a stub (see above) — the single
  biggest outstanding gap in the system.
- Reschedule fees are calculated/logged ([[M09-policy-enforcement|M09]]) but never posted as a
  billable line item here, even though `reschedule_fee` is a valid
  `transaction_line_items` type.
