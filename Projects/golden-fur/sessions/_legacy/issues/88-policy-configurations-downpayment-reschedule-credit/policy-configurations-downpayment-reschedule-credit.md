# Issue #88 Verification: ALTER policy_configurations — downpayment %, reschedule fee, credit expiry

**Issue:** #88 — chore(db): ALTER policy_configurations — downpayment %, reschedule fee, credit expiry columns
**Owner:** Matthew
**Branch:** `chore/policy-configurations-downpayment-reschedule-credit` (implemented here on `dev` directly — see this batch's doc, `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** Sprint 2 Issue #52 merged (`policy_configurations` stub); Aug 4, 2026 scheduling batch merged (lunch break ALTER, migration `20260804091`)
**Sprint:** Sprint 5 Epic B — M09 Policy Enforcement

## Overview

ALTER (not CREATE) onto the existing `policy_configurations` table: 7 new columns (downpayment %, reschedule fee enable/type/value/allowance, credit expiry enable/days) plus the one genuinely new enum this epic introduces, `reschedule_fee_type`. Every pre-existing column, index, RLS policy, and the `enforcement_mode` enum are untouched.

### Deviations from the Guide, flagged for the reviewer

- **Migration numbering.** The Guide assumed the latest merged migration was `...092` and numbered this epic `093`-`097`. The actual latest on `dev` at the time this batch was built was `20260804093` (`m01_staff_unavailability_blocks_leave_type`), so this epic's migrations are renumbered `094`-`099` — one more than the Guide's own already-corrected count. This is the second time this epic's assumed "latest migration" needed correcting, exactly as the Guide's own Open Items predicted.
- **A 6th migration was added.** The Guide's Directory Structure/Files inventory lists only 5 migrations for this epic, but Issue #92's own Development Notes and the Design sheet's "Cross-Module Note" both require a `bookings.pending_reschedule_fee_amount` column that no migration file actually covers. Migration `099` (`m09_bookings_pending_reschedule_fee_amount.sql`) fills that gap — see #92's doc for detail.
- **`issue_credit()`, an atomic Postgres function, was added beyond the Design sheet's literal `credit_balances`/`credit_transactions` column list**, in migration `097` (not this issue's own migration, but worth flagging here since it's the same "don't just follow the column list literally" theme). See #90's doc.

## What Changed

- **Added** `supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql` — `reschedule_fee_type` enum (`Flat`, `Percentage`); 7 new `policy_configurations` columns with CHECK constraints matching the Design sheet's documented ranges (0–100 for `downpayment_percentage`, `>= 0` for fee/allowance/expiry-day values).
- **Modified** `server/src/features/booking/booking.types.ts` — `PolicyConfiguration`/`EffectivePolicy` gain the 7 new fields; new `RescheduleFeeType` type.
- **Modified** `server/src/features/booking/modules/validators/booking.validator.ts` — `updatePolicyValidator` gains the 7 new optional fields, a cross-field check requiring `reschedule_fee_type`/`reschedule_fee_value` together, and a ≤100 cap when the type is `Percentage`.
- **Modified** `server/src/features/booking/services/staffPicker.service.ts` — `DOCUMENTED_DEFAULTS` and `updatePolicyConfiguration()`'s baseline-seeding both extended with the 7 new fields (despite the file name, this is the de facto policy-configuration service — unchanged from Sprint 2 #52's own naming).
- **Modified** `client/src/features/booking/booking.types.ts` — client mirror of the same 7 fields, on `PolicyConfiguration`/`EffectivePolicy`/`UpdatePolicyPayload`.

## Acceptance Criteria Map

| AC                                                                                                                           | Automated                                                                                                          | Manual                                      |
| ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| AC-1 `policy_configurations` gains exactly the 7 new columns via ALTER; every pre-existing column/index/RLS policy untouched | schema exists at migration-apply time (no app-level test)                                                          | Section D, step 2 (information_schema diff) |
| AC-2 `reschedule_fee_type` enum exists (`Flat`, `Percentage`); `enforcement_mode` not redeclared                             | migration re-apply would fail on `create type` if redeclared — implicit                                            | step 2                                      |
| AC-3 the pre-existing unique indexes still hold                                                                              | `staffPicker.service.spec.ts`'s existing AC-2 test (branch-override row creation) exercises this unchanged         | step 3                                      |
| AC-4 RLS still restricts write to Admin/Superadmin, read to all staff                                                        | `booking.validator.spec.ts` (validator only); RLS itself isn't exercised by vitest — needs the Supabase SQL Editor | step 4                                      |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/booking
```

Expected: typecheck clean, all `booking` feature tests pass (includes `staffPicker.service.spec.ts`, `booking.validator.spec.ts`).

From `client/`:

```powershell
npx tsc -b
```

Expected: typecheck clean (no client tests directly exercise this issue's types alone — see #94's doc for the consuming page's own verification).

## Manual Verification

### Prerequisites

- Docker Desktop running (for `supabase db reset`).
- Supabase CLI installed (`supabase --version`).

### D. Steps

1. From the repo root, run `supabase db reset`. Confirm no errors — in particular that migration `094` applies cleanly on top of `093` (the Aug 5 staff-unavailability-blocks migration) without redeclaring `enforcement_mode` or any pre-existing column.
2. In the Supabase SQL Editor, run:
   ```sql
   select column_name, data_type, is_nullable, column_default
   from information_schema.columns
   where table_name = 'policy_configurations'
   order by ordinal_position;
   ```
   Confirm the original 11 columns (from migrations `037`/`091`) are present unchanged, plus exactly 7 new ones: `downpayment_percentage`, `reschedule_fee_enabled`, `reschedule_fee_type`, `reschedule_fee_value`, `reschedule_free_allowance`, `credit_expiry_enabled`, `credit_expiry_days`.
3. Run `select * from policy_configurations;` — confirm exactly 2 rows still exist (the seeded system-wide default plus whatever branch overrides already existed before this migration), each now showing the new columns at their defaults (`downpayment_percentage = 50.00`, `reschedule_fee_enabled = false`, `credit_expiry_enabled = true`, `credit_expiry_days = 30`).
4. As a non-Admin/Superadmin staff role, attempt `update policy_configurations set downpayment_percentage = 75 where branch_id is null;` directly in the SQL Editor while impersonating that role (or exercise `PATCH /bookings/policy` — see #94's Postman collection) — confirm RLS still rejects it.

### E. Cleanup

None required — schema-only change; step 4's rejected write makes no lasting change.
