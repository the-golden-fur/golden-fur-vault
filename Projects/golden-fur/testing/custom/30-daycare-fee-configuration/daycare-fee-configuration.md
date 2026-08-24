# Daycare fee configuration

Branch: `30-daycare-fee-configuration`

Fourth "while you're at it" follow-up in the original session, after
`27-daycare-hotel-parity-and-fixed-pricing`, `28-fix-pricing-matrix`, and
`29-fix-supabase-reset-seed` - a distinct P-1 item from
`temp/context/Architectural-Change-Suggestions.docx`. Revised on live
follow-up feedback (see "Design revision" below) before any of it was
committed.

## Why

The user's request, verbatim:

- 850 for daycare booking if not picked up (overnight payment) + all 50 for
  succeeding hours - `850 * number of nights + 100 + sum of 50`.
  - Add a configuration in admin settings where that fixed 850 price can be
    changed but default 850.
  - This should be added to a policies page in settings > config.
- When creating a daycare service, include this initial hour + fee for
  subsequent hours - this fee itself is attached to the service, not
  hardcoded to all daycare services.

The ₱850/night overnight fee already existed
(`pricing_configuration.daycare_overnight_fee`, migration
`20260803088_m08_daycare_overnight_pricing.sql`, default 850.00) and the
`850 * nights + 100 + sum of 50` formula was already implemented in
`daycareBilling.service.ts`'s `computeDaycareCharge` (from the
`22-daycare-overnight-billing` custom change). What was missing was exactly
the two bullets above:

1. The 850 default lived on `pricing_configuration` - a Grooming-focused
   singleton surfaced only on the Pricing Configuration page - not
   admin-configurable anywhere resembling "settings > config."
2. The ₱100 first-hour / ₱50 succeeding-hour figures were hardcoded module
   constants in `daycareBilling.service.ts`, applying uniformly to every
   Daycare service with no per-service attachment at all.

## Design revision (live follow-up feedback)

The first draft of this change moved `daycare_overnight_fee` onto
`policy_configurations` (Settings > Config > Policies), matching the
request's literal "policies page in settings > config" wording - see the
git history of this migration for that intermediate shape. Before any of it
shipped, live follow-up feedback on the resulting Policies page asked to
move it again: "I think we should move the daycare overnight fee from the
settings > config, into when creating a daycare type service, so that each
daycare type service can have its own overnight fee" - and to make it
"visible when booking." Since nothing had been committed yet, the migration
and code were revised in place rather than layering a second migration on
top - **the final, shipped design is per-service, not per-branch-policy**,
described below.

## What changed

### DB

`supabase/migrations/20260807107_m06_m09_daycare_fee_config.sql`:

- `services.daycare_overnight_fee numeric(10,2) check (>= 0)` - nullable,
  Daycare-only in meaning (NULL falls back to the documented ₱850 default).
  Backfilled from whatever `pricing_configuration.daycare_overnight_fee`
  already held (or 850.00) onto the seeded Daycare service.
- `pricing_configuration.daycare_overnight_fee` dropped - it's now purely a
  per-service Daycare fee, alongside the two below.
- `services.first_hour_fee numeric(10,2) check (>= 0)` and
  `services.succeeding_hour_fee numeric(10,2) check (>= 0)` - nullable
  (NULL falls back to the documented ₱100/₱50 defaults). The seeded Daycare
  service (`id = 'a1300000-0000-4000-a000-000000000011'`) is updated to
  `first_hour_fee = 100.00, succeeding_hour_fee = 50.00`, preserving the
  exact prior hardcoded behavior for existing data.
- `stays.service_id uuid references services(id)` - records which
  service's fee schedule a Daycare (or Hotel) stay was billed under.

Seed files (`supabase/seeds/module-3-maintenance/`,
`supabase/seeds/module-6-*`) updated in parallel so a fresh
`supabase db reset` produces the same shape without needing the migration's
UPDATE statements.

### Server

- `maintenance.types.ts` / `maintenance.validator.ts` -
  `daycare_overnight_fee` added to `Service`, `createServiceValidator`
  (optional - falls back to ₱850 even when omitted for a Daycare service),
  `updateServiceValidator` (optional, nullable). A new `superRefine`
  (`requireDaycareFeesOrBasePrice`) enforces the create-time trade-off
  below: `base_price` is required for every category except Daycare, where
  `first_hour_fee`/`succeeding_hour_fee` are required instead.
