# Issue #32 Verification: Pet CRUD Backend

**Issue:** #32 — feat(customers): pet CRUD backend
**Owner:** Matthew
**Branch:** `feat/pet-crud` (bundled — see Note below)
**Base:** `dev`
**Depends on:** #31 merged
**Sprint:** Sprint 1 — M02 Customer Portal & Pet Management

**Note on bundling (Jul 12, 2026):** Issues #31–#35 (all of Epic C) were bundled into a single implementation pass, per user request. Each issue keeps its own verification doc/Postman collection/SQL script here.

## Overview

Creates the `pets` table from scratch (it did not already exist in the repo, despite the Design doc's assumption that it was "existing... Sprint 0/1" — confirmed via a full repo search before implementation) and its full CRUD backend: customer self-service over their own pets, plus the same staff-manage-all access pattern Issue #31 established for `customer_profiles`.

## What Changed

- **Added** `supabase/migrations/20260712023_m02_create_pet_enums.sql` — `pet_species` (Dog, Cat), `pet_gender` (Male, Female), `pet_weight_class` (S, M, L, XL), `pet_coat_type` (SC, LC).
- **Added** `supabase/migrations/20260712024_m02_create_pets.sql` — the `pets` table. `customer_id`, `name`, `species`, `weight_class`, `coat_type` are `NOT NULL`; `breed`, `gender`, `date_of_birth`, `health_conditions` are nullable, per Modules-Features M02 Process 4's flowchart.
- **Added** `supabase/migrations/20260712025_m02_pets_rls.sql` — 4 customer-self policies (`auth.uid() = customer_id`, one per SELECT/INSERT/UPDATE/DELETE) + 1 staff "manage all" policy (`FOR ALL`, same role list as Issue #31). Deliberately does not touch the separately-flagged `pets.branch_id` gap (Sprint 2 follow-up per Modules-Overview).
- **Added** `server/src/features/customers/pets/pet.types.ts`, `modules/validators/pet.validator.ts` (`.strict()`, required: name/species/weight_class/coat_type), `pet.controller.ts` (list/create/get/update/delete, same self-or-authorized-staff pattern as Issue #31's controller).
- **Added** `server/src/features/customers/pets/pet.routes.ts` — `GET`/`POST /customers/:customerId/pets`, `GET`/`PATCH`/`DELETE /pets/:id`. Mounted from `customer.routes.ts`. (This file is also where Issue #33's vaccination-record/medical-note sub-routes are added, per the Guide's directory structure — see that issue's doc.)
- **Added tests:** `pet.validator.spec.ts` (8 unit tests), `pets/tests/pet.integration.spec.ts` (11 integration tests via `supertest`).

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all test files pass, typecheck produces no output, lint reports 0 errors (pre-existing unrelated warnings unchanged).

## Structural Verification

```powershell
Get-ChildItem supabase/migrations -Filter "20260712023*","20260712024*","20260712025*"
Select-String -Path server/src/features/customers/pets/pet.routes.ts -Pattern "router\.(get|post|patch|delete)"
```

## Database Verification

1. **Push the migrations**:

   ```powershell
   supabase db push
   ```

2. **Run the verification SQL script** — Supabase Studio → SQL Editor → paste and run:

   ```text
   testing/docs/issues/32-pet-crud/pet-crud.sql
   ```

   Confirms the 4 pet enums, the `pets` table shape, and its 5 RLS policies.

## Postman Verification

Needs one customer account (`customer_email`/`customer_password`, `customer_id` filled in manually), a second customer's id (`other_customer_id`) for the cross-customer 403 check, and one staff account with an authorized role (`staff_identifier`/`staff_password`).

### A. Import and configure the collection

1. Postman → **Import** → `testing/docs/issues/32-pet-crud/pet-crud.postman_collection.json`.
2. **Issue 32 - Pet CRUD Backend** → **Variables** tab → fill in `base_url`, `customer_email`/`customer_password`/`customer_id`, `other_customer_id`, `staff_identifier`/`staff_password`. Leave `pet_id`/`staff_pet_id`/token variables blank.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 12)**.

| #   | Request                                                 | Expected                            |
| :-- | :------------------------------------------------------ | :---------------------------------- |
| 1   | Login as customer                                       | `200`, sets `customer_access_token` |
| 2   | Login as staff                                          | `200`, sets `staff_access_token`    |
| 3   | AC-1: customer creates a pet, all required fields       | `201`, sets `pet_id`                |
| 4   | AC-2: missing a required field                          | `400`, `details` present            |
| 5   | AC-3: owner lists their pets                            | `200`, non-empty array              |
| 6   | AC-3: a different customer's pet list                   | `403`                               |
| 7   | AC-4: owner GETs the pet directly                       | `200`                               |
| 8   | AC-4: owner PATCHes the pet                             | `200`, change persisted             |
| 9   | AC-4: authorized staff GETs the pet                     | `200`                               |
| 10  | AC-5: staff creates a pet on behalf of another customer | `201`, sets `staff_pet_id`          |
| 11  | Cleanup: owner deletes their pet                        | `204`                               |
| 12  | Cleanup: staff deletes the walk-in pet                  | `204`                               |

## Acceptance Criteria Checklist

- [x] **AC-1:** `POST /customers/:customerId/pets` with all required fields returns 201 and creates the pet — integration test `AC-1: creates a pet...`; Postman request 3.
- [x] **AC-2:** Missing a required field returns 400 with field-level validation errors — validator unit test + integration test `AC-2: returns 400...`; Postman request 4.
- [x] **AC-3:** `GET /customers/:customerId/pets` returns only that customer's pets for the owner; 403 for a different customer — integration tests; Postman requests 5–6.
- [x] **AC-4:** `GET`/`PATCH`/`DELETE /pets/:id` succeed for the owner or authorized staff, 403 otherwise — integration tests; Postman requests 7–9.
- [x] **AC-5:** An authorized staff member can create a pet on behalf of any customer via `POST /customers/:customerId/pets` — integration test `AC-5: allows an authorized staff member...`; Postman request 10.
