# Issue #24 Verification: Staff Unavailability Block Backend

**Issue:** #24 — feat(staff): Unavailability Block backend (replaces Busy toggle)
**Owner:** Matthew
**Branch:** `feat/staff-unavailability-block-backend`
**Base:** `dev`
**Depends on:** #22 merged (schema/table already exists from Epic A-1 #11)
**Sprint:** Sprint 1 — M01 Staff Auth & Access Control

## Overview

Adds backend-only support for staff unavailability blocks on top of the `staff_unavailability_blocks` table and RLS shipped in Epic A-1 (#11). No migration in this issue. Like the rest of `server/src/features/staff/`, the service uses the service-role `supabase` singleton and enforces "self, or Admin/Superadmin on behalf of another staff member" authorization in code (mirroring `staff.controller.ts`'s existing pattern), since backend requests bypass RLS entirely.

**Scope note on roles:** the issue's Dev Notes and AC-4 say "Admin/Supervisor" may act on another staff member's block. The actual RLS policies (`supabase/migrations/20260701015_m01_fix_staff_rls_role_recursion.sql`) and the existing `ADMIN_ROLES` constant only grant elevated access to `Admin`/`Superadmin` — `Supervisor` has no special grant anywhere in the schema. This implementation follows `ADMIN_ROLES` (`Admin`, `Superadmin`) to stay consistent with what's actually enforced at the DB level and with issues #22/#38. Flagging this discrepancy — if `Supervisor` is intended to have this power, that needs its own RLS migration first.

## What Changed

- **Added** `server/src/features/staff/services/unavailabilityBlock.service.ts`:
  - `createUnavailabilityBlock` — validates the requester can act on the target staff_id (self, or `ADMIN_ROLES`), resolves the block's start/end (quick-action vs. custom range), checks for an overlapping active block (`409` if found), then inserts.
  - `resolveShiftEnd` — given a branch's IANA `timezone` and `operating_hours` JSON, computes "closing time today" as a real UTC instant. Mirrors the day/offset resolution already used by `get_staff_availability()` (#12) so both places agree on what "end of shift" means.
  - `cancelUnavailabilityBlock` — same authorization check, confirms the block belongs to the target staff_id (`404` otherwise), then deletes it.
  - `listUnavailabilityBlocks` — same authorization check, returns blocks for the target staff_id where `end_time` is in the future (active + upcoming), ordered by `start_time`.
- **Added** `server/src/features/staff/services/unavailabilityBlock.service.spec.ts` — 12 unit tests covering AC-1 through AC-5, the on-behalf-of Admin path, and validation edge cases (bad range, overlap, forbidden).
- **Modified** `server/src/features/staff/staff.controller.ts` — adds `createUnavailabilityBlockController`, `cancelUnavailabilityBlockController`, `listUnavailabilityBlocksController`, plus a `createUnavailabilityBlockValidator` (zod, `.strict()`) and a small `sendServiceError` helper shared by all three new handlers to map thrown `statusCode` errors to HTTP responses.
- **Modified** `server/src/features/staff/staff.routes.ts` — adds `POST /staff/:id/unavailability`, `GET /staff/:id/unavailability`, `DELETE /staff/:id/unavailability/:blockId`, all behind `jwtMiddleware → requireRole(ALL_STAFF_ROLES) → requireBranch`.
- **Modified** `server/src/features/staff/staff.types.ts` — adds the `UnavailabilityBlock` interface matching the table's columns.

### Request shape

`POST /staff/:id/unavailability` body:

- Quick action: `{ "quick_action": true, "reason": "optional" }` — `start_time` is always "now"; `end_time` is derived from the target staff member's branch `operating_hours` for the current day (in the branch's `timezone`). `400` if the branch has no operating hours configured for today.
- Custom range: `{ "start_time": "<ISO>", "end_time": "<ISO>", "reason": "optional" }` — `400` if either is missing/unparseable or `end_time` is not after `start_time`.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all server test files pass (12 new tests in `unavailabilityBlock.service.spec.ts`, 36/36 in the `staff` feature directory), `tsc --noEmit` produces no output, `eslint .` reports no new errors.

## Structural Verification

