# Issue #102 Verification: get_daily_sales_report() function + DSR backend

**Issue:** #102 — chore(db)+feat(reports): get_daily_sales_report() function + DSR backend
**Owner:** Matthew
**Branch:** `chore/reporting-functions`
**Base:** `dev`
**Depends on:** Sprint 5 Epic A #82 (transactions) merged; Sprint 5 Epic B #90 (credit_balances) merged
**Sprint:** Sprint 6 Epic A — M14 Report Management

## Overview

Creates `get_daily_sales_report()`, `get_cage_occupancy_report()`, and `get_analytics_summary()` (the latter is #103's function, sharing this same migration file per the Guide) — all read/aggregation layers over already-merged M03/M05/M08 tables, no new schema. Also adds `transactionHistory.service.ts`, a plain filtered Supabase query (not a SQL function).

### Deviations from the Guide, flagged for the reviewer

- **Migration renumbered twice.** Same story as #96: the Guide planned `099`; Sprint 5 Epic B took `094-099` on `dev` mid-branch, so this migration is `20260805101` (following #96's `100`).
- **Credit-usage section now reads real `credit_transactions`.** The Guide specified reading `credit_transactions where transaction_type = 'redemption'`. At the start of this issue, that table didn't exist (Epic B hadn't merged yet) — a first draft sourced this section from `transactions.credit_applied_amount` instead. Once Epic B merged mid-branch, the function was rewritten to read `credit_transactions` directly (joined through `credit_balances` for branch-scoping), matching the Guide's original intent exactly. Note: `billing/services/creditStub.service.ts` (Epic A's checkout) still hasn't been swapped to actually redeem credit at checkout — that swap is explicitly out of Epic B's own scope — so this section will correctly report zero activity until that swap lands, not because the query is wrong.
- `get_daily_sales_report()` returns a single `jsonb` object (not a row set) so the breakdown/credit-usage/misc-sale sections can each keep their own shape independently, rather than forcing a lowest-common-denominator row type across all three.

## What Changed

- **Added** `supabase/migrations/20260805101_m14_create_reporting_functions.sql` — the three functions.
- **Added** `server/src/features/reports/reports.types.ts`, `services/dailySalesReport.service.ts`, `services/cageOccupancy.service.ts`, `services/transactionHistory.service.ts`, `reports.controller.ts`, `reports.routes.ts` — `GET /reports/dsr`, `/reports/cage-occupancy`, `/reports/transaction-history` (Admin/Supervisor/Superadmin) plus `/reports/analytics` (#103, Superadmin-only, same routes file).
- **Modified** `server/src/shared/app.routes.ts` — registers `reportsRoutes`.

## Acceptance Criteria Map

| AC                                                                                                 | Automated                                                                                   | Manual            |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 correctly totals transactions by service type and payment method for any branch/date          | not yet unit-tested (no vitest DB harness in this repo — see Open Items)                    | Section D, step 2 |
| AC-2 credit usage and misc sales in their own sections, not merged into the service-type breakdown | code inspection: `v_credit_usage`/`v_misc_sales` are separate jsonb keys                    | step 2            |
| AC-3 `p_branch_id = NULL` aggregates across both branches                                          | code inspection: every query's `WHERE` clause is `p_branch_id is null or ... = p_branch_id` | step 3            |
| AC-4 `get_cage_occupancy_report()` matches the cages table exactly at query time                   | plain `count(*) group by size, status` over `cages`, no caching                             | step 4            |
| AC-5 transaction history filterable by customer/pet/date range/service type, composable            | code inspection: `transactionHistory.service.ts`'s conditional query builder                | step 5            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx eslint src/features/reports
```

Expected: both clean, no errors.

## Manual Verification

### Prerequisites

`supabase db reset` with migrations through `101` applied; a few seeded `transactions`/`transaction_line_items` rows across both branches and both `transaction_type`s; a Hotel cancellation that issued credit (Epic B) if testing the credit-usage section with real data.

### D. Steps

1. `select get_daily_sales_report(null, current_date);` in the SQL Editor — confirm the returned jsonb has `breakdown`, `totals`, `credit_usage`, `misc_sales`, `misc_sales_total` keys, each populated from today's seeded transactions.
2. Confirm `credit_usage.total_credit_applied` reflects `credit_transactions` rows of type `redemption` for today, not merged into `breakdown`.
3. `select get_daily_sales_report('<branch id>', current_date);` — confirm only that branch's transactions are counted; `select get_daily_sales_report(null, current_date);` — confirm both branches combined.
4. `select * from get_cage_occupancy_report(null);` — cross-check the returned counts against `select size, status, count(*) from cages group by size, status;` directly.
5. `GET /reports/transaction-history?customer_id=...&date_from=...&service_category=Hotel` (Admin/Supervisor session) — confirm all filters compose (combining customer + date + category narrows results further than any one alone).

### E. Cleanup

None — read-only verification, no writes to roll back.

## Open Items

- No automated test harness exists in this repo for exercising real Postgres functions (`get_daily_sales_report`, `get_cage_occupancy_report`) — verification here is manual-only via the Supabase SQL Editor, consistent with how prior schema-only issues (e.g. #89, #90) were verified in this same batch.
