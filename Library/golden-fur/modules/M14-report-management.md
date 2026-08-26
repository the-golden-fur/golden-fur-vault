---
title: "M14 · Report Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M14 · Report Management

**Layer:** Back-office
**Code:** `features/reports` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Daily Sales Report (DSR), Cage Occupancy Report, Transaction History,
and a Superadmin Analytics Dashboard — backed by real SQL functions,
not just designed. `get_daily_sales_report()`, `get_cage_occupancy_report()`,
and `get_analytics_summary()` didn't exist in the database until
2026-08-05.

## Daily Sales Report

`get_daily_sales_report(branch, date)` returns a breakdown by service
category and payment method, totals, a credit-usage section (from
`credit_transactions` redemption rows), and a Miscellaneous Sales
total/row list — no individual transaction line-item array (the
`DailySalesReport` TS type has no such field; that granularity is only
available via the separate Transaction History report below). Passing
no branch returns a Superadmin combined-branches view. The credit-usage section reads zero until
checkout's credit-redemption stub ([[M08-sales-billing|M08]]/[[M10-credit-balance-management|M10]]) is replaced with
the real thing.

## Cage Occupancy Report

A real-time snapshot of cage status per size category (S/M/L/XL) —
Available, Occupied, Reserved, Under Maintenance — computed straight off
the `cages` table. Available to receptionists, admins, and supervisors.

## Transaction History

A searchable, filterable log of past transactions, computed directly
from a plain filtered query (no backing SQL function). Staff access:
Superadmin, Admin, Supervisor, Receptionist, Cashier — at `GET
/reports/transaction-history`. A parallel customer-facing My
Transactions page (`GET /reports/my-transaction-history`, scoped
server-side to the caller) lives at `/portal/transactions`.

## Analytics Dashboard (Superadmin)

`get_analytics_summary(branch, time_filter)` returns total revenue,
booking count, cancelled count, and cancellation rate, filterable by
Today / This Week / This Month / This Year / All Time, per branch or
combined. Gated to Superadmin at the route layer, distinct from the
operational DSR ledger.

Status-based breakdowns anywhere in this module reflect the current
five-value booking status (Pending/In Progress/Completed/Cancelled/
No-show) plus the independent `payment_stage` (Unpaid/Paid in
Advance/Paid) — see [[M03-appointment-booking|M03]].

## Workflows

- [[M14-01-daily-sales-report-generation|Daily Sales Report Generation]]
- [[M14-02-cage-occupancy-report-generation|Cage Occupancy Report Generation]]
- [[M14-03-transaction-history-search|Transaction History Search]]
- [[M14-04-analytics-dashboard-summary|Analytics Dashboard Summary]]

## Relationship to other modules

Depends on [[M08-sales-billing|M08]] (transaction data), [[M05-pet-hotel-boarding-management|M05]] (cage status), and
[[M03-appointment-booking|M03]] (booking history, `booking_items`, `payment_stage`). A future Staff
Utilization Report is anticipated to depend on [[M01-staff-authentication-access-control|M01]]'s branch
operating-hours/lunch-break configuration.
