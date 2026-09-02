# Issue #66 Verification: veterinary consultation backend — vitals/diagnosis/procedures + vaccination record + current-prescription derivation

**Issue:** #66 — feat(veterinary): consultation backend — vitals/diagnosis/procedures + vaccination record + current-prescription derivation
**Owner:** Matthew
**Branch:** `feat/veterinary-consultation-backend`
**Base:** `dev`
**Depends on:** #63 merged
**Sprint:** Sprint 3 Epic A — M07 Health & Veterinary Management

## Overview

`GET /veterinary/consultations/queue` (today's Makati consultations, auto-vivifying a `'Pending'` row for any confirmed Veterinary booking that doesn't have one yet — mirrors #64's `grooming_sessions` pattern) + `PATCH /veterinary/consultations/:id` (records vitals/diagnosis/medications while `Ongoing`; on → `Completed`, writes `consultation_line_items` and optionally a `pet_vaccination_records` row) + `GET /veterinary/pets/:petId/current-prescription` (read-only, computed on demand) + `GET /veterinary/pets/:petId/history` (read-only, for the Pet History tab).

## What Changed

- **Added** `server/src/features/veterinary/veterinary.types.ts` — `VETERINARY_READ_ROLES` (`Veterinarian/Admin/Supervisor/Superadmin/Receptionist`), `VETERINARY_WRITE_ROLES` (`Veterinarian` only), `Consultation`, `ConsultationLineItem`, `CurrentPrescription`.
- **Added** `server/src/features/veterinary/modules/validators/veterinary.validator.ts` — `updateConsultationValidator` (status only ever `'Ongoing'|'Completed'`; `professional_fee` and a per-medication `amount` required only when completing).
- **Added** `server/src/features/veterinary/services/consultation.service.ts` (+spec, 9 tests) — `listConsultationQueue()` (auto-vivifying, unscoped by requester — no per-vet restriction), `getConsultation()`, `listPetConsultationHistory()`, `updateConsultation()`.
- **Added** `server/src/features/veterinary/services/currentPrescription.service.ts` (+spec, 2 tests) — `getCurrentPrescription()`, its own file since M05 (Sprint 4) will call it directly for Hotel check-in auto-fill.
- **Added** `server/src/features/veterinary/veterinary.controller.ts`, `veterinary.routes.ts` (shared with #67 — see decision note below), registered in `server/src/shared/app.routes.ts`.

### Decision flagged for the reviewer: `veterinary.routes.ts` is wired here, not in #67

The Guide's Affected Files list `veterinary.routes.ts` only under Issue #67, not #66. Since both issues are implemented in this same session/branch pass, `veterinary.controller.ts`/`veterinary.routes.ts` were created once and register both #66's consultation/current-prescription/history endpoints and #67's follow-up endpoint together — there's no functional reason to split one Express router file across two commits when both land at once. **Raise with Alarie if a strictly separate #66-only routes file was intended** (e.g. for a different merge order than assumed here).

### Decision flagged for the reviewer: line-item amounts are caller-supplied, not a fee schedule

Neither the Guide nor `Sprint3-EpicA-Design.xlsx` specifies a professional-fee amount or per-medication/procedure pricing anywhere (M08's real fee schedule is Sprint 5 scope). `consultation_line_items.amount` is `NOT NULL`, so the PATCH payload requires the vet to supply `professional_fee` and an `amount` per medication/procedure at completion time (validated in `veterinary.validator.ts`); nothing is defaulted or invented. **Raise with Alarie if a fixed/configurable professional fee was actually intended for this sprint.**

## Acceptance Criteria Map

| AC                                                                                                                               | Automated                                    | Postman                                    |
| -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------ |
| AC-1 any Veterinarian can open any Pending/Ongoing Makati consultation, record vitals/diagnosis/medications/procedures           | `consultation.service.spec.ts`               | requests 3, 5                              |
| AC-2 marking Completed writes `consultation_line_items` for professional fee + every medication + procedure                      | `consultation.service.spec.ts`               | request 6                                  |
| AC-3 vaccination updates during a consultation immediately update `pet_vaccination_records` and are reflected on the pet profile | `consultation.service.spec.ts`               | request 6 (manual Supabase Studio check)   |
| AC-4 current prescription returns the single most recent Completed consultation's medications, without altering prior records    | `currentPrescription.service.spec.ts`        | request 7                                  |
| AC-5 a consultation cannot be created against a non-Makati booking (server-side)                                                 | `consultation.service.spec.ts` ("AC-5" test) | not exercised via Postman — see note below |

**Note on AC-5 in Postman:** a Veterinary booking at a non-Makati branch is already rejected at booking-creation time (#53, `assertVeterinaryBranchEligibility`), so there is no way to reach a "non-Makati Veterinary booking" through the normal API to then exercise this auto-vivify re-check — it's a defense-in-depth guard for a state the API itself never produces. Covered by the automated unit test (which calls the service directly against a mocked non-Makati booking row) instead of Postman.

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all 54 test files / 499 tests pass (11 new for this issue across `consultation.service.spec.ts` + `currentPrescription.service.spec.ts`, plus 3 more from #67's `followUp.service.spec.ts` landing in the same pass); typecheck silent; lint 0 errors (3 pre-existing `no-console` warnings, unrelated).

## Postman Verification

### Prerequisites

- Migrations through `040` pushed (`supabase db push`) — no new migration in this issue.
- One **Veterinarian** account at Makati and one **Receptionist** account at Makati (Sprint 1 seed data, e.g. `makati.vet1@goldenfur.com` / `makati.receptionist1@goldenfur.com`, password `password123`).
- A **Confirmed Veterinary booking** at Makati for **today**, assigned to that Veterinarian — the fastest way is #51's booking collection with `scheduled_start`/`scheduled_end` set to a slot later today and `service_category: "Veterinary"`, `branch_id` = Makati's.

### A. Collect the IDs (Supabase Studio)

1. `staff_profiles` — the Veterinarian's `id` (must match the booking's `assigned_staff_id`).
2. `bookings` — the `id` of today's Confirmed Veterinary booking at Makati (`vet_booking_id`).

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/66-veterinary-consultation-backend/veterinary-consultation-backend.postman_collection.json`.
2. Open the collection → **Variables** tab → fill `base_url`, `vet_email`/`vet_password`, `receptionist_email`/`receptionist_password`, `vet_booking_id`. Leave tokens/`consultation_id`/`pet_id` blank — the collection captures them automatically.
3. Save (Ctrl+S).

### C. Start the server

```powershell
npm --prefix server run dev
```

### D. Run requests 1→9 in order (top to bottom)

Each request carries its own tests — the **Test Results** tab must be green:

1. **Login Veterinarian** → 200, token captured.
2. **Login Receptionist** → 200, token captured.
3. **GET queue (Vet)** → 200; consultation for `vet_booking_id` appears with `status = "Pending"` (auto-created on first list). Captures `consultation_id`, `pet_id`.
4. **Receptionist attempts PATCH** → **403** (Receptionist can read consultations but not write clinical fields).
5. **AC-1 PATCH → Ongoing with vitals/diagnosis** (Vet) → 200; `status = "Ongoing"`, diagnosis and medications saved.
6. **AC-2/AC-3 PATCH → Completed with line items + vaccination** (Vet) → 200; `status = "Completed"`, `completed_at` set. Then in Supabase Studio → Table Editor, confirm `consultation_line_items` has 3 rows for this `consultation_id` (`professional_fee` ₱500, `medication` ₱150, `procedure`/`Vaccination` ₱300) and `pet_vaccination_records` has a new `Rabies` row for `pet_id`.
7. **AC-4 GET current prescription** → 200; `medications[0].name = "Amoxicillin"`, `consultation_id` matches the one just completed.
8. **GET pet history** → 200; the completed consultation appears with its diagnosis.
9. **PATCH an already-Completed consultation** → **409** with an "already finalized" message.

### E. Cleanup

Supabase Studio → Table Editor → delete the `consultation_line_items` rows (filter by `consultation_id`), then the `consultations` row, then the `pet_vaccination_records` row created in step 6 (filter by `pet_id`). The underlying `bookings` row can stay or be deleted alongside.
