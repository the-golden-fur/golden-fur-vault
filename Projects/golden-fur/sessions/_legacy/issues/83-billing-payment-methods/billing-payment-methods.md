# Issue #83 Verification: payment method backend — manual methods + PayMongo (GCash/Maya) integration & webhook confirmation

**Issue:** #83 — feat(billing): payment method backend — manual methods + PayMongo (GCash/Maya) integration & webhook confirmation
**Owner:** Matthew
**Branch:** `feat/billing-payment-methods` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** #82
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

Every accepted payment method records a transaction the same way: the five manual methods (Cash, Card, Bank Transfer, Grabmart, Pickaroo) and GCash/Maya's walk-in-QR channel all confirm immediately on cashier action; GCash/Maya's customer-portal channel stays `Pending` until the PayMongo webhook confirms it, no cashier action required.

### Infra gap, flagged for the reviewer (not hidden)

"Sprint 0, Issue 0-D" (PayMongo sandbox credentials + a published-rate source) is referenced throughout the Sprint5-EpicA-Guide but **does not exist anywhere in this repo** — no prior Sprint 0 issue docs, no `PAYMONGO_*` env vars before this issue. `initiatePaymongoPayment`/webhook signature verification are coded correctly against PayMongo's real REST API shape (Sources endpoint, `paymongo-signature` HMAC scheme) but are **untestable end-to-end without real sandbox credentials**, which this environment doesn't have. New placeholders added to `server/.env.example`; `getPaymongoServiceFeeRate()` reads a configurable `PAYMONGO_SERVICE_FEE_PERCENT` env var (default 2.5) rather than a hardcoded number, since PayMongo has no public "current rate" API to poll.

## What Changed

- **Added** `server/src/features/billing/services/paymentMethod.service.ts` — `computeCashChange` (rejects tendered < due, rounds to the centavo); `resolvePaymentConfirmation` (manual methods + walk-in QR → `Fully Paid` immediately; portal channel → `Pending`).
- **Added** `server/src/features/billing/services/paymongo.service.ts` — `initiatePaymongoPayment` (creates a PayMongo e-wallet Source), `verifyPaymongoWebhookSignature` (HMAC-SHA256 against the raw request body), `parsePaymongoWebhookEvent`, `getPaymongoServiceFeeRate`.
- **Added** `server/src/features/billing/services/webhookConfirmation.service.ts` — `confirmPaymongoWebhookEvent`, idempotent (a second delivery for an already-`Fully Paid` transaction is a no-op via a conditional `UPDATE ... WHERE payment_status = 'Pending'`).
- **Added** `server/src/features/billing/routes/paymongoWebhook.routes.ts` — unauthenticated `POST /billing/paymongo/webhook`, HMAC-verified.
- **Modified** `server/src/app.ts` — `express.json({ verify })` now captures the raw request body onto `req.rawBody`, required for webhook signature verification (the parsed-then-restringified JSON wouldn't match the HMAC PayMongo computed over the original bytes).
- **Modified** `server/.env.example` — `PAYMONGO_SECRET_KEY`, `PAYMONGO_WEBHOOK_SECRET`, `PAYMONGO_SERVICE_FEE_PERCENT`, `PAYMONGO_REDIRECT_SUCCESS_URL`, `PAYMONGO_REDIRECT_FAILED_URL`.
- **Modified** `client/vite.config.ts` — added a `/billing` dev-proxy entry (needed for every billing endpoint, including this issue's `GET /billing/paymongo/fee-rate`, to reach Express instead of falling through to Vite's dev server).
- Also added in this issue's scope: `GET /billing/paymongo/fee-rate` (`paymongoFeeRateController` in `billing.controller.ts`/`billing.routes.ts` — shared files also touched by #84/#85, see those docs).

## Acceptance Criteria Map

| AC                                                                                                        | Automated                                                                                                                                                                      | Manual                                                               |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| AC-1 all five manual methods record a transaction correctly, incl. computed change for Cash               | `paymentMethod.service.spec.ts`                                                                                                                                                | not independently testable without #84/#85 wired up — see those docs |
| AC-2 a GCash/Maya portal payment is confirmed automatically on webhook receipt, no cashier action         | `webhookConfirmation.service.spec.ts`                                                                                                                                          | Section 5, requires real sandbox credentials — see gap above         |
| AC-3 a duplicate webhook delivery does not create a duplicate transaction or double-apply a status change | `webhookConfirmation.service.spec.ts` ("is idempotent" case)                                                                                                                   | same as AC-2                                                         |
| AC-4 the PayMongo service fee rate returned to the frontend matches PayMongo's currently published rate   | not automatable (depends on a real, current PayMongo rate) — `getPaymongoServiceFeeRate` returns the configured env var, which the operator is responsible for keeping current | step D1                                                              |

## Automated Verification

```powershell
npx tsc --noEmit
npx vitest run src/features/billing/services/paymentMethod.service.spec.ts src/features/billing/services/webhookConfirmation.service.spec.ts
```

Expected: 10/10 tests pass (2 files).

## Manual Verification

### Prerequisites

- `server`/`client` dev servers running.
- A Cashier (or higher) staff login.

### D. Steps

1. `GET /billing/paymongo/fee-rate` (any staff token) — confirm it returns whatever `PAYMONGO_SERVICE_FEE_PERCENT` is set to in `server/.env` (or 2.5 if unset). Set the env var to a different number, restart the server, confirm the response changes.
2. Without real PayMongo credentials configured, confirm attempting a GCash/Maya portal checkout (#84/#86) fails gracefully with a 502 surfaced as a checkout error, not a server crash.
3. **If you have PayMongo sandbox credentials:** set `PAYMONGO_SECRET_KEY`/`PAYMONGO_WEBHOOK_SECRET` in `server/.env`, retry a GCash/Maya portal checkout, confirm a real PayMongo checkout URL is returned. Use PayMongo's webhook test tool to send the same event twice against `POST /billing/paymongo/webhook` — confirm the transaction flips to `Fully Paid` exactly once (`webhook_confirmed_at` set once, not overwritten on the second delivery).

### E. Cleanup

If step 3 was run against real sandbox data, void/cancel the test payment in the PayMongo dashboard per their sandbox cleanup guidance.
