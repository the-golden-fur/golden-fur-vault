# Issue #29 Verification: Unavailability Block request/approval — schema + backend

**Issue:** #29 — feat(staff): Unavailability Block request/approval — schema + backend
**Owner:** Matthew
**Originally planned branch:** `feat/staff-unavailability-request-approval-backend`
**Actual branch (bundled Jul 12, 2026):** `feat/staff-unavailability-approval-bundle-28-30` — Issues #28, #29, and #30 were bundled into a single branch/PR going forward to save review overhead; this doc still covers #29 in isolation.
**Base:** `dev`
**Depends on:** #24 merged, #28 merged (same bundle)
**Sprint:** Sprint 1 — M01 Staff Auth & Access Control

## Overview

Adds the review/approval workflow for staff-requested Unavailability Blocks: a staff member's own custom-range request lands as `pending` and must be approved or denied by a _different_ Admin/Supervisor/Superadmin before it counts as unavailability; quick-action and on-behalf-of entries stay auto-approved.

**Scope note — the schema half of this issue already shipped (flagged and reconciled before implementation):** Issue #27's own verification doc explains that its `staffAvailability.service.ts` had a hard dependency on the `status` column, so migration `20260711019_m01_staff_unavailability_blocks_add_status.sql` landed **only the schema piece #27 needed** — the `unavailability_block_status` enum, the four new columns, the `enforce_unavailability_block_status()` trigger, and dropping the staff "own" UPDATE policy — ahead of this issue, with an explicit note that #29's actual scope (the review/pending-list endpoints and the no-self-review RLS tightening) remained separate future work. **This branch is that remaining work.** Nothing here re-creates the schema from `...019`; this issue adds:

