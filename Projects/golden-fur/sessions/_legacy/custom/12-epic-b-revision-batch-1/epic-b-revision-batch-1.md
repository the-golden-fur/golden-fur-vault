# Epic B — Revision Batch 1 (Issues #79-#85)

Type: Epic implementation, sourced from `temp/context/1-Architectural_Change_Suggestions-EpicB-Guide.md.docx` + `...EpicB-Design.xlsx` + `...EpicStructure.xlsx`.
Branch: `dev` (this batch spans 7 issues the Guide itself splits across 6 feature branches — `feat/services-status-toggle-collapse`, `chore/pricing-configuration-schema`, `feat/pricing-configuration-page`, `chore/package-pricing-configuration-schema`, `feat/package-bundled-price-preview`, `feat/promo-cap-and-activation-schema`, `feat/discount-management-overhaul` — but everything landed together here on `dev` in one pass).

## Scope

- **#79** `feat(m13)`: collapse the Services page's status control into a single toggle.
- **#80** `chore(db)`: `pricing_configuration` singleton — the shared grooming size/coat calculation.
- **#81** `feat(m13)`: Pricing Configuration page + derived size/coat matrix preview (replaces manual per-cell entry).
- **#82** `chore(db)`: `package_pricing_configuration` singleton + `packages.bundled_price` dropped in favor of a derived column.
- **#83** `feat(m13)`: derived package bundled price + inline bundle-discount-% configuration.
- **#84** `chore(db)+feat(m13)`: `promo_cap_configuration` + `transaction_promo_selections` — replaces `promos.is_exclusive` with a per-transaction cap.
- **#85** `feat(m12)`: Discount Management UI overhaul — category scope, search/filter, card layout.

## Corrections from the original brief

The Guide was written against an assumed schema/file layout that didn't match what Sprint 2 actually shipped on `dev`. Three real deviations, confirmed by reading the merged migrations and source before writing new ones:

- **#80/#81 — the "8 manual matrix columns" don't exist.** The Guide assumed `services` had 8 `price_<size>_<coat>` columns to drop. The actual Sprint 2 schema (migration `20260715032`) normalized that into its own table, `service_pricing_tiers` (one row per service × weight*class × coat_type), populated via `ServicePricingTierEditor`. That table — not 8 columns — is this epic's real "manual entry" mechanism, and it's what migration `20260726047` drops (logging every pre-existing tier value via `RAISE NOTICE` first, same non-destructive intent the Guide asked for). `booking.service.ts`'s `resolveServicePrice` reads `service.service_pricing_tiers` to price a Grooming booking by the pet's size/coat — an M03 (Sprint 2) consumer the Guide never looked at. Rather than rename the field and touch every consumer, `services.service.ts` now computes the matrix on read (`deriveGroomingMatrix(base_price, pricing_configuration)`) and attaches it under the \_same* `service_pricing_tiers` key/shape (with a synthesized `id`/`service_id` per cell, since there's no longer a real row behind it) — `booking.service.ts`, the client pages, and every existing test needed zero changes to that field's _shape_, only to how its values are produced.
- **#83 — same pattern for `packages.bundled_price`.** `booking.service.ts` also reads `pkg.bundled_price` directly to price a package booking. `packages.service.ts` keeps returning a `bundled_price` field with that exact name — now computed via `deriveBundledPrice` from the included services' `base_price` (fetched via a nested `package_services(service_id, services(base_price))` select) and `package_pricing_configuration`, instead of being read from a dropped column.
- **#85 — no new migration needed.** The Guide's Issue #85 assumed `discounts.scope_type`/`discounts.category` needed adding. They already existed — the actual Sprint 2 discounts migration (`20260715033`) shipped category scope from the start, including the `discounts_scope_matches_type` CHECK's category branch. `AdminDiscountManagementPage` already had a working category-scope create/edit form and a per-row `ToggleSwitch`, just laid out as `<ul>`/`<li>` rows instead of cards with no search/scope-type/status filters. This epic's real remaining work for #85 was purely client-side: extract `DiscountCard`/`DiscountFilterBar`/`DiscountCategoryScopeSelect` and switch the list to a card grid with client-side search + scope-type + status filtering (matching the existing branch filter's already-client-side pattern — no new query params on `GET /discounts`).
- **#79 — no separate Deactivate/Activate pair existed either.** `AdminServicesPage` already had a single button toggling between "Deactivate"/"Reactivate" text, not two separate actions. To make this a genuine single _toggle_ (not just a single button whose label changes) and match the pattern this same codebase already uses elsewhere (`AdminDiscountManagementPage`'s per-row `ToggleSwitch`), the row control is now a real `ToggleSwitch` bound to `is_active`, labeled `Enable/Disable {name}`.

