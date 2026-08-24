# 35 - Service Types, Cage Picker, Promo Cap move & booking-flow autosave

Seven requested changes, bundled into one pass because they landed in the
same conversation. Two turned out to already be satisfied by the current
`dev` branch (documented below, no code changed for those).

1. **Promo Cap Configuration** moved into the Promos page - no more separate
   admin-settings tile/route.
2. **Product Catalog** (`/staff/admin/product-catalog`) - investigated,
   **left unchanged** per your explicit decision (Misc Sales still depends
   on it for `misc_retail` products, and it's the only way to create the
   "global" reference food/med entries shown read-only on customers' own
   catalogs).
3. **Cage Picker** config (Admin Settings) + a Hotel-only step in the
   booking flow, mirroring the existing Staff Picker.
4. **Credit expiry "Expires after" field** - already read-only when "Unused
   credit expires" is unchecked (`PolicyConfigurationPage.tsx`'s
   `disabled={!form.credit_expiry_enabled}` was already there). Nothing to
   change.
5. **Service Types admin CRUD** - rename/deactivate/add the four service
   lines (Grooming/Hotel/Daycare/Veterinary), and (per your follow-up) set
   each type's Staff Picker/Cage Picker toggle right on its own create/edit
   form.
6. **Booking-flow draft autosave** - the customer booking wizard (also used
   by receptionists for walk-ins, at `/staff/bookings/new`) now survives an
   accidental browser close and restores where you left off.
7. **Services, Service Types, and Packages merged into one page** -
   "Services and Packages" in Settings → Config, replacing the three
   separate tiles/routes with one tabbed page (per your follow-up).

---

## Important limitation to understand before testing #5

`ServiceCategory` (`'Grooming' | 'Hotel' | 'Daycare' | 'Veterinary' | 'Misc'`)
is a hardcoded TypeScript union baked into ~7 backend files (availability,
capacity, pricing, vet eligibility, line items, cage assignment, etc.) plus
separate feature folders per type with bespoke logic. The new **Service
Types** page does **not** turn that into a fully dynamic system - it
controls:

- the customer-facing **display name** used at the booking flow's Service
  Type step (renaming "Hotel" to something else, for example),
- whether a type is **Active** (shown at all in that step),
- each type's **Staff Picker** / **Cage Picker** toggle.

Adding a brand-new row (e.g. "Boarding") makes it _selectable_ if you flip
it Active, but it has **no real booking behavior** - no availability
checking, no pricing, no capacity, nothing - until that's separately built
in code. The admin page's own copy says this explicitly so it doesn't look
like a bug later.

---

## 1. Promo Cap Configuration → merged into Promos

**What changed:**

- `PromoCapConfigurationPage` (its own page/route) was deleted. Its content
  (the per-branch + system-wide cap cards) now renders as a "Promo Cap
  Configuration" section at the bottom of `AdminPromoConfigPage`
  (`/staff/admin/maintenance/promos`).
- The "Promo Cap Configuration" tile was removed from Settings → Config.
- Route `/staff/admin/maintenance/promo-cap-configuration` no longer exists.

**Files:** `client/src/features/maintenance/pages/AdminPromoConfigPage/*`,
`client/src/pages/SettingsPage/tabs/ConfigTab.tsx`,
`client/src/features/maintenance/maintenance.routes.tsx` (deleted
`PromoCapConfigurationPage/` folder entirely).

**Verify manually:**

1. Log in as Admin or Superadmin, go to **Settings → Config**. Confirm
   there's only one "Promos" tile now (no separate "Promo Cap
   Configuration" tile).
2. Click **Promos**. Scroll to the bottom, below the promo cards - you
   should see a **Promo Cap Configuration** section with a card for "Both
   branches (system-wide default)" and one card per branch.
3. Change a branch's cap value and click **Save** - confirm "Promo cap
   updated." appears and the value persists on refresh.
4. Manually navigate to `/staff/admin/maintenance/promo-cap-configuration`
   in the URL bar - it should no longer resolve to anything (falls through
   to the app's normal not-found/redirect behavior).

---

## 2. Product Catalog - no change

Confirmed still needed as-is:

- `MiscellaneousSaleForm.tsx` (Billing) reads `listProducts` (the admin
  catalog) for `misc_retail` items when staff record a walk-in sale.
- The customer-facing food/medication catalog (`CustomerFoodMedicationPage`,
  used by Hotel/Daycare care instructions) is a **different** table scope
  (`owner_customer_id` set) on the same `product_catalog` table - it shows
  admin's **global** entries read-only for reference, but only Admin can
  create those global entries, via the page you asked about.

No verification needed - nothing was touched.

---

## 3. Cage Picker

**Concept:** mirrors the existing Staff Picker exactly. Admin controls
whether it's offered (now per Service Type, not a branch-override policy
row like Staff Picker - see below); when enabled, the customer/receptionist
sees a "Cage" step in the Hotel booking flow and can name a specific cage
preference, or "No preference". It's **advisory only** - the real cage
claim still happens at check-in (`suggestCage`/`assignCage`, unchanged);
this only lets the receptionist see what the customer already asked for.

