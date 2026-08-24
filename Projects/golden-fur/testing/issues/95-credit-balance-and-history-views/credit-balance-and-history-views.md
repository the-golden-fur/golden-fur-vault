# Issue #95 Verification: credit balance & history views

**Issue:** #95 — feat(credits): credit balance & history views
**Owner:** James
**Branch:** `feat/credit-balance-and-history-views` (implemented here on `dev` directly — see `testing/docs/custom/25-policy-fees-and-credit-balances`)
**Base:** `dev`
**Depends on:** #90, #93
**Sprint:** Sprint 5 Epic B — M10 Credit Balance Management

## Overview

Cashier/Admin/Superadmin view of a customer's credit balance, history, and expiry dates; the customer portal surfaces the same customer's own balance with an expiry-approaching badge.

### Deviations from the Guide, flagged for the reviewer

- **`credits.controller.ts`/`credits.routes.ts` (server) were built as part of this issue**, not #90/#93. The Design sheet's Files inventory attributes both to "Issue #95," but the Guide docx's own per-issue Affected Files table for #95 lists only client files — a minor inconsistency between the two planning documents. Since this batch implements every issue in one pass regardless of the Guide's per-person `Owner` split (Matthew/James), this only matters for anyone reconstructing individual PRs from this batch later; functionally nothing is missing.
- **A single role-branching endpoint pair, not two separate route surfaces**, for the "customer-scoped self-read" + "staff can view any customer" requirement — mirrors the established `GET /bookings` pattern (`listBookings()` in `booking.service.ts`) rather than inventing `/credits/me` + `/credits/balance/:customerId`. A customer caller omits `customer_id` (resolves to themself); a staff caller (`Cashier`/`Admin`/`Superadmin`) must provide it. See `creditBalance.service.ts`'s `resolveTargetCustomerId()`.
- **`CREDIT_STAFF_ROLES` is `['Superadmin', 'Admin', 'Cashier']`** — narrower than `billing.types.ts`'s own `BILLING_STAFF_ROLES` (which also includes `Supervisor`/`Receptionist`) — matching AC-3's exact wording ("cashier/Admin/Superadmin can see any customer's"), not the wider money-handling set.
- **`CreditManagementPage` has no branch selector.** Since credit is branch-locked, the page instead lists one `CreditBalanceCard` per branch the selected customer has a balance at, each independently expandable to that branch's own `CreditHistoryTable` — this shows the branch-lock directly rather than requiring the cashier to already know which branch to look at.
- **The expiry-approaching lookahead window is hardcoded at 7 days**, per the Guide's own Open Items: "no exact threshold is specified by Modules-Features beyond 'as expiry approaching'... a 7-day example was floated... treat it as illustrative, not confirmed." `EXPIRY_LOOKAHEAD_DAYS` in `CreditBalanceCard.tsx` is a single named constant with a comment pointing back at this Open Item — confirm the real number with the requirements owner before treating it as final.
- **The customer portal (`CustomerPortalPage.tsx`) only shows branches with a nonzero balance** — a zero-balance row has nothing to display and no meaningful expiry state, so it's filtered out client-side rather than shown as an empty card.

## What Changed

- **Added** `server/src/features/credits/credits.controller.ts`, `server/src/features/credits/credits.routes.ts`, `server/src/features/credits/modules/validators/credits.validator.ts`.
- **Modified** `server/src/shared/app.routes.ts` — registers `creditsRoutes`.
- **Completed** `server/src/features/credits/services/creditBalance.service.ts` — `listCreditBalances()`/`listCreditHistory()` (stubbed by #90).
- **Added** `client/src/features/credits/credits.types.ts`, `client/src/features/credits/api/credits.api.ts`.
- **Added** `client/src/features/credits/components/CreditBalanceCard/*`, `client/src/features/credits/components/CreditHistoryTable/*`.
- **Added** `client/src/features/credits/pages/CreditManagementPage/*`, `client/src/features/credits/credits.routes.tsx`.
- **Modified** `client/src/routes.tsx` — registers `creditsRoutes`.
- **Modified** `client/src/features/staff/config/staffDashboard.config.ts` — "Credit Management" tile under Admin's Cashier section and the Cashier dashboard, linking to `/staff/credits`.
- **Modified** `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx` (+ `.module.css`, `.spec.ts`) — shows `CreditBalanceCard` per nonzero branch balance.

## Acceptance Criteria Map

| AC                                                                                                   | Automated                                                                                                                                                      | Manual            |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 `CreditManagementPage` shows a customer's balance, history, expiry, scoped to branch            | `creditBalance.service.spec.ts` (server-side data shape); no client spec for the page itself (matches this codebase's existing client-page-testing convention) | Section D, step 2 |
| AC-2 customer portal shows own balance with an expiry-approaching badge within the lookahead window  | `CustomerPortalPage.spec.ts`'s new "#95" tests (2 tests)                                                                                                       | step 3            |
| AC-3 a customer sees only their own balance/history; Cashier/Admin/Superadmin see any, branch-scoped | `creditBalance.service.spec.ts`'s AC-3 tests (5 tests)                                                                                                         | step 4            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **734/734 tests pass** (77 files).

From `client/`:

```powershell
npx tsc -b
npx vitest run
```

Expected: typecheck clean, **538/538 tests pass** (117 files).

Both confirmed clean as of this revision.

## Manual Verification

### Prerequisites

- `client/`/`server/` dev servers running, migrations through `099` applied.
- At least one customer with a nonzero credit balance at some branch (see #91's doc, steps 1-3, to create one).
- A Cashier, Admin, or Superadmin staff login, and a separate customer login for the same test customer.

### D. Steps

1. As Cashier/Admin/Superadmin, open the dashboard — confirm a **Credit Management** tile appears under Cashier (Admin dashboard's Cashier section, or the Cashier dashboard directly), linking to `/staff/credits`.
2. On `/staff/credits`, search for and select the test customer (reuses the booking flow's own `CustomerPicker`). Confirm a card appears for each branch with a balance, showing the correct amount. Click **View history** on the test branch's card — confirm the issuance row from #91's test appears with the correct date/amount/expiry.
3. Log in as the test customer, navigate to `/portal`. Confirm a credit balance card appears for the test branch with the correct amount. If its `expires_at` is within 7 days (see #93's doc, step 1's short-expiry setup), confirm an "Expires in N day(s)" badge renders.
4. As a _different_ customer (no credit balance), confirm `/portal` shows no credit card at all. As a non-Cashier/Admin/Superadmin staff role, confirm `/staff/credits`'s dashboard tile is absent and the route itself redirects to `/staff/dashboard`.

### E. Cleanup

None beyond what #90/#91/#93's own docs already clean up — this issue adds no new data of its own, only read surfaces.
