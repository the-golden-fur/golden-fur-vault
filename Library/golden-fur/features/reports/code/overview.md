---
title: Reports — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, reports]
project: golden-fur
---

Gives staff and customers ways to see what's already happened in the business — a cashier's Daily Sales Report, a live snapshot of which cages are free, a searchable log of every transaction, and (for Superadmins) a revenue/booking analytics dashboard. Nothing here creates or changes business data; it only reads and summarizes it.

**Part of:** [[M14-report-management]]

## Client-side (`client/src/features/reports/`)

### pages/
- **`DailySalesReportPage.tsx`** — the DSR a cashier or manager prints at end of day: a service/payment-method breakdown table with a totals row, a credit-usage line, and a separate Miscellaneous Sales table. Admin/Supervisor are locked to their own branch; Superadmin gets a branch dropdown (including "All branches"). Has a date picker and a Print button. Calls `getDailySalesReport`.
- **`AnalyticsDashboardPage.tsx`** — Superadmin-only revenue/bookings/cancellation-rate dashboard with a branch selector and a time-period selector (Today/This week/This month/This year/All time). Calls `getAnalyticsSummary`, then renders the `BranchRevenueComparisonChart` component below the summary cards.
- **`CustomerTransactionHistoryPage.tsx`** — the customer-portal page at `/portal/transactions` showing a signed-in customer their own transactions (table or board view), with filter/sort/search and a "Pay" flow for any Pending charge (account credit, GCash, or Maya) plus a way to pay down part of a Partially Paid booking's remaining balance. Always calls the customer-scoped `getMyTransactionHistory` (never passes a customer_id — the server infers the caller).

### components/
- **`CageOccupancyReport/CageOccupancyReport.tsx`** — the staff-facing cage occupancy page (route `/staff/reports/cage-occupancy`), open to Admin/Supervisor/Superadmin/Receptionist. Shows a per-size (S/M/L/XL) summary of Available/Occupied/Reserved/Under Maintenance counts (`getCageOccupancyReport`), plus a separate searchable/sortable/filterable list of individual cages pulled from the Hotel module's own `getCageGrid`, always scoped to the viewer's own branch.
- **`TransactionHistoryTable/TransactionHistoryTable.tsx`** — the full staff Transactions page (route `/staff/reports/transaction-history`), open to Superadmin/Admin/Supervisor/Receptionist/Cashier. Notion-style filter tiles + sort + search, a table/board view switcher, a "Mark as paid" modal (cash/card/bank transfer/credit) for Pending charges, and an "Add a balance payment" modal for Partially Paid bookings. Calls `getTransactionHistory`.
- **`TransactionHistoryTable/TransactionBoard.tsx`** — the kanban-style board view shared by both the staff and customer transaction pages: fixed columns for Pending/Partially Paid/Fully Paid, one card per transaction, with a slot for page-specific corner actions (a "..." menu for staff, a Pay button for customers).
- **`TransactionHistoryTable/transactionDisplay.ts`** — small label-formatting helpers (`paymentChoiceLabel`, `transactionTypeLabel`, `paymentStatusLabel`) shared by the table and board views so wording like "Due payment" instead of the raw "Pending" stays consistent everywhere.
- **`TransactionHistoryTable/transactionFilterFields.ts`** — defines the filter/sort field configurations for the staff and customer transaction views (date range, service, transaction type, payment choice, status, plus customer/pet for staff), and the functions that turn a filter-tile selection into query params for `getTransactionHistory` (`deriveServerParams`, `deriveStatusFilter`, `deriveSortKey`) or into client-side sort comparators (`COMPARATORS`).
- **`BranchRevenueComparisonChart/BranchRevenueComparisonChart.tsx`** — a donut chart (via Recharts) comparing Makati vs. Southwoods revenue for the dashboard's selected time period, always both branches regardless of the page's own branch dropdown. Calls `getAnalyticsSummary` once per branch.
- **`CageAvailabilityWidget/CageAvailabilityWidget.tsx`** — a Superadmin dashboard widget listing available-cage counts for both branches at once (calls `getCageOccupancyReport` once per branch, since the endpoint itself only reports one branch — or all combined — per call).
- **`GoalStatsBoard/GoalStatsBoard.tsx`** — a Superadmin dashboard header showing three tables (total appointments, appointments per service, revenue), each comparing this calendar month so far against all of last month against a +10% "goal" computed client-side off last month's actual (there is no goals table in the database). Reuses `listBookings` and `getTransactionHistory` — no dedicated goals endpoint.
- **`RecentTransactionsWidget/RecentTransactionsWidget.tsx`** — a Superadmin dashboard widget listing the 5 most recent transactions across every branch, with a "View all" link to the full Transactions page. Calls `getTransactionHistory` with no filters and slices the top 5 client-side.