## Migration numbering

The Guide assumed Epic A's last migration was `...031` and numbered Epic B's migrations `032`-`035` accordingly. The actual last merged migration on `dev` at the time this batch was built was `20260725046`, so this batch's three migrations are renumbered `20260726047`-`20260726049`:

- `20260726047_m13_create_pricing_configuration.sql` (#80) — creates the singleton, logs and drops `service_pricing_tiers`.
- `20260726048_m13_package_pricing_configuration.sql` (#82) — creates the singleton, logs and drops `packages.bundled_price`.
- `20260726049_m13_promo_cap_and_transaction_promo_selections.sql` (#84) — creates `cap_type_enum`, `promo_cap_configuration`, `transaction_promo_selections`; drops `promos.is_exclusive`.

No migration was needed for #85 (see above).

## Other things worth knowing

- **`updated_by_staff_id` is nullable**, not `NOT NULL` as the Design sheet listed, on all three new config tables. Each singleton/default row is seeded by its own migration, which has no real requester to attribute it to — this matches the existing nullable `created_by`/`updated_by` convention already used on `services`/`packages`/`promos`/`discounts`, rather than inventing a system staff row that doesn't exist.
- **`transaction_promo_selections.transaction_id` has no foreign key yet.** `public.transactions` doesn't exist until M08 ships (Sprint 5) — Postgres can't reference a table that isn't there. The constraint is documented in the migration's comments and must be added via `alter table ... add constraint` in the M08 migration that creates `transactions`.
- **`transaction_promo_selections` RLS is staff-only for now** (Admin/Superadmin manage, all staff read). A correct "the owning customer can insert/toggle `is_activated`" policy needs to join to `transactions` to verify ownership, and that table doesn't exist yet — approximating it against a non-existent table would be worse than deferring the customer-facing policy to the same M08 migration that adds the FK.
- **`CustomerBookingFlowPage`'s pricing preview** (a Sprint 2/M03 page, not owned by this epic) previously auto-picked an `is_exclusive` promo first when several applied. With that field gone, it now just takes the first applicable candidate — real cap enforcement (walking activated promos in `activated_at` order until the cap is reached) is explicitly M08/M09 scope per the Guide's Issue #84 Dev Notes, not something to approximate here.
- **Client-side `deriveGroomingMatrix`/`deriveBundledPrice` are duplicated**, not imported from the server. The service form and Pricing Configuration page need to preview a matrix from a **not-yet-saved** `base_price` typed into the create form — there's no network round trip to compute that, and the client/server are separate builds with no shared TS module between them. Both copies are unit-tested (`server/.../utils/*.spec.ts`, `client/.../utils/*.spec.ts`) against the same expected values so a divergence would show up as a test failure in one side, not a silent drift.
- **Route/label naming**: the Guide's assumed component names (`ServicesPage`, `PackagesPage`, `PromosPage`, `DiscountManagementPage`) don't match this repo's actual ones (`AdminServicesPage`, `AdminPackageBuilderPage`, `AdminPromoConfigPage`, `AdminDiscountManagementPage`) — edited in place under their real names/paths. The new `PricingConfigurationPage` was added at `/staff/admin/maintenance/pricing-configuration` with a matching Staff Dashboard tile.

## Files changed (high level)

**Migrations** (`supabase/migrations/`): `20260726047_m13_create_pricing_configuration.sql`, `20260726048_m13_package_pricing_configuration.sql`, `20260726049_m13_promo_cap_and_transaction_promo_selections.sql`.

**Server**: `features/maintenance/maintenance.{types,controller,routes}.ts`, `features/maintenance/modules/validators/maintenance.validator.ts`, `features/maintenance/services/{services,packages,promos}.service.ts`, `features/maintenance/services/{pricingConfiguration,packagePricing,promoCap}.service.ts` (new), `features/maintenance/utils/{deriveGroomingMatrix,deriveBundledPrice}.ts` (new).

**Client**: `features/maintenance/maintenance.types.ts`, `features/maintenance/api/maintenance.api.ts`, `features/maintenance/utils/{deriveGroomingMatrix,deriveBundledPrice}.ts` (new), `features/maintenance/components/{PricingMatrixPreview,PackagePricingPreview,PromoCapConfigForm}/*` (new), `features/maintenance/pages/PricingConfigurationPage/*` (new), `features/maintenance/pages/{AdminServicesPage,AdminPackageBuilderPage,AdminPromoConfigPage}/*.tsx`, `features/maintenance/maintenance.routes.tsx`, `features/staff/config/staffDashboard.config.ts`, `features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (promo auto-pick fallback only), `features/discounts/components/{DiscountCard,DiscountFilterBar,DiscountCategoryScopeSelect}/*` (new), `features/discounts/pages/AdminDiscountManagementPage/*`.

**Removed**: `client/src/features/maintenance/components/ServicePricingTierEditor/*` (superseded by the read-only `PricingMatrixPreview`; no longer referenced anywhere).

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **556/556 tests pass** (60 files).

From `client/`:

```powershell
npx tsc -b
npx vitest run
```

Expected: typecheck clean, **367/367 tests pass** (91 files).

Both confirmed clean as of this revision.

## Manual Verification

You'll need: the `server/` and `client/` dev servers running (`npm run dev` from the repo root runs both), a Supabase project with this batch's 3 migrations (047-049) applied, and Postman (or the included collection) for the API-level checks.

### 0. Apply migrations

1. From the repo root: `npm run supabase:push` (or `npm run supabase:reset` for a fresh local database, which also re-runs the seeds).
2. Re-run `npm run seed:module-1` through `npm run seed:module-2` (or whichever seed scripts this project uses) if you reset, so the Postman collection's default identifiers resolve to real accounts.

### 1. Schema checks — `epic-b-revision-batch-1.sql`

Open the SQL file in this folder in Supabase Studio's SQL Editor and run Sections 1-5 (read-only). Confirm: `pricing_configuration` and `package_pricing_configuration` each have exactly one row; `service_pricing_tiers` and `packages.bundled_price` no longer exist; `promos.is_exclusive` no longer exists; `promo_cap_configuration` has a seeded system-wide default (`branch_id` NULL); `transaction_promo_selections` exists with no FK on `transaction_id`; `discounts_scope_matches_type` already includes the category branch. Section 6 (the direct-insert check for Issue #84 AC-6) is wrapped in `begin`/`rollback` — confirm `is_activated` defaults to `false` and `activated_at` to `NULL`, then confirm the rollback left no row behind.

### 2. API checks — `epic-b-revision-batch-1.postman_collection.json`

Import the collection and **Run** it top-to-bottom. It logs in as Admin and a non-admin staff role, then exercises, in order:

1. **#80** — any staff role can `GET /maintenance/pricing-configuration`; a non-Admin gets `403` on `PATCH`.
2. **#81** — `POST /maintenance/services` with a Grooming category and no `pricing_tiers` field returns `201` with an 8-cell **derived** `service_pricing_tiers` array; the same request _with_ a `pricing_tiers` field is rejected `400` (strict payload, the field is gone).
3. **#82/#83** — any staff role can `GET /maintenance/package-pricing-configuration`; `POST /maintenance/packages` with a `bundled_price` field is rejected `400`.
4. **#84** — any staff role can `GET /maintenance/promo-cap-configurations` and sees the system-wide default (`branch_id` null); an Admin can `PUT` an updated cap value; a non-Admin gets `403` on the same `PUT`; `POST /maintenance/promos` with an `is_exclusive` field is rejected `400`.
5. **#85** — `GET /discounts` includes at least one `scope_type: "category"` row (seeded government-mandated discounts), confirming the category-scope schema/read path already worked before this epic touched anything.

Expected: every request's inline test script passes (Postman shows all green).

### 3. Services page — single status toggle (#79)

1. Visit `/staff/admin/maintenance/services` as an Admin or Superadmin.
2. Confirm each service row shows one toggle switch (not a "Deactivate"/"Reactivate" button) reading "Disable {name}" when active or "Enable {name}" when inactive.
3. Click it — confirm the service's status flips immediately (no page reload) and the row drops out of / appears in the Active-only view per the Status filter, exactly as before.
4. Confirm no other row action changed (Edit still works).

### 4. Pricing Configuration page + derived matrix (#80/#81)

1. Visit `/staff/admin/maintenance/pricing-configuration` as an Admin or Superadmin (also reachable from the Staff Dashboard's new "Pricing Configuration" tile).
2. Confirm the four size multipliers and the long-coat add-on are editable, and a live preview below (driven by a "Sample base price" field) updates as you type.
3. Change a multiplier (e.g. Size M from 1.10 to 1.20) and the long-coat add-on, click **Save pricing configuration** — confirm a "Pricing configuration updated." confirmation and the preview reflects the new saved values.
4. Visit `/staff/admin/maintenance/services`, open **New service**, select category **Grooming**, and enter a base price. Confirm a read-only "Size & coat pricing matrix (Grooming) - derived, read-only" preview appears with 8 computed cells and **no editable inputs** — there is no way to type a per-cell price anymore.
5. Confirm the preview updates live as you change the base price field, and disappears entirely if you switch category away from Grooming.
6. Save the service, then open **Edit** on an existing Grooming service — confirm the same derived preview shows there too, computed from that service's stored `base_price`.

### 5. Package bundled price + bundle discount (#82/#83)

1. Visit `/staff/admin/maintenance/packages` as an Admin or Superadmin, click **New package**, pick a branch, and select two or more services.
2. Confirm there is **no** "Bundled price" input anywhere in the form — instead, a "Bundled price (derived, read-only)" panel shows a live-computed PHP amount that updates immediately as you check/uncheck services.
3. With zero services selected, confirm the panel shows "Add two or more services to see the bundled price." instead of an error or a stale number.
4. In that same panel, change "Bundle discount (%)" (e.g. to 20) and click **Save discount %** — confirm a "Bundle discount updated." confirmation, and that the computed price for _every_ package (not just the one you're editing) reflects the new percentage the next time you view it.
5. Save the new package and confirm its list-row price matches what the preview showed.

### 6. Promo cap replaces exclusivity (#84)

1. Visit `/staff/admin/maintenance/promos` as an Admin or Superadmin.
2. Confirm the promo create/edit form no longer has a "Cannot be combined with other promos" toggle, and no promo row shows an "Exclusive" badge.
3. Confirm a "Promo Cap" panel is visible on the page with a Branch selector (defaulting to "Both branches (system-wide default)"), a Cap type (Percentage/Flat), and a Cap value.
4. Change the cap value and click **Save promo cap** — confirm a "Promo cap updated." confirmation.
5. Switch the Branch selector to Makati or Southwoods — confirm the form either shows that branch's previously-saved cap, or resets to the 20%/percentage default if none has been saved for that branch yet — and that saving there doesn't overwrite the system-wide default from step 4.

### 7. Discount Management overhaul (#85)

1. Visit `/staff/admin/discounts` as an Admin or Superadmin.
2. Confirm discounts render as **cards** (name, branch badge, scope badge, value, status) in a grid, not table/list rows.
3. Type into the new **Search** field — confirm the visible cards narrow to matching names in real time.
4. Use the new **Scope type** filter (All/Service/Package/Category) — confirm it narrows the cards correctly, including to Category-scoped rows.
5. Use the **Status** filter (All/Active only/Inactive only) alongside the existing Branch filter — confirm all four filters combine correctly.
6. Create a new custom discount with Scope = Category, pick a category (e.g. Grooming) — confirm it saves and its card shows "Category: Grooming".
7. Confirm existing Service- and Package-scoped discounts from before this batch still display and toggle correctly (no regression).
