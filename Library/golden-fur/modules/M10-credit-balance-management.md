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
**non-transferable** between branches, and **non-refundable as cash**,
with a 30-day expiry from issuance by default (configurable —
[[M09-policy-enforcement|M09]]).

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

A Credit Management page (Cashier/Admin) lists balances and history;
customers see their own balance plus a 7-day expiry-approaching badge on
the portal.

## Status

Credit can be correctly issued, tracked, and expired end to end — but
**applying it to reduce a transaction total at checkout is not wired
up** on the billing side ([[M08-sales-billing|M08]] still reads a stub there), so the
DSR's credit-usage figures ([[M14-report-management|M14]]) read zero until that redemption
path ships. This module did not exist in the database at all before
2026-08-05.

## Workflows

- [[M10-01-cancellation-to-credit-conversion|Cancellation-to-Credit Conversion]]
- [[M10-02-credit-expiry-sweep|Credit Expiry Sweep]]
- [[M10-03-credit-balance-and-history-access|Credit Balance & History Access]]

## Relationship to other modules

Issued by [[M09-policy-enforcement|M09]] on a qualifying cancellation. Intended to be consumed
in [[M08-sales-billing|M08]] at checkout (not yet wired — see above). Visible in the
customer portal ([[M02-customer-portal-pet-management|M02]]) and cashier/admin views. Feeds [[M14-report-management|M14]]'s DSR
credit-usage section.