- The `PATCH /staff/:id/unavailability/:blockId/review` and `GET /staff/unavailability/pending` endpoints (service + controller + routes).
- Migration `20260711021_m01_staff_unavailability_blocks_no_self_review.sql` — the "no self-review" RLS tightening the Guide's dev notes describe as migration `...013` (renumbered here to fit after `...019`/`...020`), adding `staff_id <> auth.uid()` to the Admin/Supervisor/Superadmin "manage all" UPDATE policy from Issue #28.
- An **application-layer** self-review check in `reviewUnavailabilityBlock()` (`requesterId === targetStaffId` → `403 cannot_review_own_request`) — required in addition to the RLS policy because the server uses the service-role Supabase client and bypasses RLS entirely (same pattern flagged in #24's and #28's docs). AC-9 explicitly asks for both layers; this is where the endpoint-level one lives.

## What Changed

- **Added** `supabase/migrations/20260711021_m01_staff_unavailability_blocks_no_self_review.sql` — restricts the Admin/Supervisor/Superadmin "manage all" UPDATE policy (from Issue #28's `...020`) so `staff_id <> auth.uid()`, closing the self-approval gap that policy would otherwise have.
- **Modified** `server/src/features/staff/services/unavailabilityBlock.service.ts` — adds `reviewUnavailabilityBlock()` (role check → self-review check → pending-status check → update) and `listPendingUnavailabilityBlocks()` (role check → fetch all `status = 'pending'` rows with an embedded `staff_profiles` summary → branch-scope for non-Superadmin → flag `reviewable: staff_id !== requesterId`).
- **Modified** `server/src/features/staff/staff.controller.ts` — adds `reviewUnavailabilityBlockController` and `listPendingUnavailabilityBlocksController`, plus a `.strict()` zod validator for the review payload (`decision`, optional `denial_reason`).
- **Modified** `server/src/features/staff/staff.routes.ts` — adds `PATCH /staff/:id/unavailability/:blockId/review` and `GET /staff/unavailability/pending`, both behind `jwtMiddleware → requireRole(UNAVAILABILITY_MANAGER_ROLES) → requireBranch`.
- **Modified** `server/src/features/staff/staff.types.ts` — adds `UnavailabilityBlockStatus`, extends `UnavailabilityBlock` with the five new columns, adds `PendingUnavailabilityBlock`/`PendingUnavailabilityBlockStaffSummary`.
- **Modified** `server/src/features/staff/services/unavailabilityBlock.service.spec.ts` — adds `reviewUnavailabilityBlock` and `listPendingUnavailabilityBlocks` describe blocks (AC-4, AC-5, AC-6, AC-8, AC-9, AC-10, plus role-gate and no-op-on-forbidden-supabase-call cases).
- **Modified** `server/src/features/staff/tests/staff.integration.spec.ts` — adds route-level coverage for AC-9 (self-review 403 at the HTTP layer, with the exact `cannot_review_own_request` body) and the `requireRole` gate on both new routes.
- **Modified client files** (mirrors the server types/API so #30's UI can consume them — see the #30 doc in this folder's sibling for the UI itself): `client/src/features/staff/staff.types.ts`, `client/src/features/staff/api/staff.api.ts` (+ spec), `client/src/features/staff/modules/validators/staff.validator.ts` (adds a client-side mirror of the review validator).

### Response shape

`GET /staff/unavailability/pending` returns `{ blocks: PendingUnavailabilityBlock[] }`, each with an embedded `staff` object (`id`, `display_name`, `profile_photo_url`, `role`, `branch_id`) and a `reviewable` boolean. Admin/Supervisor see only their own branch's rows (matched against the embedded `staff.branch_id`); Superadmin sees all branches. The caller's own pending row is included but `reviewable: false`.

`PATCH /staff/:id/unavailability/:blockId/review` body: `{ "decision": "approved" | "denied", "denial_reason"?: string }`. Returns the updated block on success (`200`), `404` if the target row isn't currently `pending`, `403` with `{ "error": "cannot_review_own_request" }` if the caller is the requester.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
npm --prefix client test -- --run
npx tsc -b --project client
npm --prefix client run lint
```

Expected: all test files pass in both projects, both typechecks produce no output, both lints report 0 errors (pre-existing `no-console` warnings in unrelated server auth controllers are expected and unchanged).

## Structural Verification

1. Confirm the migration exists:

   ```powershell
   Get-ChildItem supabase/migrations -Filter "20260711021*"
   ```

2. Confirm the new routes are registered:

   ```powershell
   Select-String -Path server/src/features/staff/staff.routes.ts -Pattern "review|pending"
   ```

   Expected: matches for both the `PATCH .../review` route and the `GET /staff/unavailability/pending` route.

## Database Verification

1. **Push the migrations** (if not already done as part of #28's verification — `...020` must land before `...021`):

   ```powershell
   supabase db push
   ```

2. **Run the verification SQL script** — Supabase Studio → SQL Editor → paste and run:

   ```text
   testing/docs/issues/29-staff-unavailability-request-approval-backend/staff-unavailability-request-approval-backend.sql
   ```

   Confirms the update policy now carries `staff_id <> auth.uid()`, the prerequisite schema/trigger from `...019` is present, and the overall policy count matches expectations.

## Postman Verification

Needs one regular staff account (`staff_identifier`/`staff_password`/`staff_id`) and one Admin account (`admin_identifier`/`admin_password`/`admin_id` — **`admin_id` must be filled in manually with the Admin's own `staff_profiles.id`**, the login response doesn't return it) whose branch covers the staff account.

### A. Import and configure the collection

1. Open Postman → **Import** → `testing/docs/issues/29-staff-unavailability-request-approval-backend/staff-unavailability-request-approval-backend.postman_collection.json`.
2. Open **Issue 29 - Staff Unavailability Request Approval Backend** → collection **Variables** tab. Fill in `base_url`, `staff_identifier`/`staff_password`/`staff_id`, `admin_identifier`/`admin_password`/`admin_id`. Leave every token/block-id variable blank.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 18)**. Each has a **Tests** tab that asserts automatically.

| #   | Request                                       | Expected                                                                 |
| :-- | :-------------------------------------------- | :----------------------------------------------------------------------- |
| 1   | Login as staff                                | `200`, sets `staff_access_token`                                         |
| 2   | Login as Admin                                | `200`, sets `admin_access_token`                                         |
| 3   | AC-1: staff self-requests a custom range      | `201`, `status: pending`, sets `staff_block_id`                          |
| 4   | AC-2: staff quick-action                      | `201`, `status: approved` (or `400` if branch closed today)              |
| 5   | AC-3: Admin POST on behalf of staff           | `201`, `status: approved`, sets `admin_onbehalf_block_id`                |
| 6   | Admin self-requests a custom range            | `201`, `status: pending`, sets `admin_self_block_id`                     |
| 7   | AC-9: Admin reviews their own pending request | `403`, `error: cannot_review_own_request`                                |
| 8   | AC-8: GET pending queue                       | `200`; staff row `reviewable: true`, Admin's own row `reviewable: false` |
| 9   | AC-4: Admin approves the staff request        | `200`, `status: approved`, `reviewed_by` = `admin_id`                    |
| 10  | AC-6: re-review the now-approved request      | `404`                                                                    |
| 11  | Staff submits a second pending request        | `201`, `status: pending`, sets `staff_block_id_2`                        |
| 12  | AC-5: Admin denies with a reason              | `200`, `status: denied`, `denial_reason` matches                         |
| 13  | AC-5 (also): staff calling review at all      | `403`                                                                    |
| 14  | Cleanup: staff deletes quick-action block     | `204` (or `404` if request 4 hit branch-closed-today)                    |
| 15  | Cleanup: staff deletes their approved request | `204`                                                                    |
| 16  | Cleanup: staff deletes their denied request   | `204`                                                                    |
| 17  | Cleanup: Admin deletes the on-behalf-of block | `204`                                                                    |
| 18  | Cleanup: Admin deletes their own request      | `204`                                                                    |

## Acceptance Criteria Checklist

- [x] **AC-1:** Self custom-range POST creates a `pending` row regardless of any `status` sent in the body — trigger-level, unaffected by this branch (see #27's doc); re-verified here via Postman request 3.
- [x] **AC-2:** Self quick-action POST creates an `approved` row immediately — Postman request 4.
- [x] **AC-3:** On-behalf-of POST (any range) creates an `approved` row immediately — Postman request 5.
- [x] **AC-4:** `PATCH .../review` with `{ decision: 'approved' }` sets status and `reviewed_by`/`reviewed_at`, when the caller is not the requester — unit tests `AC-4: an Admin approves...`; Postman request 9.
- [x] **AC-5:** `PATCH .../review` with `{ decision: 'denied', denial_reason }` sets status and reason; a plain staff member calling this endpoint at all gets `403` — unit tests `AC-5: denies a request...`; Postman requests 12–13.
- [x] **AC-6:** Reviewing a non-pending row returns `404` — unit test `AC-6: returns 404 when the block is not pending`; Postman request 10.
- [x] **AC-7:** A staff member cannot UPDATE their own row's status via a direct table update (RLS-level; no UPDATE policy exists for staff on their own rows since `...019`) — verified via `staff-unavailability-request-approval-backend.sql` section 1 (only one UPDATE policy exists, and it excludes the row owner).
- [x] **AC-8:** `GET /staff/unavailability/pending` returns only `pending` rows, branch-scoped, with the caller's own row included but flagged non-reviewable — unit test `AC-8: scopes results to the caller branch...`; Postman request 8.
- [x] **AC-9:** Self-review returns `403 cannot_review_own_request`, both via the endpoint and via a raw RLS-layer update — unit test `AC-9: rejects self-review...`; integration test `AC-9: PATCH .../review returns 403...`; Postman request 7; RLS confirmed via the `.sql` script section 1.
- [x] **AC-10:** An elevated-role user can review another elevated-role user's request (the restriction is "not yourself," not "not another Admin/Supervisor/Superadmin") — unit test `AC-10: allows reviewing another elevated-role user's pending request`.
