---
title: Credits — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, credits]
project: golden-fur
---

Tracks each customer's branch-locked account credit balance — issued when a qualifying booking cancellation converts its paid amount into credit, spent at checkout or against a pending transaction, and swept away on expiry. Most of the server-side logic lives in its own `server/src/features/credits/` module (reads, expiry job), but the actual redemption code (`creditStub.service.ts`) is colocated inside `server/src/features/billing/services/` — kept there so billing's existing callers don't need new import paths — and issuance is triggered from `server/src/features/booking/services/cancellation.service.ts` (Automatic mode) and `creditReview.service.ts` (Manual review queue). This guide covers all of it.

**Part of:** [[M10-credit-balance-management]]

## Client-side (`client/src/features/credits/`)

### api/

- **`credits.api.ts`** — `listCreditBalances` (`GET /credits/balances`, self-scoped for a customer caller or `customer_id`-scoped for staff), `listCreditHistory` (`GET /credits/history`), and `runCreditExpiry` (`POST /credits/expire`, Admin/Superadmin manual trigger). Coerces the PostgREST-serialized numeric `balance`/`amount`/`next_expires_amount` fields to real numbers so every consumer does number math, not string concatenation.

### components/

- **`CreditBalanceCard/CreditBalanceCard.tsx`** — a per-branch balance card (branch name + amount) that also shows the soonest upcoming expiry (date, amount, days-left) or "Does not expire" once `history` has loaded. Used by both the staff Credit Management page and the customer credits page.
- **`CreditBalanceIndicator/CreditBalanceIndicator.tsx`** — the navbar wallet pill showing the signed-in customer's total credit across branches; hovering/focusing it opens a popover with a per-branch breakdown and each branch's soonest expiry. Always rendered, even at zero balance, so customers discover the feature. Customer-only.
- **`CreditHistoryTable/CreditHistoryTable.tsx`** — a plain issuance/redemption/expiry ledger table for one (customer, branch) pair; amounts are already signed at the source so only styling (positive/negative) is applied here.

### pages/

