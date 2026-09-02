# Issue #41 Verification: Packages CRUD Backend

**Issue:** #41 — feat(maintenance): packages CRUD backend (package_services, per-branch toggle)
**Owner:** Matthew
**Branch:** `feat/packages-crud-backend` (delivered bundled with #39–#44)
**Base:** `dev`
**Depends on:** #40 merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Packages CRUD over `packages` + the `package_services` junction. Key design
points implemented per the issue's Dev Notes:

- **Per-branch rows (MA22):** `branch_id` is a required create field, not a
  filter. "The same" package at both branches = two rows.
- **Bundle-time validation only:** every `service_id` must exist and be
  `is_active = true` **at create/edit time**; a service deactivated after
  being bundled is deliberately not rejected retroactively.
- **No price coupling:** `bundled_price` has no validation against the sum of
  the included services' prices.
- **Two or more services:** the validator enforces `service_ids.min(2)`,
  taken from the user story's "bundle two or more services" wording. Flag if
  a single-service package should be allowed.

## What Changed

- **Added** `server/src/features/maintenance/services/packages.service.ts`
  (+ spec, 7 tests) — `listPackages` / `getPackageById` / `createPackage` /
  `updatePackage` (service_ids = full bundle replacement).
- **Modified** `maintenance.controller.ts` / `maintenance.routes.ts` /
  `maintenance.types.ts` — package handlers, routes, and types (same files as
  #40, as the Guide's Affected Files predict).

### Endpoints

| Method | Path                                                          | Roles            |
| :----- | :------------------------------------------------------------ | :--------------- |
| GET    | `/maintenance/packages` (`?branch_id=&include_inactive=true`) | all staff        |
| GET    | `/maintenance/packages/:id`                                   | all staff        |
| POST   | `/maintenance/packages`                                       | Admin/Superadmin |
| PATCH  | `/maintenance/packages/:id`                                   | Admin/Superadmin |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all pass, including `packages.service.spec.ts` and the packages
tests inside `maintenance.integration.spec.ts`.

## Postman Verification

Prereqs: same as issue #40's doc (migrations applied, server running, Admin +
non-admin accounts), **plus the #44 seed applied** so at least two active
Grooming services exist for request 3 to pick up (otherwise create two via
issue #40's collection first).

1. Import
   `testing/docs/issues/41-packages-crud-backend/packages-crud-backend.postman_collection.json`.
2. Collection **Variables** tab → fill `base_url`, `admin_identifier`,
   `admin_password`, `staff_identifier`, `staff_password`, and `branch_id`
   (Supabase Studio → **Table Editor** → `branches` → copy an `id`). Leave the
   rest blank. Save.
3. `npm --prefix server run dev`, then run requests **in order (1 → 9)**:

| #   | Request                           | Expected                                            |
| :-- | :-------------------------------- | :-------------------------------------------------- |
| 1–2 | Logins                            | `200`, tokens set                                   |
| 3   | Pick two active Grooming services | `200`, sets `service_id_a`/`service_id_b`           |
| 4   | AC-1/AC-2: POST package           | `201`, price stored as `123.45` (≠ sum), 2 services |
| 5   | AC-3: PATCH bundle + name + price | `200`, edits reflected                              |
| 6   | Single-service bundle             | `400`                                               |
| 7   | AC-5: GET by branch as non-admin  | `200`, package listed                               |
| 8   | AC-5: POST as non-admin           | `403`                                               |
| 9   | Cleanup: deactivate test package  | `200`, `is_active: false`                           |

## AC-4: RESTRICT end-to-end

AC-4 ("deleting a service still referenced by an active package fails with a
clear error") concerns a **hard SQL DELETE** — the API deliberately has no
DELETE route (services soft-delete via `is_active`). It is verified at the
DB level by issue #39's SQL script, Block 4
(`testing/docs/issues/39-maintenance-discounts-schema/maintenance-discounts-schema.sql`),
which bundles a service into a package and shows the DELETE failing with the
`package_services_service_id_fkey` FK violation. The unit spec
`packages.service.spec.ts` additionally covers the bundle-time
unknown/inactive-service rejection.

## Acceptance Criteria Checklist

- [x] **AC-1:** POST creates a branch-scoped package with name, service ids,
      bundled price — unit test `AC-1/AC-2: creates a per-branch package...`;
      Postman 4.
- [x] **AC-2:** bundled price independent of the services sum — same test;
      Postman 4 (`123.45` vs. the real seeded prices).
- [x] **AC-3:** PATCH adds/removes services and edits name/price/status —
      unit tests `AC-3: ...`; Postman 5, 9.
- [x] **AC-4:** RESTRICT verified end-to-end — issue #39 SQL Block 4 (see
      above).
- [x] **AC-5:** non-admin write 403, staff GET filterable by branch —
      integration tests; Postman 7–8.
