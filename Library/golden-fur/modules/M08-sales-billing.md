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

## Payment/transactions model rework (2026-09-01, migrations 20260901150–157)

A booking's payment state is now a **straight rollup of its `transactions`
rows**, not a separately-advanced track:

- `bookings.payment_stage` (`Unpaid` / `Paid in Advance` / `Paid`) and its
  enum were **dropped** (`20260901150`). `bookings.payment_status` reuses
  the **same enum as `transactions.payment_status`** — `Pending` /
  `Partially Paid` / `Fully Paid` — and is maintained by the
  `settle_transaction()` SQL RPC and the app-side
  `recomputeBookingPaymentStatus` (webhook path). There is no booking-level
  payment enum of its own any more.
- [[M03-01-new-appointment-booking|Booking creation]] collects **no payment
  method** — only an optional `payment_scheme` (`full` / `downpayment`) —
  and emits **one `Pending` `booking_payment` transaction** (the whole net
  total, or just the down payment). Veterinary is skipped (priced during
  the visit).
- A cashier settles those transactions on the **Transactions page**
  (`/staff/billing/transactions`) — see
  [[M08-04-recording-a-counter-payment|Recording a Counter Payment]]. This
  replaced the old Payments Queue.
- `settle_transaction()` flips a transaction to `Fully Paid` with its real
  method/details and recomputes the parent booking's `payment_status` in
  one Postgres transaction. `add_booking_payment()` adds a balance charge
  (`payment_choice = 'balance'`) as a new `Pending` transaction.
- `payment_method` gained a `'Credit'` value (`20260901152`); a customer
  (or staff on their behalf) can settle a whole `Pending` `booking_payment`
  transaction from account credit — see
  [[M10-04-paying-a-transaction-with-credit|M10-04]].
- The slot-hold gate now keys on `payment_status != 'Pending'` instead of
  `payment_stage != 'Unpaid'` (`get_staff_availability` migration
  `20260901156`; `SLOT_HOLD_PAID_OR_FILTER` mirrored in the
  grooming/consultation queue filters).
- DSR and analytics aggregations now count only
  `payment_status = 'Fully Paid'` transactions (`20260901157`) — see
  [[M14-01-daily-sales-report-generation|M14-01]] /
  [[M14-04-analytics-dashboard-summary|M14-04]].

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

## Payments Queue — removed

`/staff/billing/payments-queue` is **gone**. Its responsibilities were
split:

- **Recording payment** moved to the Transactions page
  (`/staff/billing/transactions`) — per-transaction, not per-booking — see
  [[M08-04-recording-a-counter-payment|Recording a Counter Payment]].
  Access: `BILLING_STAFF_ROLES` (Superadmin, Admin, Supervisor,
  Receptionist, Cashier).
- **Start/Complete, the Misc-category (Initial Assessment/Reassessment)
  Start/Complete + pet-assessment capture, and the Admin/Superadmin
  status override** were folded into the Receptionist Bookings Queue
  (`ReceptionistBookingsQueuePage`, [[M03-appointment-booking|M03]]) —
  which is therefore no longer read-only for status.

## Customer self-service online payment

Customers can pay for their own booking from the portal (My Bookings >
Pay) — full payment, or the downpayment only if still required — via
the same GCash/Maya PayMongo integration. Gated by a policy toggle,
`online_payments_enabled` ([[M09-policy-enforcement|M09]]), per branch or system-wide; when
off, the Pay button stays visible but disabled with a tooltip.
`transactions.initiated_by` (`staff`/`customer`) and
`transactions.payment_choice` (`full`/`downpayment`/`balance`) distinguish
this path — a customer-initiated payment is rolled up by
`recomputeBookingPaymentStatus` (which replaced `advancePaymentStage`) on
webhook confirmation, while staff counter payments use the
`settle_transaction` RPC; both then run
`applyFirstBookingPaymentSideEffects`. See
[[M08-02-customer-self-service-online-payment|Customer Self-Service Online
Payment]].

## Credit application

- **At checkout** (`checkoutAggregation.service.ts`): the cashier can apply
  some or all of a customer's branch-locked, non-transferable credit
  balance, capped at the lesser of balance or transaction total, with
  atomic deduction and partial application. `applyCredit` /
  `creditStub.service.ts` is **no longer a stub** — it wraps the atomic
  `redeem_credit()` RPC (`20260901155`).
- **On a Pending booking-payment transaction**: a customer (or staff on
  their behalf) can settle the _whole_ charge from credit — full-cover
  only, no partial — via `POST /billing/transactions/:id/pay-with-credit`,
  the **Pay with credit** button on the portal Transaction History page.
  See [[M10-04-paying-a-transaction-with-credit|M10-04]].

## Downpayment netting

For a booking whose per-transaction downpayment policy was in effect
([[M09-policy-enforcement|M09]]), checkout automatically nets out what
was already collected: a "Downpayment already collected" negative line
item for Grooming/Misc/Daycare/Veterinary; Hotel has its own
downpayment-netting logic based on the stay record ([[M05-pet-hotel-boarding-management|M05]]).

## Miscellaneous Sale Entry

A transaction type with no booking record (`booking_id` NULL,
`transaction_type = miscellaneous_sale`), used mainly for credit
redemption against non-inventory retail items, under a dedicated DSR
category. Distinct from the _Misc_ `service_category` (Initial
Assessment/Reassessment — [[M13-maintenance-packages-services-promos|M13]]), which does have a booking record and
its own `booking_payment` transaction like any other category.

## Workflows

- [[M08-01-cashier-checkout|Cashier Checkout]]
- [[M08-02-customer-self-service-online-payment|Customer Self-Service Online Payment]]
- [[M08-03-miscellaneous-sale-entry|Miscellaneous Sale Entry]]
- [[M08-04-recording-a-counter-payment|Recording a Counter Payment]]

## Relationship to other modules

Receives the initial `booking_payment` transaction from
[[M03-appointment-booking|M03]] and the category modules
[[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]].
Redeems credit from [[M10-credit-balance-management|M10]] (issuance **and**
redemption now both live) and applies discounts/promos from
[[M12-discount-management|M12]]/[[M13-maintenance-packages-services-promos|M13]].
Reads the online-payments toggle and downpayment policy from
[[M09-policy-enforcement|M09]]. Feeds [[M14-report-management|M14]].
Cashier-facing; also visible to Admins and Supervisors.

## Open items

- Reschedule fees are calculated/logged ([[M09-policy-enforcement|M09]]) but never posted as a
  billable line item here, even though `reschedule_fee` is a valid
  `transaction_line_items` type.
- `checkoutAggregation.service.ts` / `/billing/checkout` still exist
  server-side after the rework; whether the cashier checkout screen is
  still reachable from the staff console (vs. superseded by the
  Transactions page) needs confirmation — see
  [[M08-01-cashier-checkout|M08-01]].