- **`CreditManagementPage/CreditManagementPage.tsx`** — Cashier/Admin/Superadmin staff screen at `/staff/credits`. Reuses the booking flow's `CustomerPicker` to search for a customer, then lists their per-branch balances with expandable transaction history.
- **`CustomerCreditsPage/CustomerCreditsPage.tsx`** — the customer-facing `/portal/credits` page (the navbar pill's destination). Reads balances from the shared `CreditBalanceProvider`, fetches each funded branch's history itself, and renders a full expiry schedule (via `computeExpirySchedule`) plus the raw ledger per branch.

### providers/

- **`CreditBalanceContext.ts`** / **`useCreditBalance.ts`** — a small context (`balances`, `total`, `isLoading`, `refresh`) and its hook, available inside the customer app shell.
- **`CreditBalanceProvider.tsx`** — holds the signed-in customer's own balances so the navbar pill and portal pages share one fetch. Aggressively revalidates: initial load, a 20s poll, on tab focus/visibility change, on every in-app navigation, and on an explicit `refresh()` or the `goldenfur:credit-balance-changed` window event. A failed pull never blanks out an already-loaded balance.
- **`creditBalanceEvents.ts`** — defines `CREDIT_BALANCE_CHANGED_EVENT` and `notifyCreditBalanceChanged()`, a window event any flow (e.g. a cancellation, a credit payment) can fire so the provider re-pulls without needing direct access to the context.

### Other files

- **`credits.routes.tsx`** — wires `CreditManagementPage` under `/staff/credits` (`StaffAuthGuard`) and `CustomerCreditsPage` under `/portal/credits` (`CustomerAuthGuard`). Role enforcement for the staff page happens client-side inside the page itself.
- **`credits.types.ts`** — `CreditBalance` (including the read-time-computed `next_expires_at`/`next_expires_amount`) and `CreditTransaction` (`issuance`/`redemption`/`expiry`, signed `amount`) — mirrors the server's own `credits.types.ts`.
- **`utils/expiry.ts`** — the shared expiry math used by the card, the customer page, and the navbar popover: `computeExpirySchedule` buckets not-yet-expired issuance lots by Manila calendar day and walks the running balance forward (FIFO, capped so already-redeemed credit isn't double-counted) to produce each future expiry event; `soonestExpiry` is just its first entry. `describeDaysLeft`/`formatExpiryDate` format the result. Deliberately pure — `now` is always passed in, never read internally.

The `.module.css` files paired with each component/page are pure styling and are skipped here as boilerplate.

## Server-side

### `server/src/features/credits/` — balance reads & expiry

- **`credits.controller.ts`** / **`credits.routes.ts`** — `GET /credits/balances` and `GET /credits/history` (both `jwtMiddleware`-only; a customer resolves to themself, staff must be `CREDIT_STAFF_ROLES` and must name a `customer_id`) and `POST /credits/expire` (`CREDIT_ADMIN_ROLES`-only manual trigger).
- **`services/creditBalance.service.ts`** — `resolveTargetCustomerId` is the shared role-branch that makes the single-endpoint self-or-staff-read pattern work. `listCreditBalances` reads every `credit_balances` row for a customer (one per branch, since credit is branch-locked) and enriches each with `next_expires_at`/`next_expires_amount` via `nextExpiry`, which mirrors the `expire_credits()` SQL function's own FIFO/day-grouping rule — a best-effort enrichment that degrades to bare balances if the lot query fails. `listCreditHistory` returns the full issuance/redemption/expiry ledger for one (customer, branch) pair.
- **`services/creditIssuance.service.ts`** — `issueCredit` wraps the atomic `issue_credit()` Postgres function (upserts the balance and inserts a signed issuance `credit_transactions` row in one step, so AC requiring both together is guaranteed). Never throws; returns `null` on failure so the caller treats it as "nothing was issued" rather than assuming success.
- **`services/creditExpiry.job.ts`** — `runCreditExpiryJob` wraps the `expire_credits()` RPC. The preferred mechanism is that migration's own conditional `pg_cron` schedule; this manual trigger is the primary mechanism (not just a verification aid) in any environment without `pg_cron`.
- **`modules/creditExpiry.util.ts`** — `manilaDayKey`/`manilaEndOfDayIso`: credit expires per **calendar day** in Asia/Manila time (fixed UTC+8, no DST), not per exact second, so two lots issued hours apart on the same day expire together. Mirrored on the client by `utils/expiry.ts`.
- **`modules/validators/credits.validator.ts`** — Zod query schemas for the two list endpoints.
- **`credits.types.ts`** — `CreditBalance`/`CreditTransaction` plus this feature's role lists, `CREDIT_STAFF_ROLES` (Superadmin/Admin/Cashier — deliberately narrower than billing's own staff-role set) and `CREDIT_ADMIN_ROLES`.

### `server/src/features/billing/services/creditStub.service.ts` — redemption

Despite the "stub" name (kept only so `checkoutAggregation.service.ts`/`miscSale.service.ts` didn't need new import paths when Epic B shipped), this is the live redemption code:

- **`getAvailableCredit`** — reads the customer's balance at one branch (0 if no row exists).
- **`applyCredit`** — redeems `MIN(requestedAmount, available)` via the atomic `redeem_credit()` RPC (upsert-decrement the balance + insert a signed-negative redemption row in one DB transaction), returning how much was actually applied. Called from billing's checkout, group checkout, and misc-sale flows, and from `transactionPayment.service.ts`'s `payTransactionWithCredit` (which wraps a further RPC, `pay_transaction_with_credit`, redeeming + settling a `Pending` transaction + rolling up the booking in one atomic step — full detail in [[M08-sales-billing]]'s Code Guide).

### `server/src/features/booking/services/` — where issuance is triggered

- **`cancellation.service.ts`** — not a credits file itself, but the main call site: on a cancellation, `confirmedAmountPaid` reads the booking's actually-settled `transactions` total (never the booking's own `payment_status` rollup, so the credited amount can't be inflated by a rollup lag), and — when the branch's notice period was met, something was paid, and the branch isn't in Manual credit-review mode — multiplies it by the branch's `cancellation_credit_conversion_rate` and calls `issueCredit`.
- **`creditReview.service.ts`** — the Manual-mode counterpart: `listPendingCreditReviews` lists queued `cancellation_logs` rows (`credit_review_status = 'pending'`) with a preview of what approving would credit at the branch's _current_ rate; `decideCreditReview` on approval resolves the rate/expiry policy fresh at decision time and calls the exact same `issueCredit` path, only updating the log row after issuance succeeds (so a failure never leaves it half-decided).

## How it connects

Credit is minted by [[M03-appointment-booking|a booking cancellation]] via [[M09-policy-enforcement|the branch's notice-period and credit-review policy]] (`cancellation.service.ts` for Automatic mode, `creditReview.service.ts` for Manual), landing in `credit_balances`/`credit_transactions`. It's spent inside [[M08-sales-billing|M08]] — at cashier checkout, on a miscellaneous sale, or paying down a pending transaction directly — all through `creditStub.service.ts`'s `applyCredit`. Customers see their own balance and expiry schedule on `/portal/credits` and the navbar pill; staff look up any customer's balance on `/staff/credits`. Redeemed/expired credit usage feeds [[M14-report-management|M14]]'s DSR credit-usage section.
