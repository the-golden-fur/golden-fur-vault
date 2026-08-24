# Issue #105 Verification: cage occupancy report + transaction history UI

**Issue:** #105 — feat(reports): cage occupancy report + transaction history UI
**Owner:** Alarie
**Branch:** `feat/cage-occupancy-transaction-history-ui`
**Base:** `dev`
**Depends on:** #102; Sprint 4 Epic A (cages) merged
**Sprint:** Sprint 6 Epic A — M14 Report Management

## Overview

`CageOccupancyReport` (real-time count grouped by size category, reusing `--color-cage-status-*` unchanged) and `TransactionHistoryTable` (filterable by customer/pet/date range/service type, all composable).

### Deviations from the Guide, flagged for the reviewer

- **No dedicated "page" file for either component** — the Guide's Files sheet lists only the two `components/` files for this issue, with no page wrapper. Both are routed directly as full-page components (`/staff/reports/cage-occupancy`, `/staff/reports/transaction-history`) rather than introducing an unlisted `ReportsPage.tsx` container, matching the Guide's exact file list.
- **Customer/pet filters are `<select>` dropdowns**, not a search-as-you-type picker — `listCustomers()`/`listCustomerPets()` (existing APIs) populate them. A dedicated customer/pet search component would be a reasonable follow-up for a large customer base, but wasn't in the Guide's file list for this issue.

## What Changed

- **Added** `client/src/features/reports/components/CageOccupancyReport/CageOccupancyReport.tsx` (+ `.module.css`) — grouped by size (S/M/L/XL), badges reuse `--color-cage-status-*` (Sprint 4 Epic A, #79) unchanged.
- **Added** `client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx` (+ `.module.css`) — customer/pet/date-range/service-type filters, all composable.
- **Modified** `client/src/features/reports/reports.routes.tsx` — registers both routes (same file as #104's two pages).
- **Modified** `client/src/features/staff/config/staffDashboard.config.ts` — adds "Cage Occupancy" and "Transaction History" tiles to the Admin/Supervisor dashboards' Supervisor section, alongside #104's "Branch Reports" tile.

## Acceptance Criteria Map

| AC                                                                                          | Automated                                                                                             | Manual            |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 cage occupancy returns a real-time count by size category, correct at load             | `npx tsc --noEmit` confirms render shape; correctness verified against `cages` table directly         | Section D, step 2 |
| AC-2 transaction history filterable by customer/pet/date range/service type, all combinable | code inspection: `TransactionHistoryTable`'s filter state all feed one `getTransactionHistory()` call | step 3            |

## Automated Verification

From `client/`:

```powershell
npx tsc --noEmit
npx eslint src/features/reports/components
```

Expected: both clean, no errors (the customer-select `onChange` clears `pets`/`selectedPetId` synchronously in the event handler rather than in an effect, avoiding the `react-hooks/set-state-in-effect` cascading-render lint rule).

## Manual Verification

### Prerequisites

`npm run dev` in both `client/` and `server/`; seeded cages across S/M/L/XL with a mix of statuses; a customer with 2+ pets and transaction history spanning multiple dates/service categories.

### D. Steps

1. Navigate to `/staff/reports/cage-occupancy` — confirm counts per size/status match `select size, status, count(*) from cages group by size, status;` run directly against the DB.
2. As Superadmin, toggle the branch selector — confirm counts update to that branch only.
3. Navigate to `/staff/reports/transaction-history`. Select a customer — confirm the pet dropdown populates with only that customer's pets. Combine a date range + service type filter — confirm results narrow further than either filter alone, and clearing the customer filter resets the pet dropdown to "All pets".

### E. Cleanup

None — read-only verification.