- `services.service.ts` - **base_price is no longer admin-entered for
  Daycare** (see "why are there so many prices to config" below):
  `createService` mirrors `first_hour_fee` into `base_price` for a Daycare
  service (satisfying the NOT NULL column and giving Daycare bookings a
  sensible price snapshot at _booking_ creation time, before the actual
  hourly charge is known at _checkout_); `updateService` keeps `base_price`
  in sync whenever the (possibly just-changed) category is Daycare and a
  `first_hour_fee` is resolvable, covering both "category changed to
  Daycare" and "first_hour_fee changed on an existing Daycare service."
- `booking.types.ts` / `booking.validator.ts` / `staffPicker.service.ts` -
  the intermediate `daycare_overnight_fee` addition to
  `PolicyConfiguration`/`EffectivePolicy`/`updatePolicyValidator`/
  `resolveEffectivePolicy` was reverted (never shipped).
- `daycareCheckIn.service.ts` - unchanged from the first draft: new
  `resolveDaycareServiceId(branchId, bookingId, explicitServiceId)`
  determines which service's fee schedule applies at check-in (from the
  linked booking's `booking_items`, an explicit `service_id` on a walk-in,
  or the branch's first active/available Daycare service), storing it on
  `stays.service_id`.
- `daycareBilling.service.ts` - `computeDaycareCharge` now takes optional
  `firstHourFee`/`succeedingHourFee`/`dailyOvernightFee` parameters
  (defaulting to the documented ₱100/₱50/₱850 constants) - the overnight
  fee is now a plain parameter, not fetched via `resolveEffectivePolicy`
  (that call was removed entirely). `resolveDaycareFeeSchedule(serviceId)`
  resolves all three from the session's own service (falling back to the
  documented defaults for nulls, or when there's no `service_id` at all -
  e.g. legacy Hotel stays). `checkOutDaycareSession` resolves the session's
  own fee schedule before computing the charge.

### Client

- `maintenance.types.ts` - `daycare_overnight_fee` added to `Service`,
  `CreateServicePayload`, `UpdateServicePayload`; `base_price` is now
  optional on `CreateServicePayload` (Daycare omits it).
