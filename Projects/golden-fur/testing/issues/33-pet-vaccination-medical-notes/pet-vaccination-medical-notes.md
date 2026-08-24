# Issue #33 Verification: Vaccination Records + Medical Notes

**Issue:** #33 — feat(customers): vaccination records + medical notes
**Owner:** Matthew
**Branch:** `feat/pet-vaccination-medical-notes` (bundled — see Note below)
**Base:** `dev`
**Depends on:** #32 merged
**Sprint:** Sprint 1 — M02 Customer Portal & Pet Management

**Note on bundling (Jul 12, 2026):** Issues #31–#35 (all of Epic C) were bundled into a single implementation pass, per user request. Each issue keeps its own verification doc/Postman collection/SQL script here.

## Overview

First-ever CRUD and RLS for `pet_vaccination_records` and `pet_medical_notes` — both tables existed only as bare, un-RLS'd schema before this issue. Built now (ahead of Modules-Overview's documented Sprint 3 population date for vaccination records) so a receptionist can record a walk-in's existing vaccination history and annotate medical notes/allergies/behavioral flags at intake.

## What Changed

- **Added** `supabase/migrations/20260712026_m02_create_pet_vaccination_records.sql` — table (`vaccine_name`, `date_administered` NOT NULL; `next_due_date`, `administered_by`, `notes` nullable).
- **Added** `supabase/migrations/20260712027_m02_pet_vaccination_records_rls.sql` — staff (Receptionist, **Veterinarian**, Admin, Supervisor, Superadmin) manage-all; customers read-only their own pets' records via a join through `pets.customer_id`. Note the role list is broader than Issue #31/#32's `CUSTOMER_MANAGER_ROLES` — Veterinarian is added here specifically, per Modules-Features M02 Process 5 (`VACCINATION_MANAGER_ROLES` in `vaccinationRecord.service.ts`).
- **Added** `supabase/migrations/20260712028_m02_create_medical_note_category_enum.sql` — `medical_note_category` (Medical Note, Allergy, Behavioral Flag).
- **Added** `supabase/migrations/20260712029_m02_create_pet_medical_notes.sql` — table (`staff_id` NOT NULL, `created_at` defaulted).
- **Added** `supabase/migrations/20260712030_m02_pet_medical_notes_rls.sql` — staff INSERT/SELECT only (same role list); customers read-only. **No UPDATE/DELETE policy exists on this table at all** — matches the "permanent annotation trail" design.
- **Added** `server/src/features/customers/pets/services/vaccinationRecord.service.ts` (+ spec) — create/list/update/delete, each gated by `assertIsAuthorizedStaff`/`assertCanRead`.
- **Added** `server/src/features/customers/pets/services/medicalNote.service.ts` (+ spec) — **create + list only**, deliberately no update/delete function.
- **Modified** `server/src/features/customers/pets/pet.routes.ts` — adds `POST`/`GET /pets/:id/vaccination-records`, `PATCH`/`DELETE /pets/:id/vaccination-records/:recordId`, `POST`/`GET /pets/:id/medical-notes`. **No PATCH/DELETE route exists for `/pets/:id/medical-notes/:noteId` at all** — a request to it 404s at the router level, not a 403 authorization check (AC-6). Per the Guide's own affected-files list for this issue (no new controller file, only the two services + a routes.ts change), request handling for these routes is inlined directly in `pet.routes.ts` rather than added to `pet.controller.ts`.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Structural Verification

```powershell
Get-ChildItem supabase/migrations -Filter "20260712026*","20260712027*","20260712028*","20260712029*","20260712030*"
Select-String -Path server/src/features/customers/pets/pet.routes.ts -Pattern "vaccination-records|medical-notes"
```

Confirm no PATCH/DELETE route exists for medical notes:

```powershell
Select-String -Path server/src/features/customers/pets/pet.routes.ts -Pattern "medical-notes/:noteId"
```

Expected: **no matches** — the AC-6 route genuinely does not exist anywhere in the file.

## Database Verification

1. **Push the migrations**:

   ```powershell
   supabase db push
   ```