**Where it lives:**

- Config: on the **Hotel** row of the new **Service Types** page (see
  section 5) - a "Cage picker enabled" toggle, not a separate Policies-page
  section (Staff Picker's existing per-branch override on the Policies page
  was left alone - Cage Picker is new, simpler, type-level-only config, not
  a migration of that existing feature).
- Booking flow: inside the existing "Cage & Date" step (`availability`),
  right after the existing cage-**size**-capacity display, once a slot/date
  is picked. It does **not** get its own top-level stepper tab - the
  existing merged-step design (documented in the code) exists specifically
  to show availability before the customer invests effort picking exact
  services, and giving Cage Picker a separate flashing-in-and-out tab would
  reintroduce the exact "shown then hidden" UX bug that design avoids. Functionally
  it's still "after service type selection", just grouped with the other
  Hotel-only availability content instead of a new tab.

**New DB:** `bookings.preferred_cage_id` (nullable, references `cages`).

**New API:** `GET /bookings/cage-picker?branch_id=...` (mirrors
`GET /bookings/staff-picker` but branch-only - cage availability is a live
status snapshot, not a time-window check). `POST /bookings` now accepts an
optional `cage_preference: { type: 'no_preference' | 'specific', cage_id? }`.

**Files:**
`supabase/migrations/20260809113_custom_create_service_types.sql`,
`supabase/migrations/20260809114_custom_bookings_preferred_cage_id.sql`,
`server/src/features/booking/services/cagePicker.service.ts` (+ spec),
`server/src/features/booking/{booking.controller,booking.routes,booking.types}.ts`,
`server/src/features/booking/modules/validators/booking.validator.ts`,
`client/src/features/booking/components/CagePickerList/*` (new, mirrors
`StaffPickerList`), `client/src/features/booking/{api/booking.api,booking.types}.ts`,
`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`.

**Verify manually:**

