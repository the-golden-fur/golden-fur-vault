# Issue #42 Verification: Promos CRUD + Automatic Expiry

**Issue:** #42 — feat(maintenance): promos CRUD backend + automatic expiry deactivation
**Owner:** Matthew
**Branch:** `feat/promos-crud-and-expiry` (delivered bundled with #39–#44)
**Base:** `dev`
**Depends on:** #41 merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Promos CRUD over `promos` + `promo_scope`, plus the three-layer expiry
mechanism the Guide asked for:

1. **Preferred — pg_cron:** migration `...032` creates
   `deactivate_expired_promos()` and a `DO` block that schedules it daily at
   00:05 **only if the pg_cron extension is already installed** (its approval
   is an Open Item). Nothing breaks when it isn't.
2. **Fallback — application scheduler:**
   `server/src/features/maintenance/jobs/promoExpiry.job.ts` calls the same
   SQL function via RPC daily at 00:05 server time (plain `setTimeout` chain —
   no new dependency). Started by `app.ts` outside the test env. Known
   limitation, flagged per the Guide: it only runs while the server process is
   alive.
3. **Defensive read-time filter (AC-5):** every active-promos GET excludes
   `end_date < today` rows regardless of job state, so a delayed job can never
   surface an expired promo to the booking flow.

Other Dev-Notes rules implemented: `scope_type = 'specific'` requires ≥ 1
scope row and `'all_services'` requires none (validator, not just
controller); condition-based promos (`condition_note`, NULL dates) are exempt
from expiry; manual deactivation always available.

## What Changed

- **Added** `services/promos.service.ts` (+ spec, 11 tests) — list (with the
  defensive filter and `branch_scope` matching where `'both'` matches either
  branch), get, create (+ scope rows), update (merged-state cross-field
  validation, scope replacement/clearing).
- **Added** `jobs/promoExpiry.job.ts` (+ spec, 7 tests) — `runPromoExpiryJob`,
  `msUntilNextRun`, `startPromoExpiryScheduler` (returns a stop function;
  failures logged, never fatal).
- **Added** `tests/maintenance.integration.spec.ts` — HTTP-level coverage for
  #40–#42 per-role (the Guide attributes this file to this issue).
- **Modified** `maintenance.controller.ts` / `maintenance.routes.ts` /
  `maintenance.types.ts` — promo handlers, routes, types.
- **Modified** `server/src/app.ts` — starts the fallback scheduler
  (`NODE_ENV !== 'test'`).

### Endpoints

| Method | Path                                                           | Roles            |
| :----- | :------------------------------------------------------------- | :--------------- |
| GET    | `/maintenance/promos` (`?branch_scope=&include_inactive=true`) | all staff        |
| GET    | `/maintenance/promos/:id`                                      | all staff        |
| POST   | `/maintenance/promos`                                          | Admin/Superadmin |
| PATCH  | `/maintenance/promos/:id`                                      | Admin/Superadmin |

`include_inactive=true` is the #47 admin-management view; the default list is
the consumer view with both filters applied.

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all pass — `promos.service.spec.ts`, `promoExpiry.job.spec.ts`
(includes fake-timer scheduler tests: fires at 00:05, reschedules daily,
survives a failing run), `maintenance.integration.spec.ts`.

## Postman Verification (AC-1, AC-4, AC-5, AC-6)

Same setup as issue #40's doc. Import
`promos-crud-and-expiry.postman_collection.json`, fill `base_url` and the
four credential variables, save, start the server, run **in order (1 → 10)**:

| #   | Request                          | Expected                                           |
| :-- | :------------------------------- | :------------------------------------------------- |
| 1–2 | Logins                           | `200`, tokens set                                  |
| 3   | AC-1: POST date-bounded promo    | `201` with dates, exclusivity, branch scope        |
| 4   | AC-1: POST condition-based promo | `201`, `condition_note` set, dates `null`          |
| 5   | POST already-expired promo       | `201` (setup for 6)                                |
| 6   | AC-5: GET active promos          | `200`, expired promo **absent**, live ones present |
| 7   | POST dates + condition together  | `400`                                              |
| 8   | AC-4: PATCH manual deactivation  | `200`, `is_active: false`                          |
| 9   | AC-6: PATCH as non-admin         | `403`                                              |
| 10  | Cleanup                          | `200`                                              |

## SQL Verification (AC-2, AC-3)

Open **Supabase Studio → SQL Editor → New query** and run
`promos-crud-and-expiry.sql` (this folder) block by block:

1. Seeds three `__expiry_test` promos: expired / future / condition-based.
2. `select deactivate_expired_promos()` → returns `1`.
3. Per-row check: expired → `false`; future → `true`; **condition-based
   (NULL end_date) → still `true` (AC-3)**.
4. Second run returns `0` (idempotent).
5. Optional: shows the pg_cron job row if the extension is installed.
6. Cleanup (`DELETE 3`).

AC-2's "verified in a test that fast-forwards or mocks the date" is the unit
suite: the SQL function's date comparison is exercised here with a genuinely
past `end_date`, and the scheduler's timing is fake-timer-tested in
`promoExpiry.job.spec.ts`.

## Acceptance Criteria Checklist

- [x] **AC-1:** POST with name, dates or condition note, type/value, scope,
      branch scope, exclusivity — Postman 3–4; unit tests.
- [x] **AC-2:** expired promo auto-deactivated — SQL Blocks 2–3; scheduler
      unit tests (fake timers).
- [x] **AC-3:** NULL end_date never auto-deactivated — SQL Block 3.
- [x] **AC-4:** manual deactivation regardless of end_date — Postman 8; unit
      test.
- [x] **AC-5:** GET never returns an expired promo even before the job runs —
      Postman 5–6; unit test asserting the read-time filter.
- [x] **AC-6:** non-admin write 403 — Postman 9; integration test.