1. Confirm the new files exist:

   ```powershell
   Get-ChildItem server/src/features/staff/services -Filter "unavailabilityBlock*"
   ```

   Expected: `unavailabilityBlock.service.ts`, `unavailabilityBlock.service.spec.ts`.

2. Confirm the routes are registered:

   ```powershell
   Select-String -Path server/src/features/staff/staff.routes.ts -Pattern "unavailability"
   ```

   Expected: matches for the `POST`, `GET`, and `DELETE` routes.

## Postman Verification

Needs one regular staff account (`staff_identifier`/`staff_password`), a peer staff account **in the same branch** (`peer_staff_id`, no login needed), and one Admin account (`admin_identifier`/`admin_password`) whose branch covers both. Reuse the accounts/branch layout from issue #22's verification if you still have them noted down.

### A. Import and configure the collection

1. Open Postman → **Import** → `testing/docs/issues/24-staff-unavailability-block-backend/staff-unavailability-block-backend.postman_collection.json`.
2. Open **Issue 24 - Staff Unavailability Block Backend** → collection **Variables** tab. Fill in **Current value**:
   - `base_url` — `http://localhost:3000` (adjust if `SERVER_PORT` differs).
   - `staff_identifier`, `staff_password`, `staff_id`.
   - `peer_staff_id` — a different staff_id in the **same branch** as `staff_id` (needed so the Admin's on-behalf-of block and the quick-action branch lookup resolve against a real branch).
   - `admin_identifier`, `admin_password`.
   - Leave `staff_access_token`, `admin_access_token`, `block_id`, `quick_block_id`, `peer_block_id` blank — requests fill these in automatically.
3. Save (Ctrl+S).

### B. Start the server and run the requests

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 11)**. Each has a **Tests** tab that asserts automatically.

| #   | Request                                          | Expected                                                                                            |
| :-- | :----------------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| 1   | Login as self                                    | `200`, sets `staff_access_token`                                                                    |
| 2   | AC-2: POST custom range block                    | `201`, sets `block_id`, `start_time`/`end_time` match the request                                   |
| 3   | AC-3: POST overlapping range                     | `409`                                                                                               |
| 4   | AC-5: GET list of blocks                         | `200`, `block_id` present in `blocks`                                                               |
| 5   | AC-4: DELETE own block                           | `204`                                                                                               |
| 6   | AC-1: POST quick-action block                    | `201` (or `400` if the branch has no operating hours today — see note below), sets `quick_block_id` |
| 7   | Cleanup: DELETE quick-action block               | `204`                                                                                               |
| 8   | Login as Admin                                   | `200`, sets `admin_access_token`                                                                    |
| 9   | Admin POST block on behalf of peer staff         | `201`, `staff_id` = `peer_staff_id`, `created_by` = admin's id, sets `peer_block_id`                |
| 10  | AC-4: self staff attempts to DELETE peer's block | `403`                                                                                               |
| 11  | AC-4: Admin DELETEs peer's block (cleanup)       | `204`                                                                                               |

**Note on request 6:** if the branch tied to `staff_id` has no `operating_hours` entry for today's weekday, the API correctly returns `400` — this isn't a bug, it's the "branch closed today" case. Check the `branches` table (Supabase Studio → Table Editor → `branches` → `operating_hours` column) and pick a `staff_id` whose branch is open today if you want to see the `201` path.

## Acceptance Criteria Checklist

- [x] **AC-1:** quick-action POST ends the block at the branch's closing time for the current day — unit test `AC-1: quick action ends the block...`; Postman request 6.
- [x] **AC-2:** custom start/end range POST creates a block for that exact range — unit test `AC-2: custom range creates a block...`; Postman request 2.
- [x] **AC-3:** overlapping block for the same staff_id returns `409` — unit test `AC-3: rejects a block that overlaps...`; Postman request 3.
- [x] **AC-4:** DELETE cancels an active block; cross-staff cancel is forbidden unless Admin/Superadmin — unit tests `AC-4: cancels an active block...`, `AC-4: rejects cancelling another staff member's block...`, `AC-4: allows an Admin to cancel...`; Postman requests 5, 9, 10, 11.
- [x] **AC-5:** GET returns active and upcoming blocks for that staff_id — unit test `AC-5: returns active and upcoming blocks...`; Postman request 4.