2. **Run the verification SQL script** — Supabase Studio → SQL Editor → paste and run:

   ```text
   testing/docs/issues/33-pet-vaccination-medical-notes/pet-vaccination-medical-notes.sql
   ```

   Confirms both tables' shapes, the `medical_note_category` enum, and that `pet_medical_notes` has zero UPDATE/DELETE policies.

## Postman Verification

Needs the pet's owning customer account (`customer_email`/`customer_password`, `customer_id`), a second, unrelated customer account (`other_customer_email`/`other_customer_password`) for the cross-customer 403 check, and a staff account with an authorized role (`staff_identifier`/`staff_password` — Receptionist or Veterinarian recommended, matching Modules-Features Process 5).

### A. Import and configure the collection

1. Postman → **Import** → `testing/docs/issues/33-pet-vaccination-medical-notes/pet-vaccination-medical-notes.postman_collection.json`.
2. **Issue 33 - Vaccination Records + Medical Notes** → **Variables** tab → fill in `base_url`, both customer credential pairs + `customer_id`, `staff_identifier`/`staff_password`. Leave `pet_id`/`record_id`/`note_id`/token variables blank.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 15)** — this collection creates its own test pet (request 4) rather than depending on Issue #32's collection having left one behind, and cleans it up at the end.

| #   | Request                                                    | Expected                                               |
| :-- | :--------------------------------------------------------- | :----------------------------------------------------- |
| 1   | Login as customer (pet owner)                              | `200`, sets `customer_access_token`                    |
| 2   | Login as a different customer                              | `200`, sets `other_customer_access_token`              |
| 3   | Login as staff                                             | `200`, sets `staff_access_token`                       |
| 4   | Setup: customer creates a test pet                         | `201`, sets `pet_id`                                   |
| 5   | AC-1: staff creates a vaccination record                   | `201`, sets `record_id`                                |
| 6   | AC-2: owning customer GETs records (read-only)             | `200`, non-empty array                                 |
| 7   | AC-2: a different customer is forbidden                    | `403`                                                  |
| 8   | AC-3: staff PATCHes the record                             | `200`                                                  |
| 9   | AC-3: customer PATCHing the record is forbidden            | `403`                                                  |
| 10  | AC-4: staff creates a medical note (valid category)        | `201`, `staff_id`/`created_at` present, sets `note_id` |
| 11  | AC-5: owning customer GETs notes (read-only)               | `200`, non-empty array                                 |
| 12  | AC-5: staff GETs notes                                     | `200`                                                  |
| 13  | AC-6: PATCH the medical note                               | `404` — route doesn't exist                            |
| 14  | Cleanup: staff deletes the vaccination record              | `204`                                                  |
| 15  | Cleanup: customer deletes the test pet (cascades the note) | `204`                                                  |

## Acceptance Criteria Checklist

- [x] **AC-1:** `POST /pets/:id/vaccination-records` by an authorized staff role creates a record with vaccine name, date administered, and optional next due date — unit test `AC-1: an authorized staff role creates a record...`; Postman request 5.
- [x] **AC-2:** `GET /pets/:id/vaccination-records` is available to the owning customer (read-only) and authorized staff; 403 for any other customer — unit tests; Postman requests 6–7.
- [x] **AC-3:** `PATCH`/`DELETE /pets/:id/vaccination-records/:recordId` are staff-only; a customer gets 403 — unit tests; Postman requests 8–9.
- [x] **AC-4:** `POST /pets/:id/medical-notes` by an authorized staff role creates a note with a valid category and records `staff_id` + timestamp automatically — unit test `AC-4: an authorized staff role creates a note...`; Postman request 10.
- [x] **AC-5:** `GET /pets/:id/medical-notes` is available to the owning customer (read-only) and authorized staff — unit tests; Postman requests 11–12.
- [x] **AC-6:** No PATCH or DELETE route exists for `/pets/:id/medical-notes/:noteId` at all, verified at the router level — structural verification (`Select-String` finds no match) + Postman request 13 (404, not 403).
