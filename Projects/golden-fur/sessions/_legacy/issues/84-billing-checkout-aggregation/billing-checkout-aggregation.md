# Issue #84 Verification: checkout aggregation backend — line items, credit application, discount/promo evaluation

**Issue:** #84 — feat(billing): checkout aggregation backend — line items, credit application, discount/promo evaluation
**Owner:** Matthew
**Branch:** `feat/billing-checkout-aggregation` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** #82, #83; Epic B Issue #90 (`credit_balances`) — not yet built, see the credit-stub deviation below
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

Aggregates billable line items from whichever of M04/M05/M06/M07 a booking's `service_category` points to, evaluates M12 discounts and M13 promos automatically, applies credit, and computes `total_amount` server-side from `SUM(transaction_line_items.line_total)` — never trusted from the client.

### Deviations from the original Guide, flagged for the reviewer

- **Credit is a stub.** Epic B (`credit_balances`/`credit_transactions`) has not been built or even guide-documented in this repo. Per the Guide's own contingency ("build the credit-lookup call behind a thin interface... TODO(Epic B, #90): replace stub credit lookup once credit_balances is merged"), `creditStub.service.ts`'s `getAvailableCredit`/`applyCredit` always report/apply 0, isolated to one file for a one-file swap once Epic B ships.
- **Discount/promo evaluation was built from scratch.** No prior "evaluate which discounts/promos apply to a booking" logic existed anywhere in the codebase (`discounts.service.ts`/`promos.service.ts` are admin CRUD only). `discountPromoEvaluation.service.ts` matches M12 discounts by scope (service/package/category), gates mandated discounts (Senior Citizen/PWD) on an additional cashier-flagged eligibility check on top of the normal scope match, and matches M13 promos by branch scope + active date window + service/package scope, capped by `promo_cap_configuration` (largest-value-first, last one trimmed to fit — a judgment call, the Guide doesn't specify a tie-break order).
- **New read-only preview endpoint**, not in the original Guide's file list: `GET /billing/checkout/:bookingId/preview` (`buildCheckoutPreview` in `checkoutAggregation.service.ts`). Added because AC-1 requires the cashier checkout screen (#86) to show line items **before** confirming — which needs a read path separate from the commit-and-charge `POST /billing/checkout`. Both endpoints share the exact same aggregation logic (`buildCheckoutPreview` is called by both), so there's no drift between what the cashier previews and what gets charged.
- **Hotel line items are split into components**, not one pre-netted figure — mirrors `checkout.service.ts`'s existing `remainingBalance` formula (`total_price - downpayment_amount + extension_fee + supplied_items_charge`) as separate signed lines (service, downpayment credit, extension fee, supplied items) so the cashier screen can show each one. `SUM(line_total)` still reproduces the same total.
- **Daycare walk-ins are out of scope.** `daycare_sessions` allows `booking_id IS NULL` (walk-ins); `POST /billing/checkout` always requires a `booking_id`, so a walk-in daycare charge has no billing entry point in this issue.

## What Changed

- **Added** `server/src/features/billing/services/lineItemSources.service.ts` — `getBookingForBilling`, `getServiceLineItems` (dispatches per `service_category` to Grooming/Hotel/Daycare/Veterinary-specific line-item builders).
- **Added** `server/src/features/billing/services/discountPromoEvaluation.service.ts` — `evaluateDiscounts`, `evaluatePromos`.
- **Added** `server/src/features/billing/services/creditStub.service.ts` — `getAvailableCredit`, `applyCredit` (see deviation above).
- **Added** `server/src/features/billing/services/checkoutAggregation.service.ts` — `buildCheckoutPreview`, `checkoutBooking`.
- **Modified** `server/src/features/billing/billing.controller.ts` / `billing.routes.ts` — `previewCheckoutController`/`GET /billing/checkout/:bookingId/preview` and `checkoutController`/`POST /billing/checkout` (shared files, also touched by #83's `paymongoFeeRateController` and #85's misc-sale controllers).
- **Modified** `server/src/features/billing/modules/validators/billing.validator.ts` — `checkoutValidator` (shared file, also carries #85's `createMiscSaleValidator`/`updateMiscSaleValidator`).

## Acceptance Criteria Map

| AC                                                                                                                                 | Automated                                                                                                                                                 | Manual     |
| ---------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AC-1 checkout aggregates correct line items from the completed M04/M05/M06/M07 record for the booking being paid                   | manual — see step D2 below (no service-level spec was written for this issue's aggregation logic given the batch's scope; flagged as a test-coverage gap) | step D2    |
| AC-2 eligible discounts/promos are applied automatically and recorded as signed line items; ineligible ones are not shown          | same as AC-1                                                                                                                                              | step D3    |
| AC-3 credit applied never exceeds `MIN(available_balance, transaction_total)`; balance decrement + transaction creation are atomic | not meaningfully testable while credit is a stub (always 0) — will apply once Epic B ships                                                                | N/A (stub) |
| AC-4 partial credit application is supported and the remaining balance is calculated correctly                                     | same as AC-3                                                                                                                                              | N/A (stub) |

**Test-coverage gap, flagged for the reviewer:** `checkoutAggregation.service.ts` and `discountPromoEvaluation.service.ts` have no dedicated `.spec.ts` files — the mocking surface (bookings + 4 different service-category joins + discounts + promos + promo_cap_configuration, all via the shared Supabase mock pattern) is large enough that this was deferred given the size of this batch. `paymentMethod.service.spec.ts` and `webhookConfirmation.service.spec.ts` (#83) and `productCatalog.service.spec.ts` (Unified Product Catalog) are the automated coverage that exists; AC-1/AC-2 here rely on the manual verification below plus the Postman collection's `SUM(line_total) = total_amount` assertion.

## Automated Verification

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, full suite passes (666/666 as of this batch — see the Unified Product Catalog doc for the counts breakdown).

## Manual Verification

Import `billing-checkout-aggregation.postman_collection.json` — fill in `cashier_identifier`/`cashier_password` and a real `booking_id` (a Completed/Paid booking with no existing transaction) before running.

### D. Steps

1. Complete a Grooming (or Hotel/Daycare/Veterinary) booking through to `Completed`/`Paid` via its normal flow.
2. `GET /billing/checkout/:bookingId/preview` — confirm the returned `serviceLines` match the booking's actual charges (service + add-ons for Grooming; service/downpayment-credit/extension-fee/supplied-items for Hotel; the single `computed_charge` line for Daycare; each `consultation_line_items` row for Veterinary), and `preCreditTotal` is the correct sum.
3. If a matching active discount/promo exists for the booking's branch/category, confirm it appears in `discountLines`/`promoLines` with no manual entry required. Retry with `senior_citizen_eligible=true`/`pwd_eligible=true` query params and confirm a mandated discount appears only when both the flag is set and the discount is enabled+scoped for that branch/category.
4. `POST /billing/checkout` with the same booking — confirm `SUM(lineItems[].line_total) === transaction.total_amount` (AC-1's implied invariant, same one AC-4 of #82 enforces at the DB level).
5. Repeat the same `POST /billing/checkout` call — confirm a 409 ("already has a transaction").

### E. Cleanup

Delete the test transaction row directly in Supabase Studio if you want the booking re-checkout-able for further testing (no DELETE endpoint exists for `booking_payment` transactions by design — see #82's RLS notes).
