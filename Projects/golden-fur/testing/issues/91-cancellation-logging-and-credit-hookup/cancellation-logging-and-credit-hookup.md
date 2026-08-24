# Issue #91 Verification: cancellation_logs writes + credit-issuance hookup

**Issue:** #91 — feat(policy): cancellation_logs writes + credit-issuance hookup for cancellation/reschedule events
**Owner:** Matthew
**Branch:** `feat/cancellation-logging-and-credit-hookup` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** #88, #89, #93 (credit issuance is called from here but implemented there)
**Sprint:** Sprint 5 Epic B — M09 Policy Enforcement

## Overview

Fills the `TODO(Sprint 5, M09/M10)` marker that used to sit in `cancellation.service.ts`. `evaluateNoticePeriod()` (Sprint 2 #54) is **not** rebuilt — confirmed by reading `reschedule.service.ts`/`cancellation.service.ts` in full before touching either file, exactly as the Guide's Prerequisites instructed. The only new work is: write a `cancellation_logs` row for every cancellation/reschedule event, and call into #93's `creditIssuance.service.ts` once a cancellation is confirmed to qualify.

### Deviations from the Guide, flagged for the reviewer

- **The credit issuance call is via an atomic Postgres RPC (`issue_credit()`, #90), not a two-step application-layer write.** The Guide doesn't specify the mechanism, only that #93 "calls into it once a cancellation is confirmed to qualify" — this keeps `cancellation.service.ts` itself unaware of the atomicity concern, only that `issueCredit()` returns a transaction row or `null`.
- **`cancellation_logs` rows are always inserted with `credit_issued: false` / `credit_amount: null` first, then patched via a second `UPDATE` once issuance actually succeeds** (`markCreditIssuedOnLog()`), rather than trying to compute the final credit outcome before the first insert. This guarantees AC-5 ("every event writes exactly one row") holds even if credit issuance itself fails after the log row already exists — the log row would just under-report an issuance that technically failed, which is more honest than optimistically claiming success up front.
- **Both `writeCancellationLog()` and `markCreditIssuedOnLog()` are best-effort** (catch internally, log to `console.error`, never throw) rather than surfacing a 500 to the caller — a logging failure must never undo an already-committed `bookings` status update that has no cheap rollback path. This wasn't spelled out in the Guide's Dev Notes but follows the same "never crash the caller" precedent `promoExpiry.job.ts` already established in this codebase.
- **Credit issuance is additionally gated on the booking actually having a nonzero `downpayment_amount`**, not just on `notice.met`. The Guide's Goals/Dev Notes describe this as specifically a _Hotel_ downpayment-to-credit conversion; Grooming/Daycare/Veterinary bookings have no downpayment concept at all (`downpayment_amount` is `null`/`0`), so a qualifying-by-notice cancellation of one of those never reaches the credit path. Covered by `cancellation.service.spec.ts`'s "a qualifying notice with no downpayment (e.g. Daycare) never issues credit" test.

## What Changed

- **Added** `server/src/features/booking/services/cancellationLog.service.ts` — `writeCancellationLog()`, `markCreditIssuedOnLog()`.
- **Modified** `server/src/features/booking/services/cancellation.service.ts` — fills the TODO; new `credit_issued` field on `CancellationResult`.
- **Modified** `server/src/features/booking/services/reschedule.service.ts` — also writes a `cancellation_logs` row per completed reschedule (not just cancellations) — see #92's doc for the fee-calculation half of this same edit.

## Acceptance Criteria Map

| AC                                                                                                         | Automated                                                                                                                                                                                                  | Manual                                                                  |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| AC-1 Strict notice-met/unmet reschedule behavior is unchanged                                              | `reschedule.service.spec.ts`'s pre-existing AC-1/AC-2 tests pass unmodified                                                                                                                                | —                                                                       |
| AC-2 notice met → `cancellation_logs` row with `credit_issued: true`, triggers `creditIssuance.service.ts` | `cancellation.service.spec.ts` "AC-2 (#91)" test                                                                                                                                                           | Postman: cancel-with-notice request                                     |
| AC-3 Strict + notice unmet → `credit_issued: false`, downpayment forfeited                                 | `cancellation.service.spec.ts` "AC-3 (#91)" test                                                                                                                                                           | Postman: cancel-without-notice request                                  |
| AC-4 Soft + notice unmet → `policy_violation: true`, `credit_issued: false`                                | `cancellation.service.spec.ts` "AC-4 (#91)" test                                                                                                                                                           | Postman: same request against a Soft-mode branch                        |
| AC-5 every event writes exactly one row with correct fields                                                | `cancellation.service.spec.ts` "AC-5 (#91)" test                                                                                                                                                           | SQL: `select count(*) from cancellation_logs where booking_id = '<id>'` |
| AC-6 a no-show never triggers credit issuance / never writes a row                                         | no code path reaches `cancelBooking`/`rescheduleBooking` for a no-show — nothing to test beyond confirming the lazy status-flip path (`applyNoShowTransition`, unmodified by this epic) never calls either | —                                                                       |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/booking/services/cancellation.service.spec.ts src/features/booking/services/cancellationLog.service.spec.ts src/features/booking/services/reschedule.service.spec.ts
```

Expected: typecheck clean, all three files pass (9 + 4 + 10 tests).

## Manual Verification

### Prerequisites

- `server/` and Supabase running locally, migrations through `099` applied.
- A Hotel booking with `downpayment_amount` set, `scheduled_start` far enough out to test both notice-met and notice-unmet paths.
- Postman (or this batch's collection, `testing/docs/custom/25-policy-fees-and-credit-balances/policy-fees-and-credit-balances.postman_collection.json`).

### D. Steps

1. `POST /bookings/:id/cancel` on a Hotel booking scheduled more than `notice_period_days` out. Confirm the response includes `credit_issued: true`.
2. `select * from cancellation_logs where booking_id = '<id>';` — confirm one row, `event_type = 'cancellation'`, `notice_period_met = true`, `credit_issued = true`, `credit_amount` equal to the booking's `downpayment_amount`.
3. `select * from credit_balances where customer_id = '<the booking's customer>' and branch_id = '<the booking's branch>';` — confirm the balance increased by the downpayment amount.
4. Repeat step 1 on a booking scheduled within the notice window (Strict branch policy). Confirm `credit_issued: false` in the response and in the log row, and that `credit_balances` is unchanged.
5. Switch the branch's policy to Soft (`PATCH /bookings/policy`, see #94), repeat step 4. Confirm the log row has `policy_violation: true`, `credit_issued: false`.

### E. Cleanup

```sql
delete from credit_transactions where cancellation_log_id in (select id from cancellation_logs where booking_id = '<test booking id>');
delete from cancellation_logs where booking_id = '<test booking id>';
update credit_balances set balance = balance - <issued amount> where customer_id = '<...>' and branch_id = '<...>';
update bookings set status = 'Pending', cancelled_at = null, cancellation_reason = null where id = '<test booking id>';
```
