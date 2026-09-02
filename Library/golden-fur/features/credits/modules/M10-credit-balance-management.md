---
title: "M10 · Credit Balance Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M10 · Credit Balance Management

**Layer:** Back-office
**Code:** `features/credits` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Tracks customer credit balances from cancelled Hotel downpayments — and,
since downpayment is now a per-transaction policy applying to any
category ([[M03-appointment-booking|M03]]/[[M09-policy-enforcement|M09]]), from any qualifying cancelled
booking that had one applied. Credits are
**branch-specific** (`credit_balances` is unique per customer + branch),
**non-transferable** between branches, and **non-refundable as cash**.
Expiry is per-branch policy: a `credit_expiry_mode` enum (`none` /
`rolling` — `credit_expiry_days` after issuance, default 30 / `fixed_date` —
one calendar date for the whole branch), replacing the former on/off
`credit_expiry_enabled` boolean since
`feat/credit-expiry-visibility-and-config`. A mode/day/date change is
**retroactive** — see
[[M10-05-credit-expiry-policy-retroactive-restamp|M10-05]]. Configured via
Settings → Config → Policies ([[M09-policy-enforcement|M09]]).

## Issuance

Atomic: a single `issue_credit()` database function upserts the balance
and inserts a signed `credit_transactions` row (issuance / redemption /
expiry — issuance positive, redemption/expiry negative) in one
transaction, called from the cancellation flow ([[M09-policy-enforcement|M09]]) whenever a
cancellation qualifies. Expiry is swept by `expire_credits()` — run on a
schedule (`pg_cron`) where available, otherwise via an
Admin/Superadmin-triggerable endpoint — writing an offsetting expiry
transaction and decrementing the balance for anything past its expiry
date.

A Credit Management page (Cashier/Admin) lists balances and history.
Customers see their per-branch balances, the soonest expiry date + amount,
days-left, and a full expiry schedule on the `/portal/credits` page and the
navbar wallet-pill hover popover — both read views of
[[M10-03-credit-balance-and-history-access|`GET /credits/balances`]]'s
`next_expires_at` / `next_expires_amount` fields.

## Redemption

Since the 2026-09-01 payment/transactions rework, credit **redemption is
live**. The atomic `redeem_credit()` RPC (`20260901155`) — the mirror of
`issue_credit()` — locks the `credit_balances` row, re-checks
`balance ≥ amount`, decrements it, and writes a signed-negative
`redemption` `credit_transactions` row linked to the `transactions` row it
paid. Two callers:

- **Checkout** (`checkoutAggregation.service.ts` via `applyCredit`) —
  partial application allowed, capped at the lesser of balance or total.
- **Pay with credit** on a `Pending` `booking_payment` transaction
  (`payTransactionWithCredit`) — **full-cover only**, from the portal
  Transaction History page or staff on the customer's behalf. See
  [[M10-04-paying-a-transaction-with-credit|M10-04]].

`payment_method` gained a `'Credit'` value (`20260901152`) for the settled
transaction. The DSR credit-usage section ([[M14-report-management|M14]])
now reports real figures.

## Status

Credit can be issued, tracked, redeemed, and expired end to end. This
module did not exist in the database at all before 2026-08-05.

## Workflows

- [[M10-01-cancellation-to-credit-conversion|Cancellation-to-Credit Conversion]]
- [[M10-02-credit-expiry-sweep|Credit Expiry Sweep]]
- [[M10-03-credit-balance-and-history-access|Credit Balance & History Access]]
- [[M10-04-paying-a-transaction-with-credit|Paying a Transaction with Credit]]
- [[M10-05-credit-expiry-policy-retroactive-restamp|Credit-Expiry Policy Change — Retroactive Re-stamp]]

## Relationship to other modules

Issued by [[M09-policy-enforcement|M09]] on a qualifying cancellation.
Redeemed in [[M08-sales-billing|M08]] — at checkout and via the
pay-with-credit path — through the same `settle_transaction` RPC that rolls
up `bookings.payment_status` ([[M03-appointment-booking|M03]]). Visible in
the customer portal ([[M02-customer-portal-pet-management|M02]]) and
cashier/admin views. Feeds [[M14-report-management|M14]]'s DSR credit-usage
section.
