# Issue #90 Verification: credit_balances + credit_transactions tables

**Issue:** #90 — chore(db): credit_balances + credit_transactions tables
**Owner:** Matthew
**Branch:** `chore/credit-ledger-schema` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** Sprint 1 (`customer_profiles`, `branches`) merged
**Sprint:** Sprint 5 Epic B — M10 Credit Balance Management

## Overview

The credit ledger schema: `credit_balances` (per-customer, per-branch, branch-locked) and `credit_transactions` (signed issuance/redemption/expiry history). Unaffected by this epic's revision-note corrections — scope, shape, and rationale are unchanged from the original draft.

**CROSS-EPIC:** Epic A's checkout credit-application logic (`server/src/features/billing/services/checkoutAggregation.service.ts`, Issue #84, already merged) reads this table via a stub interface, `server/src/features/billing/services/creditStub.service.ts`, whose own `TODO(Epic B, #90)` comment names this table and this issue by number. **That stub was intentionally left untouched by this batch** — swapping it for a real `credit_balances`-backed implementation isn't listed in the Guide's Directory Structure/Files inventory for any of #88-#95, and doing it anyway would mean editing an Epic A file the user described as "already implemented, reference-only" without being asked. See this batch's own doc's Open Items for the follow-up flag.

### Deviations from the Guide, flagged for the reviewer

- **Migration numbering** — renumbered `096`/`097` (were `095`/`096`), same renumbering as #88/#89.
- **`expired_at` added to `credit_transactions`, beyond the Design sheet's literal column list.** The Design sheet gives `credit_transactions` no way to tell whether a given `'issuance'` row has already been swept by `expire_credits()` (#93) — there's no other row-level link between an issuance and the expiry row that eventually offsets it. `expired_at` (nullable, only ever set on `'issuance'` rows) closes that gap. See #93's doc for how it's used.
- **`issue_credit()`, an atomic Postgres function, was added** in this same migration (`097`), beyond the Design sheet's literal table/column list. AC-1 for #93 requires the balance increment and the issuance row to be atomic; a two-step application-layer read-modify-write across separate PostgREST round trips can't guarantee that, so a single `SECURITY DEFINER` PL/pgSQL function does the `on conflict (customer_id, branch_id) do update` increment and the `credit_transactions` insert inside one Postgres transaction. Called by #93's `creditIssuance.service.ts` via `supabase.rpc('issue_credit', ...)`, not by a two-step client-side write.

## What Changed

- **Added** `supabase/migrations/20260805096_m10_create_credit_balances_schema.sql` — `credit_balances` table; `UNIQUE(customer_id, branch_id)`; `CHECK (balance >= 0)`; RLS (customer reads own, Cashier/Admin/Superadmin read any).
- **Added** `supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql` — `credit_transactions` table (incl. the added `expired_at` column); RLS; `issue_credit()` atomic helper function.
- **Added** `server/src/features/credits/credits.types.ts` — `CreditBalance`/`CreditTransaction` types, `CREDIT_STAFF_ROLES`/`CREDIT_ADMIN_ROLES` role lists.
- **Added** `server/src/features/credits/services/creditBalance.service.ts` — stub read path (`listCreditBalances`/`listCreditHistory`), completed in full by #95.

## Acceptance Criteria Map

| AC                                                                                            | Automated                                                                                                                       | Manual            |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 both tables exist with every Design-sheet column                                         | schema exists at migration-apply time; `creditBalance.service.spec.ts` / `creditIssuance.service.spec.ts` exercise the shape    | Section D, step 2 |
| AC-2 `UNIQUE(customer_id, branch_id)` and `CHECK (balance >= 0)` present and enforced         | `issue_credit()`'s `on conflict` clause depends on the unique constraint existing — implicit                                    | step 3            |
| AC-3 `credit_transactions.transaction_id` FKs successfully to `transactions.id` (Epic A, #82) | not exercised by vitest                                                                                                         | step 4            |
| AC-4 RLS: customer reads own, Cashier/Admin/Superadmin read any, only server-role writes      | `creditBalance.service.spec.ts`'s AC-3 tests exercise the _application-layer_ mirror of this; DB-level RLS needs the SQL Editor | step 5            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/credits
```

Expected: typecheck clean, `creditBalance.service.spec.ts` (7 tests), `creditIssuance.service.spec.ts` (2 tests), `creditExpiry.job.spec.ts` (2 tests) all pass.

## Manual Verification

### Prerequisites

- Docker Desktop running; migrations `094`/`095` (#88/#89) already applied.

### D. Steps

1. Run `supabase db reset`. Confirm `096`/`097` apply cleanly, including `issue_credit()`'s creation.
2. In the SQL Editor: confirm `credit_balances` and `credit_transactions` both exist with every column from the Design sheet (plus `credit_transactions.expired_at`, the documented addition above).
3. Run `select public.issue_credit('<a real customer_profiles.id>', '<a real branches.id>', 500, null, null);` twice in a row with the same customer/branch. Confirm the second call increments the existing `credit_balances` row (via the `on conflict ... do update`) rather than erroring or creating a duplicate row — `select * from credit_balances where customer_id = '<...>' and branch_id = '<...>';` should show `balance = 1000`, and `select * from credit_transactions where credit_balance_id = (select id from credit_balances where customer_id = '<...>' and branch_id = '<...>');` should show two `'issuance'` rows of 500 each.
4. Confirm `credit_transactions.transaction_id` accepts a real `transactions.id` (any row from Epic A's billing checkout) and rejects a non-existent UUID.
5. As a Groomer (non-Cashier/Admin/Superadmin) staff session, confirm `select * from credit_balances;` returns zero rows. As the customer who owns a balance row (via their own JWT), confirm they can read their own row but not another customer's.

### E. Cleanup

```sql
delete from credit_transactions where credit_balance_id = (select id from credit_balances where customer_id = '<test customer id>' and branch_id = '<test branch id>');
delete from credit_balances where customer_id = '<test customer id>' and branch_id = '<test branch id>';
```
