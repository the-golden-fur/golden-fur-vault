# Issue #22 Verification: Staff Profile CRUD Backend

**Issue:** #22 — feat(staff): staff profile CRUD backend
**Owner:** Matthew
**Branch:** `feat/staff-profile-crud-backend`
**Base:** `dev`
**Depends on:** Epic A-1 (#11–#15) merged
**Sprint:** Sprint 1 — Epic B, M01 Staff Auth & Access Control

## Overview

Adds the first non-auth staff feature: a `server/src/features/staff/` module exposing `GET /staff` (branch-scoped directory), `GET /staff/:id` (single profile), and `PATCH /staff/:id` (narrow self-service update). Authorization is enforced in the controller, not Postgres RLS — every query in this module uses the existing service-role `supabase` singleton (the same one `getStaffRole`/`getStaffBranch` already use), because `staff_profiles`' RLS policies only grant SELECT to the row owner and to Superadmins; there is no RLS policy letting an Admin read a different Admin's own branch-mate. The controller replicates that "self, or Admin within-branch, or Superadmin any-branch" rule in code instead.

## What Changed

- **Added** `server/src/features/staff/staff.types.ts` — `ALL_STAFF_ROLES` (mirrors the `staff_role` Postgres enum), `ADMIN_ROLES`, and the `StaffProfile` shape.
- **Added** `server/src/features/staff/modules/validators/staff.validator.ts` — `updateStaffProfileValidator`, a `zod` `.strict()` object allowing only `display_name`, `phone_number`, `emergency_contact_name`, `emergency_contact_number`, `preferred_communication_channel`. Any other key (including `role`, `branch_id`, `username`, `profile_photo_url`) fails validation instead of being silently stripped.
- **Added** `server/src/features/staff/modules/validators/staff.validator.spec.ts` — unit tests for the validator (valid payloads, empty payload, each disallowed field, invalid enum value).
- **Added** `server/src/features/staff/staff.controller.ts`:
  - `listStaffController` — `GET /staff`. Filters by `branch_id` for every role except `Superadmin`.
  - `getStaffProfileController` — `GET /staff/:id`. Allows the caller's own `id` for any role; for a different `id`, requires `Admin` (same branch only) or `Superadmin` (any branch), else `403`.
  - `updateStaffProfileController` — `PATCH /staff/:id`. Same authorization rule as the GET, then validates the body against `updateStaffProfileValidator` (`400` on failure) before writing.
- **Added** `server/src/features/staff/staff.routes.ts` — mounts all three routes behind `jwtMiddleware → requireRole(ALL_STAFF_ROLES) → requireBranch`, reusing the existing Epic A-1 middleware unmodified.
- **Added** `server/src/features/staff/tests/staff.integration.spec.ts` — 11 supertest cases covering AC-1 through AC-5 plus the Admin branch-scoping behavior described in the issue's dev notes.
- **Modified** `server/src/shared/app.routes.ts` — registers the new `staffRoutes` router alongside the existing `authRoutes`.

### Scope notes

- `profile_photo_url` is never accepted by the PATCH validator and is not written by this controller — it stays reserved for the avatar service (#23), per the issue's dev notes.
- `role`, `branch_id`, and `username` changes are out of scope for this endpoint entirely (for both self and Admin callers) — there is no code path in this controller that can write them, regardless of who the caller is.
- Admin access to a _different_ staff member's profile (GET or PATCH) is branch-scoped; Superadmin is not. This isn't explicitly spelled out in AC-2's wording, but it's what the issue's Development Notes describe ("Admin/Superadmin access within/across branch per existing policy") and matches AC-3's list-scoping rule, so the integration suite covers both the literal AC-2 case (non-admin → 403) and this extra Admin-branch-scoping behavior.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected result: all server test files pass (20 files / 149 tests as of this pass, including the 11 new integration tests and 11 new validator tests), `tsc --noEmit` produces no output, and `eslint .` reports 0 errors (3 pre-existing `no-console` warnings, unrelated to this change).

## Structural Verification

1. Confirm the new feature files exist:

   ```powershell
   Get-ChildItem server/src/features/staff -Recurse -File
   ```

   Expected: `staff.controller.ts`, `staff.routes.ts`, `staff.types.ts`, `modules/validators/staff.validator.ts`, `modules/validators/staff.validator.spec.ts`, `tests/staff.integration.spec.ts`.

2. Confirm the router is registered:

   ```powershell
   Select-String -Path server/src/shared/app.routes.ts -Pattern "staffRoutes"
   ```

   Expected: two matches (the import and the `router.use(staffRoutes)` call).

3. Confirm `profile_photo_url` is never written by this controller:

   ```powershell
   Select-String -Path server/src/features/staff/staff.controller.ts,server/src/features/staff/modules/validators/staff.validator.ts -Pattern "profile_photo_url"
   ```

   Expected: no matches.

## Postman Verification

This module needs at least one real staff account per role (a regular staff role, an `Admin`, and a `Superadmin`), spread across **two different branches**, so the branch-scoping checks (AC-2's Admin case, AC-3) have something real to assert against. If your Supabase project doesn't have this yet, seed it first — steps below assume you don't normally use Supabase Studio, so they're spelled out in full.

### A. Find the staff IDs and branch IDs you'll need (Supabase Studio)

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and open this project.
2. In the left sidebar, click the **Table Editor** icon (looks like a grid/spreadsheet).
3. From the table dropdown at the top, select **staff_profiles**.
4. You'll see columns including `id`, `branch_id`, `username`, `role`. Widen columns by dragging their borders if you need to read full UUIDs, or click a cell to see its full value in a side panel.
5. Identify (and write down) the following rows:
   - **Self staff**: any non-Admin, non-Superadmin row (e.g. `role = Receptionist`). Note its `id` (→ `staff_id`) and `branch_id`.
   - **Peer staff**: a _different_ row with the **same** `branch_id` as your self staff. Note its `id` (→ `peer_staff_id`).
   - **Admin**: a row with `role = Admin`. Note its `branch_id` — this is "the admin's branch".
   - **Admin same-branch staff**: any row (other than the Admin itself) sharing the Admin's `branch_id` (→ `admin_same_branch_staff_id`).
   - **Admin other-branch staff**: any row with a _different_ `branch_id` from the Admin (→ `admin_other_branch_staff_id`).
   - **Superadmin**: a row with `role = Superadmin`.
   - **Any other-branch staff** for the Superadmin check (→ `any_other_branch_staff_id`) — can reuse `admin_other_branch_staff_id`.
6. For each of the three login accounts (self staff, Admin, Superadmin) you'll also need their `username` (or `registered_email`) and password to log in through the API — use accounts you created yourself during setup/testing, since Supabase Studio does not show plaintext passwords.

If you don't have staff members split across two branches yet, open the **branches** table the same way, confirm at least two branch rows exist, then edit a couple of `staff_profiles.branch_id` values in Studio (double-click the cell, paste a different branch's UUID, press Enter) to spread your test accounts across branches. This is safe to do on a dev/test project.

### B. Import and configure the collection

1. Open Postman.
2. Click **Import** (top left) → **Files** → browse to `testing/docs/issues/22-staff-profile-crud-backend/staff-profile-crud-backend.postman_collection.json` (or drag the file onto the Import window).
3. Open the imported collection, **Issue 22 - Staff Profile CRUD Backend**.
4. Click the collection name → **Variables** tab. Fill in the **Current value** column (leave **Initial value** as-is or copy the same value in):
   - `base_url` — `http://localhost:3000` (default; adjust if `SERVER_PORT` differs).
   - `staff_identifier`, `staff_password`, `staff_id` — the self staff account from step A.
   - `peer_staff_id` — the peer staff from step A.
   - `admin_identifier`, `admin_password` — the Admin account's login.
   - `admin_same_branch_staff_id`, `admin_other_branch_staff_id` — from step A.
   - `superadmin_identifier`, `superadmin_password` — the Superadmin account's login.
   - `any_other_branch_staff_id` — from step A.
   - Leave every `*_access_token` variable blank — the login requests fill these in automatically.
5. Click **Save** (Ctrl+S) to persist the variable values.

### C. Start the server and run the requests

1. Start the server:
   ```powershell
   npm --prefix server run dev
   ```
2. In Postman, open each request **in order (1 → 14)** and click **Send**. Each request has a **Tests** tab with an assertion that runs automatically and shows a pass/fail check under the **Test Results** tab of the response panel.
3. Expected result per request:

   | #   | Request                                     | Expected                                                |
   | :-- | :------------------------------------------ | :------------------------------------------------------ |
   | 1   | Login as self                               | `200`, sets `staff_access_token`                        |
   | 2   | AC-1: GET own profile                       | `200`, `staff.id` equals `staff_id`                     |
   | 3   | AC-2: GET a different staff_id as non-admin | `403`                                                   |
   | 4   | AC-4: PATCH own profile, valid payload      | `200`, `staff.display_name` = `"Postman Verified Name"` |
   | 5   | AC-5: PATCH sets `role`                     | `400`                                                   |
   | 6   | AC-5: PATCH sets `branch_id`                | `400`                                                   |
   | 7   | AC-3: GET `/staff` list as non-Superadmin   | `200`, exactly one distinct `branch_id` across results  |
   | 8   | Login as Admin                              | `200`, sets `admin_access_token`                        |
   | 9   | AC-2: Admin GET same-branch staff_id        | `200`                                                   |
   | 10  | Admin GET other-branch staff_id             | `403` (branch-scoping from the dev notes)               |
   | 11  | AC-3: GET `/staff` list as Admin            | `200`, exactly one distinct `branch_id`                 |
   | 12  | Login as Superadmin                         | `200`, sets `superadmin_access_token`                   |
   | 13  | AC-3: GET `/staff` list as Superadmin       | `200`, more than one distinct `branch_id`               |
   | 14  | AC-2: Superadmin GET any staff_id           | `200`                                                   |

4. After request 4, you can also confirm persistence directly in Supabase Studio: reopen **Table Editor → staff_profiles**, find the self staff row by `id`, and confirm `display_name` now reads `Postman Verified Name`.

## Acceptance Criteria Checklist

- [x] **AC-1:** `GET /staff/:id` returns the caller's own profile for any authenticated staff role — integration test `AC-1: returns the caller's own profile...`, Postman request 2.
- [x] **AC-2:** `GET /staff/:id` for a different `staff_id` returns `403` unless the caller is Admin or Superadmin — integration tests `AC-2: returns 403...`, `AC-2: allows an Admin...`, `AC-2: allows a Superadmin...`; Postman requests 3, 9, 14.
- [x] **AC-3:** `GET /staff` returns only the caller's branch for non-Superadmin roles, and all branches for Superadmin — integration tests under `GET /staff`; Postman requests 7, 11, 13.
- [x] **AC-4:** `PATCH /staff/:id` on one's own profile with a valid payload returns `200` and persists the change — integration test `AC-4: updates and persists...`; Postman request 4 (+ Supabase Studio spot-check).
- [x] **AC-5:** `PATCH /staff/:id` rejects unknown/disallowed fields (`role`, `branch_id`) with `400` — integration tests `AC-5: rejects an attempt to set role...` / `...branch_id...`; validator unit tests; Postman requests 5, 6.
