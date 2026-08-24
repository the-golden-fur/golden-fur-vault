# Hotel booking flow follow-up: capacity display, pricing, feeding overhaul, per-night care

Branch: `23-hotel-care-instructions-and-pricing`

## Why

Six follow-up requests came in against the Hotel booking flow shipped in
`22-booking-flow-and-pricing-revamp`:

1. The time-of-day dropdown in Cage & Date (`TimeSlotInput`) repeated
   "X of 2 available" on every single time block for Hotel bookings - cage
   capacity isn't time-of-day-specific, so this was the same number shown
   24+ times over, and it's already shown once above the dropdown
   (`SlotPicker`'s "Cage availability for this size" line) and again
   per-size in the `CagePicker` grid.
2. What do the 3/5-night preset buttons actually do, besides being a
   shortcut for typing that number? (Answered below - no code change.)
3. On the Services step, every Hotel cage-size card showed a redundant
   "PHP 1950.00 (PHP 650.00/night × 3)" even though the Running Total row
   directly below already sums the same thing.
4. Feeding instructions were three fixed Morning/Afternoon/Evening
   checkboxes, unlike Walking/Playing/Medications which were already free
   add/remove lists. Needed to become the same kind of list, gain a "Noon"
   time option, start empty, and stop pulling from the old staff-global
   food catalog - a customer's own catalog already existed
   (`/customers/me/food-medication-catalog`) but nothing in the booking
   wizard actually read from it.
5. Per-night care instructions: the schema/validator already fully
   supported a `stay_date` on every feeding/walking/playing/medication row
   (nullable = "every night"); only the UI to actually switch a booking
   into per-night mode was missing.

## What changed

### 1. Cage capacity text (item 1)

`client/src/features/booking/components/TimeSlotInput/TimeSlotInput.tsx` -
`availabilityText()` now returns `null` for the cage-capacity case instead
of a string, so the per-option text no longer renders for Hotel bookings.
The `eligible_staff_count` case (Grooming/Veterinary) is unchanged - that
count genuinely varies slot-to-slot. `SlotPicker`'s own summary line and
`CagePicker` are untouched; they're the surviving single source for this
number.

### 2. Nights preset buttons (item 2)

No code change. The 3/5-night buttons call `setHotelNights(nights)` -
literally identical to typing that number into the field next to them.
`hotelNights` itself is load-bearing: it multiplies `slotDurationMinutes`
into the real `scheduled_end` sent to the server (drives the actual
checkout date), and multiplies every Hotel service/package's per-night
rate into the price shown at Services and Payment.

### 3. Services step pricing (item 3)

`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` -
Hotel cage-size cards now show only the per-night rate (`PHP 650.00/night`),
not the computed total-with-formula. The Running Total row appends a
`× N nights` suffix (matching the Payment step's own existing convention)
so the "cage × nights" total lives in exactly one place.

### 4. Feeding overhaul (item 4)

- `supabase/migrations/20260804089_m05_add_noon_meal_time.sql`: widens
  `care_feeding_instructions.meal_time`'s check constraint to
  `('Morning', 'Noon', 'Afternoon', 'Evening')`. `care_walking_instructions`/
  `care_playing_instructions.time_block` are untouched - only asked for on
  feeding.
- `MealTime` (both `client/src/features/hotel/hotel.types.ts` and
  `server/src/features/hotel/hotel.types.ts`) widened to include `'Noon'`;
  `PartOfDay` (walking/playing) unchanged. Same split applied to the inline
  `meal_time` union in both `booking.types.ts` files, and to the Zod
  validators (`hotel.validator.ts`'s new `mealTime` enum,
  `booking.validator.ts`'s new `hotelMealTime` enum) - `partOfDay`/
  `hotelPartOfDay` keep walking/playing at three values.
  `client/src/features/hotel/utils/careScheduleBounds.ts`'s
  `MEAL_TIME_WINDOWS` gained a `Noon: { start: '10:00', end: '13:00' }`
  entry so the wizard's day-one/last-day applicability check doesn't crash
  on the new value.
- New staff-facing endpoint `GET /customers/:customerId/food-medication-catalog`
  (`server/src/features/catalog/catalog.routes.ts` +
  `listCustomerCatalogForStaffController` in `catalog.controller.ts`,
  gated the same as `/catalog/products` - `CATALOG_READ_ROLES`). Reuses the
  existing `listCustomerCatalog()` service function unchanged - it already
  took an explicit `customerId` param. Client counterpart
  `listCustomerCatalogForStaff()` added to
  `client/src/features/catalog/api/catalog.api.ts`.
- `CatalogComboBox` (`client/src/features/catalog/components/CatalogComboBox/CatalogComboBox.tsx`)
  gained an optional `hidePrice` prop - every catalog item reachable from
  hotel Care Instructions is now customer-owned or global hotel-scope with
  a forced `price: 0`, so showing "PHP 0.00" was meaningless noise.
- `CustomerBookingFlowPage.tsx`: `hotelFeeding` changed from a
  `Record<MealTime, row|null>` (fixed 3 checkboxes) to a free array, same
  shape as Walking/Playing/Medications (`addHotelFeeding`/
  `updateHotelFeeding`/`removeHotelFeeding`), starting empty. The catalog
  fetch now follows `effectiveCustomerId`: receptionist mode calls the new
  staff endpoint for the walk-in customer, self-service customer mode calls
  the existing `/customers/me/...` endpoint (previously self-service
  customers got no catalog at all, plain freetext only - this also wires
  up the standalone `CustomerFoodMedicationPage` catalog into the wizard
  for the first time). Both Feeding and Medication now always render
  `CatalogComboBox` with `hidePrice` (the old
  `isReceptionistMode ? CatalogComboBox : plain input` fork is gone).
- `HotelCheckInPanel.tsx` got the identical feeding-list conversion and
  catalog-source swap (`listCustomerCatalogForStaff(booking.customer_id, ...)`).
  This isn't optional scope creep - without it, a `'Noon'` preference
  captured in the wizard would have been silently dropped at check-in
  (its old prefill/render loop was hard-coded to exactly three slots).

### 5. Per-night care instructions (item 5)

- New shared `client/src/features/booking/components/NightTabs/NightTabs.tsx`
  (an "All nights" pill + one pill per calendar night) and
  `client/src/features/booking/utils/hotelNights.ts`'s
  `getHotelNightDates(checkInDateIso, nights)` helper, used by both call
  sites below so the date math isn't duplicated.
- **Wizard (creation time)**: `hotelUniformInstructions` is now a real
  checkbox ("Same instructions every night") instead of a hardcoded
  `true`. Unchecking it reveals `NightTabs`; every feeding/walking/playing/
  medication row gained a `stay_date`, filtered to the active tab when not
  in uniform mode, stamped onto newly-added rows from whichever tab is
  active. No server/validator change was needed here -
  `hotelPreferencesValidator` already accepted an optional `stay_date` on
  every row shape end-to-end (confirmed by the #22 doc's own "known scope
  reduction" note - the schema was always per-night-ready, only the UI
  wasn't built).
- **Booking details page (read-only)**: confirmed with the requester that
  this stays read-only (that page has no edit actions anywhere by design,
  and there is no backend path to edit `bookings.hotel_preferences` after
  creation - `hotel_stays`/`care_*_instructions` rows, which DO support
  editing, only exist once a stay is physically checked in). New "Care
  instructions" section on `BookingDetailsPage.tsx` shows the same
  `NightTabs`, resolving each night's rows with `rowsForNight()` - a dated
  row wins over the dateless fallback when both would otherwise apply,
  mirroring the server's own `rowsForDate()` in
  `hotel/services/careInstructions.service.ts` exactly.

## Verification

### 1. Cage capacity text

1. As a receptionist, start a new booking (`/staff/bookings/new` or via
   the queue's "New booking" action) and pick a pet, branch, and Hotel as
   the category.
2. On the Cage & Date step, open the time-of-day dropdown - each option
   should show only the time (e.g. "10:00 AM"), no "X of Y available"
   text. The "Cage availability for this size: X of Y free" line above the
   dropdown, and the S/M/L/XL grid below it, should still show the number.
3. Repeat for a Grooming or Veterinary booking - the time dropdown should
   still show "N slots available" per option (unchanged).

### 2. Services step pricing

1. Continue the Hotel booking from step 1 into the Services step with 3+
   nights selected.
2. Each cage-size card should show only `PHP <rate>/night`, no repeated
   total/formula.
3. The Running Total row at the bottom should show the actual total (rate
   × nights) with a `× N nights` label next to "Running total", matching
   how the Payment step later shows the same line items.

### 3. Feeding list + customer-scoped catalog

1. As a customer, go to `/portal/food-medication` and create a food type
   (e.g. "Chicken kibble"). Note there's no price field - customers were
   never meant to price these.
2. Start a Hotel booking as that same customer (self-service,
   `/portal/book`) and advance to the Care Instructions step. Feeding
   should start with zero rows; "Add feeding time" should reveal a
   Morning/Noon/Afternoon/Evening select plus a food-type field that is
   now a searchable dropdown (not plain freetext) - typing should surface
   "Chicken kibble" from step 1, with no price shown next to it.
3. As a receptionist creating a booking on behalf of that same customer
   (`/staff/bookings/new`, pick that customer at the Customer step), reach
   the same Care Instructions step - the food-type dropdown should again
   surface "Chicken kibble" (that customer's own catalog, not a mixed
   global list), still with no price. Pick a different customer and
   confirm the dropdown's options change to match.
4. Add a Noon feeding row, submit the booking. As a receptionist, open
   Hotel check-in (`/staff/hotel`, Check In tab) and select that booking -
   the Noon row should appear pre-filled in the (now also list-based)
   feeding section, not silently missing. Complete check-in successfully.

### 4. Per-night wizard editing

1. Start a new Hotel booking with 3 nights.
2. At Care Instructions, confirm "Same instructions every night" is
   checked by default and no night tabs are visible.
3. Uncheck it - a tab strip should appear ("All nights" + one tab per
   calendar date of the stay).
4. With a specific date tab selected, add a walk time - it should only be
   visible while that date's tab is active, not under "All nights" or the
   other date tabs.
5. Switch to "All nights" and add a different walk time there - it should
   be visible under "All nights" but not under any specific date tab.
6. Submit the booking.

### 5. Per-night read-only details view

1. As a receptionist, open `/staff/bookings/:id` for the booking from
   section 4 (via "View details" from the queue).
2. A new "Care instructions" section should appear with the same
   All-nights + per-date tabs.
3. Clicking the specific date tab used in step 4.4 should show that
   night's own walk time (not the "All nights" one); the other date tabs
   should fall back to showing the "All nights" walk time from step 4.5.
4. Confirm there is still no edit control anywhere on this page (read-only
   by design, unchanged).

### 6. API-level checks (Postman)

See `hotel-care-instructions-and-pricing.postman_collection.json` in this
folder.

1. Open Postman (or the VS Code Postman/Thunder Client extension if that's
   what's installed) and import the collection file: **File → Import →**
   select the `.json` file in this folder (or drag it into the Postman
   window).
2. Click the collection name in the sidebar, open its **Variables** tab,
   and fill in: `customer_identifier`/`customer_password` (a seeded
   customer login), `receptionist_identifier`/`receptionist_password` (a
   seeded Receptionist/Admin login), `branch_id` (any active branch id -
   grab one from Supabase or the app's branch list), and `pet_id` (a
   Dog/Cat pet owned by that customer that staff have already
   weight/coat-assessed). Leave `customer_access_token`,
   `receptionist_access_token`, `customer_id`, and `hotel_booking_id`
   blank - the collection fills those in automatically as you run
   requests.
3. Make sure the server is running locally (`npm run dev` in `server/`,
   default `http://localhost:3000` - update the `base_url` variable if
   yours differs).
4. Run each request **in numeric order, one at a time** (or use the
   collection's "Run" button for a full automated pass) - later requests
   depend on tokens/ids captured by earlier ones. Check the **Test
   Results** tab on requests 4, 5, 6, and 7 for pass/fail - all should be
   green.

### 7. Migration

If your local/remote Supabase project doesn't already have
`20260804089_m05_add_noon_meal_time.sql` applied:

- **With Supabase CLI access**: `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access to the linked project** (same workaround used
  for a prior migration-blocked session): open the Supabase Dashboard for
  this project → left sidebar **SQL Editor** → **New query** → paste the
  contents of `hotel-care-instructions-and-pricing.sql` in this folder →
  **Run**. Afterwards, confirm it applied cleanly by running:
  ```sql
  select conname, pg_get_constraintdef(oid)
  from pg_constraint
  where conrelid = 'public.care_feeding_instructions'::regclass
    and conname = 'care_feeding_instructions_meal_time_check';
  ```
  The definition should read
  `CHECK (meal_time = ANY (ARRAY['Morning'::text, 'Noon'::text, 'Afternoon'::text, 'Evening'::text]))`.

## Test suites

- `server`: `npm run test` (from `server/`) - all 698 existing tests still
  pass; nothing needed updating (no server spec asserted on the exact
  `meal_time` enum values or the old catalog routes).
- `client`: `npm run test` (from `client/`) and `npx tsc -b` - both clean.
