---
title: Catalog — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, catalog]
project: golden-fur
---

A plain-English tour of the `catalog` feature's code: one shared
`product_catalog` table (food, medication, and misc-retail items) used
both by staff (the admin Product Catalog page, Misc Sale) and by
customers (their own reusable food/medication "types" for future Hotel
bookings). Replaces what used to be two near-identical hotel-only
tables.

**Part of:** [[M05-pet-hotel-boarding-management]]

## Client-side (`client/src/features/catalog/`)

### pages/

- **`ProductCatalogPage/ProductCatalogPage.tsx`** — the
  Admin/Superadmin-only staff catalog screen at
  `/staff/admin/product-catalog`. It's a thin wrapper that resolves
  the viewer's role (via `GET /staff`) and, if allowed, renders
  `CatalogAdminPage` wired to the staff product endpoints.
- **`CustomerFoodMedicationPage/CustomerFoodMedicationPage.tsx`** — the
  customer-facing "My Food & Medication Types" page. Lets a customer
  add, rename, and remove their own food/medication entries, grouped
  into two sections. Every row this page creates is owned by the
  viewing customer; any global (staff-managed) rows would also show up
  here read-only-in-spirit, but the page's own CRUD only ever touches
  the customer's own rows.

### components/

- **`CatalogAdminPage/CatalogAdminPage.tsx`** — the generic
  add/search/sort/edit/archive admin table, reused by
  `ProductCatalogPage`. Takes the list/create/update/archive functions
  as props, so it isn't hardcoded to one catalog category — a category
  and service-scope dropdown on the Add form default to
  `food`/`medication`/`misc_retail` and `hotel`/`general`, but both
  accept free-text "Other (custom)" values too, since these fields are
  a documented convention rather than an enforced enum.
- **`CatalogComboBox/CatalogComboBox.tsx`** — a hybrid dropdown/
  freetext picker used elsewhere (e.g. the Hotel booking wizard) to
  select a food type or medication name: it offers matching catalog
  items in a dropdown, but also accepts a value that doesn't match
  anything in the catalog (stored as plain text, never written back).

### api/

- **`catalog.api.ts`** — calls to two route groups: the staff-admin
  `/catalog/products/*` endpoints (list/create/update/archive/restore/
  hard-delete), and the customer-scoped
  `/customers/me/food-medication-catalog` /
  `/customers/:customerId/food-medication-catalog` endpoints (the
  second lets a staff member, e.g. a receptionist, read *a specific
  customer's* saved types rather than their own).

### Other files

- **`catalog.routes.tsx`** — mounts `/staff/admin/product-catalog`
  behind `StaffAuthGuard`; role enforcement happens inside the page.
- **`catalog.types.ts`** — `ProductCatalogItem` and the create/update/
  filter payload shapes shared by both pages.

## Server-side (`server/src/features/catalog/`)

### Controller & routes

- **`catalog.controller.ts`** — request handlers for both the staff
  product-catalog endpoints and the customer food/medication endpoints,
  each validating its body with the matching Zod schema before calling
  a service function.
- **`catalog.routes.ts`** — mounts `/catalog/products/*` (staff read/
  write, via `CATALOG_READ_ROLES`/`CATALOG_WRITE_ROLES`) and
  `/customers/me|:customerId/food-medication-catalog` (any
  authenticated customer for their own rows; staff-read for the
  `:customerId` variant). Neither route group is branch-scoped.

### Service

- **`services/productCatalog.service.ts`** — the staff-admin CRUD
  (list/create/update/archive/restore/hard-delete) over
  `product_catalog`, filterable by `category` and `service_scope`.
  Collapses what used to be two parallel services (one for hotel food,
  one for hotel medication) into one. Follows the project's
  deactivate-first archive pattern (`assertInactiveBeforeArchive`,
  `assertArchivedBeforeHardDelete`) and turns a foreign-key violation
  on hard delete into a friendly "still referenced by a check-in or a
  sale" error.
- **`services/customerProductCatalog.service.ts`** — the leaner
  customer-owned CRUD: a customer's rows are always
  `service_scope: 'hotel'`, `price: 0` (never billed), and scoped by
  `owner_customer_id`. `listCustomerCatalog` returns both the
  customer's own rows and any global (`owner_customer_id` null)
  reference rows. `assertOwnedByCustomer` guards rename/remove so a
  customer can only touch their own entries. No `is_active`/hard-delete
  here — archiving is the only lifecycle a customer's own catalog
  needs.

### Types & validators

- **`catalog.types.ts`** — `ProductCatalogItem` plus the feature-local
  `CATALOG_READ_ROLES`/`CATALOG_WRITE_ROLES`. `category` and
  `service_scope` are deliberately plain strings, not an enum, so a
  future category never needs a schema or type change.
- **`modules/validators/catalog.validator.ts`** — Zod schemas for
  staff product create/update, and separately for the customer's own
  food/medication item create/update (name + a closed `food`/
  `medication` category, no price or service scope — those aren't the
  customer's to set).

## How it connects

`catalog` grew out of `hotel`'s food/medication catalog and still
lives conceptually there — see
[[M05-pet-hotel-boarding-management|M05]]'s "Food & Medication
Catalog" section — but the same `product_catalog` table now also backs
Cashier's Misc Sale product picker in [[M08-sales-billing|M08]]. A
catalog item selected during the Hotel booking wizard's Care
Instructions step, or check-in, can prefill from a pet's current
prescription (see [[M07-health-veterinary-management|M07]]).
