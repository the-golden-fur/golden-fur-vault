# Admin-managed pet types with a fixed-price override

Branch: `feat/pet-type-admin-fixed-pricing`

## The request, verbatim

> Add admin config to pet types. CRUD for pet types. Make it so that they can
> set X fixed price to pet types, this will override service and package
> prices. By default, set cat type to 800 php for both services and packages
> (seed this). As an admin/superadmin, I want ALL SERVICES AND PACKAGES for
> cat type pets to be fixed price at 800.

## Root cause / Context

`pet_type` was a fixed 2-value Postgres enum (`Dog`/`Cat`), and the "Cat is
special" pricing rule was a literal string check (`pet.pet_type === 'Cat'`)
hardcoded into two pricing functions in `booking.service.ts`. This session
converts `pet_type` into a real admin-CRUD table and replaces the hardcoded
Cat check with a data-driven fixed-price-override table, so Cat's ₱800
becomes a seeded row instead of a code branch, and a brand-new admin-created
pet type "just works" with zero extra code.

## What changed

### Database

- `supabase/migrations/20260912191_custom_pet_types_admin_crud.sql` — creates
  `pet_types` (key/name/is_active, open read, Admin/Superadmin
  insert/update/delete), seeds `Dog`/`Cat`, converts `pets.pet_type` and
  `breeds.pet_type` from the enum to a `text` FK against `pet_types(key)`,
  drops `public.pet_type`.
- `supabase/migrations/20260912192_custom_pet_type_price_overrides.sql` —
  creates `pet_type_price_overrides` (pet_type + nullable branch_id +
  fixed_price, mirrors `policy_configurations`' default/branch-override
  pattern), seeds the system-wide default `('Cat', 800.00)` row.
- `supabase/seeds/m02-customers-pets/m02-customers-pets.seed.sql` — dropped a
  now-invalid `::public.pet_type` cast (the enum this cast referenced no
  longer exists).

### Server

- `booking.service.ts` — `resolveServicePrice`/`resolvePackagePrice` no
  longer special-case `'Cat'`; both accept a `fixedPriceOverride` parameter
  that short-circuits the matrix/base_price logic when set.
  `resolveBookingItems` fetches the override once (via the new
  `getFixedPrice`) and threads it through every item.
  `bookingGroup.service.ts` needed no changes — it only calls
  `resolveBookingItems`.
- New `maintenance/services/petTypes.service.ts` and
  `petTypePriceOverrides.service.ts` (list/create/update/delete + the
  `getFixedPrice` resolver), each with a `.spec.ts` mirroring
  `breeds.service.spec.ts`'s test shape.
- `maintenance.controller.ts` / `maintenance.routes.ts` — new
  `GET/POST/PATCH/DELETE /maintenance/pet-types[/:id]` and
  `GET/PUT/DELETE /maintenance/pet-type-price-overrides[/:id]`.
- `maintenance.validator.ts` / `pet.validator.ts` — the two hardcoded
  `PET_TYPES = ['Dog','Cat']` Zod enums (gating breed and pet creation) are
  loosened to a free string; the real validation is now the DB foreign key.
  Added `createPetTypeValidator`/`updatePetTypeValidator`/
  `upsertPetTypePriceOverrideValidator`.
- `pet.controller.ts` — added a friendly `23503`-on-`pet_type` → 400
  "Invalid pet type" mapping on pet create/update (the FK replaces the old
  enum-level rejection).
- `PetType` type alias loosened from `'Dog' | 'Cat'` to `string` in all three
  server/client locations it's declared.

### Client

- New `maintenance/pages/AdminPetTypesPage/` — one Settings > Config tile
  ("Pet Types") with two sections: a CRUD list (add/rename/deactivate/delete
  a pet type) and a fixed-price-override editor (branch selector +
  per-pet-type price input, mirroring `PolicyConfigurationPage`'s
  branch-selector pattern).
- `maintenance/api/maintenance.api.ts` — 7 new functions for the above.
- `customers/api/customer.api.ts` — new open-read `listPetTypes()` for the
  customer-facing pet forms.
- Every hardcoded `['Dog', 'Cat']` dropdown/filter converted to fetch from
  `listPetTypes()`: `PetForm.tsx`, `PetDetailPanel.tsx`,
  `AdminBreedsPage.tsx` (the breed-type filter/selector), `MyPatientsPage.tsx`.
- `configTiles.config.ts` / `maintenance.routes.tsx` — new tile and route
  registration.

### Follow-up fix (found during the user's own live testing)

The user tested the fix against the actual booking flow and found the
Review step still showed a Grooming service's plain ₱300 price for a real
Cat pet ("Luna"), not ₱800 — the server-side data was already correct (the
migrations had in fact already been applied to the dev Supabase project,
confirmed by querying `pet_types`/`pet_type_price_overrides`/`pets` directly
against it), but the customer-facing price preview computed its running
total entirely client-side from each service/package's own `base_price`,
with no way to know about a server-side override.

