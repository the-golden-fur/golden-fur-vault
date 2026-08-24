# Lock pet weight_class/coat_type to staff-only; gate bookings on assessment

Branch: `feat/pet-assessment-gate`

## Why

Client interview finding: customers could freely set/edit their own pet's
`weight_class` and `coat_type` at any time, and those two fields directly
drive Grooming price (the `service_pricing_tiers` lookup in
`booking.service.ts`'s `resolveServicePrice`) and Hotel cage-size assignment
(`cageAssignment.service.ts`). A customer could under-report either field to
get a cheaper price or a smaller cage. The real process: the pet comes
onsite, staff physically weighs it and inspects its coat, and only then
should it price/cage correctly.

## What changed

### 1. Schema (`supabase/migrations/`)

- `20260802073_m02_pets_assessment_lock.sql`:
  - `pets.weight_class` / `pets.coat_type` are now nullable. `NULL` means
    "not yet assessed."
  - New nullable columns `pets.assessed_by` (references `staff_profiles`)
    and `pets.assessed_at` - stamped automatically, never client-writable.
  - New trigger `trg_enforce_pet_assessment_writes` (function
    `public.enforce_pet_assessment_writes`, `BEFORE INSERT OR UPDATE ON
public.pets`): any caller who isn't Receptionist/Admin/Supervisor/
    Superadmin (`current_staff_role()`) is rejected outright if they try to
    set or change `weight_class`/`coat_type`. This is the DB-layer
    defense-in-depth backstop; the primary, UX-facing enforcement is the
    app-layer validator split below.
- `20260802074_m13_services_requires_assessed_pet.sql`:
  - `services.requires_assessed_pet boolean not null default true`.
  - Seeds a new **"Initial Assessment"** Grooming service
    (`a1300000-0000-4000-a000-000000000022`), `requires_assessed_pet =
false`, `base_price = 0` (placeholder - an Admin should set the real fee
    via the Services admin page before launch).

### 2. Server (`server/src/features/...`)

- `customers/pets/modules/validators/pet.validator.ts`: `createPetValidator`/
  `updatePetValidator` (customer-facing) no longer accept `weight_class`/
  `coat_type` at all - a payload containing either is rejected with a clean 400. New `createPetValidatorStaff`/`updatePetValidatorStaff` variants
  accept them (both optional - a pet can be registered before it's weighed).
- `customers/pets/pet.controller.ts`: `createPetController`/
  `updatePetController` pick the customer vs. staff validator based on the
  same ownership/role check that already gated write access, so the
  self-service path (`isSelf`/`isOwner`) never even queries staff role.
- `booking/services/booking.service.ts`: after the existing pet-ownership
  check, `isPetAssessed(pet)` gates the rest of `createBooking` - an
  unassessed pet (`weight_class`/`coat_type` both null) can only book a
  service flagged `requires_assessed_pet = false`; a package is never
  exempt. Hotel/Daycare capacity code is unaffected since it only ever runs
  after this gate passes.
- `maintenance/`: `Service.requires_assessed_pet` added to types + the
  create/update service validators, so Admin/Superadmin can toggle it from
  the existing Services admin page without a future code change.

### 3. Client (`client/src/features/...`)

- `customers/customer.types.ts`: `Pet.weight_class`/`coat_type` widened to
  nullable; added `assessed_by`/`assessed_at`. New `PetCreatePayloadStaff`/
  `PetUpdatePayloadStaff` types (customer payload types no longer include
  the two fields at all).
- `customers/components/forms/PetForm/PetForm.tsx` and
  `customers/components/panels/PetDetailPanel/PetDetailPanel.tsx`: new
  `isStaff` prop. A customer editing their own pet never sees or submits the
  weight/coat inputs; a staff-authorized editor does, and they're optional.
  Every caller of these two shared components was updated to pass the
  correct value (`CustomerPetManagerPage`/`PetProfilePage`: customer;
  `CustomerManagementPage`, `DaycareCheckInPage`, `StaffPetProfilePage`:
  staff; `CustomerBookingFlowPage`: staff only in Receptionist mode).
- `customers/components/cards/PetCard/PetCard.tsx`,
  `booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`,
  `booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`: null-safe
  display ("Not yet assessed" badge/copy instead of blank/`null`).
- `CustomerBookingFlowPage.tsx` additionally: the Service step now filters
  out any service with `requires_assessed_pet = true` when the selected pet
  is unassessed (so only Initial Assessment shows), hides the Package tab
  entirely for an unassessed pet, and shows an explanatory message.
- `maintenance/maintenance.types.ts` +
  `maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`: new
  "Requires an assessed pet" toggle in the service create/edit form, and a
  "No assessment required" badge on the service row when it's off.

## Known limitations / follow-ups (out of scope, per the confirmed direction)

- No approval-queue UI, no `pending`/`approved` pet status, no blocking
  reassessment step inserted into the booking flow. Reassessment (see below)
  is a normal bookable service, not a workflow state.
- Who can create a pet is unchanged - customers keep self-serve create.
- `cageAssignment.service.ts`'s `suggestCage()` still reads `weight_class`
  with no gate of its own, but it's only reachable from an already-created
  (thus already-gated) Hotel booking, so this is a documented non-issue, not
  a gap.

## Follow-up: trigger bug fix, booking UX, Reassessment, "last assessed", seeds

Live testing on the branch above surfaced a booking-flow dead end, and while
investigating it a **more serious bug** turned up in the DB trigger itself:

- **Bug**: `enforce_pet_assessment_writes()` read `current_staff_role()`,
  which resolves from `auth.uid()`/`request.jwt.claims`. Every write in this
  codebase (including `pet.controller.ts`'s legitimate staff PATCH) goes
  through the single shared **service-role** Supabase client
  (`server/src/config/supabase/supabase.config.ts`) with no per-request JWT
  propagated into the Postgres session - so `auth.uid()` was always `NULL`
  for the app's real write path, meaning the trigger **rejected every
  legitimate staff write**, not just customer ones. This didn't surface in
  the automated suite (which mocks Supabase entirely) or in earlier manual
  testing (the local DB still had pre-migration pet rows, and the trigger
  only fires on INSERT/UPDATE) - it would have surfaced the moment a fresh
  `supabase db reset` re-seeded assessed pets, or the first real staff
  "assess a pet" PATCH against a fresh database.
- **Fix** (`20260802075_m02_pets_assessment_trigger_fix.sql`): the trigger
  now only rejects when it can positively identify a real authenticated
  **non-staff** caller (`auth.uid() is not null`); a `NULL` caller
  (service-role/seed context - the app's actual path) passes through
  untouched, trusting the app layer, consistent with how every other write
  in this codebase already works (RLS itself is already bypassed for
  service-role writes). `assessed_by`/`assessed_at` stamping moved into
  `pet.controller.ts` (`resolveAssessmentStamp`) since the trigger can no
  longer infer caller identity for the service-role path - it only stamps
  when `weight_class`/`coat_type` actually _change value_ (not merely
  "present in the payload" - the staff edit form resends both on every
  save), so an unrelated name/photo edit never resets "last assessed."
- **Booking UX** (`CustomerBookingFlowPage.tsx`): an unassessed pet used to
  dead-end on "No Grooming services available at this branch." Now:
  `availableCategories` only offers the Grooming tab for an unassessed pet
  (Hotel/Daycare/Veterinary are always dead ends for it); selecting a pet
  resets any stale category/service selection; and a new effect
  auto-selects Initial Assessment the moment the branch catalog loads, so
  Next is enabled immediately with no manual browsing required. Review &
  Pay needed no special-casing - Initial Assessment is a normal (if
  currently zero-priced-placeholder) service.
- **New "Reassessment" service**
  (`20260802076_m13_seed_reassessment_service.sql`, id `...0023`): for a pet
  that already has an assessment on file but may need re-weighing.
  Deliberately `requires_assessed_pet = true` (the opposite of Initial
  Assessment) - it's not a substitute entry point for a brand-new pet, just
  another ordinary bookable Grooming service.
- **"Last assessed X ago"**: new `client/src/shared/utils/
formatRelativeTime.ts` (no relative-time helper existed anywhere in the
  client before this). Shown on `PetCard.tsx` (Pet Manager grid, both
  customer and staff "View Pets") and `PetDetailPanel.tsx` (pet profile,
  both customer and staff views) whenever `assessed_at` is set. Deliberately
  timestamp-only, no staff name - `assessed_by` isn't resolved to a display
  name anywhere (would need a new server-side join, left out of scope).
- **Seeds** (`supabase/seeds/module-2-customers-pets/`): the existing 8
  "assessed" pets now also get `assessed_by`/`assessed_at` (resolved via a
  seeded Receptionist lookup, `assessed_at` varied per pet via an
  `assessed_days_ago` field so the "X ago" display isn't identical across
  the board). One new, deliberately never-assessed pet was added per
  customer (5 new rows) so every customer has at least one assessed and one
  unassessed pet. Total pets 8 → 13. Both the `.sql` and `.ts` seed scripts
  were updated identically; `module-2-customers-pets.seed.spec.ts` covers
  the new count and the assessed/unassessed mix.

### Incidental fix: stale `packages.bundled_price` seed reference

Unrelated to pet assessment, but discovered and fixed here because it was
blocking verification of everything above: a full `supabase db reset`
failed at the module-3 seed step with `column "bundled_price" of relation
"packages" does not exist`. `packages.bundled_price` was dropped back in
`20260726048_m13_package_pricing_configuration.sql` (the price became
derived on read from `package_pricing_configuration` instead of stored),
but `module-3-maintenance.seed.{sql,ts}`'s Golden Package insert was never
updated to match - apparently no one had run a full fresh reset since that
migration landed. Fixed by dropping `bundled_price` from both seed scripts'
package insert; `module-3-maintenance.seed.spec.ts` updated to match (no
longer asserts a stored `bundled_price` value).

## Verification steps

### 1. Automated tests (already run and passing as of this change)

- `cd server && npm run typecheck && npm run lint && npm test` - 72 test
  files / 682 tests passing.
- `cd client && npx tsc -b && npm run lint && npm test` - 115 test files /
  518 tests passing.
- `npm run test:seed` (repo root) - 4 test files / 21 tests passing,
  including the updated pet seed spec.

### 2. Apply the migrations, then do a FULL fresh reset

However you normally apply migrations locally (`supabase db reset` or
`supabase migration up`) - this now picks up four new migration files
(`...073` through `...076`). **Run a full `supabase db reset`** (not just
`migration up`) at least once - this is the actual regression test for the
trigger bug: before the `...075` fix, a fresh reset would fail outright
while seeding assessed pets. It's also the regression test for the
`bundled_price` fix above - the reset should now get past the module-3
seed step instead of erroring on `packages.bundled_price`. If it completes
without error end-to-end and `select count(*) from public.pets;` returns
13, both fixes are working.

### 3. Confirm the schema/trigger in Supabase (SQL Editor)

Open your project's Supabase dashboard → SQL Editor, paste in
`pet-assessment-gate.sql` from this folder, and run each numbered section.
Expected results are noted inline as SQL comments. Section 7 specifically
exercises the trigger-fix scenario (a real authenticated non-staff session
is still rejected; the service-role/postgres session - the app's actual
write path - is not).

### 4. Confirm the customer flow can't set weight/coat (Postman)

Import `pet-assessment-gate.postman_collection.json` from this folder. Fill
in `customer_identifier`/`customer_password` (an existing customer login)
and `admin_identifier`/`admin_password` (Admin or Superadmin), then run the
requests in order:

1. Login as customer.
2. Create a pet as the customer, **including** `weight_class`/`coat_type` in
   the body → expect **400** (rejected before it ever reaches the DB).
3. Create a pet as the customer **without** those fields → expect **201**,
   and the returned pet has `weight_class: null`, `coat_type: null`.
4. Try to PATCH that same pet's `weight_class` as the customer → expect
   **400**.
5. Login as Admin/staff.
6. PATCH the same pet's `weight_class`/`coat_type` as staff → expect **200**,
   and the returned pet now has `assessed_by`/`assessed_at` populated.

### 5. Confirm the booking gate (same Postman collection, continued)

7. As the customer, try to create a booking for a **different**, still-
   unassessed pet against a normal service (e.g. any Grooming service other
   than Initial Assessment) → expect **403**.
8. Same unassessed pet, but book the **Initial Assessment** service instead
   → expect **201**.
9. Same unassessed pet, try to book a **package** → expect **403** (packages
   are never assessment-exempt).
10. Same unassessed pet, try to book **Reassessment** → expect **403**
    (unlike Initial Assessment, it requires an already-assessed pet).

### 6. Manual UI smoke test

1. Log in to the customer portal, go to Pet Manager, add a pet. Confirm the
   form has no weight class / coat type fields at all, just a note that
   staff will record them onsite. Confirm the new pet's card shows "Not yet
   assessed" (no "Last assessed" line).
2. Start a booking for that new pet (`/portal/book`). On the pet step, it
   should show "Not yet assessed." On the branch step, pick a branch. On the
   service step: only the **Grooming tab** should be shown (no Hotel/
   Daycare/Veterinary tabs), **Initial Assessment should already be
   pre-selected** with no clicking required, and Next should already be
   enabled.
3. Log in to the staff app as a Receptionist/Admin, open Customer Management
   → the same customer → View Pets → the pet's profile
   (`/staff/pets/:petId`). Click Edit - weight class and coat type fields
   should now be present. Set them and save. Confirm the pet's detail page
   now shows a "Last assessed" row reading "today."
4. As the customer again, start a new booking for that same pet - the full
   service catalog and Packages tab should now be available (Hotel/Daycare/
   Veterinary tabs reappear too), Grooming pricing should reflect the
   assessed size/coat tier, and "Reassessment" should be selectable
   alongside every other Grooming service.
5. As Admin, go to Services (`/staff/admin/maintenance/services`) → New
   service. Confirm the "Requires an assessed pet" toggle is present and
   defaults on; find the seeded "Initial Assessment" and "Reassessment"
   services in the list - only Initial Assessment should show the "No
   assessment required" badge.
6. Reset your local Supabase (`supabase db reset`) and check the customer
   Pet Manager for `customer1@goldenfur.com` (password `password123`) -
   confirm it shows 3 pets (Max, Luna - both with a "Last assessed" line
   showing a plausible time in the past - and Cooper, "Not yet assessed").
