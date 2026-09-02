# Issue #40 Verification: Services CRUD Backend

**Issue:** #40 — feat(maintenance): services CRUD backend (size-coat pricing matrix)
**Owner:** Matthew
**Branch:** `feat/services-crud-backend` (delivered bundled with #39–#44)
**Base:** `dev`
**Depends on:** #39 merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

First backend issue of the `features/maintenance/` folder: services CRUD over
`services`, `service_pricing_tiers`, and `service_branch_availability`. Like
the rest of the server, it uses the service-role `supabase` singleton, so
role gating is enforced in code — at the route level via
`requireRole(MAINTENANCE_WRITE_ROLES)` for writes and the full staff role
list for reads, mirroring `staff.routes.ts`. `requireBranch` is deliberately
omitted: catalog configuration is not branch-scoped for **access** (an Admin
manages both branches from one panel); branch is data, not authorization.

Decisions from the issue's Dev Notes, as implemented:

- **Tier upserts for non-Grooming services are rejected in the service layer**
  (`400`), not a CHECK constraint — on create the validator also rejects it.
- **Branch availability defaults to available at both branches on create**
  (the Guide's recommended option): `createService` inserts an
  `is_available = true` row per branch, since Modules-Features frames this as
  a toggle to _disable_ a branch, not opt in.
- **Soft-delete only:** there is no DELETE route at all; deactivation is
  `PATCH { is_active: false }`.

## What Changed

- **Added** `server/src/features/maintenance/maintenance.types.ts` — Service/
  Package/Promo/tier interfaces + feature-local role lists.
- **Added** `server/src/features/maintenance/modules/validators/maintenance.validator.ts`
  (+ spec) — zod `.strict()` validators for all three entities (#40–#42 share
  the file per the Guide's directory plan).
- **Added** `server/src/features/maintenance/services/services.service.ts`
  (+ spec, 12 tests) — `listServices` / `getServiceById` / `createService` /
  `updateService` / `setServiceBranchAvailability`.
- **Added** `server/src/features/maintenance/maintenance.controller.ts` and
  `maintenance.routes.ts` — services endpoints (packages/promos handlers are
  #41/#42 but ship in the same files, as the Guide's Affected Files predict).
- **Modified** `server/src/shared/app.routes.ts` — mounts the maintenance
  router (the Files sheet's "mounted in app.ts route wiring" — the actual
  mount point since Sprint 1 Epic D #36 is `shared/app.routes.ts`).

### Endpoints

| Method | Path                                                                    | Roles            |
| :----- | :---------------------------------------------------------------------- | :--------------- |
| GET    | `/maintenance/services` (`?category=&branch_id=&include_inactive=true`) | all staff        |
| GET    | `/maintenance/services/:id`                                             | all staff        |
| POST   | `/maintenance/services`                                                 | Admin/Superadmin |
| PATCH  | `/maintenance/services/:id`                                             | Admin/Superadmin |
| PATCH  | `/maintenance/services/:id/branch-availability`                         | Admin/Superadmin |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all pass; new files `services.service.spec.ts` (12 tests) and
`maintenance.validator.spec.ts` (services portion) are included in the run.

## Postman Verification

Prereqs: migrations 032/033 applied (see issue #39's doc), server env
(`server/.env`) pointing at that database, and two accounts from the Sprint 1
seed: an **Admin** and any **non-admin** staff role (e.g.
`makati.admin1@goldenfur.com` / `makati.groomer1@goldenfur.com` — password per
seed, `password123`).

### A. Import and configure

1. Open Postman → **Import** (top-left) → drag in
   `testing/docs/issues/40-services-crud-backend/services-crud-backend.postman_collection.json`.
2. Click the imported collection **Issue 40 - Services CRUD Backend** → open
   the **Variables** tab. Fill in the **Current value** column:
   - `base_url` — `http://localhost:3000` (adjust if `SERVER_PORT` differs).
   - `admin_identifier` / `admin_password` — the Admin account.
   - `staff_identifier` / `staff_password` — the non-admin account.
   - `branch_id` — a real branch id: in Supabase Studio open **Table Editor**
     (left sidebar, grid icon) → `branches` table → copy the `id` cell of
     either row (click the cell → Ctrl+C).
   - Leave the token/`service_id` variables blank — requests fill them.
3. **Save** (Ctrl+S).

### B. Start the server and run

```powershell
npm --prefix server run dev
```

Run requests **in order (1 → 10)** — each asserts automatically in its
**Tests** tab (green = pass):

| #   | Request                                     | Expected                                      |
| :-- | :------------------------------------------ | :-------------------------------------------- |
| 1   | Login as Admin                              | `200`, sets `admin_access_token`              |
| 2   | Login as non-admin staff                    | `200`, sets `staff_access_token`              |
| 3   | AC-1: POST Grooming service + 8-tier matrix | `201`, 8 tiers, both branches available       |
| 4   | AC-2: PATCH one tier only                   | `200`, M/LC price now 999, still 8 tiers      |
| 5   | AC-4: PATCH branch availability off         | `200`, `is_available: false` for that branch  |
| 6   | AC-3: PATCH `is_active: false`              | `200`                                         |
| 7   | AC-3: GET active list                       | `200`, created service **absent**             |
| 8   | AC-3: GET by id                             | `200`, row still returned, `is_active: false` |
| 9   | AC-5: POST as non-admin                     | `403`                                         |
| 10  | AC-5: GET as non-admin                      | `200`                                         |

The test service is left deactivated on purpose (no hard delete exists);
inactive rows never surface in active views, so no cleanup is needed.

## Acceptance Criteria Checklist

- [x] **AC-1:** POST creates service + full size×coat tier set in one call —
      unit test `AC-1: creates a Grooming service...`; Postman 3.
- [x] **AC-2:** PATCH edits any field incl. individual tiers without the full
      set — unit test `AC-2: upserts individual pricing tiers...`; Postman 4.
- [x] **AC-3:** `is_active = false` removes from active GET, row queryable by
      id — unit tests `AC-3: ...`; Postman 6–8.
- [x] **AC-4:** per-branch toggle via dedicated endpoint — unit test
      `AC-4: toggles a single branch...`; Postman 5.
- [x] **AC-5:** non-admin write 403 / staff GET 200 — integration tests
      `AC-5: ...` in `maintenance.integration.spec.ts`; Postman 9–10.
