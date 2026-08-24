# Issue #92 Verification: reschedule fee calculation against a booking's booking_items total

**Issue:** #92 — feat(policy): reschedule fee calculation against booking_items total
**Owner:** Matthew
**Branch:** `feat/reschedule-fee-calculation` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** #88
**Sprint:** Sprint 5 Epic B — M09 Policy Enforcement

## Overview

Flat/percentage reschedule fee, applied only once the configured free-reschedule allowance (`bookings.reschedule_count`, already incremented by Sprint 2 #54) is exhausted, calculated against `bookings.total_price` — a multi-item total (`booking_items`-derived) as of the current schema, never assumed to come from one service/package row. Staff Picker visibility is explicitly **not** part of this issue — it shipped complete in Sprint 2 #52; the Guide's original draft bundled it into this issue and this revision removed it.

### Deviations from the Guide, flagged for the reviewer

- **A 6th migration, `099`, adds `bookings.pending_reschedule_fee_amount`.** Both the Design sheet's "Cross-Module Note" and this issue's own Dev Notes describe writing to this column, but neither the Design sheet's Files inventory nor the Guide's Directory Structure actually lists a migration file for it — a genuine gap in the planning docs, not a stale-assumption correction like the others. See migration `099`'s own header comment and #88's doc.
- **No extra DB round trip for the fee calculation itself.** `rescheduleFee.service.ts`'s `calculateRescheduleFee()` is a pure function — `reschedule.service.ts` already has both the resolved policy (from `evaluateNoticePeriod()`'s return) and the booking row in hand by the time it needs the fee, so the result is folded directly into the same `bookings` update the reschedule flow was already making, rather than a separate write.
- **A `NULL` `reschedule_free_allowance` (the documented "unlimited" default) short-circuits before ever reading `reschedule_fee_type`/`reschedule_fee_value`** — a fee is never charged when the allowance is unlimited, even if `reschedule_fee_enabled` is `true`. This isn't spelled out explicitly in the Guide's AC list but follows directly from Modules-Features' own "unlimited; configurable to 1 or 2" description.

## What Changed

- **Added** `server/src/features/booking/services/rescheduleFee.service.ts` — `calculateRescheduleFee()`.
- **Modified** `server/src/features/booking/services/reschedule.service.ts` — computes the fee against the pre-update booking state, writes it into the same `bookings` update payload as `pending_reschedule_fee_amount`.
- **Modified** `server/src/features/booking/booking.types.ts` / `client/src/features/booking/booking.types.ts` — `Booking.pending_reschedule_fee_amount: number | null`.
- **Added** `supabase/migrations/20260805099_m09_bookings_pending_reschedule_fee_amount.sql` (the gap-filling migration described above).

## Acceptance Criteria Map

| AC                                                                                                    | Automated                                                                                                                                                             | Manual                                                |
| ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| AC-1 fee calculated correctly (flat/%) and written only once `reschedule_count` exceeds the allowance | `rescheduleFee.service.spec.ts` (6 tests, incl. "earlier reschedules within the free allowance incur no fee" / "charged once reschedule_count reaches the allowance") | Postman: reschedule sequence                          |
| AC-2 `reschedule_fee_enabled = false` → no fee regardless of allowance                                | `rescheduleFee.service.spec.ts` "AC-2" test                                                                                                                           | —                                                     |
| AC-3 a multi-item booking's fee is calculated against its full `total_price`                          | `rescheduleFee.service.spec.ts` "AC-3" test (2500 total, 10% → 250)                                                                                                   | SQL: verify a real multi-item booking's `total_price` |
| AC-4 the existing GET/PATCH `/bookings/policy` correctly read/update the 3 new fee fields             | covered by #88's `booking.validator.spec.ts` extension + #94's manual Postman steps                                                                                   | see #94's doc                                         |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/booking/services/rescheduleFee.service.spec.ts src/features/booking/services/reschedule.service.spec.ts
```

Expected: typecheck clean, 6/6 + 10/10 tests pass (the pre-existing `reschedule.service.spec.ts` tests needed **zero** modifications — the new `cancellation_logs` write and fee calculation both degrade harmlessly against those tests' existing mocked results, confirmed by the unmodified suite still passing).

## Manual Verification

### Prerequisites

- `PATCH /bookings/policy` access (Admin/Superadmin token) to configure `reschedule_fee_enabled: true, reschedule_fee_type: 'Percentage', reschedule_fee_value: 10, reschedule_free_allowance: 1`.
- A booking with `total_price` from more than one `booking_items` row (e.g. a multi-service Grooming booking).

### D. Steps

1. Configure the policy per Prerequisites (see #94's Postman collection for the exact request).
2. `POST /bookings/:id/reschedule` once (the booking's first reschedule). Confirm the response's `booking.pending_reschedule_fee_amount` is `null` (still within the free allowance of 1).
3. `POST /bookings/:id/reschedule` a second time. Confirm `pending_reschedule_fee_amount` now equals 10% of the booking's `total_price`, rounded to 2 decimals.
4. `select total_price, reschedule_count, pending_reschedule_fee_amount from bookings where id = '<id>';` — confirm the DB row matches the API response.
5. Set `reschedule_fee_enabled: false` via `PATCH /bookings/policy`, reschedule a third time — confirm `pending_reschedule_fee_amount` is now `null` again (a disabled fee clears any earlier pending amount).

### E. Cleanup

```sql
update bookings set reschedule_count = 0, pending_reschedule_fee_amount = null where id = '<test booking id>';
```

Also reset the branch's policy row (`reschedule_fee_enabled: false`) via `PATCH /bookings/policy` if you don't want it to persist.
