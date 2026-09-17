---
title: Discounts — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, discounts]
project: golden-fur
---

A plain-English tour of the `discounts` feature's code: standing,
per-branch discounts (percentage or flat) scoped to a service, a
package, or a whole service category, plus the two built-in
Senior Citizen / PWD discounts. Covers the Admin management page and
the server CRUD + branch-availability API behind it.

**Part of:** [[M12-discount-management]]

## Client-side (`client/src/features/discounts/`)

### pages/

- **`AdminDiscountManagementPage/AdminDiscountManagementPage.tsx`** —
  the Admin/Superadmin-only screen for managing discounts. Loads
  discounts, services, packages, and branches together; splits the
  list into "Government-Mandated" and "Custom Discounts" sections;
  and renders a create/edit form with a scope picker (service,
  package, or category). A discount's `is_active` isn't a toggle on
  this form — it's derived from whichever branches the discount is
  marked available at, via the "Branch Availability" modal. Mandated
  discounts (Senior/PWD) have their name field locked read-only.

### components/

- **`DiscountFilterBar/DiscountFilterBar.tsx`** — the search box plus
  branch/scope-type/status filter row shown above the discount list.
- **`DiscountCategoryScopeSelect/DiscountCategoryScopeSelect.tsx`** —
  a small dropdown of the five discount categories (Grooming, Hotel,
  Daycare, Veterinary, Assessment), shown only when a discount's scope
  is set to "Category" rather than a specific service or package.

### api/

- **`discounts.api.ts`** — every `fetch` call to the server's
  `/discounts` routes: list, create, update, archive/restore,
  hard-delete, and the per-branch availability toggle
  (`setDiscountBranchAvailability`). `listDiscounts` deliberately does
  _not_ default to active-only, so the management page can still show
  mandated-but-off rows for an Admin to enable.

### Other files

- **`discounts.routes.tsx`** — wires `/staff/admin/discounts` behind
  `StaffAuthGuard`; the Admin/Superadmin-only check happens inside the
  page itself (viewer role is resolved from `GET /staff`), not in the
  route.
- **`discounts.types.ts`** — client-side mirror of the server types
  (`Discount`, `DiscountBranchAvailability`, create/update payloads).

## Server-side (`server/src/features/discounts/`)

### Controller & routes

- **`discounts.controller.ts`** — thin request handlers: parse/
  validate the body with the Zod validators, call the matching
  service function, and translate thrown errors (via their
  `statusCode`) into an HTTP response.
- **`discounts.routes.ts`** — mounts `/discounts` at the server root
  (same pattern as `maintenance`/`staff`). All staff roles can read;
  only Admin/Superadmin can write (`DISCOUNT_READ_ROLES` /
  `DISCOUNT_WRITE_ROLES`, defined in `discounts.types.ts`). No branch
  gate — a discount's branch is a data field/query filter, not an
  authorization boundary.

### Service

- **`services/discounts.service.ts`** — the core business logic, and
  the most important file in this feature:
  - `createDiscount` always inserts `is_mandated: false` and
    `is_active: true` (a discount must be created with at least one
    branch, via `branch_ids`, so it's always active somewhere from the
    start — there's no "created but switched off" state).
  - `setDiscountBranchAvailability` upserts one
    `discount_branch_availability` row and then re-syncs the parent
    discount's `is_active` flag: true whenever _any_ branch is
    available, false when none are. This is the single place that
    flips `is_active` now that it's no longer independently settable.
  - `updateDiscount` blocks renaming a mandated discount (Senior
    Citizen / PWD), and resets the other scope columns whenever
    `scope_type` changes, so the `discounts_scope_matches_type`
    database CHECK constraint (exactly one of
    service/package/category) always holds.
  - `archiveDiscount` / `hardDeleteDiscount` follow the project's
    deactivate-first archive pattern: a discount must be inactive
    before it can be archived (soft-deleted, reversible), and archived
    before it can be permanently deleted.

### Types & validators

- **`discounts.types.ts`** — the `Discount` shape plus the read/write
  role lists.
- **`modules/validators/discounts.validator.ts`** — Zod schemas for
  create/update/branch-availability payloads. `validateScopeShape`
  enforces that exactly one of `scope_service_id` /
  `scope_package_id` / `scope_category` is set and that it matches
  `scope_type`; a percentage discount's value can't exceed 100.
  `is_mandated` is never an accepted field on any payload — `.strict()`
  rejects it outright.

## How it connects

Discounts (M12) is its own feature folder, deliberately separate from
`maintenance` (M13), even though the two ship together. Discounts can
be applied by staff at booking time — see
[[M03-appointment-booking|M03]]'s "Booking-time discounts and promos"
— and at checkout in [[M08-sales-billing|M08]]; both paths write to
the same `discounts` data. See
[[M12-02-discount-eligibility-calculation-and-application|M12-02]] for
how eligibility and the actual discount amount are calculated.
