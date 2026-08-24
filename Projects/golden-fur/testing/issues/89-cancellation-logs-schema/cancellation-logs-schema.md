# Issue #89 Verification: cancellation_logs table

**Issue:** #89 — chore(db): cancellation_logs table
**Owner:** Matthew
**Branch:** `chore/cancellation-logs-schema` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** #88 (needs the pre-existing `enforcement_mode` enum); Sprint 2 Epic B merged (`bookings` table)
**Sprint:** Sprint 5 Epic B — M09 Policy Enforcement

## Overview

Schema-only issue: a genuinely new table logging every cancellation/reschedule event and its policy outcome — created regardless of whether credit was actually issued, so Admin/Supervisor dashboards always have a complete record. Unaffected by this epic's revision-note corrections; shape is unchanged from the original draft.

### Deviations from the Guide, flagged for the reviewer

- **Migration numbering** — renumbered `095` (was `094` in the Guide), for the same reason flagged in #88's doc.
- **RLS write access.** The Guide's AC-2 says "server-role client, application-layer inserts only" — implemented here by giving `cancellation_logs` no `INSERT`/`UPDATE`/`DELETE` policy for `authenticated` at all, relying on Supabase's standard behavior that the service-role client (which the server always uses) bypasses RLS entirely. No explicit `to service_role` policy was needed or added.

## What Changed

- **Added** `supabase/migrations/20260805095_m09_create_cancellation_logs_schema.sql` — `cancellation_logs` table (see AC-1 column list below); CHECK constraints tying `credit_amount`/`reschedule_fee_charged` to their respective flags; RLS (Admin/Supervisor/Superadmin read-only).

## Acceptance Criteria Map

| AC                                                                                                     | Automated                                                                                                                                                     | Manual            |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 table exists with every Design-sheet column, referencing the pre-existing `enforcement_mode` enum | schema exists at migration-apply time; exercised indirectly by #91's `cancellationLog.service.spec.ts` inserting rows shaped exactly this way                 | Section D, step 2 |
| AC-2 RLS restricts write to the server-role client only; Admin/Supervisor/Superadmin can read          | not exercised by vitest (RLS is a DB-layer concern)                                                                                                           | step 3            |
| AC-3 FKs to `bookings`/`customer_profiles`/`branches` are valid                                        | `cancellation.service.spec.ts`/`reschedule.service.spec.ts` insert with real-shaped IDs (mocked, not FK-checked); the DB-level FK itself needs the SQL Editor | step 4            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/booking/services/cancellationLog.service.spec.ts
```

Expected: 4/4 tests pass — this issue's own table has no server code of its own to test yet (that's #91), but #91's `cancellationLog.service.ts` unit tests exercise the exact insert shape this table must accept.

## Manual Verification

### Prerequisites

- Docker Desktop running; migration `094` (#88) already applied.

### D. Steps

1. Run `supabase db reset`. Confirm migration `095` applies cleanly after `094`.
2. In the Supabase SQL Editor: `select column_name, data_type from information_schema.columns where table_name = 'cancellation_logs' order by ordinal_position;` — confirm all 13 columns from the Design sheet are present, and that `enforcement_mode_applied`'s type is `enforcement_mode` (not a new enum).
3. As a Groomer (non-Admin/Supervisor/Superadmin) staff session, attempt `select * from cancellation_logs;` — confirm RLS returns zero rows (not an error — `for select` policies filter rather than reject). Attempt an `insert` directly — confirm it's rejected (no matching policy for `authenticated`).
4. Attempt `insert into cancellation_logs (booking_id, customer_id, branch_id, event_type, notice_period_met, enforcement_mode_applied) values ('00000000-0000-0000-0000-000000000000', ...)` with a non-existent `booking_id` while using the `service_role` key (e.g. via `supabase db psql` or the SQL Editor's service-role context) — confirm the FK constraint rejects it.

### E. Cleanup

Roll back any manual test row inserted in step 4 with `delete from cancellation_logs where id = '<the test row's id>';` if the insert unexpectedly succeeded (it shouldn't).
