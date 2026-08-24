# Issue #53 Verification: server-side Makati-only Veterinary enforcement

**Issue:** #53 — feat(booking): server-side Makati-only Veterinary enforcement
**Owner:** Matthew
**Branch:** `feat/makati-vet-enforcement`
**Base:** `dev`
**Depends on:** #51 merged
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

A single guard function — `assertVeterinaryBranchEligibility()` — rejects any `service_category = 'Veterinary'` request whose branch has `branches.is_vet_branch = false`, at the **API layer**, so a crafted or replayed request can't create an invalid booking even though #55's UI will also hide the option. It is called:

- at the very top of `booking.service.ts`'s creation flow, **before any capacity check** — a Veterinary booking at Southwoods fails fast with a distinct branch-eligibility error (422), never a confusing "no capacity" error;
- by `reschedule.service.ts` (#54) whenever a reschedule targets a branch — so moving a Makati Veterinary booking to Southwoods is rejected by the same guard.

The client-side filtering #55 adds later is a UX convenience; this is the enforcement boundary and must not be replaced by it.

## What Changed

- **Added** `server/src/features/booking/services/veterinaryEligibility.service.ts` (+spec) — the guard; no-op for every non-Veterinary category (AC-2), 404 on unknown branch, 422 with a message naming Makati exclusivity otherwise.
- **Modified** `services/booking.service.ts` — calls the guard first (before pricing/capacity).
- (#54's `reschedule.service.ts` calls the same guard for branch changes — its wiring is verified here as AC-4 and again in #54's own doc.)

## Prerequisite check (Guide)

Confirm `branches.is_vet_branch` is populated correctly on dev: Supabase Studio → **Table Editor → branches** — the Makati row must show `is_vet_branch = true`, Southwoods `false`. (The column has existed since migration `20260625001`.)

## Acceptance Criteria Map

| AC                                                                                 | Automated                                                          | Postman   |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------- |
| AC-1 direct API Veterinary-at-Southwoods → distinct clear error (not 500/capacity) | `veterinaryEligibility.service.spec.ts`, `booking.service.spec.ts` | request 2 |
| AC-2 Grooming/Hotel/Daycare at Southwoods unaffected                               | spec (guard never queries branches for them)                       | request 3 |
| AC-3 Veterinary at Makati unaffected                                               | spec                                                               | request 4 |
| AC-4 reschedule of a Makati Vet booking to Southwoods rejected                     | `reschedule.service.spec.ts`                                       | request 5 |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Postman Verification

Needs one **customer** account with a pet, and the ids below from Supabase Studio → Table Editor: `branch_makati_id`, `branch_southwoods_id` (`branches`), `pet_id` (`pets`, owned by your customer), `vet_service_id` (`services` where category = Veterinary), `daycare_service_id`.

1. Import `makati-vet-enforcement.postman_collection.json` → fill the collection variables → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login customer** → 200.
   2. **AC-1 Veterinary at Southwoods** → **422**; the error message names Makati/branch eligibility and does **not** mention capacity, and is not a 500.
   3. **AC-2 Daycare at Southwoods** → **201** — the guard is scoped to Veterinary only.
   4. **AC-3 Veterinary at Makati** → **201 Confirmed**; captures `vet_booking_id`.
   5. **AC-4 Reschedule that Vet booking to Southwoods** → **422** from the same guard.
4. Cleanup: Studio → `bookings` → delete rows with `special_instructions = issue53-postman`.

## Notes

- The guard reads `is_vet_branch` rather than hardcoding a branch name, so a future third branch that offers Veterinary works without code changes — "Makati-only" is data, the code enforces "vet-branch-only".
