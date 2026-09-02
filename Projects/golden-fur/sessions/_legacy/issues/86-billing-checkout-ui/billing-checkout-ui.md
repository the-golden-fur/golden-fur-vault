# Issue #86 Verification: cashier checkout UI

**Issue:** #86 — feat(billing): cashier checkout UI
**Owner:** James
**Branch:** `feat/billing-checkout-ui` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** #83, #84
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

`CashierCheckoutPage` at `/staff/billing/checkout` (and `/staff/billing/checkout/:bookingId`) — a single screen showing every line item (services, add-ons, auto-applied discounts/promos), the customer's available credit, and whichever payment method form applies, with the PayMongo fee notice rendered inline before confirmation.

### Decision flagged for the reviewer: no "browse active bookings" list

Same scope note as #81 (`HotelCheckoutPage`)/#69 (`DaycareCheckoutPage`): no "list bookings ready for checkout" endpoint exists, so this screen is reached with a known booking id — pasted manually, since no upstream page currently links here with a pre-filled id (unlike Hotel Checkout, which gets one from Check-in's "Go to checkout" link). Wiring that link is a natural follow-up once a Bookings Queue-style entry point is prioritized, but was out of scope here.

## What Changed

- **Added** `client/src/features/billing/pages/CashierCheckoutPage/CashierCheckoutPage.tsx` (+CSS module) — booking-id entry, line-item preview (via #84's `GET /billing/checkout/:bookingId/preview`), running total, Senior/PWD eligibility checkboxes, credit panel, payment form, PayMongo notice, confirm.
- **Added** `client/src/features/billing/components/PaymentMethodForm/PaymentMethodForm.tsx` (+CSS module) — the correct minimal form per selected payment method.
- **Added** `client/src/features/billing/components/CreditApplicationPanel/CreditApplicationPanel.tsx` (+CSS module) — shows available balance, client-side `MIN(available, total)` guard. Currently always shows "No available credit" since Epic B's `credit_balances` doesn't exist yet (see #84's credit-stub deviation) — this is expected, not a bug.
- **Added** `client/src/features/billing/components/PayMongoServiceFeeNotice/PayMongoServiceFeeNotice.tsx` (+CSS module) — fetches #83's `GET /billing/paymongo/fee-rate`, shown inline for GCash/Maya only.
- **Added** `client/src/features/billing/api/billing.api.ts`, `billing.types.ts`, `billing.routes.tsx` — API client, types, route registration for the whole billing feature (also used by #87).
- **Modified** `client/src/routes.tsx` — mounts `billingRoutes`.
- **Modified** `client/vite.config.ts` — added a `/billing` dev-proxy entry (see #83's doc; without it, requests fell through to Vite's dev server and surfaced as a generic error with no obvious network/console failure).

## Acceptance Criteria Map

| AC                                                                                                                     | Automated                                                                                  | Manual  |
| ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ------- |
| AC-1 checkout screen lists every line item with a correct running total                                                | not covered by an automated component spec (test-coverage gap, flagged)                    | step D2 |
| AC-2 available credit is shown; a partial-application control prevents overdrafting the balance                        | `CreditApplicationPanel`'s `Math.min` clamp is exercised implicitly by manual testing only | step D3 |
| AC-3 every payment method renders its correct minimal form and successfully records a transaction                      | same as AC-1                                                                               | step D4 |
| AC-4 the PayMongo fee notice appears inline before confirmation for GCash/Maya only, doesn't alter the displayed total | same as AC-1                                                                               | step D5 |

**Test-coverage gap, flagged for the reviewer:** no `.spec.ts` files were written for the new billing client components/pages, given the size of this batch (server-side logic and the Unified Product Catalog's client components got the automated-test budget instead). Recommended follow-up: at minimum a `PaymentMethodForm.spec.ts` covering the conditional-field logic per method, mirroring `CatalogComboBox.spec.ts`'s existing coverage depth.

## Automated Verification

```powershell
npx tsc -b
npx eslint .
npx vitest run
```

Expected: typecheck clean, lint clean, full client suite passes (508/508 — see the Unified Product Catalog doc).

## Manual UI Verification

### Prerequisites

- Server + client running (client restarted after the `vite.config.ts` proxy fix), migrations applied.
- A Cashier (or higher) login.
- One completed booking per service category you want to exercise (Grooming/Hotel/Daycare/Veterinary).

### D. Steps

1. Log in as Cashier, go to `/staff/billing/checkout`, paste a booking id, click Load.
2. Confirm the line-item list matches the booking's actual charges and the running total is correct (AC-1).
3. If the customer has no credit (expected, Epic B stub), confirm the panel reads "No available credit" rather than erroring (AC-2).
4. Select Cash, enter a tendered amount, confirm computed change. Confirm checkout, confirm success. Repeat with Bank Transfer (confirm the BPI/BDO selector appears) (AC-3).
5. Select GCash or Maya — confirm the fee notice appears with a percentage; select Cash — confirm it disappears and the displayed total is unchanged either way (AC-4).
6. Attempt to check out the same booking again — confirm a clear error, not a silent failure or crash.

### E. Cleanup

Delete the test transaction row directly in Supabase Studio if you want the booking checkout-able again.