- `AdminServicesPage.tsx` - **Base price (PHP) is hidden entirely for
  Daycare** (the server derives it from First hour fee). The Daycare form
  section gained a third field, "Overnight fee (PHP/night... optional,
  defaults to ₱850)", alongside First/Succeeding hour fee; a new
  service-row badge shows "₱{daycare_overnight_fee ?? 850}/night if not
  picked up", and the generic base-price badge is suppressed for Daycare
  rows (redundant with the first-hour-fee badge once they're synced).
- `booking.types.ts` / `PolicyConfigurationPage.tsx` - the intermediate
  Policies-page section (form field, `FormState` entry, documented default,
  submit payload, description copy) was fully reverted.
- `hotel.types.ts` - `service_id` added to `HotelStay` (shared by
  `DaycareSession`, unchanged from the first draft).
- `CustomerBookingFlowPage.tsx` - **"visible when booking"**: a Daycare
  service's option card now shows "₱{first_hour_fee} first hr,
  ₱{succeeding_hour_fee}/hr after" in place of the generic flat price, plus
  a second line "₱{daycare_overnight_fee ?? 850}/night if not picked up
  before closing" - both read directly off the service the customer/staff
  is about to select, before they commit to booking it.

## "Why are there so many prices to config?" (base_price vs. first_hour_fee)

Live follow-up question, on the Services page: what's the difference
between Base price and First hour fee for a Daycare service? Before this
revision there were three: `base_price` (admin-entered, used only as the
_booking-creation-time_ price snapshot - the estimate a customer sees before
the actual stay happens), `first_hour_fee` (used only at _checkout_ to
compute the real charge), and `succeeding_hour_fee`. Since a Daycare pet's
actual duration is never known at booking time, `base_price` was really
just "whatever the admin thinks a typical first hour costs" - i.e.
`first_hour_fee` under a different name, configured separately and prone to
drifting out of sync. Resolved by dropping the _admin-facing_ field, not
the underlying column: `base_price` still exists (services.base_price stays
`NOT NULL`, and booking.service.ts's price snapshot still reads it - no
booking-flow code changed), but for Daycare it's now always mirrored from
`first_hour_fee` automatically, server-side, on every create/update. An
admin now configures exactly two numbers for a plain Daycare service (First
hour fee, Succeeding hour fee), plus the optional Overnight fee.

## Known limitations

- Hotel stays (`stay_type = 'Hotel'`) get a `service_id` recorded the same
  way (via `resolveDaycareServiceId`... in practice unused there - Hotel's
  own checkout path doesn't call `resolveDaycareFeeSchedule`), so the
  first/succeeding/overnight-fee columns and their fallback logic only ever
  affect Daycare billing today, matching the request's explicit "for
  daycare booking" / "daycare service" scope.
- If a Daycare service is later deactivated or unassigned from a branch
  after a stay checked in against it, `resolveDaycareFeeSchedule` still
  resolves its stored fee columns by id (not by active/availability
  status) - checkout billing reflects whatever that service's fees were
  configured as, regardless of its current availability.

## Verification

### 1. Migration

- **With Supabase CLI access**: `supabase db reset` (fresh local db) or
  `supabase db push` (linked remote project).
- **Without CLI/push access**: Supabase Dashboard → **SQL Editor** → paste
  `daycare-fee-configuration.sql` in this folder → **Run**. Confirm with:

  ```sql
  select column_name from information_schema.columns
  where table_name = 'policy_configurations' and column_name = 'daycare_overnight_fee';
  select name, first_hour_fee, succeeding_hour_fee, daycare_overnight_fee
  from public.services where id = 'a1300000-0000-4000-a000-000000000011';
  select column_name from information_schema.columns
  where table_name = 'stays' and column_name = 'service_id';
  ```

  Expect: the `policy_configurations` column query returns no rows (never
  landed there); the seeded Daycare service shows `first_hour_fee = 100.00,
succeeding_hour_fee = 50.00, daycare_overnight_fee = 850.00`;
  `stays.service_id` exists.

### 2. Per-service fee configuration on the Services page

1. As Admin/Superadmin, open `/staff/admin/maintenance/services`, create or
   edit a Daycare service. Confirm **no "Base price" field appears** for
   this category - only "First hour fee", "Succeeding hour fee", and
   "Overnight fee (PHP/night... optional, defaults to ₱850)".
2. Set First hour fee = 200, Succeeding hour fee = 75, Overnight fee = 900,
   save. Confirm the service row shows "₱200.00 first hr, ₱75.00/hr after"
   and "₱900.00/night if not picked up" badges (no separate base-price
   badge).
3. Leave Overnight fee blank on a different Daycare service - confirm its
   badge falls back to "₱850.00/night if not picked up".

### 3. The overnight/hourly fee is visible at booking time

1. Start a Daycare booking (`/staff/bookings/new` or `/portal/book`),
   reach the Services step.
2. The service option card for the ₱200/₱75/₱900 service from step 2 above
   should show "PHP 200.00 first hr, PHP 75.00/hr after" and a second line
   "PHP 900.00/night if not picked up before closing" - not a flat
   `base_price` figure.

### 4. Checkout bills using the session's own service fees, not the hardcoded defaults

1. Check in a Daycare walk-in explicitly naming the ₱200/₱75/₱900 service
   from step 2 (or a booking whose `booking_items` links that service).
2. Check out within the first hour. Confirm `computed_charge` is `200`,
   not the documented ₱100 default.
3. Repeat with a Daycare service that has no custom fees set (nulls) -
   confirm checkout still charges the ₱100/₱50/₱850 defaults, matching
   prior behavior exactly.

### 5. Overnight fee still compounds correctly, using the session's own service

1. Check in a Daycare session against the ₱900-overnight service, hold it
   past the branch's closing time across N nights.
2. Check out. Confirm `computed_charge` equals
   `900 * N + hourly charge` - not `850 * N`.

### 6. API-level checks (Postman)

See `daycare-fee-configuration.postman_collection.json` in this folder.

1. Import the collection, fill in `admin_identifier`/`admin_password`,
   `branch_id`, `pet_id` (owned by any customer, staff-assessed).
2. Run requests in order. All Test Results should be green - covers
   `POST /maintenance/services` with `first_hour_fee`/`succeeding_hour_fee`/
   `daycare_overnight_fee` for a Daycare service (and confirms no
   `base_price` is required), and a full Daycare check-in/checkout
   exercising per-service fee resolution.

## Test suites

- `server`: `npm run test` (from `server/`) - 751/751 passing. Key specs:
  `daycareBilling.service.spec.ts` (custom first/succeeding-hour and
  overnight-fee overrides, `checkOutDaycareSession` resolving the full fee
  schedule from the session's own `service_id`), `services.service.spec.ts`
  (`createService`/`updateService` mirroring `first_hour_fee` into
  `base_price` for Daycare), `maintenance.validator.spec.ts`
  (`createServiceValidator`'s Daycare-vs-base_price trade-off).
  `npx tsc -b` clean.
- `client`: `npm run test` - 540/540 passing (`AdminServicesPage.spec.ts`
  covers the hidden base-price field and Daycare-only creation payload).
  `npx tsc -b` clean.
