# Issue #78 Verification: cage status + checkout backend — availability feed, extension fee, billing handoff

**Issue:** #78 — feat(hotel): cage status + checkout backend — availability feed, extension fee, billing handoff
**Owner:** Matthew
**Branch:** `feat/hotel-cage-status-checkout`
**Base:** `dev`
**Depends on:** #71, #72 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

Three endpoints: `GET /hotel/cages` (grid grouped by size), `GET /hotel/cages/available` (per-size Available counts, for the M03 Slot Picker feed), `PATCH /hotel/cage/:id/status` (Admin/Superadmin-only Under Maintenance toggle), and `POST /hotel/stays/:id/checkout` (extension-fee calculation, downpayment reconciliation, cage release).

### Extension fee rate — flagged judgment call

Modules-Features specifies an extension fee "per configured hotel rate" with **no concrete number**, and the real M09 Policy Configuration screen for it is explicitly Sprint 5 scope (Guide's Out of Scope). `checkout.service.ts` uses a placeholder flat `₱500/additional day` (`EXTENSION_FEE_PER_DAY`), rounding any partial extension day up to a full day. **This number is a stand-in, not a client-confirmed rate** — raise with Alarie/the client before this is treated as final; swapping it for a real M09-driven rate in Sprint 5 requires no schema change (the computed value is what's stored on `hotel_stays.extension_fee`, not the rate itself).

### Billing-ready, not a real transaction

Per Out of Scope, `transactions`/`transaction_line_items` don't exist until Sprint 5 (M08). Checkout reconciles `booking.total_price - downpayment_amount + extension_fee` and stores it, releasing the cage — no transaction row is created. `checkout.service.ts` carries a `TODO(Sprint 5, M08)` at the exact spot a real transaction-creation call should replace this.

## What Changed

- **Added** `server/src/features/hotel/services/cageStatus.service.ts` (+spec) — `getCageGrid()`, `getAvailableCageCountsBySize()`, `setCageMaintenanceStatus()`.
- **Added** `server/src/features/hotel/services/checkout.service.ts` (+spec) — `checkOutHotelStay()`, `extensionDays()` (exported, pure).
- **Modified** `server/src/features/hotel/hotel.routes.ts`, `hotel.controller.ts` — added the cage grid/available/status and checkout routes.
- **Modified** `server/src/features/booking/services/capacity.service.ts`, `availability.service.ts` — see #75's verification doc for the `getHotelCageCapacity()` real-count wiring (grouped there since it's part of the same `TODO(Sprint 4, M05)` this epic resolves).

## Acceptance Criteria Map

| AC                                                                                                 | Automated                                 | Postman           |
| -------------------------------------------------------------------------------------------------- | ----------------------------------------- | ----------------- |
| AC-1 grid query correct counts per size, excluding Under Maintenance and Occupied from "available" | `cageStatus.service.spec.ts`              | requests 3, 4     |
| AC-2 only Admin/Superadmin can set Under Maintenance/reset to Available; others rejected           | `cageStatus.service.spec.ts`              | requests 5, 6     |
| AC-3 on-time checkout: no fee; late checkout: correct fee for the additional duration              | `checkout.service.spec.ts`                | requests 8, 9     |
| AC-4 checkout reconciles total - downpayment + extension fee; cage updates to Available atomically | `checkout.service.spec.ts`                | request 8         |
| AC-5 M03 Slot Picker reflects a cage's Available status change immediately after checkout          | `capacity.service.spec.ts` (new #78 test) | manual note below |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Postman Verification

### Prerequisites

- A checked-in Hotel stay (#75).
- One **Receptionist**, one **Admin** account.

### A. Collect the IDs

Supabase Studio → `hotel_stays` → the checked-in stay's `id` (`stay_id`) and `cage_id`.

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/78-hotel-cage-status-checkout/hotel-cage-status-checkout.postman_collection.json`.
2. Fill `base_url`, `receptionist_email`/`receptionist_password`, `admin_email`/`admin_password`, `stay_id`, `cage_id`.

### C. Run requests 1→9

1. **Login Receptionist** → 200, token captured.
2. **Login Admin** → 200, token captured.
3. **AC-1 GET cage grid** → 200; `grid.S/M/L/XL` each an array; `cage_id` shows `status: "Occupied"`.
4. **AC-1 GET available counts** → 200; the Occupied cage's size is **not** counted in that size's total (compare against request 3's raw count for the size).
5. **AC-2 PATCH cage status (Receptionist, forbidden)** → **403**.
6. **AC-2 PATCH an Available cage to Under Maintenance (Admin)** → 200. Reset it back to `Available` afterward (repeat with `status: "Available"`) so it doesn't skew other tests.
7. **AC-3 on-time POST checkout** → 200; `extensionFee: null`, `remainingBalance` = `downpaymentAmount` (assuming the underlying booking's `total_price` equals `2 × downpayment_amount`, per the 50% rule — adjust the expected value if not).
8. **AC-4 verify cage released** — repeat request 3; the cage now shows `status: "Available"`.
9. **AC-3 late checkout (separate stay)** — check in a second stay, manually set its `scheduled_check_out_date` to yesterday in Supabase Studio, then checkout: `extensionFee` is `500 × <days late>`, not null and not zero.

### D. AC-5 manual Slot Picker check

`GET /bookings/availability?branch_id=...&service_category=Hotel&date=<today>&slot_duration_minutes=60&pet_weight_class=<size>` (M03, already merged) before and after step 8's checkout — the returned slot(s) `level` should improve (e.g. `full` → `available`) now that the cage is free again.
