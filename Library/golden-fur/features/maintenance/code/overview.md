---
title: Maintenance — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, maintenance]
project: golden-fur
---

Despite the name, this isn't software upkeep — "maintenance" is Golden Fur's
back-office catalog and pricing panel. It's where an Admin/Superadmin
defines what the business sells (services, bundled packages, promos), how
each is priced (the Grooming size/coat matrix, package bundle discounts,
per-pet-type fixed prices), and shared config (branches/operating hours, pet
weight-class cut-offs, breeds, pet types, Service Type display settings).

**Part of:** [[M13-maintenance-packages-services-promos|M13]]

## Client-side (`client/src/features/maintenance/`)

### pages/
- **`AdminServicesAndPackagesPage.tsx`** — the Settings > Config entry point. Pure tab-bar shell (Services / Service Types / Packages) over a `?section=` query param; each tab renders one of the three page components below unmodified.
- **`AdminServicesPage.tsx`** — CRUD list for the atomic Grooming/Hotel/Daycare/Veterinary/Assessment offerings. The create/edit modal changes shape by category: Daycare hides `base_price` (derived from `first_hour_fee` instead) and asks for hourly fees; Hotel asks for the "free package after N nights" fields; Grooming shows a live `PricingMatrixPreview` when "vary by weight/coat" is on. Row actions (Configure, Branch Availability) live behind `MoreOptionsMenu`; there's no more row-level Activate/Deactivate — per-branch availability is the only way to take a service off sale.
- **`AdminServiceTypesPage.tsx`** — CRUD for the four booking-flow category display rows (`service_types`): rename the customer-facing label, toggle Staff Picker/Cage Picker for that type, pick which staff roles the Staff Picker offers, manage per-branch availability. A brand-new type shows up as selectable but has no real booking behavior behind it yet.
- **`AdminPackageBuilderPage.tsx`** — the package builder: pick branches, pick two or more services (filtered to ones available at every selected branch), see a live bundled-price preview (`PackagePricingPreview`) and, if "vary by weight/coat" is on, a `PricingMatrixPreview` of that bundled price. Also owns the shared bundle-discount-% input, saved alongside the package in one submit.
- **`AdminPromoConfigPage.tsx`** — the largest page. A two-step create wizard (pick Date range vs. Weekly recurring first, since a promo's type is immutable after creation), then the shared discount/scope/branch fields. Also renders the inline "Promo Cap Configuration" section underneath — one row per branch, each with its own `PromoCapCard` modal for cap type/value.
- **`AdminBreedsPage.tsx`** — simple grouped CRUD list (add/rename/delete) for `breeds`, grouped by pet type.
- **`AdminPetTypesPage.tsx`** — CRUD for the `pet_types` table (add/rename/deactivate/delete a pet type) plus a second section for per-branch fixed-price overrides: set a flat price that fully replaces normal pricing for a given pet type, scoped to "system default" or one branch.
- **`PricingConfigurationPage.tsx`** — edits the single shared Grooming size/coat pricing rule set (one rule per S/M/L/XL size plus Long Coat, each independently Multiplier/Flat/Percentage). Includes a live sample-price preview using `PricingMatrixPreview`.
- **`WeightClassConfigurationPage.tsx`** — edits the single shared kg cut-offs (M/L/XL starting weights) that turn a pet's recorded weight into S/M/L/XL. Shows the resulting bands as plain text.
- **`SystemConfigurationPage.tsx`** — Superadmin-only (narrower role gate than the rest of this feature). Branch identity (name/address/contact/timezone/vet flag) and per-weekday operating hours; can also create a brand-new branch. This is the only UI that ever edits `branches.operating_hours`, which slot generation and staff shift-end resolution elsewhere in the app already read.

### components/
- **`BranchAvailabilityModal.tsx`** — the shared "toggle per branch" modal used by Services/Service Types/Packages/Promos row actions; a searchable/sortable list of branch toggle switches.
- **`BranchMultiSelect.tsx`** — checkbox multiselect over the branch list, used on every create/edit form's "Available at" field.
- **`ServiceMultiSelect.tsx`** — generic {id, label, sublabel} checkbox multiselect, reused for picking a package's included services and a promo's scoped services/packages (via a `svc:`/`pkg:` prefixed composite id in the promo case).
- **`StaffRoleMultiSelect.tsx`** — checkbox multiselect over the fixed 8 staff roles, used by the Service Type form's "eligible staff roles for the Staff Picker" field.
- **`DayOfWeekPicker.tsx`** — 7-checkbox weekday picker for a weekly-recurring promo's `days_of_week`.
- **`PricingMatrixPreview.tsx`** — read-only S/M/L/XL × SC/LC price grid, computed client-side via `deriveGroomingMatrix`. Shared by the Service form, the package builder, and the Pricing Configuration page's own preview so all three can never disagree.
- **`PackagePricingPreview.tsx`** — live bundled-price total plus the bundle-discount-% input, computed via `deriveBundledPrice`; recalculates as services are added/removed from a package.
- **`PromoCard.tsx`** — one promo's summary card (name, timing badge, discount value, date window, active toggle, Edit/Branch Availability/Archive actions).
- **`PromoFilterBar.tsx`** — search + branch/timing/status filter controls above the promo card grid.
- **`PromoCapCard.tsx`** — the editable cap-type/cap-value form shown inside a "Configure" modal for one branch's promo cap.
- **`*.module.css`** (one per component/page above) — pure CSS-module styling on shared design tokens; no logic.

### api/
- **`maintenance.api.ts`** — the bulk of this feature's HTTP layer: `fetch` wrappers for every `/maintenance/*` Express endpoint (services, packages, promos, service types, breeds, pet types, pet-type price overrides, pricing configuration, package pricing configuration, pet weight-class configuration, promo cap configuration, image upload). Also has `listBranches()`, which reads the `branches` table directly via the Supabase client (RLS-open to any authenticated staff) since there's no Express endpoint for a lightweight branch-name lookup.
- **`branches.api.ts`** — separate, smaller wrapper for the Superadmin-only `/branches` endpoints (full branch read/create/update) used by System Configuration — distinct from `maintenance.api.ts`'s `listBranches`, which every role can call for name dropdowns.

### Other
- **`maintenance.routes.tsx`** — registers the seven `/staff/admin/maintenance/*` routes, each behind `StaffAuthGuard`; the Admin/Superadmin role gate itself lives inside each page (read off the viewer's own `/staff` row), not in the router.
- **`maintenance.types.ts`** — the client-side mirror of the server's DB-backed shapes (Service, Package, Promo, PricingConfiguration, PetTypeRow, etc.) plus every Create/Update payload type.
- **`utils/deriveBundledPrice.ts`, `utils/deriveGroomingMatrix.ts`, `utils/deriveWeightClass.ts`** — client-side copies of the same three pure pricing/weight-class formulas the server uses (see below), needed here so previews can recompute live without a round trip. Each file explicitly notes it must be kept in sync with its server twin by hand — there's no shared module between the two builds.
- **`utils/promoTiming.ts`** — classifies a promo as `Upcoming`/`Active`/`Ended` relative to today's date, for the Promos page's timing filter and badge.

## Server-side (`server/src/features/maintenance/`)

### Controller & routes
- **`maintenance.routes.ts`** — mounts every `/maintenance/*` endpoint (and the standalone `/maintenance/images` upload). Two middleware stacks: `staffRead` (any authenticated staff role) for GETs, `adminWrite` (Admin/Superadmin only) for everything that changes data. Unlike booking features, there's no branch-scoping middleware — an Admin manages both branches' catalog from one panel; branch filtering is just a query parameter.
- **`maintenance.controller.ts`** — one thin handler per route: parses the body with the matching Zod validator, calls the matching service function, maps a thrown `statusCode` into the HTTP response. No business logic lives here by design (that's all in `services/`).

### Service
- **`services.service.ts`** — CRUD for `services`. `createService`/`updateService` mirror `first_hour_fee` into `base_price` for Daycare (since Daycare's real price is computed at checkout, not admin-entered). `attachPricingMatrix` derives the read-time Grooming size/coat grid via `deriveGroomingMatrix` and attaches it under the same `service_pricing_tiers` key old consumers expect, with synthesized (non-DB) ids. `setServiceBranchAvailability` is the *only* place `services.is_active` changes now — it's kept in sync as "active whenever at least one branch has it available."
- **`packages.service.ts`** — CRUD for `packages`. `attachBundledPrice` derives `bundled_price` (via `deriveBundledPrice`) and `total_duration_minutes` (via `derivePackageDuration`) from the joined included services on every read — neither is a stored column. `assertServicesExistAndActive` guards that every bundled service id is real and currently active at create/edit time (but does **not** retroactively reject a package whose member was deactivated afterward). Archive is soft (`archived_at`) and gated behind `is_active === false` first; hard delete requires the package to already be archived and translates a foreign-key violation into a friendly "still referenced by a booking or sale" error.
- **`promos.service.ts`** — CRUD for `promos`. `listPromos` applies a defensive read-time eligibility filter (`isPromoCurrentlyEligible`, shared with checkout) so an expired promo is never returned as active even if the nightly expiry job hasn't run yet. `updatePromo` re-validates cross-field rules (date/condition exclusivity, date ordering, weekly-recurring day requirement, scope_type consistency) against the *merged* existing+patch state, since the Zod validator only sees whatever fields are present in a given PATCH. `promos.is_active` is deliberately **not** synced from branch availability the way services/packages/service types are — it also drives automatic date-based expiry, which is independent of which branches carry the promo.
- **`pricingConfiguration.service.ts`** — get/update for the singleton Grooming size/coat rule row (`pricing_configuration`). Always exactly one row (seeded by migration).
- **`packagePricing.service.ts`** — get/update for the singleton package bundle-discount-% row (`package_pricing_configuration`).
- **`petWeightClassConfiguration.service.ts`** — get/update for the singleton S/M/L/XL kg cut-off row. `updatePetWeightClassConfiguration` re-checks `m < l < xl` against the *merged* stored+patch values (the Postgres CHECK constraint is the final backstop).
- **`promoCap.service.ts`** — list/upsert for `promo_cap_configuration` (one row per branch plus a `branch_id = null` system-wide default). No client-visible row id to PATCH against, so `branch_id` itself is the upsert key: look up by branch, update if found, insert if not.
- **`petTypePriceOverrides.service.ts`** — list/upsert/delete for `pet_type_price_overrides`. `getFixedPrice(petType, branchId)` is the resolution function booking/pricing code calls: a branch-specific row wins over the `branch_id = null` system-wide default; `null` means no override, so normal base-price/matrix pricing applies.
- **`petTypes.service.ts`** — plain CRUD for the admin-managed `pet_types` table; delete is blocked (409) if a pet or breed still references it.
- **`breeds.service.ts`** — plain CRUD for `breeds`, keyed by `pet_type`. Duplicate name within a pet type is a 409; delete is blocked if a pet still references the breed.
- **`serviceTypes.service.ts`** — CRUD for `service_types` (the four booking-flow category rows). `key` is generated server-side via `randomUUID()` on create (no longer client-supplied) but still does real work as the join `cagePicker.service.ts`/the booking flow uses to match a row to its hardcoded `ServiceCategory`. `setServiceTypeBranchAvailability` keeps `is_active` in sync the same way `services.service.ts` does.
- **`maintenanceImageUpload.service.ts`** — validates and uploads an icon/photo (PNG/JPEG/WebP, 5MB max) to the `service-images` Storage bucket under a random-UUID-prefixed path, used by the "Add new..." forms before a record even exists to attach the image to.

### Types & validators
- **`maintenance.types.ts`** — server-side row shapes (`Service`, `Package`, `Promo`, `PricingConfiguration`, etc.) plus the two feature-local role lists: `MAINTENANCE_READ_ROLES` (all 8 staff roles) and `MAINTENANCE_WRITE_ROLES` (Admin/Superadmin only).
- **`modules/validators/maintenance.validator.ts`** — every Zod schema for this feature's request bodies. Notable cross-field rules: `requireDaycareFeesOrBasePrice` (Daycare needs hourly fees instead of `base_price`), `rejectZeroMultiplier` (a `multiplier`-type pricing rule can't be set to 0 — it would silently zero out that size's price), and `validatePromoShape` (shared by create/update: date-vs-condition exclusivity, weekly-recurring day-of-week requirements, scope_type/scope consistency). Also defines the curated `SERVICE_ICON_NAMES` allowlist mirrored from the client's icon picker.

### Other
- **`jobs/promoExpiry.job.ts`** — calls the `deactivate_expired_promos()` Postgres function daily at 00:05 server time as an application-level fallback to the preferred `pg_cron` schedule. Only touches date-bounded promos (a condition-based promo with no `end_date` is never auto-deactivated). Since this only runs while the Node process is alive, `promos.service.ts`'s own read-time filter is the real backstop against a missed run.
- **`utils/deriveBundledPrice.ts`, `utils/deriveGroomingMatrix.ts`, `utils/deriveWeightClass.ts`** — the authoritative pure pricing/weight-class formulas (client has hand-synced copies, see above). `deriveGroomingMatrix` also documents that `percentage`-type rules always apply against the service's own `base_price`, never an already size-adjusted running total, so combining a size rule and the coat rule can't depend on evaluation order.
- **`utils/derivePackageDuration.ts`** — plain sum of a package's included services' `duration_minutes` (a `null` member counts as 0); no discount concept for time the way there is for price.

## How it connects

The client's admin pages call `maintenance.api.ts`, which hits the `/maintenance/*` Express routes; each route's controller validates the payload and calls the matching `services/*.service.ts` function, which reads/writes the `services`, `packages`, `promos`, `service_types`, `pricing_configuration`, `package_pricing_configuration`, `pet_weight_class_configuration`, `promo_cap_configuration`, `pet_types`, `pet_type_price_overrides`, and `breeds` tables (plus their `*_branch_availability` join tables). These catalog rows are then consumed everywhere else in the app: booking selection and pricing in [[M03-appointment-booking|M03]], the Cage Picker; execution in [[M04-grooming-management|M04]]; cage CRUD and Hotel fixed pricing in [[M05-pet-hotel-boarding-management|M05]]; Daycare fee schedules in [[M06-daycare-management|M06]]; billing/downpayment netting in [[M08-sales-billing|M08]]; and Misc-category (assessment) services feed [[M02-customer-portal-pet-management|M02]]'s pet-assessment flow. See [[M13-01-package-creation-bundled-pricing|Package Creation & Bundled-Price Derivation]] and [[M13-02-promo-creation-cap-evaluation|Promo Creation, Branch Availability & Per-Transaction Cap Evaluation]] for the step-by-step workflows built on top of this code.
