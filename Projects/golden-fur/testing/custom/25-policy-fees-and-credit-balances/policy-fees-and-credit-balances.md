# Sprint 5 Epic B — Policy fees & credit balances (Issues #88-#95)

Branch: `25-policy-fees-and-credit-balances` (all 8 issues landed together on `dev` in one pass, same convention as `12-epic-b-revision-batch-1` and `24-scheduling-and-policy-config`)

Type: Epic implementation, sourced from `temp/context/Sprint5-EpicStructure.xlsx`, `Sprint5-EpicB-Design.xlsx`, and `Sprint5-EpicB-Guide.md.docx`.

## Scope

Sprint 5 Epic B = M09 Policy Enforcement + M10 Credit Balance Management, the back-office rules-and-ledger pair for Sprint 5 (Epic A, M08 Billing, is already implemented and reference-only — see `Sprint5-EpicStructure.xlsx`'s Epic Structure sheet for why the two don't share an epic).

- **#88** `chore(db)`: ALTER `policy_configurations` — downpayment %, reschedule fee (+ `reschedule_fee_type` enum), credit expiry columns.
- **#89** `chore(db)`: `cancellation_logs` table.
- **#90** `chore(db)`: `credit_balances` + `credit_transactions` tables.
- **#91** `feat(policy)`: `cancellation_logs` writes + credit-issuance hookup for cancellation/reschedule events.
- **#92** `feat(policy)`: reschedule fee calculation against a booking's `booking_items` total.
- **#93** `feat(credits)`: credit issuance on qualifying cancellation + credit expiry job.
- **#94** `feat(policy)`: extend the existing Policies admin page with downpayment %, reschedule fee, and credit expiry sections.
- **#95** `feat(credits)`: credit balance & history views.

Per-issue detail, AC tables, and step-by-step manual verification live in `testing/docs/issues/88-*` through `testing/docs/issues/95-*`. This doc covers what's shared across the whole batch: corrections from the planning docs, migration numbering, cross-cutting decisions, and one combined verification pass.

## Corrections from the planning docs

