# Issue #75 Verification: check-in backend — cage assignment + care instruction capture + care log generation

**Issue:** #75 — feat(hotel): check-in backend — cage assignment + care instruction capture + care log generation
**Owner:** Matthew
**Branch:** `feat/hotel-check-in-backend`
**Base:** `dev`
**Depends on:** #71, #72, #73, #74 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

`POST /hotel/check-in` — a single flow that: validates the confirmed Hotel booking, resolves/claims a cage (server-suggested by the pet's `weight_class`, or a validated manual override), writes the three `care_*_instructions` tables, and auto-generates one `care_log_entries` row per scheduled action per day of the stay. Two supporting GET endpoints back the check-in form's live pre-fill: `GET /hotel/pets/:petId/cage-suggestion` and `GET /hotel/pets/:petId/current-prescription` (a thin proxy over M07's `currentPrescription.service.ts`, reused directly per that service's own Sprint 3 dev note anticipating this exact use).

### Not a real DB transaction

`supabase-js` has no cross-table transaction here. A failure after the cage is claimed (e.g. the `hotel_stays` insert fails) releases the cage back to `Available` as a compensating action (`cageAssignment.service.ts`'s `releaseCage`) — covered by a dedicated test (`careInstructions.service.spec.ts`, "releases the claimed cage if the hotel_stays insert fails").

### Medication pre-fill dual path

Per the Guide's dev notes ("the endpoint reads `consultations.medications`... at check-in"), the service itself auto-fills when the request's `medications` field is **omitted entirely**: empty when no current prescription exists, or copied from M07's current-prescription derivation (with a `source_prescription_note`) when one does. When the request **provides** the field (including `[]`), it's used verbatim as the receptionist's own, possibly-edited list — matching AC-3 and #73's "one-time copy, never a live FK" design. The frontend (#79) calls `GET .../current-prescription` first to show the pre-fill live in the form, then always submits the final (possibly edited) list explicitly.

### M03 Slot Picker / capacity integration

`server/src/features/booking/services/capacity.service.ts` carried an explicit `TODO(Sprint 4, M05): replace with a real count against the cages table` for `getHotelCageCapacity()`. That stub is now replaced with a real `count(*)` against `cages` (env override still available). The _reservation_ capacity model (counting overlapping Confirmed bookings against this total) is unchanged and intentionally **not** replaced with a `cages.status = 'Available'` count — `cages.status` only reflects physical occupancy _right now_, and would incorrectly shrink capacity for a future date range just because today's cage happens to be occupied by an unrelated, already-checked-out-by-then stay. See the code comment on `getHotelCageCapacity` for the full reasoning.

## What Changed

- **Added** `server/src/features/hotel/hotel.types.ts`, `server/src/features/hotel/modules/validators/hotel.validator.ts` (`checkInValidator`, `cageStatusUpdateValidator`).
- **Added** `server/src/features/hotel/services/cageAssignment.service.ts` (+spec) — `suggestCage()`, `assignCage()` (optimistic claim, conditional `UPDATE ... WHERE status = 'Available'`), `releaseCage()`.
- **Added** `server/src/features/hotel/services/careInstructions.service.ts` (+spec) — `checkInHotelStay()` orchestrator, `enumerateDates()` (exported, pure).
- **Added** `server/src/features/hotel/hotel.controller.ts`, `hotel.routes.ts` — registered in `server/src/shared/app.routes.ts`.
- **Modified** `server/src/features/booking/services/capacity.service.ts`, `availability.service.ts` — `getHotelCageCapacity()` is now async and queries `cages` for the real per-branch, per-size count (see above).

## Acceptance Criteria Map

| AC                                                                                           | Automated                                                             | Postman                               |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------- |
| AC-1 one transaction-equivalent: `hotel_stays` + instruction rows + full care log            | `careInstructions.service.spec.ts`                                    | request 5                             |
| AC-2 cage suggestion matches weight_class; override validated; Occupied/Maintenance rejected | `cageAssignment.service.spec.ts`                                      | requests 3, 6                         |
| AC-3 medication pre-fill from M07 when it exists; empty when it doesn't                      | `careInstructions.service.spec.ts`                                    | requests 4, 5                         |
| AC-4 cage status updates to Occupied atomically with the `hotel_stays` insert                | `cageAssignment.service.spec.ts` + `careInstructions.service.spec.ts` | request 5                             |
| AC-5 check-in rejected for non-Hotel or non-Confirmed bookings                               | `careInstructions.service.spec.ts`                                    | manual (needs a pre-made bad booking) |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all test files pass, including the new `hotel/services/*.spec.ts` files and the updated `capacity.service.spec.ts` (added one test for the real cages-table count).

## Postman Verification

### Prerequisites

- Migrations `050`–`053` pushed and the `module-4-hotel` seed applied (`supabase db reset` locally, or `npm run seed:module-4` / `supabase db push` + run `module-4-hotel.seed.sql` manually against a hosted project).
- One **Receptionist** account (Sprint 1 seed data or your own).
- A **Confirmed Hotel booking** for **today**, for a pet with a `weight_class` that has at least one seeded cage — create one via `POST /bookings` (`service_category: "Hotel"`).
- Optional, for AC-3's "prescription exists" branch: a **Completed** M07 consultation for the same pet with at least one medication (`POST /veterinary/consultations/:id` flow, or seed directly).

### A. Collect the IDs (Supabase Studio)

1. `staff_profiles` — Receptionist's `id`.
2. `bookings` — the Confirmed Hotel booking's `id` and its `pet_id`.

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/75-hotel-check-in-backend/hotel-check-in-backend.postman_collection.json`.
2. Fill `base_url`, `receptionist_email`/`receptionist_password`, `hotel_booking_id`, `pet_id`. Leave `receptionist_token`/`cage_id`/`stay_id` blank.

### C. Start the server and run requests 1→6 in order

```powershell
npm --prefix server run dev
```

1. **Login Receptionist** → 200, token captured.
2. **GET cage suggestion** → 200; `suggestedSize` matches the pet's `weight_class`; `availableCages` non-empty (seed provides 2 of S/M/L, 1 of XL per branch). Captures `cage_id`.
3. **GET current prescription** → 200; `prescription` is `null` if you skipped the optional M07 setup, or populated otherwise.
4. **AC-1/AC-3/AC-4 POST check-in** → 201; response includes `stay` (`status: "Active"`), the requested `feeding`/`walking`/`medications` rows, and `careLogEntries` (one row per scheduled action per day). Captures `stay_id`.
5. **AC-2/AC-4 verify cage Occupied** — Supabase Studio → `cages` → the row for `cage_id` now shows `status = "Occupied"`.
6. **AC-2 POST check-in again with the same cage (second booking)** → **409** "Selected cage is not available".

### D. Cleanup

Supabase Studio → delete the `care_log_entries` / `care_*_instructions` / `hotel_stays` rows created above (in that FK order, or rely on `ON DELETE CASCADE` from `hotel_stays`), then reset the cage's `status` back to `Available` if needed.
