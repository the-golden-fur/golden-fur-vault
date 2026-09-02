# Issue #31 Verification: Customer Profile CRUD Backend

**Issue:** #31 — feat(customers): customer profile CRUD backend
**Owner:** Matthew
**Branch:** `feat/customer-profile-crud` (bundled — see Note below)
**Base:** `dev`
**Depends on:** Epic A #8, #9 merged (customer_profiles table + signup/login/OAuth-merge already exist)
**Sprint:** Sprint 1 — M02 Customer Portal & Pet Management

**Note on bundling (Jul 12, 2026):** Issues #31–#35 (all of Epic C) were bundled into a single implementation pass to save review overhead, per user request ("we're short on time"). Each issue still has its own verification doc/Postman collection/SQL script here, kept separate per issue as usual.

## Overview

Gives customers a self-service GET/PATCH over their own `customer_profiles` row, and gives staff (Receptionist/Admin/Supervisor/Superadmin) the same access on any customer's row — closing the RLS gap where `customer_profiles` previously had only customer-self policies (migration `...009`) and no staff-facing path at all. This is the prerequisite Issue #35's walk-in management depends on.

## What Changed

- **Added** `supabase/migrations/20260712022_m02_customer_profiles_staff_rls.sql` — adds staff SELECT/INSERT/UPDATE policies scoped to `current_staff_role() in ('Receptionist','Admin','Supervisor','Superadmin')`. Existing customer-self policies (`...009`) are untouched.
- **Added** `server/src/features/customers/customer.types.ts` — `CustomerProfile` interface, `CUSTOMER_MANAGER_ROLES` constant.
- **Added** `server/src/features/customers/modules/validators/customer.validator.ts` — `.strict()` Zod validator for the self-service PATCH payload; deliberately excludes `account_email` so an email change is always rejected with 400 rather than silently applied (AC-5).
- **Added** `server/src/features/customers/customer.controller.ts` — `listCustomersController`, `getCustomerProfileController`, `updateCustomerProfileController`. Each resolves "self, or authorized staff" via a local `isAuthorizedStaff()` helper rather than the existing `requireRole` middleware — `requireRole` always looks up `staff_profiles` and 403s when the row doesn't exist, which would block every customer from reaching their own data. `listCustomersController` also accepts an optional `?email=` query filter (used by Issue #35's walk-in lookup).
- **Added** `server/src/features/customers/customer.routes.ts` — `GET /customers`, `GET /customers/:id`, `PATCH /customers/:id`, all behind `jwtMiddleware` only (no `requireRole`, for the reason above). Also mounts `pets/pet.routes.ts` (Issue #32).
- **Added** `server/src/shared/auth/api/supabaseAuth.api.ts` → `getStaffRoleOrNull()` — like the existing `getStaffRole()` but resolves to `null` instead of throwing when the caller has no `staff_profiles` row (a customer). This is the helper `isAuthorizedStaff()` is built on, and it's reused by Issues #32/#33 too.
- **Modified** `server/src/shared/app.routes.ts` — mounts `customerRoutes`. (Epic D Issue #36 was going to do this formally; it's pre-wired here so Epic C is actually testable/reachable this session rather than sitting dead until Epic D lands. Epic D's own pass over this file is then a no-op for the server side.)
- **Added tests:** `customer.validator.spec.ts` (6 unit tests), `tests/customer.integration.spec.ts` (11 integration tests via `supertest` against the real `app`).

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all test files pass, typecheck produces no output, lint reports 0 errors (3 pre-existing `no-console` warnings in unrelated Epic A auth controllers are expected and unchanged).

## Structural Verification

1. Confirm the migration exists:

   ```powershell
   Get-ChildItem supabase/migrations -Filter "20260712022*"
   ```

2. Confirm the routes are registered:

   ```powershell
   Select-String -Path server/src/shared/app.routes.ts -Pattern "customerRoutes"
   Select-String -Path server/src/features/customers/customer.routes.ts -Pattern "router\.(get|patch)"
   ```

## Database Verification

1. **Push the migration**:

   ```powershell
   supabase db push
   ```

2. **Run the verification SQL script** — Supabase Studio → SQL Editor → paste and run the contents of:

   ```text
   testing/docs/issues/31-customer-profile-crud/customer-profile-crud.sql
   ```

   Confirms the 3 new staff policies exist alongside the 2 existing customer-self policies, and that the staff policies carry the correct role list.

## Postman Verification

Needs one customer account (`customer_email`/`customer_password`, its `customer_id` filled in manually — the login response doesn't return it, look it up via Supabase Studio's `customer_profiles` table or the `auth.users` table), a second customer's id (`other_customer_id`, any other seeded customer) for the cross-customer 403 checks, and one staff account with an authorized role (`staff_identifier`/`staff_password` — Receptionist, Admin, Supervisor, or Superadmin).

### A. Import and configure the collection

1. Open Postman → **Import** → `testing/docs/issues/31-customer-profile-crud/customer-profile-crud.postman_collection.json`.
2. Open **Issue 31 - Customer Profile CRUD Backend** → collection **Variables** tab. Fill in `base_url`, `customer_email`/`customer_password`/`customer_id`, `other_customer_id`, `staff_identifier`/`staff_password`. Leave the token variables blank.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 10)**. Each has a **Tests** tab that asserts automatically.

| #   | Request                                        | Expected                                   |
| :-- | :--------------------------------------------- | :----------------------------------------- |
| 1   | Login as customer                              | `200`, sets `customer_access_token`        |
| 2   | Login as staff                                 | `200`, sets `staff_access_token`           |
| 3   | AC-1: customer GETs own profile                | `200`, `customer.id` matches `customer_id` |
| 4   | AC-2: customer GETs another customer's profile | `403`                                      |
| 5   | AC-2: staff GETs the customer's profile        | `200`                                      |
| 6   | AC-3: staff lists all customers                | `200`, array                               |
| 7   | AC-3: customer attempts to list all customers  | `403`                                      |
| 8   | AC-4: customer PATCHes own profile             | `200`, change persisted                    |
| 9   | AC-5: customer PATCHes with `account_email`    | `400`                                      |
| 10  | AC-6: staff PATCHes on the customer's behalf   | `200`, change persisted                    |

The exhaustive per-role matrix (Groomer/Veterinarian/Cashier/Pet Assistant all rejected) is covered by the automated integration tests rather than repeated manually here.

## Acceptance Criteria Checklist

- [x] **AC-1:** `GET /customers/:id` returns the caller's own profile for an authenticated customer — integration test `AC-1: returns the caller's own profile...`; Postman request 3.
- [x] **AC-2:** `GET /customers/:id` for a different customer returns 403 unless the caller is an authorized staff role — integration tests `AC-2: returns 403...` / `AC-2: allows a Receptionist...`; Postman requests 4–5.
- [x] **AC-3:** `GET /customers` (list) is staff-only (Receptionist/Admin/Supervisor/Superadmin); other roles get 403 — integration tests `AC-3: is available to a Receptionist` / `AC-3: returns 403 for a Groomer` / `AC-3: returns 403 for a customer`; Postman requests 6–7.
- [x] **AC-4:** `PATCH /customers/:id` on one's own profile persists the change — integration test `AC-4: updates own profile...`; Postman request 8.
- [x] **AC-5:** `PATCH /customers/:id` rejects an `account_email` field with 400 — validator unit test + integration test `AC-5: rejects an account_email field...`; Postman request 9.
- [x] **AC-6:** An authorized staff member can PATCH any customer's profile on their behalf; an unauthorized staff role gets 403 — integration tests `AC-6: allows an authorized staff member...` / `AC-6: returns 403 for an unauthorized staff role...`; Postman request 10.
