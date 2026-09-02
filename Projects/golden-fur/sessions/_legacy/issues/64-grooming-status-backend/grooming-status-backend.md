# Issue #64 Verification: grooming status-transition backend + billing handoff stub

**Issue:** #64 — feat(grooming): status-transition backend (Waiting → In Progress → Completed) + billing handoff stub
**Owner:** Matthew
**Branch:** `feat/grooming-status-backend`
**Base:** `dev`
**Depends on:** #61 merged
**Sprint:** Sprint 3 Epic A — M04 Grooming Management

## Overview

`GET /grooming/queue` (today's confirmed Grooming bookings, scoped by role) + `PATCH /grooming/sessions/:id/status` (one-directional Waiting → In Progress → Completed). Reaching `Completed` sets `bookings.status = 'Completed'` and marks the booking billing-ready — no `transactions` table exists yet (M08 is Sprint 5), so "billing-ready" here just means the booking's status is `Completed` with its already-snapshotted `total_price` queryable. A `TODO(Sprint 5, M08)` marks the exact spot a real transaction should be created.

### Decision flagged for the reviewer: how `grooming_sessions` rows come to exist

Neither the Guide nor the DB Design sheet says who creates a `grooming_sessions` row for a newly-confirmed booking, and #64's own Affected Files list only names `grooming.service.ts` / `grooming.routes.ts` — `booking.service.ts` (Sprint 2 Epic B, already merged) is not listed as touched anywhere in this epic. Two designs were possible: (a) a DB trigger on `bookings`, or (b) lazy creation inside the grooming feature itself. No migration in this codebase uses a trigger anywhere (checked: only plain functions like `current_staff_role()` / `get_staff_availability()` exist), so a trigger would be a first-of-its-kind pattern with no local precedent. Implementation instead makes `listGroomingQueue()` **auto-vivify** a `'Waiting'` row for any confirmed Grooming booking in today's scope that doesn't have one yet, the first time the queue is listed. This keeps the change fully contained to the grooming feature, matches the Files list literally, and needs no change anywhere in Sprint 2 code. **Raise with Alarie if a trigger-based design was actually intended.**

## What Changed

- **Added** `server/src/features/grooming/grooming.types.ts` — `GROOMING_QUEUE_ROLES` (`Groomer/Admin/Supervisor/Superadmin`), `GroomingStatus`, `GroomingSession`.
- **Added** `server/src/features/grooming/modules/validators/grooming.validator.ts` — PATCH body accepts only `'In Progress'` or `'Completed'` (`'Waiting'` is never a valid target — it's only ever the table default).
- **Added** `server/src/features/grooming/services/grooming.service.ts` (+spec, 8 tests) — `listGroomingQueue()` (role-scoped, auto-vivifying) and `transitionGroomingSessionStatus()` (ownership + forward-only transition enforcement + the billing handoff).
- **Added** `server/src/features/grooming/grooming.controller.ts`, `grooming.routes.ts` — registered in `server/src/shared/app.routes.ts`.
- Route-level gate: `requireRole(GROOMING_QUEUE_ROLES)` + `requireBranch`; ownership (`assigned_groomer_id === requester`) and branch-scoping are re-checked at the service layer as defense-in-depth, mirroring the RLS-plus-application-layer pattern used throughout M01/M03.

## Acceptance Criteria Map

| AC                                                                                     | Automated                  | Postman          |
| -------------------------------------------------------------------------------------- | -------------------------- | ---------------- |
| AC-1 Waiting → In Progress → Completed; skipping/reverting rejected                    | `grooming.service.spec.ts` | requests 3, 4, 7 |
| AC-2 Completed sets `completed_at`, `bookings.status = 'Completed'`, billing-ready     | `grooming.service.spec.ts` | request 4        |
| AC-3 only the assigned groomer (or Admin/Supervisor/Superadmin) can transition         | `grooming.service.spec.ts` | requests 5, 6    |
| AC-4 transitioning an already-Completed session gets a clear "already finalized" error | `grooming.service.spec.ts` | request 8        |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all 51 test files / 485 tests pass (8 new in `grooming.service.spec.ts`); typecheck silent; lint 0 errors (3 pre-existing `no-console` warnings, unrelated to this change).

## Postman Verification

### Prerequisites

- Migrations `038–040` pushed (`supabase db push`).
- One **Groomer** account, one **second Groomer** account at the same branch, and one **Admin or Supervisor** account at that branch — all from Sprint 1's seed data (`makati.groomer1@goldenfur.com` / `makati.groomer2@goldenfur.com` / `makati.admin1@goldenfur.com`, password `password123`, or your own seeded equivalents).
- A **Confirmed Grooming booking** scheduled for **today**, assigned to Groomer 1 — the fastest way is to run #51's booking collection with `scheduled_start`/`scheduled_end` set to a slot later today (rather than "next Monday"), or create one directly via `POST /bookings`.

### A. Collect the IDs (Supabase Studio)

Open **Supabase Studio → Table Editor**:

1. `staff_profiles` — copy Groomer 1's `id` (`groomer1_id`, must match the booking's `assigned_staff_id`), Groomer 2's `id` (`groomer2_id`), and the Admin/Supervisor's `id`.
2. `bookings` — copy the `id` of today's Confirmed Grooming booking assigned to Groomer 1 (`grooming_booking_id`).

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/64-grooming-status-backend/grooming-status-backend.postman_collection.json`.
2. Open the collection → **Variables** tab → fill `base_url`, `groomer1_email`/`groomer1_password`, `groomer2_email`/`groomer2_password`, `admin_email`/`admin_password`, `grooming_booking_id`. Leave tokens/`session_id` blank — the collection captures them automatically.
3. Save (Ctrl+S).

### C. Start the server

```powershell
npm --prefix server run dev
```

### D. Run requests 1→8 in order (top to bottom)

Each request carries its own tests — the **Test Results** tab must be green:

1. **Login Groomer 1** → 200, token captured.
2. **Login Groomer 2** → 200, token captured.
3. **Login Admin** → 200, token captured.
4. **GET queue (Groomer 1)** → 200; the session for `grooming_booking_id` appears with `status = "Waiting"` (auto-created on first list). Captures `session_id`.
5. **AC-1 PATCH → In Progress (Groomer 1)** → 200; `status = "In Progress"`, `started_at` set.
6. **AC-3 PATCH → Completed (Groomer 2, wrong groomer)** → **403**.
7. **AC-1/AC-2 PATCH → Completed (Groomer 1)** → 200; `status = "Completed"`, `completed_at` set. Verify in Supabase Studio → `bookings` table that the row's `status` is now `Completed`.
8. **AC-4 PATCH → Completed again (Groomer 1)** → **409** with an "already finalized" message.
9. **AC-1 skip-state test** — create a second today-scheduled Grooming booking assigned to Groomer 1, GET the queue to get its fresh `session_id` (status `Waiting`), then PATCH it straight to `Completed` → **409** (cannot skip a state).
10. **AC-3 Admin transitions any session** — repeat request 5's PATCH (using a fresh Waiting session) with the Admin's token instead of Groomer 1's → 200.

### E. Cleanup

Supabase Studio → Table Editor → `grooming_sessions` → filter by the `booking_id`s used above → delete the rows. The underlying `bookings` rows can stay `Completed` or be deleted alongside if they were created solely for this test.