- `catalog.service.ts` (`getBookingCatalog`) — now accepts an optional
  `petType` and resolves/returns `fixedPrice` via the same `getFixedPrice`
  the booking-creation flow uses, so the preview and the actual charge are
  guaranteed to agree.
- `booking.controller.ts` / `booking.validator.ts` — threaded a new
  `pet_type` query param through `GET /bookings/catalog`.
- `CustomerBookingFlowPage.tsx` — passes the selected pet's type into the
  catalog fetch, and uses the returned `fixedPrice` (falling back to each
  item's own price when null) everywhere a price is shown: the
  service/package option cards, the running total, and the persistent
  selection summary. Daycare's hourly-fee display line is deliberately left
  alone (see the "known follow-up" note below - showing a flat price there
  would be misleading about what Daycare actually bills at pickup).
- Added a component test asserting a Cat's Bath selection shows ₱800.00 on
  both the option card and the running total, not ₱300.00.

## Manual test — step by step

1. Run `supabase db reset` locally (or apply the two new migrations to a dev
   project) so `pet_types` and `pet_type_price_overrides` exist and are
   seeded.
2. Open the app, log in as an Admin or Superadmin staff account, and go to
   **Settings → Config → Pet Types** (a new tile with a paw-print icon).
3. Under **Existing pet types**, confirm **Dog** and **Cat** are both
   listed. Under **Fixed price overrides**, with the Branch dropdown on
   "System default (all branches)", confirm **Cat** shows `800` in its
   price box.
4. Add a new pet type: type a key (e.g. `Rabbit`) and name (`Rabbit`), click
   **Add pet type**. Confirm it appears in the list above and (after a
   refresh) in the fixed-price-overrides list.
5. Go to a customer's pet-add form (**Bookings → your pets → Add a pet**, or
   the receptionist walk-in intake form) and confirm the Pet Type dropdown
   now includes **Rabbit** alongside Dog/Cat.
6. Book any service or package for a **Cat** pet (any branch) and confirm
   the charged price is exactly ₱800, regardless of that service's own
   listed price or weight/coat matrix settings.
7. Back in **Pet Types → Fixed price overrides**, switch the Branch dropdown
   to one specific branch, set a different price for **Dog** there (e.g.
   `500`), click **Save**. Book a Dog service at that branch and confirm it
   charges ₱500; book the same service at the _other_ branch and confirm it
   still prices normally (no override there).
8. Book a service for a **Rabbit** pet with no override configured and
   confirm it prices exactly like a Dog would (the matrix if the service
   opts in, otherwise its own flat price) — no error.
9. Try **Delete** on a pet type currently assigned to an existing pet (e.g.
   Dog or Cat) — confirm it's blocked with a friendly error rather than a
   raw database message. **Deactivate** it instead and confirm it disappears
   from the pet-add dropdown without affecting any existing pets of that
   type.

## Test suites

- `server`: `npx vitest run` — 1103/1103 passing (99 files, up from 1083 —
  20 new tests across `petTypes.service.spec.ts`/
  `petTypePriceOverrides.service.spec.ts`/`catalog.service.spec.ts`);
  `npx tsc --noEmit` clean; `npx eslint` clean on every touched file.
- `client`: `npx vitest run` — 867/867 passing (166 files, +1 for the new
  Cat fixed-price component test); `npx tsc --noEmit` clean; `npx eslint`
  clean on every touched file (one `react-hooks/exhaustive-deps` warning in
  `AdminBreedsPage.tsx` was fixed during the session).
- Prettier: clean on every touched non-SQL file (checked from repo root per
  this repo's convention).
- Verified directly against the live dev Supabase project and the running
  dev server (not just mocks): `pet_types`/`pet_type_price_overrides` exist
  and are seeded correctly there, and `GET /bookings/catalog` (hit for real,
  as `customer1@goldenfur.com`, against the real running server) returns
  `fixedPrice: 800` for Cat at Makati while Bath's own `base_price` is 300.
- The user re-tested the actual booking flow end-to-end after the follow-up
  fix above and confirmed it now shows the correct fixed price.

All counts above were run directly in this session, not carried over from a
prior review.

## Open items

- No `.postman_collection.json` was added for the 7 new
  `/maintenance/pet-types*` and `/maintenance/pet-type-price-overrides*`
  routes, or for `GET /bookings/catalog`'s new `pet_type` param — worth
  adding if API-level regression coverage is wanted later.
- **Known gap, deliberately deferred**: Daycare's final checkout charge
  (`daycareBilling.service.ts`'s `checkOutDaycareSession`/
  `computeDaycareCharge`) is computed independently from the service's
  hourly fee columns, entirely bypassing `price_at_booking` and the
  fixed-price override - a Cat's Daycare stay would still bill hourly at
  pickup regardless of any override. Flagged to the requester during this
  session; not fixed here.
- The `pet_types`/`pet_type_price_overrides` migrations were confirmed
  already applied to the linked dev Supabase project during this session's
  own verification (not pushed by this session itself - already present
  when checked).
