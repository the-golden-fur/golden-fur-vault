# Issue #43 Verification: Discounts CRUD Backend

**Issue:** #43 — feat(discounts): discounts CRUD backend (SC/PWD types, per-service toggle)
**Owner:** Matthew
**Branch:** `feat/discounts-crud-backend` (delivered bundled with #39–#44)
**Base:** `dev`
**Depends on:** #39 merged (not #40–#42 — separate feature folder)
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

M12 Discounts CRUD in its own `server/src/features/discounts/` folder (M12
and M13 are distinct modules, per the Guide, despite shipping together).
Standing, indefinite discounts — the two government-mandated types plus
admin-defined custom ones — per branch, scoped to exactly one of a service, a
package, or a whole category.

Rules implemented per the issue's Dev Notes:

- **Exactly-one-of scope** matching `scope_type`, enforced three times over:
  zod validator, service layer (nulls the other scope columns on a scope
  change), and the `discounts_scope_matches_type` CHECK constraint (#39).
- **Mandated rows are not special-cased in write logic** beyond what's
  required: `is_mandated` is never an accepted API field (`.strict()`
  validators reject it), a mandated row's **name** is immutable (service
  layer, `400`), and everything else — including the `is_active` toggle —
  goes through the same path as custom rows.
- **Inactive by default:** `createDiscount` forces `is_active = false`; an
  explicit Admin toggle is required to enable anything.
- **Category scope** (`scope_category = 'Veterinary'` etc.) is how panel
  comment MA29's veterinary SC/PWD concern is modeled — confirm with the
  client per Open Items.

## What Changed

- **Added** `server/src/features/discounts/discounts.types.ts`,
  `discounts.routes.ts`, `discounts.controller.ts`.
- **Added** `modules/validators/discounts.validator.ts` (+ spec, 12 tests).
- **Added** `services/discounts.service.ts` (+ spec, 9 tests).
- **Added** `tests/discounts.integration.spec.ts` (7 HTTP-level tests).
- **Modified** `server/src/shared/app.routes.ts` — mounts the discounts
  router.

### Endpoints

| Method | Path                                          | Roles            |
| :----- | :-------------------------------------------- | :--------------- |
| GET    | `/discounts` (`?branch_id=&active_only=true`) | all staff        |
| GET    | `/discounts/:id`                              | all staff        |
| POST   | `/discounts`                                  | Admin/Superadmin |
| PATCH  | `/discounts/:id`                              | Admin/Superadmin |

Note: the default GET returns **all** rows including inactive ones — the #48
management UI must show the switched-off mandated rows so an Admin can enable
them; `active_only=true` is the consumer view (M08 checkout, Sprint 5).

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all pass, including the three new discounts spec files.

## Postman Verification

Prereqs: same setup as issue #40's doc, **plus the #44 seed applied** (request
3 asserts the seeded SC/PWD rows). Import
`discounts-crud-backend.postman_collection.json`, fill `base_url`, the four
credential variables, and `branch_id` (Supabase Studio → **Table Editor** →
`branches` → copy an `id`), save, start the server, run **in order (1 → 11)**:

| #   | Request                                    | Expected                                              |
| :-- | :----------------------------------------- | :---------------------------------------------------- |
| 1–2 | Logins                                     | `200`, tokens set                                     |
| 3   | AC-2: GET discounts for the branch         | `200`, SC + PWD present, `is_mandated`, 20%, inactive |
| 4   | AC-1: POST custom category discount        | `201`, non-mandated, inactive by default              |
| 5   | AC-3/AC-4: toggle mandated ON              | `200`, `is_active: true`                              |
| 6   | AC-3: rename mandated                      | `400`                                                 |
| 7   | AC-3: PATCH `is_mandated`                  | `400 Invalid payload` (strict validator)              |
| 8   | AC-3: edit custom value + scope→Veterinary | `200` (MA29 case)                                     |
| 9   | AC-5: PATCH as non-admin                   | `403`                                                 |
| 10  | AC-5: GET as non-admin                     | `200`                                                 |
| 11  | Cleanup: mandated back OFF                 | `200`, `is_active: false`                             |

The custom test discount is left inactive (its default) — harmless; delete it
from **Table Editor → discounts** if you want a spotless table.

## Acceptance Criteria Checklist

- [x] **AC-1:** POST custom discount scoped to service/package/category per
      branch — validator + service tests; Postman 4.
- [x] **AC-2:** SC + PWD exist after the #44 seed, both inactive — Postman 3;
      #44's SQL verification.
- [x] **AC-3:** is_active toggles on any row; custom value/scope editable;
      mandated name/is_mandated changes rejected — unit + integration tests;
      Postman 5–8.
- [x] **AC-4:** category-scoped discount created/toggled independently —
      Postman 4–5, 8.
- [x] **AC-5:** non-admin write 403, staff GET 200 — integration tests;
      Postman 9–10.
