# Issue #82 Verification: transactions + transaction_line_items tables + transaction_type/payment_method/payment_status enums

**Issue:** #82 — chore(db): transactions + transaction_line_items tables + transaction_type/payment_method/payment_status enums
**Owner:** Matthew
**Branch:** `chore/billing-transactions-schema` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** Sprint 2 Epic B merged (bookings table); Sprint 4 Epic A merged (hotel_stays); the Unified Product Catalog change (`testing/docs/custom/17-unified-product-catalog`), whose own migration `20260731067` runs immediately before this one
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

Schema-only issue: `transaction_type`/`payment_method`/`payment_status` enums plus the `transactions` and `transaction_line_items` tables, so Issues #83-#85 have real tables and RLS to build against.

### Deviations from the original Guide, flagged for the reviewer

- **Migration numbering.** The Guide assumed Sprint 4's last migration was `...032`; the actual latest on `dev` is `20260729066`. These migrations are renumbered `068`/`069` (`067` is the Unified Product Catalog change's own migration, not part of this issue).
- **RLS is narrower than "all staff read."** `INSERT` is restricted to money-handling roles (`Superadmin`/`Admin`/`Supervisor`/`Receptionist`/`Cashier` — mirrors `BOOKING_MARK_PAID_ROLES`), not every staff role, since `transactions` are financial records. `UPDATE`/`DELETE` are further restricted to Admin/Superadmin **and** `transaction_type = 'miscellaneous_sale'` only (per an explicit follow-up request during implementation — see #85's doc) — booking-payment transactions stay append-only for every role.
- **The forward-declared `transaction_promo_selections` FK is added here**, in `069`, fulfilling the comment left in Epic B's migration `20260726049` ("added via `alter table ... add constraint ... foreign key` in the M08 migration that creates transactions, once it exists").

## What Changed

- **Added** `supabase/migrations/20260731068_m08_create_transactions_schema.sql` — the three enums; `transactions` table (see AC-1 column list below); CHECK constraints for `booking_id`/`transaction_type` and `misc_sale_description`/`transaction_type`; RLS.
- **Added** `supabase/migrations/20260731069_m08_create_transaction_line_items_schema.sql` — `transaction_line_items` table; RLS; the `transaction_promo_selections.transaction_id` FK.

## Acceptance Criteria Map

| AC                                                                                                         | Automated                                                                                                                       | Manual                                                                                                                             |
| ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| AC-1 `transactions`/`transaction_line_items` exist with all three enums and correct FKs                    | schema exists at migration-apply time (no app-level test)                                                                       | Section 3, this SQL doc                                                                                                            |
| AC-2 CHECK enforces `booking_id IS NULL` iff `transaction_type = 'miscellaneous_sale'`                     | exercised indirectly by `checkoutAggregation.service.ts` (#84) and `miscSale.service.ts` (#85) always inserting a matching pair | step D2                                                                                                                            |
| AC-3 RLS restricts write access to cashier/admin/superadmin roles; customers read only their own           | exercised by `billing.routes.ts` role guards (#83-#85)                                                                          | step D3, D4                                                                                                                        |
| AC-4 `SUM(transaction_line_items.line_total)` for any transaction equals that transaction's `total_amount` | `checkoutAggregation.service.ts` computes `total_amount` from exactly this sum; verified in #84's doc's Postman test            | Section 6, `m08-billing-transactions-schema.sql` (see also `testing/docs/custom/17-unified-product-catalog`'s general SQL pattern) |

## Automated Verification

No server code exists yet at this issue's own scope (schema-only) — see #83-#87's docs for the app-level tests that exercise this schema. Confirm the migrations apply cleanly:

```powershell
supabase db reset
```

## Manual Verification

### Prerequisites

- Docker Desktop running (for `supabase db reset`).
- Migration `20260731067` (Unified Product Catalog) already applied — it runs immediately before this issue's two migrations.

### D. Steps

1. Run `supabase db reset`. Confirm no errors, in particular that the `transaction_promo_selections` FK add (`069`) succeeds against the now-existing `transactions` table.
2. In the Supabase SQL Editor, attempt `insert into transactions (transaction_type, booking_id, ...) values ('miscellaneous_sale', '<some-real-booking-id>', ...)` — confirm the CHECK constraint rejects it (a misc sale must have `booking_id IS NULL`).
3. As a non-money-handling staff role (e.g. Groomer, once #83+ ship real endpoints to test through), confirm `INSERT` is rejected by RLS.
4. As a customer, confirm `SELECT` only returns transactions where `customer_id = auth.uid()`.

### E. Cleanup

None required — schema-only change, no data inserted by this issue's own verification beyond the rejected CHECK-constraint attempt in step 2.
