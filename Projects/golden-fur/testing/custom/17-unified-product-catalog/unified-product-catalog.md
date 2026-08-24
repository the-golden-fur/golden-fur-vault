# Unified Product Catalog

Type: Custom cross-cutting change (not tied to a single issue) — requested alongside Sprint 5 Epic A (Issues #82-#87, see `testing/docs/issues/82-87-*`) but scoped separately here since it isn't part of the original Guide.
Branch: `feat/m08-billing-unified-catalog` (based off `dev`).

## What changed

M05 (Sprint 4) shipped two admin-managed catalogs for the hotel check-in flow: `food_catalog` and `medication_catalog` — structurally identical tables (name/price/is_active), with near-duplicate service/controller/route code on the server and two near-duplicate admin pages on the client. Issue #85 (Miscellaneous Sale, see `testing/docs/issues/85-billing-misc-sale`) needed the exact same shape — a priced, admin-managed item a cashier can pick off a list — as a free-text-only feature per the original spec.

Instead of building Misc Sale as a third, unrelated catalog, this change merges all three into one shared `product_catalog` table, differentiated by `category` (`food`/`medication`/`misc_retail`, ...) and `service_scope` (`hotel`/`general`, ...) so each feature shows the right slice of the same underlying table. Confirmed with the user:

- One unified "Product Catalog" admin page replaces the two separate Hotel Food/Medication Catalog pages.
- Misc Sale's item picker shows every active catalog product (any category), plus a free-text fallback for anything not catalogued.

1. **Schema.** New `product_catalog` table (migration `20260731067`). Backfills `food_catalog`/`medication_catalog` rows with their **original ids preserved**, so `care_feeding_instructions.food_catalog_id`/`care_medication_instructions.medication_catalog_id` need no data migration — only their FK target changes, from `food_catalog(id)`/`medication_catalog(id)` to `product_catalog(id)`. Column names on those two tables are kept as-is (they describe the domain concept — "which food/medication was selected" — not the storage table). `food_catalog`/`medication_catalog` are dropped. Same two-tier RLS shape as before (open `SELECT`, Admin/Superadmin write).
2. **Server.** New `server/src/features/catalog/` feature collapses `foodCatalog.service.ts` + `medicationCatalog.service.ts` (which were byte-for-byte parallel — see their own deleted files' comments) into one `productCatalog.service.ts`, filterable by `category`/`service_scope`. `GET/POST/PATCH/DELETE /catalog/products` replaces `/hotel/food-catalog` and `/hotel/medication-catalog`. Read access now includes every staff role (must include `Cashier` for Misc Sale — the old `frontDeskAndAssistants` guard didn't), matching the already-open RLS. `careInstructions.service.ts`'s `getCatalogPrices` no longer takes a `table` param — both feeding and medication rows resolve their price from the same `product_catalog` table now.
3. **Client.** `CatalogAdminPage`/`CatalogComboBox` moved out of `features/hotel/components/` (no longer hotel-specific) into `features/catalog/components/`. `CatalogAdminPage` generalized to carry `category`/`service_scope` — the Add form uses real `<select>` dropdowns for both (with an "Other (custom)..." option that reveals a text field, since the underlying values stay extensible plain text, not a closed enum) rather than free text. New `ProductCatalogPage` (Admin/Superadmin, category filter) replaces `HotelFoodCatalogPage`/`HotelMedicationCatalogPage`, registered at `/staff/admin/product-catalog`. `HotelCheckInPage`'s food/medication pickers are unchanged in behavior — `hotel.api.ts`'s `listFoodCatalog`/`listMedicationCatalog` now call the shared `/catalog/products` endpoint with fixed `category`/`service_scope` filters instead of the old dedicated endpoints. `CustomerBookingFlowPage`'s hotel-preferences step (also uses `CatalogComboBox`) updated for the new import path only.
4. **Seed data.** `supabase/seeds/module-4-hotel/module-4-hotel.seed.ts`/`.sql` now insert into `product_catalog` with `category`/`service_scope` instead of the two old tables.
5. **Dev proxy bug fix.** `client/vite.config.ts` never had a proxy entry for `/catalog` (or `/billing`) — requests fell through to Vite's own dev server instead of reaching Express, surfacing client-side as a generic "Request failed. Please try again." with no obvious network/console error (same failure mode the file's own `/branches` comment documents). Added both entries.

