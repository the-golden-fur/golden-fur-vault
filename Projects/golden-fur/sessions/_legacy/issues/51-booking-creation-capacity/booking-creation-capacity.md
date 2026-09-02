# Issue #51 Verification: booking creation + capacity enforcement backend

**Issue:** #51 — feat(booking): booking creation + capacity enforcement backend (4 service types)
**Owner:** Matthew
**Branch:** `feat/booking-creation-capacity`
**Base:** `dev`
**Depends on:** #49, #50 merged
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

`POST /bookings` with fully automatic confirmation: veterinary branch guard (#53) → pet-ownership check → pricing snapshot (service tier / package bundle + add-ons) → payment gate → authoritative capacity check → atomic insert + post-insert race re-verification. No manual review step exists anywhere in the flow.

Capacity is dispatched by `service_category`:

- **Hotel** — cage count by pet size (S/M/L/XL). **Stub numbers** (real `cages` table is M05/Sprint 4): defaults S:10 M:8 L:6 XL:4 per branch, overridable via the `HOTEL_CAGE_CAPACITY` env var (JSON — global sizes or keyed by branch id). Flagged with a `TODO(Sprint 4, M05)` in `capacity.service.ts`.
- **Grooming / Veterinary** — at least one `get_staff_availability()`-eligible staff member (#49), or the one specifically requested.
- **Daycare** — per-branch session cap. **Stub number** (M06 is Sprint 3): default 15, `DAYCARE_SESSION_CAPACITY` env override. `TODO(Sprint 3, M06)`.

The capacity check deliberately runs twice — read-only at Slot Picker time and again at submission — and confirmation is race-safe: after insert, overlapping Confirmed rows are re-ranked by `(created_at, id)`; a loser deletes its own row and returns the "capacity taken" error (AC-5).

## What Changed

- **Added** `server/src/features/booking/booking.routes.ts`, `booking.controller.ts`, `booking.types.ts` (registered in `server/src/shared/app.routes.ts`).
- **Added** `modules/validators/booking.validator.ts` (+spec) — exactly-one-of service/package, window sanity, payment_method stub vocabulary, staff-preference shape.
- **Added** `services/booking.service.ts` (+spec) — creation orchestration; also `GET /bookings/:id` with ownership check.
- **Added** `services/capacity.service.ts` (+spec) — the four capacity paths + post-insert re-verification.
- **Added** `tests/booking.integration.spec.ts` — HTTP-level coverage.
- Grooming pricing uses the pet's `service_pricing_tiers` cell (S/M/L/XL × SC/LC) when one exists, else `base_price`. Hotel `downpayment_amount` = hardcoded 50% of `total_price` (policy column is Sprint 5 scope). The `booking_confirmed` notification is a log-stub (`TODO(Sprint 6, M11)`).

### Decisions flagged for the reviewer

1. **Pay-at-counter persists as `Pending`** (`payment_confirmed = false` for Hotel/Grooming/Daycare). The Design sheet's enum note says failed gates "do not persist", but Guide #58 AC-4 requires the booking to exist with `payment_confirmed = false`; `Pending` satisfies #51 AC-4 literally (it never _reaches Confirmed_) and keeps #58 buildable. Pending rows do **not** occupy capacity (all counts filter `status = 'Confirmed'`).
2. Promos are **not** applied to `total_price` — #58 reads promos for the pricing-summary display; real promo/discount math belongs to M08 (Sprint 5).

## Acceptance Criteria Map

| AC                                                             | Automated                                                                            | Postman                                                                     |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| AC-1 POST creates bookings for all 4 types                     | `booking.service.spec.ts`, integration spec                                          | requests 2–6                                                                |
| AC-2 capacity rejections per type                              | `capacity.service.spec.ts`                                                           | requests 8 (staff) — Hotel/Daycare need stub-capacity env tricks, see below |
| AC-3 Southwoods Veterinary rejected via #51's path             | `booking.service.spec.ts` ("before any capacity path")                               | request 7                                                                   |
| AC-4 Confirmed only after capacity + payment gate; Vet ungated | unit + integration specs                                                             | requests 3, 4, 6                                                            |
| AC-5 concurrent race: exactly one wins                         | `booking.service.spec.ts` race-loser test + `capacity.service.spec.ts` ranking tests | request 9 (sequential approximation only)                                   |
| AC-6 cross-customer pet rejected                               | unit + integration specs                                                             | request 10                                                                  |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all 46 test files / 457 tests pass; typecheck silent; lint 0 errors (3 pre-existing `no-console` warnings).

## Postman Verification

### Prerequisites

- Migrations `035–037` pushed (`supabase db push`) and Sprint 1 (#38) + Epic A (#44) seed data applied.
- One **customer** account you can log in with, that owns at least one pet.
- A second customer with a pet (for the AC-6 test).

### A. Collect the IDs (Supabase Studio)

Open **Supabase Studio → Table Editor** (left sidebar):

1. `branches` — copy the `id` of the Makati row (`branch_makati_id`) and the Southwoods row (`branch_southwoods_id`).
2. `services` — copy one `id` per category: Grooming → `grooming_service_id`, Daycare → `daycare_service_id`, Hotel → `hotel_service_id`, Veterinary → `vet_service_id`. Optionally a second Grooming service (e.g. nail trim) as `addon_service_id`.
3. `pets` — copy the `id` of a pet owned by **your** customer (`pet_id`) and one owned by a **different** customer (`other_customer_pet_id`).

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/51-booking-creation-capacity/booking-creation-capacity.postman_collection.json`.
2. Open the collection → **Variables** tab → fill `base_url` (default `http://localhost:3000`), `customer_account_email`, `customer_password`, and every id from step A. Leave tokens/booking ids/slot times blank — the collection computes slot times (next Monday, 10:00–13:00 Asia/Manila expressed in UTC) and captures the rest automatically.
3. Save (Ctrl+S).

### C. Start the server

```powershell
npm --prefix server run dev
```

### D. Run requests 1→10 in order (top to bottom)

Each request carries its own tests — the **Test Results** tab must be green:

1. **Login customer** → 200, token captured.
2. **AC-1 Create Grooming (paid online)** → 201; `status = "Confirmed"`, `assigned_staff_id` non-null (auto-assigned), `total_price` reflects the pet's size/coat tier when one exists. Captures `grooming_booking_id` + `assigned_groomer_id`.
3. **AC-1/AC-4 Create Daycare (pay-at-counter)** → 201; `status = "Pending"`, `payment_confirmed = false`.
4. **AC-1/AC-4 Create Hotel (50% downpayment)** → 201; `downpayment_amount` = exactly half of `total_price`; `status = "Confirmed"`.
5. **AC-1 Create Veterinary at Makati (no payment)** → 201; `status = "Confirmed"` with no payment fields sent at all.
6. **Add-on snapshot (optional — needs `addon_service_id`)** → 201; `booking_addons` row present with `price_at_booking`.
7. **AC-3 Veterinary at Southwoods** → **422** and the error names branch eligibility ("Makati"), _not_ capacity.
8. **AC-2 Same groomer, same slot, specific preference** → **409** ("no longer available") — the staff member booked in request 2 fails the single-staff re-verification.
9. **AC-5 (sequential approximation) duplicate Grooming slot** → 201 while other groomers remain free at that slot, then 409 once none are. If your seed has several groomers, duplicate this request until it 409s. The true _concurrent_ race is covered by the automated race-loser unit test.
10. **AC-6 other customer's pet** → **403** ("Pet does not belong to this customer").

### E. Hotel/Daycare capacity rejections (AC-2, optional but quick)

The stubs default to capacities you won't exhaust by hand (10 cages / 15 sessions), so shrink them via env for one run:

```powershell
$env:HOTEL_CAGE_CAPACITY = '{"S":1,"M":1,"L":1,"XL":1}'
$env:DAYCARE_SESSION_CAPACITY = '1'
npm --prefix server run dev
```

Re-run request 4 twice with the same dates → second returns **409** "No S-size cages available…". Re-run request 3 twice (after setting `payment_confirmed: true` in its body so the first occupies capacity) → second returns **409** "Daycare session capacity is full…". Close the terminal (or `Remove-Item Env:HOTEL_CAGE_CAPACITY`, `Remove-Item Env:DAYCARE_SESSION_CAPACITY`) afterwards.

### F. Cleanup

Supabase Studio → Table Editor → `bookings` → filter `special_instructions` = `issue51-postman` → delete the rows (add-ons/preferences cascade).
