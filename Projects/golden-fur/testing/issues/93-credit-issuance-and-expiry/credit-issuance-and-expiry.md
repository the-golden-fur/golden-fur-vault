# Issue #93 Verification: credit issuance on qualifying cancellation + credit expiry job

**Issue:** #93 — feat(credits): credit issuance on qualifying cancellation + credit expiry job
**Owner:** Matthew
**Branch:** `feat/credit-issuance-and-expiry` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** #90, #91
**Sprint:** Sprint 5 Epic B — M10 Credit Balance Management

## Overview

On a qualifying cancellation, converts the non-refundable Hotel downpayment into a branch-locked `credit_balances` increment plus an issuance `credit_transactions` row (#91 calls into this). A scheduled job expires unused credit after the configured duration. Unaffected by this epic's revision-note corrections — scope, shape, and rationale are unchanged from the original draft.

### Deviations from the Guide, flagged for the reviewer

- **`issueCredit()` wraps a Postgres RPC (`issue_credit()`, added in migration `097`, #90's doc), not a two-step `select`-then-`update`.** AC-1 requires the increment and the issuance row to be atomic; see #90's doc for the full rationale.
- **`expire_credits()`'s per-issuance consumption model uses the added `credit_transactions.expired_at` column** (#90's doc) rather than trying to infer "already expired" from the ledger shape alone — with no per-issuance remaining-amount tracking in the Design sheet's literal schema and no real redemption mechanism wired yet (Epic A's `creditStub.service.ts` always applies 0), the honest simplest model is: each `'issuance'` row is swept independently, oldest-`expires_at`-first, expiring `least(issuance amount, current balance)` and marking `expired_at` so it's never reprocessed.
- **`creditExpiry.job.ts` is a thin RPC wrapper (`runCreditExpiryJob()`) with no in-process scheduler**, unlike `promoExpiry.job.ts`'s own `startPromoExpiryScheduler()`. The Guide's Files sheet describes this file as "Admin-triggerable 'run expiry now' endpoint over migration 097's `expire_credits()` function" — an on-demand trigger, not a background loop — so no scheduler-start wiring was added to the server bootstrap. The primary recurring mechanism is migration `098`'s own conditional `pg_cron` schedule; the manual endpoint (wired up in #95's `credits.routes.ts`, since `credits.controller.ts`/`credits.routes.ts` didn't exist yet when this issue's own files were written) is the fallback for environments without `pg_cron`.

## What Changed

- **Added** `supabase/migrations/20260805098_m10_create_credit_expiry_function.sql` — `expire_credits()`; conditional `pg_cron` schedule (mirrors `deactivate_expired_promos()`'s precedent).
- **Added** `server/src/features/credits/services/creditIssuance.service.ts` — `issueCredit()`.
- **Added** `server/src/features/credits/services/creditExpiry.job.ts` — `runCreditExpiryJob()`.
- **Modified** `server/src/features/booking/services/cancellation.service.ts` — calls `issueCredit()` (see #91's doc for the full hookup).

## Acceptance Criteria Map

| AC                                                                                                        | Automated                                                                                                                           | Manual            |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 a qualifying cancellation increments `credit_balances.balance` and writes an issuance row atomically | `creditIssuance.service.spec.ts` (RPC call shape); the atomicity guarantee itself lives in `issue_credit()` — see #90's doc, step 3 | #90's doc, step 3 |
| AC-2 `expire_credits()` zeroes an expired issuance via a negative `'expiry'` row, not a hard delete       | not unit-testable (pure SQL function) — see Manual step 2 below                                                                     | step 2            |
| AC-3 the manual-trigger endpoint produces the same result as the scheduled run                            | `creditExpiry.job.spec.ts` (2 tests)                                                                                                | step 3            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/credits/services/creditIssuance.service.spec.ts src/features/credits/services/creditExpiry.job.spec.ts
```

Expected: typecheck clean, 2/2 + 2/2 tests pass.

## Manual Verification

### Prerequisites

- Docker Desktop running, migrations through `099` applied.
- An Admin/Superadmin staff token (for the manual-trigger endpoint, exposed by #95's `POST /credits/expire`).

### D. Steps

1. Issue a credit via a qualifying cancellation (see #91's doc, steps 1-3) with a short expiry for testing: `PATCH /bookings/policy` with `credit_expiry_enabled: true, credit_expiry_days: 1` on the relevant branch **before** cancelling, so the issuance's `expires_at` is only 1 day out.
2. In the SQL Editor, backdate the test issuance to force expiry: `update credit_transactions set expires_at = now() - interval '1 hour' where id = '<the issuance row's id>';`. Then run `select public.expire_credits();` directly. Confirm it returns `1`; confirm a new `'expiry'` row exists with a negative `amount` equal to the issuance (via a hard `select`, not a delete — the issuance row itself is still present, now with `expired_at` set); confirm `credit_balances.balance` decreased by the same amount.
3. Repeat steps 1-2 for a second test booking, but this time trigger expiry via `POST /credits/expire` (Admin/Superadmin token) instead of calling the SQL function directly. Confirm the response's `expired_count` and the resulting ledger state match step 2 exactly.
4. Confirm `expire_credits()` does **not** touch an issuance whose `expires_at` hasn't passed yet, or one already marked `expired_at`.

### E. Cleanup

```sql
delete from credit_transactions where credit_balance_id = '<test balance id>';
delete from credit_balances where id = '<test balance id>';
```

Also reset the branch's `credit_expiry_days` back to its previous value via `PATCH /bookings/policy`.