The context workbooks (`Sprint5-EpicStructure.xlsx`, `Sprint5-EpicB-Design.xlsx`, `Sprint5-EpicB-Guide.md.docx`) already carry a revision note dated Aug 5, 2026, catching two real architectural drifts from their own first draft (Jul 31, 2026): `policy_configurations` was never created fresh by this epic (it's a Sprint 2 #52 stub, extended once already by the Aug 4 scheduling batch), and there's no `features/policy/` folder — everything lives under the existing `features/booking/`. Both corrections were confirmed still accurate by reading the actual merged migrations/source before writing anything here, and one more real gap surfaced on top of the docs' own revision:

- **Migration numbering had drifted a second time.** The Guide's own revision note already corrected its assumed "latest migration" once (from `...069` to `...092`); by the time this batch was actually built, the real latest was `20260804093` (`m01_staff_unavailability_blocks_leave_type`, part of the same Aug 4 scheduling batch but numbered after the lunch-break/availability migrations the Guide _did_ account for). This epic's 6 migrations are renumbered `094`-`099` accordingly — see each affected issue's own doc.
- **`bookings.pending_reschedule_fee_amount` had no migration file at all.** Both the Design sheet's "Cross-Module Note" and Issue #92's own Dev Notes require this column, but neither the Design sheet's Files inventory nor the Guide's Directory Structure lists a migration for it among the 5 they do enumerate. Migration `099` fills that gap (see #92's doc).
- **`issue_credit()` and `expire_credits()`, two Postgres functions, were added beyond the Design sheet's literal table/column list.** AC-1 for #93 requires the balance-increment-plus-issuance-row to be atomic, which a two-step application-layer `select`-then-`write` across separate PostgREST round trips can't guarantee — see #90's doc for the full rationale on `issue_credit()`, and #93's doc for `expire_credits()`'s per-issuance sweep model (which also needed one added column, `credit_transactions.expired_at`, to track which issuance rows have already been swept — see #90's doc).
- **`PolicyConfigurationPage.tsx`'s three new sections stayed inline, not extracted into components**, despite the Guide's Directory Structure listing three new component files (`DownpaymentConfigForm`, `RescheduleFeeConfigForm`, `CreditExpiryConfigForm`). Reading the actual page first (as every issue's own Prerequisites instructed) shows its three pre-existing sections are already inline `<section>` blocks in one file — matching that real, established pattern rather than the Guide's assumption of a `PricingConfigurationPage`-style component split. See #94's doc.
- **The credit-stub swap in Epic A's `checkoutAggregation.service.ts`/`creditStub.service.ts` was deliberately left untouched.** That stub's own `TODO(Epic B, #90)` comment names this epic and table by number, and it's tempting to read that as implicit scope — but the Guide's Directory Structure/Files inventory doesn't list either billing file under any of #88-#95, and Epic A is described as "already implemented, reference-only" for this pass. Swapping it anyway would mean editing a file outside this epic's stated scope without being asked. Flagged again below under Open Items.

## Migration numbering

```
supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql   (#88, ALTER)
supabase/migrations/20260805095_m09_create_cancellation_logs_schema.sql                                   (#89)
supabase/migrations/20260805096_m10_create_credit_balances_schema.sql                                     (#90)
supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql                                 (#90, + issue_credit())
supabase/migrations/20260805098_m10_create_credit_expiry_function.sql                                     (#93, expire_credits())
supabase/migrations/20260805099_m09_bookings_pending_reschedule_fee_amount.sql                             (#92, gap-filling ALTER)
```

All six apply after `20260804093` (the actual latest on `dev` at the time this batch was built) with no gaps.

## Other things worth knowing

- **RLS on all three new tables (`cancellation_logs`, `credit_balances`, `credit_transactions`) has no `INSERT`/`UPDATE`/`DELETE` policy for `authenticated` at all.** "Server-role client, application-layer inserts only" (#89's AC-2) is satisfied by Supabase's standard behavior — the service-role client the server always uses bypasses RLS entirely — rather than an explicit `to service_role` policy, which would be redundant.
- **`CREDIT_STAFF_ROLES` (`Superadmin`/`Admin`/`Cashier`) is deliberately narrower than `billing.types.ts`'s `BILLING_STAFF_ROLES`** (which also includes `Supervisor`/`Receptionist`) — matches #95 AC-3's exact wording rather than the wider money-handling set used elsewhere.
- **The credits read surface is one role-branching endpoint pair, not two.** `GET /credits/balances`/`GET /credits/history` mirror `GET /bookings`'s own established shape (`listBookings()` in `booking.service.ts`): a customer caller omits `customer_id` and resolves to themself; a staff caller must provide one. No separate `/credits/me` surface was invented.
- **`CreditManagementPage` has no branch selector** — since credit is branch-locked, it lists one `CreditBalanceCard` per branch the selected customer actually has a balance at, each independently expandable to that branch's own history.
- **The credit-expiry-approaching lookahead window (7 days) is a single named constant** (`EXPIRY_LOOKAHEAD_DAYS` in `CreditBalanceCard.tsx`), explicitly flagged in-code as illustrative per the Guide's own Open Items — no exact threshold is specified by Modules-Features beyond "as expiry approaches."
- **Client-side pages in this codebase are, by established convention, generally not unit-tested** (`PolicyConfigurationPage.tsx` had no spec before this batch either; `CashierCheckoutPage.tsx`/`MiscSaleManagementPage.tsx` don't either). `CreditManagementPage.tsx` follows that same convention — verified via `tsc -b` plus the manual steps in #95's doc, not a new spec file. `CustomerPortalPage.spec.ts` _did_ need updating, since it already existed and this batch changes its behavior (see below).

## Files changed (high level)

**Migrations** (`supabase/migrations/`): the 6 listed above.

**Server**: `features/booking/booking.types.ts`, `features/booking/modules/validators/booking.validator.ts`, `features/booking/services/staffPicker.service.ts`, `features/booking/services/{cancellationLog,rescheduleFee}.service.ts` (new), `features/booking/services/{cancellation,reschedule}.service.ts`, `features/credits/` (new: `credits.types.ts`, `credits.controller.ts`, `credits.routes.ts`, `modules/validators/credits.validator.ts`, `services/{creditIssuance,creditExpiry.job,creditBalance}.service.ts`), `shared/app.routes.ts`.

**Client**: `features/booking/booking.types.ts`, `features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`, `features/credits/` (new: `credits.types.ts`, `api/credits.api.ts`, `components/{CreditBalanceCard,CreditHistoryTable}/*`, `pages/CreditManagementPage/*`, `credits.routes.tsx`), `features/staff/config/staffDashboard.config.ts`, `features/customers/pages/CustomerPortalPage/CustomerPortalPage.{tsx,module.css,spec.ts}`, `routes.tsx`.

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **734/734 tests pass** (77 files) — includes the 8 new/rewritten spec files this batch adds (`cancellationLog.service.spec.ts`, `rescheduleFee.service.spec.ts`, the rewritten `cancellation.service.spec.ts`, `creditBalance.service.spec.ts`, `creditIssuance.service.spec.ts`, `creditExpiry.job.spec.ts`) plus every pre-existing test, unmodified and still passing (notably `reschedule.service.spec.ts`, which needed **zero** changes — the new `cancellation_logs` write and fee calculation both degrade harmlessly against its existing mocked results).

From `client/`:

```powershell
npx tsc -b
npx vitest run
```

Expected: typecheck clean, **538/538 tests pass** (117 files).

Both confirmed clean as of this revision.

## Manual Verification

You'll need: `server/`/`client/` dev servers running (`npm run dev` from the repo root), a Supabase project with this batch's 6 migrations (094-099) applied, and Postman (or the collection alongside this doc).

### 0. Apply migrations

```powershell
supabase db reset
```

Confirm no errors — in particular that `094` applies cleanly after `093` without redeclaring `enforcement_mode` or any pre-existing `policy_configurations` column.

### 1. Configure a branch's policy

Using Postman's **Set Policy — Downpayment/Fee/Expiry** request (Admin/Superadmin token) or the Policies admin page, set: `downpayment_percentage: 50`, `reschedule_fee_enabled: true, reschedule_fee_type: 'Percentage', reschedule_fee_value: 10, reschedule_free_allowance: 1`, `credit_expiry_enabled: true, credit_expiry_days: 30`.

### 2. Exercise the reschedule-fee path

Reschedule a booking twice. Confirm the first reschedule leaves `pending_reschedule_fee_amount: null` (within the free allowance); the second shows 10% of the booking's `total_price`. Full detail: `testing/docs/issues/92-reschedule-fee-calculation`.

### 3. Exercise the cancellation → credit path

Cancel a Hotel booking with enough notice. Confirm the response's `credit_issued: true`, a matching `cancellation_logs` row, and an incremented `credit_balances` row. Repeat with insufficient notice under both Strict and Soft policy modes. Full detail: `testing/docs/issues/91-cancellation-logging-and-credit-hookup`.

### 4. Exercise credit expiry

Backdate a test issuance's `expires_at`, run `select public.expire_credits();` (or `POST /credits/expire` as Admin/Superadmin). Confirm a negative `'expiry'` row appears and the balance drops accordingly. Full detail: `testing/docs/issues/93-credit-issuance-and-expiry`.

### 5. Exercise the two new UI surfaces

On `/staff/admin/maintenance/policies`, confirm the three new sections (Downpayment, Reschedule fee, Credit expiry) render and save correctly. On `/staff/credits` (Cashier/Admin/Superadmin), search the test customer and confirm their balance/history render, scoped per branch. On `/portal` as that customer, confirm the same balance surfaces with an expiry badge if within 7 days. Full detail: `testing/docs/issues/94-policy-page-downpayment-reschedule-credit-sections` and `95-credit-balance-and-history-views`.

### Cleanup

Each issue doc lists its own cleanup SQL. In order: `credit_transactions` rows → `credit_balances` rows → `cancellation_logs` rows → reset the affected `bookings` row(s) (`status`, `cancelled_at`, `reschedule_count`, `pending_reschedule_fee_amount`) → reset the policy row(s) back to documented defaults.

## Open Items (carried forward, not resolved by this batch)

- **`server/src/features/billing/services/creditStub.service.ts`'s `getAvailableCredit()`/`applyCredit()` still return `0`/no-op.** Epic A's checkout (`checkoutAggregation.service.ts`, `miscSale.service.ts`) now has a real `credit_balances` table to read (this batch's #90), but swapping the stub for a real implementation is Epic A's file, outside this epic's stated Directory Structure, and wasn't requested — flagged here exactly as the Guide's own Handoff State asked, so whoever picks it up next has the context. The Guide describes this as "a one-file change, no caller needs to know it happened" once it's time.
- **Credit-expiry-approaching lookahead window (7 days) is illustrative, not confirmed** — see "Other things worth knowing" above.
- **Migration numbering may have moved again.** This is the _second_ time this epic's assumed "latest migration" needed correcting before work even started (the Guide's own note flagged this as likely). Reconfirm the actual latest file in `supabase/migrations/` before branching anything else on top of this batch.