### api/
- **`reports.api.ts`** — every fetch call this feature makes to the server: `getDailySalesReport`, `getCageOccupancyReport`, `getTransactionHistory` (staff, with a `TransactionHistoryFilters` object), `getMyTransactionHistory` (customer-scoped, no customer/branch filter to pass), and `getAnalyticsSummary`. Each returns `{ data, error }` so a page can show a plain-language error banner instead of crashing.

### Other
- **`reports.types.ts`** — the client's mirror of the server's report shapes (`DailySalesReport`, `CageOccupancyRow`, `TransactionRecord`, `AnalyticsSummary`, etc.) plus the `AnalyticsTimeFilter` union.
- **`reports.routes.tsx`** — wires up the five routes this feature owns: four staff routes under `/staff/reports/*` behind `StaffAuthGuard`, and `/portal/transactions` behind `CustomerAuthGuard`. Role checks happen server-side (see below); each page additionally redirects away client-side for a disallowed viewer, as defense in depth.
- **`utils/payableBalances.ts`** — `payableBalances()`, a pure function shared by both transaction pages: given a list of loaded transactions, it works out which bookings are "Partially Paid" with no charge already awaiting settlement and a positive amount still owed, so the page can offer a "pay part of the balance" button per booking.
- CSS module files (`*.module.css`, one per page/component) hold styling only — skipped individually here.

## Server-side (`server/src/features/reports/`)

### Controller & routes
- **`reports.controller.ts`** — one controller function per endpoint (`dailySalesReportController`, `cageOccupancyReportController`, `transactionHistoryController`, `customerTransactionHistoryController`, `analyticsSummaryController`). Each pulls the caller's role/branch off the authenticated request, reads query params, calls the matching service, and returns JSON or a mapped error status. The customer-facing controller trusts `req.user.sub` directly as the `customer_id` filter — a customer's JWT can only ever be their own.
- **`reports.routes.ts`** — mounts `GET /reports/dsr`, `/reports/cage-occupancy`, `/reports/transaction-history`, `/reports/my-transaction-history`, and `/reports/analytics`. Each route (except the customer one) is behind `jwtMiddleware` + `sessionTimeoutMiddleware` + `requireRole(...)` with a different allowed-role list per endpoint, plus `requireBranch` to resolve the caller's own branch. The customer route only requires a valid, logged-in session — no staff role at all.

### Service
- **`services/dailySalesReport.service.ts`** — `getDailySalesReport()` calls the Postgres function `get_daily_sales_report(branch, date)`. Enforces that a non-Superadmin can only ever see their own branch (ignoring any `branch_id` they pass); a Superadmin passing no branch gets a combined view.
- **`services/cageOccupancy.service.ts`** — `getCageOccupancyReport()` calls `get_cage_occupancy_report(branch)`, with the same branch-scoping rule as the DSR service.
- **`services/analytics.service.ts`** — `getAnalyticsSummary()` calls `get_analytics_summary(branch, time_filter)`, after checking the caller is a Superadmin (403 otherwise) and that `time_filter` is one of the five valid values (400 otherwise).
- **`services/transactionHistory.service.ts`** — `listTransactionHistory()`, the one report NOT backed by a SQL function — it's a plain, composable Supabase query against the `transactions` table (each filter chains an extra `.eq()`/`.gte()`/`.lt()` — same pattern as `booking.service.ts`'s `listBookings()`). It joins `bookings` (switching to an inner join only when filtering by pet or service category, so misc sales without a booking still show up otherwise), then does a second batched query against `customer_profiles` to resolve each row's `customer_name` for display — this is the file worth reading closely if you want to understand how the transaction list is actually assembled.

### Types & validators
- **`reports.types.ts`** — the server's report shapes (mirrored on the client), plus the four role-allowlist constants each route checks against: `REPORTS_READ_ROLES` (Superadmin/Admin/Supervisor), `TRANSACTION_HISTORY_READ_ROLES` (adds Cashier), `CAGE_OCCUPANCY_READ_ROLES` (adds Receptionist), and `ANALYTICS_READ_ROLES` (Superadmin only).

## How it connects

A report page calls one of the five functions in `reports.api.ts`, which hits a route in `reports.routes.ts`; the matching controller in `reports.controller.ts` checks the caller's role/branch and calls the matching service. Three of the four report types (DSR, cage occupancy, analytics) are thin wrappers around Postgres functions written directly against booking/transaction/cage data; only Transaction History builds its query in application code. The underlying data comes from other features — bookings and payments from [[M08-sales-billing|M08 Sales & Billing]], live cage status from [[M05-pet-hotel-boarding-management|M05 Pet Hotel]], and booking records from [[M03-appointment-booking|M03 Appointment Booking]] — this feature only reads and aggregates it, never writes to it.
