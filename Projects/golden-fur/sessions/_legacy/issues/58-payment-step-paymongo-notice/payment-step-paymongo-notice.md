# Issue #58 Verification: payment step + PayMongo fee notice

**Issue:** #58 — feat(booking): payment step + PayMongo fee notice
**Owner:** James
**Branch:** `feat/payment-step-paymongo-notice`
**Base:** `dev`
**Depends on:** #55, #51 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds `PayMongoFeeNotice` (conditional copy shown only for GCash/Maya) and
the final add-ons + pricing/payment step of `CustomerBookingFlowPage`, which
submits the booking via #51's `POST /bookings`. This step is a UI/review
surface only — per the Epic Overview's Out of Scope note, no real PayMongo
API call is made anywhere in this epic; the fee notice is illustrative copy
and the booking-creation call trusts the client-declared `payment_confirmed`
outcome rather than a real webhook (both flagged explicitly in code
comments for the Sprint 5 M08 reviewer).

## What Changed

- **Added** `client/src/features/booking/components/PayMongoFeeNotice/`
  (`.tsx`, `.module.css`, `.spec.ts`).
- **Modified** `client/src/features/booking/pages/CustomerBookingFlowPage/` —
  the Add-ons step (Grooming only — a simple checkbox list of the branch's
  other active Grooming services) and the Review & Pay step: pricing
  summary (base price + add-ons + an informational "promo available" line
  computed client-side from Epic A's `GET /maintenance/promos`, since
  promo _application_ itself is M08/Sprint 5 scope and the booking's
  persisted `total_price` never includes a promo discount — matching
  `booking.service.ts`, which computes `total_price` from base price + addons
  only), category-specific payment collection (Hotel 50% downpayment /
  Grooming+Daycare full-payment-or-pay-at-counter / Veterinary no payment
  UI), the `PayMongoFeeNotice`, and the final "Confirm booking" submit.

### Design note — payment_confirmed derivation

Rather than a separate "pay now vs. pay at counter" toggle, `payment_method`
alone decides `payment_confirmed`: selecting **GCash** or **Maya** is
treated as an online payment (simulated success, no real gateway exists yet
— `payment_confirmed: true`); any other method (Cash/Card/Bank
Transfer/Grabmart/Pickaroo) is inherently pay-at-counter
(`payment_confirmed: false`), matching M08 Process 2's own online-vs-manual
payment-method split. This satisfies AC-4 without inventing UI the spec
didn't ask for.

## Acceptance Criteria Map

| AC                                                                         | Automated                                   | Manual |
| -------------------------------------------------------------------------- | ------------------------------------------- | ------ |
| AC-1 Pricing summary reflects base price, add-ons, applicable promo        | manual (depends on live promo/service data) | Step 2 |
| AC-2 PayMongo fee notice only for GCash/Maya                               | `PayMongoFeeNotice.spec.ts`                 | Step 3 |
| AC-3 Payment collection UI matches Hotel/Grooming-Daycare/Veterinary rules | manual                                      | Step 4 |
| AC-4 pay-at-counter → `payment_confirmed: false`; online → `true`          | manual (Network tab / DB check)             | Step 5 |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/booking/components/PayMongoFeeNotice
npm --prefix client run lint
```

## Manual Browser Verification

Same startup steps as `testing/docs/issues/55-booking-flow-shell/`. The
module-3 seed creates no promos, so the "promo available" line won't appear
unless you create one first via `/staff/admin/maintenance/promos` (#47) —
optional, only needed to exercise the promo half of AC-1.

### Step 1 — Reach the Review & Pay step

1. Log in as `customer1@goldenfur.com`, go to `/portal/book`.
2. Select pet **Max**, branch **Makati**, category **Grooming**, service
   **Bath**, an available slot, "No preference" on Staff, and (Add-ons step)
   check one extra Grooming service, e.g. **Brushing**.

### Step 2 — Pricing summary (AC-1)

Expected on the Review & Pay step:

- **Base price** line matches Bath's listed price.
- **Add-ons** line matches Brushing's price.
- **Estimated total** = base + add-ons.
- A note that Grooming price may be adjusted for the pet's size/coat at
  confirmation (the summary shows the catalog base price, not the tiered
  price — the tier lookup happens server-side in `booking.service.ts`).
- If you created a promo scoped to Bath or "All services" beforehand: a
  "Promo available: `<name>` (-PHP `<amount>`, applied at checkout)" line
  appears. — **AC-1**

### Step 3 — PayMongo notice (AC-2)

1. Set **Payment method** to **GCash**.

Expected: a fee-notice paragraph appears below the selector. — **AC-2**

2. Change it to **Maya** — the notice stays visible (reworded to "Maya").
3. Change it to **Cash** — the notice disappears entirely. — **AC-2**

### Step 4 — Category-specific payment rules (AC-3)

1. Start a **Hotel** booking instead (new flow) through to Review & Pay.

Expected: a "50% downpayment required now: PHP `<half the total>`" line, and
the same payment method selector. — **AC-3**

2. Start a **Veterinary** booking (Makati only) through to Review & Pay.

Expected: no payment method selector at all — just the pricing summary (PHP
0 upfront) and a "No upfront payment is required for Veterinary bookings."
message; **Confirm booking** is enabled without picking a payment method. —
**AC-3**

### Step 5 — `payment_confirmed` mapping (AC-4)

1. On a Grooming or Daycare booking, select **Cash** and click **Confirm
   booking**.
2. Open Supabase Studio (`http://127.0.0.1:54323`) → Table Editor →
   `bookings` → find the new row.

Expected: `payment_confirmed = false`, `status = 'Pending'` (a
pay-at-counter Grooming/Daycare/Hotel booking never reaches `Confirmed`
until a future Sprint 5 cashier-confirmation flow exists, per #51 AC-4). —
**AC-4**

3. Repeat with **GCash** selected instead.

Expected: `payment_confirmed = true`, `status = 'Confirmed'`. — **AC-4**

## Acceptance Criteria Checklist

- [x] **AC-1:** Pricing summary reflects base price, add-ons, and any
      applicable promo — manual Step 2.
- [x] **AC-2:** PayMongo fee notice appears only for GCash/Maya —
      `PayMongoFeeNotice.spec.ts`; manual Step 3.
- [x] **AC-3:** Hotel shows/requires the 50% downpayment option;
      Grooming/Daycare offer full-payment-online-or-pay-at-counter;
      Veterinary shows no payment collection UI — manual Step 4.
- [x] **AC-4:** Pay-at-counter creates the booking with
      `payment_confirmed: false`; online payment creates it with
      `payment_confirmed: true` — manual Step 5.

No Postman collection or SQL file for this issue: it consumes #51's existing
`POST /bookings`, already covered by
`testing/docs/issues/51-booking-creation-capacity/`.
