# Issue #104 Verification: DSR + analytics dashboard UI

**Issue:** #104 — feat(reports): DSR + analytics dashboard UI
**Owner:** Alarie
**Branch:** `feat/dsr-analytics-ui`
**Base:** `dev`
**Depends on:** #102, #103
**Sprint:** Sprint 6 Epic A — M14 Report Management

## Overview

`DailySalesReportPage` (breakdown table, totals row, distinct misc-sales section, Superadmin branch toggle, date filter, print stylesheet) and `AnalyticsDashboardPage` (revenue/bookings/cancellation-rate cards + time-filter selector, Superadmin-only).

### Deviations from the Guide, flagged for the reviewer

- **No Figma reference was available in this pass** — the Guide's own Prerequisites note that a Figma layout should be confirmed before finalizing this UI. Layout here follows the existing table/card conventions already established by `MiscSaleManagementPage`/`CashierCheckoutPage` rather than a specific mockup; flag for design review before considering this issue's visual polish final.
- Both pages gate client-side the same way `MiscSaleManagementPage` does (`listStaff` self-lookup → role check → `<Navigate>` away if disallowed), mirroring that existing precedent rather than introducing a new gating pattern.

## What Changed

- **Added** `client/src/features/reports/reports.types.ts`, `api/reports.api.ts`.
- **Added** `pages/DailySalesReportPage/DailySalesReportPage.tsx` (+ `.module.css`, including a `@media print` block).
- **Added** `pages/AnalyticsDashboardPage/AnalyticsDashboardPage.tsx` (+ `.module.css`).
- **Added** `client/src/features/reports/reports.routes.tsx` — `/staff/reports/dsr`, `/staff/reports/analytics` (plus #105's two routes, same file).
- **Modified** `client/src/routes.tsx` — registers `reportsRoutes`.
- **Modified** `client/src/features/staff/config/staffDashboard.config.ts` — wires the previously-`to`-less "Branch Reports" tile (Admin + Supervisor dashboards) to `/staff/reports/dsr`.

## Acceptance Criteria Map

| AC                                                                                                           | Automated                                                                                                    | Manual            |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ | ----------------- |
| AC-1 DSR table renders breakdown by service type + payment method with a totals row                          | `npx tsc --noEmit` confirms the render shape compiles against `DailySalesReport`'s type                      | Section D, step 2 |
| AC-2 misc-sales section appears distinctly, not merged into the breakdown                                    | code inspection: separate `<section>` in `DailySalesReportPage.tsx`                                          | step 2            |
| AC-3 Admin/Supervisor see only their own branch; Superadmin can toggle/combine                               | code inspection: `isSuperadmin` gates the `<select>`; non-Superadmin passes `viewerBranchId` unconditionally | step 3            |
| AC-4 date filter applies correctly; DSR is printable with clean formatting                                   | manual print-preview required (not automatable)                                                              | step 4            |
| AC-5 analytics dashboard shows revenue/bookings/cancellation rate for all five time filters, Superadmin-only | code inspection + route-level `requireRole`                                                                  | step 5            |

## Automated Verification

From `client/`:

```powershell
npx tsc --noEmit
npx eslint src/features/reports
```

Expected: both clean, no errors (the `react-hooks/set-state-in-effect` rule was specifically checked against — filter-change effects don't reset `isLoading` synchronously, matching this repo's existing data-fetching convention).

## Manual Verification

### Prerequisites

`npm run dev` in both `client/` and `server/`; seeded transactions for today at both branches; an Admin, a Supervisor, and a Superadmin login.

### D. Steps

1. Navigate to `/staff/reports/dsr` as an Admin — confirm no branch toggle is shown, only that Admin's own branch's data.
2. As Superadmin, toggle between branches and "All branches" — confirm the breakdown table, totals row, and misc-sales section update accordingly and never merge into each other.
3. Change the date filter to a day with no transactions — confirm the table renders an empty/zero state without erroring.
4. Click "Print" — confirm the print preview hides the branch/date controls and the Print button itself, rendering a clean printable layout.
5. Navigate to `/staff/reports/analytics` as Superadmin — confirm all five time-filter options render revenue/bookings/cancellation-rate cards; as an Admin, confirm the same URL redirects away (`<Navigate>` to `/staff/settings`).

### E. Cleanup

None — read-only verification.