1. Apply the two new migrations first - see **Migrations** section below.
2. As Admin, go to **Settings → Config → Services and Packages → Service Types**. Confirm **Hotel**
   shows "Cage picker" toggled **on** (it's seeded that way) and Grooming/
   Daycare/Veterinary show it **off**.
3. Start a Hotel booking (as a customer, or as a receptionist via **Bookings
   queue → New booking**, category **Hotel**). On the "Cage & Date" step,
   after picking a date/slot, you should now see a **Cage** section below
   the existing size-availability cards, listing "No preference" plus any
   currently-Available cages at the branch (label + size). Pick one and
   continue the booking to completion.
4. In Supabase (Table Editor → `bookings`), find the booking you just
   created and confirm `preferred_cage_id` matches the cage you picked (or
   is `NULL` if you picked "No preference").
5. Go to **Settings → Config → Services and Packages → Service Types**, turn **Hotel's Cage picker**
   toggle **off**, save, and start a new Hotel booking - the Cage section
   should no longer appear on the "Cage & Date" step (falls back to
   exactly today's behavior). Turn it back on afterward.
6. Check in the pet at the front desk as normal (Hotel Queue) - confirm
   check-in still works exactly as before (suggest/assign cage flow is
   unchanged; this addendum doesn't yet pre-select the preferred cage there
   - see **Known follow-up** below).

**Known follow-up (not built in this pass):** check-in
(`HotelCheckInPanel`) doesn't yet pre-select `preferred_cage_id` when
suggesting a cage - it still uses the existing weight-based suggestion. The
preference is captured and visible in the database/booking record, but
wiring the check-in form to prefill it is a small follow-up if you want it.

---

## 4. Credit expiry "Expires after" field - already done

Checked `PolicyConfigurationPage.tsx` line 581 -
`disabled={!form.credit_expiry_enabled}` is already on the "Expires after
(days)" input. Nothing changed. To confirm: **Settings → Config →
Policies**, uncheck "Unused credit expires" - the "Expires after (days)"
field should immediately gray out and become unclickable.

---

## 5. Service Types admin CRUD

**New page:** originally its own tile/route, since merged (per your
follow-up) into **Settings → Config → Services and Packages →
Service Types** tab (`/staff/admin/maintenance/services-and-packages?section=service-types`)

- see section 7 below.

**Create/edit form fields:** Key (new rows only), Name, **Staff picker
enabled**, **Cage picker enabled** (per your follow-up request, these live
right on the type's own form, not only via a separate policy page). Each
existing row also gets an **Active** toggle, plus the same two picker
toggles, editable inline.

**Seeded rows** (via the new migration): Grooming (staff picker on), Hotel
(cage picker on), Daycare (both off), Veterinary (staff picker on) - these
match today's actual behavior exactly, so applying the migration changes
nothing customer-visible until you touch a toggle.

**Booking flow wiring:** the Service Type step
(`CustomerBookingFlowPage.tsx`, both the customer flow and the receptionist
walk-in flow at `/staff/bookings/new`) now reads this table - a type's
customer-facing **label** comes from `name`, and a type with **Active**
unchecked is no longer offered as a tab. The four service categories
themselves are unaffected if the table is empty/unreachable (falls back to
today's plain labels, nothing hidden).

**Files:**
`server/src/features/maintenance/services/serviceTypes.service.ts` (+
spec), `server/src/features/maintenance/{maintenance.controller,maintenance.routes,maintenance.types}.ts`,
`server/src/features/maintenance/modules/validators/maintenance.validator.ts`,
`client/src/features/maintenance/pages/AdminServiceTypesPage/*` (new;
now mounted as a tab inside `AdminServicesAndPackagesPage`, see section 7),
`client/src/features/booking/api/booking.api.ts` (public, direct-Supabase
read for the booking flow - same pattern as `listBranches`),
`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`.

**Verify manually:**

1. Apply the migrations (see below), then go to **Settings → Config →
   Services and Packages → Service Types** tab as Admin/Superadmin.
2. Confirm four rows: Grooming, Hotel, Daycare, Veterinary, all **Active**.
3. Rename "Hotel" to "Hotel & Boarding", save. Start a new booking (customer
   or receptionist) - the Service Type step's Hotel tab should now read
   "Hotel & Boarding". Rename it back to "Hotel" afterward.
4. Toggle **Daycare** to inactive, save. Start a new booking - the Daycare
   tab should no longer appear at the Service Type step. Toggle it back on.
5. Add a new type: Key `Boarding`, Name `Boarding`, leave both picker
   toggles off, save. Confirm it appears in the list with an **Active**
   toggle already on. (It will now show up as a bookable-looking tab in the
   flow, but selecting it won't lead anywhere useful yet - that's the
   documented limitation above, not a bug. Deactivate or leave it - your
   call - it doesn't affect anything else.)
6. As a non-Admin/Superadmin staff role (e.g. Receptionist), confirm you get
   redirected away from `/staff/admin/maintenance/services-and-packages`
   entirely (the gate lives on each of the three tab components
   individually, matching every other admin-config page's pattern).

---

## 6. Booking-flow draft autosave

**What changed:** the booking wizard (`CustomerBookingFlowPage.tsx`) now
saves its in-progress state to the browser's `localStorage` (survives an
actual browser/tab close, unlike `sessionStorage`) and restores it on
return.

- **Storage key:** `booking-draft:customer:{your user id}` for a customer
  booking themselves; `booking-draft:staff:{staff id}` for a receptionist
  mid walk-in booking (keyed to the staff terminal, not the walk-in
  customer - the customer isn't known yet at the very start of that flow,
  and receptionists book different walk-ins back-to-back on one terminal).
- **What's saved:** pet, branch, service type, selected services/packages,
  date/slot, nights, promo/discount, payment method/choice, special
  instructions, hotel/daycare care-instruction rows, current step, and (in
  receptionist mode) the picked walk-in customer.
- **Expiry:** a draft older than 24 hours is silently ignored (not
  restored, no banner).
- **Restore UX:** on return, a dismissible banner reads "We restored your
  in-progress booking." with a **Start over** button that clears the draft
  and resets the wizard to blank.
- **Cleared** automatically once the booking is actually submitted
  successfully.

**Verify manually:**

1. As a customer, start a booking - pick a pet, branch, and service
   category, get partway through (e.g. reach the Services step).
2. Close the browser tab entirely (not just navigate away - actually close
   it, or reopen the browser fresh) and go back to the booking page.
3. Confirm the "We restored your in-progress booking." banner appears and
   every field you'd already filled in is back exactly as you left it.
4. Click **Start over** - confirm the wizard resets to the very first step
   and the banner disappears.
5. Repeat steps 1-3, but this time finish and submit the booking instead of
   closing early. Reload the booking page fresh - confirm no restore banner
   appears (the draft was cleared on successful submission).
6. Repeat as a Receptionist via **Bookings queue → New booking**
   (`/staff/bookings/new`) - pick a walk-in customer and get partway
   through, close the tab, come back, confirm the walk-in customer and
   progress are both restored.
7. (Optional, to test the 24h expiry) In DevTools → Application →
   Local Storage, find the `booking-draft:...` key, edit its `savedAt`
   value to something more than 24 hours in the past, reload the booking
   page - confirm no restore banner appears and the wizard starts blank.

---

## 7. Services, Service Types, and Packages merged into one page

**What changed (follow-up to #5):** the three separate admin pages/tiles
(Services, Service Types, Packages) are now one page, **Services and
Packages**, with an in-page tab bar (Services / Service Types / Packages -
same tab-over-URL-query pattern the Settings page itself already uses,
`?section=service-types` etc.). Each tab renders the exact same page
component as before, unmodified internally - this is a navigation/entry-
point consolidation only, not a rewrite of any of the three pages'
behavior.

- New route: `/staff/admin/maintenance/services-and-packages`.
- Removed routes: `/staff/admin/maintenance/services`,
  `/staff/admin/maintenance/service-types`,
  `/staff/admin/maintenance/packages` no longer resolve.
- Settings → Config now shows one **"Services and Packages"** tile
  ("Manage services, service types, and packages.") instead of three.

**Files:**
`client/src/features/maintenance/pages/AdminServicesAndPackagesPage/*`
(new), `client/src/features/maintenance/maintenance.routes.tsx`,
`client/src/pages/SettingsPage/tabs/ConfigTab.{tsx,spec.ts}`.

**Verify manually:**

1. Settings → Config: confirm exactly one tile reading "Services and
   Packages" (no separate Services/Service Types/Packages tiles anymore).
2. Click it. Confirm three tabs - **Services**, **Service Types**,
   **Packages** - with **Services** selected by default and its existing
   content (service list, create form) showing.
3. Click **Service Types** - confirm the four seeded rows show, and
   Services' content is gone (not just hidden behind it). Click
   **Packages** - same check.
4. Confirm each tab's existing functionality still works exactly as before
   (e.g. create a service on the Services tab, add a package on the
   Packages tab) - nothing about the three pages' own behavior changed.
5. Manually navigate to `/staff/admin/maintenance/services` (the old URL)
   in the address bar - confirm it no longer resolves to the Services page
   (falls through to the app's normal not-found/redirect behavior).

---

## Migrations

Two new migrations, applied in order:
`supabase/migrations/20260809113_custom_create_service_types.sql` then
`supabase/migrations/20260809114_custom_bookings_preferred_cage_id.sql`.
Both are bundled for reference in
`service-types-cage-picker-autosave.sql` in this folder (source of truth is
still `supabase/migrations/`).

- **With Supabase CLI access:** `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access:** open the Supabase Dashboard for this project
  → **SQL Editor** → **New query** → paste the contents of
  `service-types-cage-picker-autosave.sql` from this folder → **Run**.
  Afterwards, confirm with:

  ```sql
  select key, name, is_active, staff_picker_enabled, cage_picker_enabled
  from public.service_types
  order by key;

  select column_name, data_type
  from information_schema.columns
  where table_name = 'bookings'
    and column_name = 'preferred_cage_id';
  ```

  The first query should return exactly 4 rows (Grooming, Hotel, Daycare,
  Veterinary) matching the seed values documented in section 5. The second
  should return one row (`uuid`).

## Postman

`service-types-cage-picker-autosave.postman_collection.json` in this folder
covers the new/changed API surface: Service Types list/create/update (plus
the two 403 checks and the duplicate-key 409 check) and the Cage Picker
GET endpoint, toggled on/off via the Service Types PATCH. Fill in
`admin_identifier`/`admin_password`, `receptionist_identifier`/
`receptionist_password`, and `branch_id` in the collection variables before
running requests 1 through 11 in order - each has a **Tests** tab that
should go green. (The Promo Cap move, Product Catalog no-op, and the
autosave feature are client-only / already-covered-elsewhere and don't need
their own Postman requests.)

## Test suites

- `server`: `npm test` (from `server/`) - **772 tests pass**. New:
  `serviceTypes.service.spec.ts`, `cagePicker.service.spec.ts`.
- `client`: `npm test` (from `client/`) - **557 tests pass** across 120
  files. New/updated: `AdminPromoConfigPage.spec.ts` (promo cap cards moved
  in, mock list extended), `CustomerBookingFlowPage.spec.ts` (+4 autosave
  tests, cage picker mocked the same way `StaffPickerList` already was,
  `listServiceTypes` mocked to an empty list by default so every existing
  test keeps seeing plain category labels), `AdminServicesAndPackagesPage.spec.ts`
  (new - tab switching), `ConfigTab.spec.ts` (updated href for the merged
  tile).
- `server`: `npx tsc --noEmit` clean. `client`: `npx tsc -b` clean.
- `eslint` clean on every touched file in both `server/` and `client/`.

## Suggested branch name

`35-service-types-cage-picker-autosave`
