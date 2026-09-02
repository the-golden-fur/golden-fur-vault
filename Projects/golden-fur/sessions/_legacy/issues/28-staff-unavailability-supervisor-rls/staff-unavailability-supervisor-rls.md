# Issue #28 Verification: Grant Supervisor on-behalf-of access for Unavailability Blocks (RLS)

**Issue:** #28 — fix(staff): grant Supervisor on-behalf-of access for Unavailability Blocks (RLS)
**Owner:** Matthew
**Originally planned branch:** `fix/staff-unavailability-supervisor-rls`
**Actual branch (bundled Jul 12, 2026):** `feat/staff-unavailability-approval-bundle-28-30` — Issues #28, #29, and #30 were bundled into a single branch/PR going forward to save review overhead; this doc still covers #28 in isolation.
**Base:** `dev`
**Depends on:** #24 merged
**Sprint:** Sprint 1 — M01 Staff Auth & Access Control

## Overview

Adds `'Supervisor'` to the four "manage all" RLS policies on `staff_unavailability_blocks` (read/insert/update/delete), closing the gap where every prose spec (Modules-Features, Issue #24 AC-4) described Supervisor as having on-behalf-of access but Epic A-1's migrations only ever granted `Admin`/`Superadmin`.

**Scope note — RLS alone does not change API behavior (flagged and resolved before implementation):** `unavailabilityBlock.service.ts` uses the **service-role** Supabase client (see Issue #24's own verification doc), which bypasses RLS entirely. The actual on-behalf-of gate the API enforces is `assertCanActOnTarget()`'s role-list check, previously `ADMIN_ROLES` (`['Admin', 'Superadmin']`). Shipping the RLS migration alone would not have made AC-1–AC-3 true — a Supervisor would still get `403` from the service before ever touching Supabase. This branch therefore also introduces `UNAVAILABILITY_MANAGER_ROLES` (`['Admin', 'Supervisor', 'Superadmin']`) in `server/src/features/staff/staff.types.ts` and switches `assertCanActOnTarget()` to use it — deliberately **not** widening `ADMIN_ROLES` itself, since that constant also gates staff profile CRUD and avatar upload, which Supervisor is not granted here. This mirrors the precedent set by Issue #24's and #27's verification docs of documenting spec-vs-implementation gaps rather than building against the aspirational spec.

## What Changed

- **Added** `supabase/migrations/20260711020_m01_staff_unavailability_blocks_add_supervisor_rls.sql` — drops and recreates the four "manage all" policies with `'Supervisor'` added to `current_staff_role() in (...)`. The four "manage own" policies are untouched.
- **Modified** `server/src/features/staff/staff.types.ts` — adds `UNAVAILABILITY_MANAGER_ROLES` (see scope note above).
- **Modified** `server/src/features/staff/services/unavailabilityBlock.service.ts` — `assertCanActOnTarget()` now checks `UNAVAILABILITY_MANAGER_ROLES` instead of `ADMIN_ROLES`.
- **Modified** `server/src/features/staff/services/unavailabilityBlock.service.spec.ts` — adds Supervisor on-behalf-of cases for create (AC-1), cancel (AC-2), and list (AC-3).

Note: migration `20260711021_...no_self_review.sql` (Issue #29's self-approval fix) further restricts the UPDATE policy this migration creates — see the #29 doc in this folder's sibling for that migration; it is documented separately since it's a different issue's AC, even though both landed in this bundle.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all server test files pass, `tsc --noEmit` produces no output, `eslint .` reports 0 errors (pre-existing `no-console` warnings in unrelated auth controllers are expected and unchanged).

## Structural Verification

1. Confirm the migration files exist:

   ```powershell
   Get-ChildItem supabase/migrations -Filter "20260711020*"
   Get-ChildItem supabase/migrations -Filter "20260711021*"
   ```

2. Confirm the service no longer imports `ADMIN_ROLES`:

   ```powershell
   Select-String -Path server/src/features/staff/services/unavailabilityBlock.service.ts -Pattern "UNAVAILABILITY_MANAGER_ROLES|ADMIN_ROLES"
   ```

   Expected: matches for `UNAVAILABILITY_MANAGER_ROLES` only, not `ADMIN_ROLES`.

## Database Verification

1. **Push the migrations** to your linked Supabase project:

   ```powershell
   supabase db push
   ```

   If the project isn't linked yet, run the Supabase login/link steps first (Supabase Dashboard → Project Settings → Database for the connection string).

2. **Run the verification SQL script** — open Supabase Studio → SQL Editor, paste in the contents of:

   ```text
   testing/docs/issues/28-staff-unavailability-supervisor-rls/staff-unavailability-supervisor-rls.sql
   ```

   and run it section by section. Confirms the four "manage all" policies now list Supervisor, the old Admin/Superadmin-only policies are gone, and the "manage own" policies are untouched (see the script's comments for exact expected output).

## Postman Verification

Needs a Supervisor account (`supervisor_identifier`/`supervisor_password`), a Receptionist account as a regression control (`receptionist_identifier`/`receptionist_password`), and a peer staff member's id in the **same branch** as the Supervisor (`peer_staff_id`, no login needed for that account).

### A. Import and configure the collection

1. Open Postman → **Import** → `testing/docs/issues/28-staff-unavailability-supervisor-rls/staff-unavailability-supervisor-rls.postman_collection.json`.
2. Open **Issue 28 - Staff Unavailability Supervisor RLS** → collection **Variables** tab. Fill in **Current value** for `base_url` (`http://localhost:3000`, adjust if `SERVER_PORT` differs), `supervisor_identifier`/`supervisor_password`, `receptionist_identifier`/`receptionist_password`, and `peer_staff_id`. Leave the token/`block_id` variables blank.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 6)**. Each has a **Tests** tab that asserts automatically.

| #   | Request                                                      | Expected                                             |
| :-- | :----------------------------------------------------------- | :--------------------------------------------------- |
| 1   | Login as Supervisor                                          | `200`, sets `supervisor_access_token`                |
| 2   | Login as Receptionist (regression control)                   | `200`, sets `receptionist_access_token`              |
| 3   | AC-5: Receptionist cannot create a block on behalf of a peer | `403`                                                |
| 4   | AC-1: Supervisor creates a block on behalf of a peer         | `201`, `staff_id` = `peer_staff_id`, sets `block_id` |
| 5   | AC-3: Supervisor reads the peer's blocks                     | `200`, `block_id` present in `blocks`                |
| 6   | AC-2: Supervisor cancels the peer's block                    | `204`                                                |

## Acceptance Criteria Checklist

- [x] **AC-1:** A Supervisor can create an Unavailability Block on behalf of another staff member — unit test `#28 AC-1: allows a Supervisor to create a block...`; Postman request 4.
- [x] **AC-2:** A Supervisor can cancel another staff member's active block — unit test `#28 AC-2: allows a Supervisor to cancel...`; Postman request 6.
- [x] **AC-3:** A Supervisor can read another staff member's unavailability blocks — unit test `#28 AC-3: allows a Supervisor to list...`; Postman request 5.
- [x] **AC-4:** The four "manage own" policies and their existing Epic A-1 tests are unchanged — verified via `staff-unavailability-supervisor-rls.sql` section 3 (no code touched those policies or tests in this branch).
- [x] **AC-5:** A Receptionist (and by the same code path, Groomer/Cashier/Veterinarian/Pet Assistant) still cannot act on another staff member's block — existing `rejects a non-admin ... with 403` unit tests (unchanged, still pass since Groomer/Receptionist/etc. are not in `UNAVAILABILITY_MANAGER_ROLES`); Postman request 3.
