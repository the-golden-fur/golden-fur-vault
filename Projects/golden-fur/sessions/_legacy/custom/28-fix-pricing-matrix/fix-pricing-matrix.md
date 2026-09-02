# Fix pricing matrix

Branch: `28-fix-pricing-matrix`

Follow-up to `27-daycare-hotel-parity-and-fixed-pricing` in the same session
("while you're at it") - a distinct P-1 item from
`temp/context/Architectural-Change-Suggestions.docx`, so it gets its own
numbered folder per this repo's one-request-per-folder convention.

## Why

Three observations from the pricing board image, all under one "Fix pricing
matrix" ask:

1. "Cat has no weight class or coat type, fixed [price] for golden
   package" - the board shows one flat Cat price for both Basic Grooming
   and the Golden Grooming Package, never a size/coat cell.
2. "Coat and weight doesn't seem to influence individual service" - the
   board's individual add-on services (Nail Trim, Teeth Brushing, Ear
   Cleaning, Anal Drain, Face Trim, Dematting, Poodle Feet) are each one
   flat price, not a size/coat matrix.
3. "Perhaps when creating a service/package, make the coat and weight
   matrix optional by adding a checkbox? So that the service/package price
   can either be flat/fixed or derived from weight/coat type."

Before this change, every Grooming service (`services.service.ts`'s
`attachPricingMatrix`) unconditionally derived a weight/coat matrix price
from `base_price` + the shared `pricing_configuration` singleton - there was
no way to turn that off per service (contradicting #2), and packages never
varied by pet at all (`bundled_price` was always one flat admin-configured
figure - not a bug the board called out directly, but the literal
"same...for a service/package" checkbox request implies packages too).

## What changed

### DB

`supabase/migrations/20260807106_m13_optional_pricing_matrix.sql`:

- `services.use_pricing_matrix boolean not null default false` - opt-in
  per service. Data update: only Bath/Blow-dry/Brushing (the seeded Golden
  Package's three member services, and the closest existing analog to the
  board's "Basic Grooming" row - the one item that does vary by size) are
  flipped to `true`; every individual add-on service stays `false`.
- `packages.use_pricing_matrix boolean not null default false` - opt-in
  per package. The seeded Golden Package is flipped to `true` (an UPDATE in
  the migration for already-seeded environments, and the seed files
  themselves updated to insert it `true` going forward - see
  `supabase/seeds/module-3-maintenance/`).

Cat handling needed no schema change - `pets.pet_type` already exists
(migration `20260725041`). It's purely an application-layer rule.

### Server

`server/src/features/booking/services/booking.service.ts`:

- `resolveServicePrice` (now exported for direct unit testing) only
  consults the weight/coat tier when `service.category === 'Grooming' &&
service.use_pricing_matrix && pet.pet_type !== 'Cat'` - otherwise it
  always returns the flat `base_price`. A Cat pet skips the matrix
  regardless of the service's own flag.
- New `resolvePackagePrice` (exported): a non-matrix package (the default)
  keeps using the flat `bundled_price`, unchanged. A matrix-enabled
  package instead sums each included service's own per-pet price
  (respecting that service's own `use_pricing_matrix` flag and the Cat
  rule - reuses `resolveServicePrice` under the hood, with the matrix cell
  derived inline via `deriveGroomingMatrix` since the raw member-service
  query has no pre-attached tier array) and applies the existing
  `package_pricing_configuration` bundle discount on top via
  `deriveBundledPrice` - the same formula the flat case already used, just
  fed per-pet prices instead of raw `base_price` values.
- `PetRow` (now exported) gained `pet_type`, and the `pets` select in
  `createBooking` now fetches it.

`server/src/features/maintenance/`: `Service`/`Package` types and the
create/update Zod validators for both gained `use_pricing_matrix`
(`maintenance.types.ts`, `modules/validators/maintenance.validator.ts`).
`services.service.ts`/`packages.service.ts` needed no changes - both
already spread the full DB row (`...service`/`...pkg`) through their
response-shaping functions, so the new column flows through for free.

### Client

- `client/src/features/maintenance/maintenance.types.ts` - mirrors the
  server type/payload additions.
- `AdminServicesPage.tsx` - a new "Derive price from weight/coat matrix"
  toggle, shown only for Grooming. The existing `PricingMatrixPreview` is
  now gated on the toggle being on (previously showed unconditionally for
  every Grooming service) - a service row also shows a "Varies by
  weight/coat" badge when it's on.
- `AdminPackageBuilderPage.tsx` - the same toggle for packages ("...sum of
  included services' own per-pet price, bundle-discounted..."). The
  existing `PackagePricingPreview` (the flat estimate) is left as-is either
  way - it's a reference figure for the admin list, not the authoritative
  booking-time price once the toggle is on.

## Known limitation / deliberate scope cut

This does **not** attempt to make the seeded catalog's actual peso figures
match the pricing board exactly. The board's "Golden Grooming Package" row
(Bath & Blow Dry, Hair Cut, Sanitary Trim, Ear Cleaning, Nail Trim, Nail
File, Toothbrush, Cologne Spray) is a materially bigger bundle than the
currently-seeded "Golden Package" (Bath + Blow-dry + Brushing only) -
several of those board items (Hair Cut, Sanitary Trim, Nail File,
Toothbrush, Cologne Spray) aren't seeded as individual services at all.
Recomposing the package's member-service list, and/or retuning the shared
`pricing_configuration` multipliers to hit the board's exact
per-size/per-coat numbers, is a catalog-content exercise distinct from "fix
the matrix mechanism" (this request), and retuning the shared singleton
multiplier formula would need a clear target spec beyond one board photo to
do safely (it now only affects Bath/Blow-dry/Brushing, since every other
Grooming service defaults to flat, but is still shared across whichever
services an admin later opts back into the matrix). This change delivers
the mechanism (opt-in matrix, Cat exemption) faithfully and lets an Admin
tune `base_price`/multipliers/package composition afterward through the
existing admin pages.

Also unrelated / out of scope for this bullet specifically: pets still
require a full staff assessment (`weight_class` **and** `coat_type` both
set) before booking most services, regardless of `pet_type` - a Cat still
needs both fields recorded today, even though neither one now affects
Grooming price. Making assessment itself optional/different for Cats is a
separate concern not raised by this bullet.

## Verification

### 1. Migration

- **With Supabase CLI access**: `supabase db reset` (fresh local db) or
  `supabase db push` (linked remote project).
- **Without CLI/push access**: Supabase Dashboard → **SQL Editor** → paste
  `fix-pricing-matrix.sql` in this folder → **Run**. Confirm with:
  ```sql
  select name, use_pricing_matrix from public.services
  where id::text like 'a1300000-%' and category = 'Grooming' order by name;
  select name, use_pricing_matrix from public.packages where name = 'Golden Package';
  ```
  Bath/Blow-dry/Brushing should show `true`; every other Grooming service
  should show `false`; every Golden Package row should show `true`.

### 2. Individual services no longer vary by size/coat

1. As Admin/Superadmin, open `/staff/admin/maintenance/services`, filter
   to Grooming.
2. Open **Nail Trim** (or any individual add-on service) for editing - the
   new "Derive price from weight/coat matrix" toggle should be **off**, and
   no matrix preview should render.
3. As a customer or receptionist, book Nail Trim for two different pets
   with different weight classes/coat types (e.g. one Small/Short-coat Dog,
   one XL/Long-coat Dog) - both bookings should charge the exact same
   price (the service's flat `base_price`).

### 3. Bath/Blow-dry/Brushing (and the Golden Package) still vary by size for Dogs

1. Open **Bath** for editing - the toggle should be **on**, with the
   derived matrix preview showing 8 cells.
2. Book Bath for a Small/Short-coat Dog vs. a Large/Long-coat Dog - the two
   charges should differ, matching the preview's S/SC vs. L/LC cells.
3. Book the **Golden Package** for the same two dogs - the two charges
   should also differ (previously identical regardless of pet).

### 4. Cat pets always get the flat price

1. Book Bath (or the Golden Package) for a Cat pet (staff must still
   record _some_ weight_class/coat_type for the pet to pass the existing
   assessment gate - any values work, they're just ignored for pricing).
2. The charge should equal the service's plain `base_price` (or the
   package's flat `bundled_price`), not a matrix-derived figure - and
   should be identical no matter what weight_class/coat_type was recorded
   for that Cat.

### 5. The optional-matrix checkbox itself

1. Create a new Grooming service, leave "Derive price from weight/coat
   matrix" unchecked, save - book it for two differently-sized Dogs, confirm
   identical pricing.
2. Edit that same service, check the toggle, save - book it again for the
   same two dogs, confirm the pricing now differs by size.
3. Repeat for a package via `/staff/admin/maintenance/packages`'s "Build
   package"/edit form.

### 6. API-level checks (Postman)

See `fix-pricing-matrix.postman_collection.json` in this folder.

1. Import the collection, fill in `admin_identifier`/`admin_password`,
   `branch_id`, `customer_id`, and `dog_pet_id`/`cat_pet_id` (both owned by
   that customer and staff-assessed - any weight_class/coat_type values are
   fine for the Cat, since they're ignored for pricing either way).
2. Run requests in order. All Test Results should be green.

## Test suites

- `server`: `npm run test` (from `server/`) - 740/740 passing (6 new: 3
  `resolveServicePrice` unit tests - matrix-tier-for-Dog, flat-for-
  non-matrix, flat-for-Cat - and 3 `resolvePackagePrice` unit tests -
  flat-bundled_price-when-off, matrix-sum-for-Dog, flat-for-Cat -
  in `booking.service.spec.ts`'s new "pricing matrix (custom change)"
  describe block). One pre-existing test (`GROOMING_SERVICE`'s "tiered
  price" fixture) needed `use_pricing_matrix: true` added, since the tier
  it asserts on is now opt-in.
- `client`: `npm run test` (538/538) and `npx tsc -b` (clean, 15/15 in the
  two admin page specs). Updated `AdminServicesPage.spec.ts` (the pricing
  matrix preview is now gated on the new toggle, queried via
  `role: 'switch'` matching `ToggleSwitch`'s actual accessible role - not
  `'checkbox'`) and `AdminPackageBuilderPage.spec.ts` (the create-package
  payload assertion needed `use_pricing_matrix: false` added, since the
  form now always sends that field).
