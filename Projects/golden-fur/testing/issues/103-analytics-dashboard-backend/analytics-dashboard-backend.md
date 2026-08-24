# Issue #103 Verification: analytics dashboard aggregation backend

**Issue:** #103 — feat(reports): analytics dashboard aggregation backend
**Owner:** Matthew
**Branch:** `feat/analytics-dashboard-backend`
**Base:** `dev`
**Depends on:** #102
**Sprint:** Sprint 6 Epic A — M14 Report Management

## Overview

`get_analytics_summary()` (created alongside #102's two functions in the same migration file) + `analytics.service.ts`, enforcing the Superadmin-only restriction at the application layer in addition to the route's own `requireRole` gate.

### Deviations from the Guide, flagged for the reviewer

- None beyond #102's migration-numbering note (this function lives in the same `20260805101` file).
- Cancellation rate uses the current five-value `booking_status` enum (Pending/In Progress/Completed/Cancelled/No-show) — `'Paid'` was retired from that enum before this function was written, per the Guide's own Spec Tension note.

## What Changed

- **Added** `server/src/features/reports/services/analytics.service.ts` — `getAnalyticsSummary()`, validating `time_filter` against the five documented values and rejecting non-Superadmin callers with a 403 even though the route already gates on role (defense in depth).
- The `GET /reports/analytics` route itself was added alongside #102's other three routes in `reports.routes.ts`/`reports.controller.ts`, gated by `ANALYTICS_READ_ROLES = ['Superadmin']` (distinct from `REPORTS_READ_ROLES`).

## Acceptance Criteria Map

| AC                                                                                              | Automated                                                                                                   | Manual            |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 aggregations for revenue/bookings/cancellations correct for all five time filters          | not yet unit-tested (see #102's Open Items — same DB-harness gap)                                           | Section D, step 2 |
| AC-2 a non-Superadmin request is rejected                                                       | route-level `requireRole(['Superadmin'])` + service-level check in `analytics.service.ts`                   | step 3            |
| AC-3 `p_branch_id = NULL` returns combined figures; a specific branch returns that branch alone | code inspection: `WHERE p_branch_id is null or ... = p_branch_id` in both revenue and booking-count queries | step 4            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx eslint src/features/reports/services/analytics.service.ts
```

Expected: both clean, no errors.

## Manual Verification

### Prerequisites

Same as #102 — migrations through `101` applied, seeded transactions/bookings across both branches and a spread of dates (to exercise `today`/`this_week`/`this_month`/`this_year`/`all_time` meaningfully).

### D. Steps

1. `select get_analytics_summary(null, 'today');`, then `'this_week'`, `'this_month'`, `'this_year'`, `'all_time'` — confirm `total_revenue`/`booking_count`/`cancellation_rate` grow monotonically (each wider window is a superset of the narrower ones, for the same seed data).
2. `GET /reports/analytics?time_filter=today` as a Superadmin session — confirm 200 with the summary.
3. Repeat as an Admin (non-Superadmin) session — confirm 403.
4. `GET /reports/analytics?branch_id=<branch id>&time_filter=all_time` vs. no `branch_id` — confirm the branch-scoped figure is less than or equal to the combined figure.

### E. Cleanup

None — read-only verification.