## Migrations

- `20260731067_m05_m08_create_product_catalog.sql` — `product_catalog` table; backfills `food_catalog`/`medication_catalog` rows (same ids); repoints `care_feeding_instructions.food_catalog_id`/`care_medication_instructions.medication_catalog_id` FKs; drops the two old tables; RLS (open SELECT, Admin/Superadmin write).

## New API surface

- `GET /catalog/products?category=&service_scope=&active_only=` — any staff role.
- `POST/PATCH/DELETE /catalog/products` — Admin/Superadmin.
- Removed: `GET/POST/PATCH/DELETE /hotel/food-catalog` and `/hotel/medication-catalog`.

## Files changed (high level)

**Server:** new migration above; new `features/catalog/` (`catalog.types.ts`, `catalog.controller.ts`, `catalog.routes.ts`, `modules/validators/catalog.validator.ts`, `services/productCatalog.service.ts` + spec); `features/hotel/` — deleted `services/foodCatalog.service.ts`/`medicationCatalog.service.ts` (+specs), trimmed `hotel.controller.ts`/`hotel.routes.ts`/`hotel.types.ts`/`modules/validators/hotel.validator.ts`, `services/careInstructions.service.ts`; `supabase/seeds/module-4-hotel/*`; `shared/app.routes.ts` (mounts `catalogRoutes`).

**Client:** new `features/catalog/` (`catalog.types.ts`, `api/catalog.api.ts`, `components/CatalogAdminPage/*`, `components/CatalogComboBox/*`, `pages/ProductCatalogPage/*`, `catalog.routes.tsx`); `features/hotel/` — deleted `pages/HotelFoodCatalogPage/`, `pages/HotelMedicationCatalogPage/`; `hotel.api.ts`, `hotel.types.ts`, `hotel.routes.tsx`, `pages/HotelCheckInPage/HotelCheckInPage.tsx` (import path only); `features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (import path only); `pages/SettingsPage/tabs/ConfigTab.tsx` (two catalog tiles → one Product Catalog tile); `routes.tsx` (mounts `catalogRoutes`); `vite.config.ts` (`/catalog` + `/billing` proxy entries).

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/catalog src/features/hotel
```

From `client/`:

```powershell
npx tsc -b
npx vitest run src/features/catalog src/features/hotel src/features/booking
```

Expected: typecheck clean on both, all listed tests pass — see `testing/docs/issues/82-billing-transactions-schema` onward for the billing-side full-suite counts (this batch's tests are a subset of that same run).

## Manual Verification

1. Run `supabase db reset` (or `supabase db push`). Confirm `product_catalog` exists with the same rows `food_catalog`/`medication_catalog` had (same ids), and `food_catalog`/`medication_catalog` no longer exist.
2. Run `npm run seed:module-4`. Confirm it reports "ensured 7 food catalog item(s)" / "ensured 6 medication catalog item(s)" against `product_catalog`.
3. Restart the client dev server (picks up the `vite.config.ts` proxy fix). Log in as Admin, go to Settings → Config → **Product Catalog**. Confirm both categories' seeded items appear, category filter works, and the Category/Service scope fields are real dropdowns (with a working "Other (custom)..." text fallback).
4. Add a new item, confirm no "Request failed" error and the item appears in the list without a page refresh.
5. Go to Hotel Check-in for a Hotel booking — confirm the food/medication pickers still show the same catalog items as before (no regression from the unification).
