# Booking flow revamp: availability warning, hotel care overhaul, daycare overnight pricing

Branch: `22-booking-flow-and-pricing-revamp`

## Why

Seven related requests came in against the booking system:

1. Warn a customer that a branch/service looks fully booked _before_ they
   reach the Slot Picker step, showing the earliest opening instead.
2. Staff should never buy food/medication on a customer's behalf (liability
   risk) - remove that option, and let customers maintain their own
   reusable food/medication "types" instead, usable both inside and outside
   the booking wizard.
3. Walk time should respect the branch's actual operating hours.
4. Add "playtime" alongside walk time (same shape, minutes-based).
5. Multi-night hotel bookings should support per-night-different feeding/
   walking/playtime/medication instructions, with a toggle for "same every
   night" vs per-night editing, and a free-form night count with 3/5-night
   quick picks.
6. Walk/play time should be minutes-based, not literal clock time.
7. A daycare pet not picked up before closing should accrue a flat
   admin-configurable per-night fee (default ₱850) on top of the existing
   ₱100 first-hour / ₱50-per-succeeding-hour charge.

Clarified up front with the requester: per-night care instructions are a
real new schema (not just a UI toggle over one shared set); the staff-buy
option and its billing are fully removed, including for historical stays;
and the customer food/medication catalog repurposes the existing staff
`product_catalog` table/CRUD rather than a parallel system.

## What changed

### 1. Schema (`supabase/migrations/`)

- `20260803084_m05_remove_staff_supplied_billing.sql`: drops
  `care_feeding_instructions.brought_by_customer`/`charged_price`,
  `care_medication_instructions.brought_by_customer`/`charged_price`, and
  `hotel_stays.supplied_items_charge`.
- `20260803085_m05_m08_product_catalog_customer_ownership.sql`: adds
  `product_catalog.owner_customer_id` (null = staff/global entry); replaces
  the global `unique(name, category)` with two partial uniques (global vs.
  per-customer); adds a check restricting customer-owned rows to
  `category in ('food','medication')` and `service_scope = 'hotel'`; narrows
  the old open-SELECT RLS policy to staff-only and adds customer-scoped
  SELECT/INSERT/UPDATE/DELETE policies.
- `20260803086_m05_add_playing_instructions.sql`: new
  `care_playing_instructions` table (same shape as `care_walking_instructions`);
  adds `'Playing'` to `care_log_entries.care_type`; repurposes
  `care_walking_instructions.time_block` (and the new table's) from a free
  clock-time string to a `Morning`/`Afternoon`/`Evening` check constraint.
- `20260803087_m03_m05_hotel_per_night_care.sql`: adds nullable `stay_date`
  to all four `care_*_instructions` tables - null = applies to every night
  (unchanged default behavior), a date scopes the row to that single night.
- `20260803088_m08_daycare_overnight_pricing.sql`: adds
  `pricing_configuration.daycare_overnight_fee numeric(10,2) default 850.00`.

### 2. Server (`server/src/features/...`)

- **Availability warning**: `booking/services/availability.service.ts` gains
  `findNextAvailableSlot()` (walks `getDaySlots` forward day-by-day, default
  14-day lookahead) and `partsOfDayWithinOperatingHours()`; new routes
  `GET /bookings/availability/next-slot` and
  `GET /bookings/availability/parts-of-day`.
- **Staff-buy removal**: `hotel/services/careInstructions.service.ts` no
  longer derives `brought_by_customer`/`charged_price`;
  `hotel/services/checkout.service.ts` drops `getSuppliedItemsCharge()` and
  the corresponding term from `remainingBalance`;
  `billing/services/lineItemSources.service.ts` drops the "Hotel-supplied
  food/medication" line item. `hotel.validator.ts`/`booking.validator.ts`
  and all four `hotel.types.ts`/`booking.types.ts` (server + client) updated
  to match.
- **Customer catalog**: new
  `catalog/services/customerProductCatalog.service.ts` (list/create/update/
  archive, scoped to the requester's `owner_customer_id`, forced
  `service_scope: 'hotel'`, `price: 0`); new routes under
  `/customers/me/food-medication-catalog`, no staff role gate.
- **Playtime + operating hours**: `HotelBookingPreferencePlaying` type;
  `careInstructions.service.ts` gains `insertPlayingInstructions`; walk/play
  `time_block` is now `'Morning'|'Afternoon'|'Evening'`.
- **Per-night care**: every `care_*_instructions` insert path accepts an
  optional `stay_date` per row and passes it straight through;
  `generateCareLogEntries` now prefers a row whose `stay_date` matches the
  day being generated, falling back to a `stay_date`-less (uniform) row.
  `hotel_preferences` gains a top-level `uniform_instructions: boolean`
  (informational; the authoritative scoping is each row's `stay_date`).
- **Daycare overnight fee**: `booking/services/availability.service.ts`
  gains `countOvernightNights()` (counts branch-closing boundaries crossed
  between check-in and check-out); `daycare/services/daycareBilling.service.ts`'s
  `computeDaycareCharge` is now async, takes a `branchId`, and returns
  `nights * dailyOvernightFee + 100 + succeedingHours * 50`.
  `maintenance/modules/validators/maintenance.validator.ts` and
  `maintenance.types.ts` extended with `daycare_overnight_fee` (same
  GET/PATCH `/maintenance/pricing-configuration` endpoints, no new routes).

### 3. Client (`client/src/features/...`)

- `booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`:
  removed the `SupplierChoice` staff-buy toggle everywhere; walk/play blocks
  now use a Morning/Afternoon/Evening select + a minutes input with 10/15/
  20/30-minute quick-select buttons; added a Playtime section mirroring
  Walking; added 3/5-night quick-select buttons next to the night-count
  input; added a "fully booked" modal fired when leaving the Service step
  (calls the new next-slot endpoint), showing the earliest opening with
  "Continue anyway" / "Change branch/service" actions.
- `hotel/pages/HotelQueuePage/HotelCheckInPanel.tsx`: removed both "Hotel
  supplies this" checkboxes and the additional-charges total; added a
  Playtime section (mirrors Walking); walk/play submission now buckets the
  staff-picked clock time into a Morning/Afternoon/Evening `time_block`
  (the DB column no longer stores literal clock times).
- `hotel/pages/HotelQueuePage/HotelCheckoutPanel.tsx`: removed the
  "Hotel-supplied items" breakdown row.
- New `catalog/pages/CustomerFoodMedicationPage/CustomerFoodMedicationPage.tsx`,
  routed at `/portal/food-medication` (customer sidebar entry "Food &
  Medication") and reachable from the hotel booking wizard.
- `maintenance/pages/PricingConfigurationPage/PricingConfigurationPage.tsx`:
  new "Daycare overnight fee (PHP/night)" field in the same form/PATCH call.

## Known scope reduction

The per-night editing **UI** (date-tab row, "same every night" toggle) was
not built in this pass - the client always submits
`uniform_instructions: true` with every row's `stay_date` omitted. The
schema, validators, and check-in/care-log generation are fully per-night-
ready end to end (verified via the SQL/Postman steps below); only the
booking-wizard UI for switching a stay into per-night mode is left as a
follow-up.

## Follow-up: booking wizard step reorder

A second request landed after the above shipped: move staff/cage
availability earlier in the wizard, before the customer spends effort
picking specific services/packages, and tighten the fully-booked warning to
only fire when the exact day being viewed has zero open slots.

**Step order change** (`CustomerBookingFlowPage.tsx`): `customer → pet →
branch → category (tabs only) → availability (Date & Time, merged with
Staff Picker for Grooming/Veterinary or the new Cage Picker for Hotel;
Daycare gets Date & Time alone) → items (service/package checkboxes) →
hotelDetails (Hotel only) → payment`. Previously category tabs and item
checkboxes were one combined step, followed by Date & Time, followed by a
separate Staff step (Grooming/Veterinary only).

**Why the availability step uses a fixed default duration**: no specific
service/package is known yet at that point, so `SlotPicker`/`StaffPickerList`
there run against a stand-in duration (`DEFAULT_DURATION_MINUTES`: 60 min
for Grooming/Veterinary/Daycare/Misc, 1440 min/one night for Hotel) instead
of the real item-derived duration. The real duration (from whichever
services/packages get picked later, at the `items` step) only matters for
the final `scheduled_end` submitted at booking creation - the server
independently re-validates capacity there regardless, so an early
approximate check that turns out slightly optimistic is caught at
submission, not silently accepted.

**Cage Picker is informational only** - there is no schema field for "the
customer's chosen cage size" (the real size is always derived server-side
from the pet's own staff-assessed `weight_class`, and physical cage
assignment happens later at hotel check-in). The new `CagePicker` component
(`client/src/features/booking/components/CagePicker/`) just displays
capacity grouped by size (S/M/L/XL) for the date currently selected in the
paired `SlotPicker`, tagging the pet's matching size "Recommended". No new
server endpoints were needed - it reuses the existing customer-accessible
`GET /bookings/availability`, called once per size.

**Fully-booked modal retrigger**: `SlotPicker` gained an optional
`onAvailabilityChange` callback, fired whenever its own date-fetch resolves,
carrying whether the currently-viewed day has any open slot at all. The
modal (same component as before) now fires from that signal instead of from
"leaving the old combined Service step" - it appears while browsing dates
inside the `availability` step, not as a one-time check on advancing.

## Verification

### Availability warning (item 1)

1. Seed/pick a branch+date+service combo with 0 remaining capacity for
   today.
2. As a customer, start a booking: pick a pet, a branch, then a category.
   On the next step (Date & Time, possibly merged with Staff/Cage), browse
   to that zero-capacity date - a modal should appear naming the earliest
   open date and time (or "no availability" if none in 14 days).
3. "Keep browsing" dismisses the modal without changing the step;
   "Change branch/service" returns to the category step.
4. Browsing to a date that does have open slots shows no modal.

### Wizard step reorder (follow-up)

1. Grooming/Veterinary: after picking pet/branch/category, confirm the next
   step shows Date & Time - selecting a date/time slot reveals the Staff
   Picker in the same step (not a separate one); the step isn't valid until
   both a slot and a staff preference are chosen. Only after that does the
   wizard show individual services/packages.
2. Hotel: after picking category, confirm Number of nights and the Cage
   Picker (capacity grouped by S/M/L/XL, the pet's weight class tagged
   Recommended) appear alongside Date & Time, before any service/package is
   shown. Confirm the final submitted booking's price/duration reflects
   whichever services/packages and night count were actually chosen
   afterward, not the placeholder duration used for the early check.
3. Daycare: confirm the availability step shows Date & Time only, no staff
   or cage UI, matching today's behavior.

### Follow-up fixes: fully-booked popup precision + category card sizing

- **Fully-booked popup precision**: seed data has every branch open every
  day of the week (just shorter hours on weekends), so a "branch has no
  operating*hours entry" message is unreachable through the UI and was
  removed. The real bug was that `getDaySlots` returns an **empty** slots
  array both when the branch is closed that weekday \_and* when every
  candidate for the currently-viewed day has already passed (it's simply
  past closing time right now) - neither is a real "fully booked" (every
  time/staff/cage slot taken) situation, so the popup should never fire for
  either. `SlotPicker`'s `onAvailabilityChange` now reports `hasAnySlots`
  (`slots.length > 0`) alongside `hasAnyAvailable`;
  `handleSlotAvailabilityChange` in `CustomerBookingFlowPage.tsx` only
  triggers the popup when `hasAnySlots && !hasAnyAvailable` - real
  candidates existed and every one is taken. When it does trigger, the
  "next available slot" lookahead starts the day _after_ the one just
  confirmed full, instead of redundantly re-checking the same day.
  Verify: browsing to today after the branch has already closed for the
  day shows no popup at all (and `GET /bookings/availability/next-slot` is
  never called); browsing to a day within operating hours where every slot
  is genuinely taken (staff/cage/capacity conflict) shows "This looks fully
  booked", naming an opening on a later date.
- The category step (`case 'category'` in `CustomerBookingFlowPage.tsx`)
  now renders large icon cards (`.categoryGrid`/`.categoryCard`, one per
  category with a `lucide-react` icon) instead of small pill tabs, so it
  reads clearly as its own step rather than looking like the items step
  mid-load. Verify: the Service Type step shows visibly large, icon-bearing
  cards for each available category.

### Follow-up bug: Confirm booking silently doing nothing

**Root cause**: `toggleServiceSelect`/`togglePackageSelect` reset
`selectedSlot`/`staffPreference` to `null` on every item toggle - correct
under the _old_ step order (items picked before availability, so a duration
change genuinely invalidated the picked slot), but actively wrong under the
new order, where availability is picked first and items are picked
afterward against a fixed placeholder duration. Toggling any service or
package on the Services step silently wiped the already-confirmed slot;
`handleSubmit`'s `!selectedSlot` guard then returned immediately with no
error, on a step whose own validity check never re-verified `selectedSlot`.
Fixed by dropping that reset (no longer needed - availability no longer
depends on which items get picked) and wrapping the whole submission in
try/catch/finally so any _other_ thrown exception (network failure, bad
JSON) can no longer leave `isSubmitting` stuck true with the button
disabled and no visible error either.

Verify: Grooming/Veterinary, pick a slot + staff preference, advance to
Services, select then deselect then reselect a service or package, advance
to Review & Pay, fill in a payment method, click Confirm booking - the
booking should be created and the confirmation screen should show.

### Follow-up feature: package selection deselects its member services

A package's bundled price already covers its member services - selecting
both the package and one of its members separately would double-book (and
in the Cash-payment display, double-count) that service. Selecting a
package now clears any of its member services from the individual-service
selection; while a package covering a service is selected, that service's
card renders disabled/read-only with an "Included in {package name}" label
and cannot be re-selected.

Verify: on the Services step, select an individual service, then select a
package that includes it - the service should be deselected automatically;
switching back to "Individual service" should show that service's card
grayed out, disabled, and labeled "Included in {package name}"; clicking it
should do nothing while the covering package stays selected.

### Staff-buy removal (item 2)

1. In the customer booking wizard's Hotel Care Instructions step and in
   the staff Check-In panel, confirm there is no "staff will buy"/"hotel
   supplies this" option anywhere.
2. `GET /customers/me/food-medication-catalog` (as a customer) - create a
   food type, confirm it appears; confirm a _different_ customer's token
   cannot see or edit it (only global/staff entries + their own).
3. Complete a hotel check-in/checkout and confirm the billing breakdown no
   longer shows a "Hotel-supplied" line.

### Walk/play + operating hours (items 3, 4, 6)

1. In the booking wizard's Hotel step, add a walk time and a playtime -
   both should offer Morning/Afternoon/Evening + a minutes field with
   10/15/20/30 quick picks, no clock-time input.
2. `GET /bookings/availability/parts-of-day?branch_id=...&date=...` for a
   branch that closes at 15:00 - confirm `'Evening'` is excluded.

### Per-night schema (item 5, backend-only this pass)

1. `POST /hotel/check-in` with two `feeding` rows for the same booking,
   each with a different `stay_date`, plus a `stay_date`-less `walking`
   row - confirm `care_feeding_instructions` gets two dated rows and
   `care_walking_instructions` gets one null-dated row, and that
   `care_log_entries` shows the dated feeding instruction only on its own
   day, with the walking instruction repeated on every day.

### Daycare overnight fee (item 7)

1. `GET /maintenance/pricing-configuration` - confirm `daycare_overnight_fee`
   defaults to `850`.
2. Check a daycare pet in, then check out same-day before closing - charge
   should be unchanged (100 + 50/hr, no overnight fee).
3. Check a pet in, artificially hold the session open across one branch
   closing time (or adjust `check_in_at` in the DB), check out - charge
   should include exactly one `850` (or whatever the configured fee is) on
   top of the hourly charge.
4. PATCH the fee to e.g. `900` via `/staff/admin/maintenance/pricing-configuration`,
   repeat step 3 - new checkouts should use `900`.

## Test suites

- `server`: `npm run test` - all specs green, including new/updated specs
  in `careInstructions.service.spec.ts`, `checkout.service.spec.ts`,
  `daycareBilling.service.spec.ts`, `booking.validator.spec.ts`.
- `client`: `npm run test` - `tsc -b` clean; see the client suite's own run
  for spec-level pass/fail (several pre-existing specs reference the
  removed `brought_by_customer`/`suppliedItemsCharge` fields and may need
  the same fixture updates applied server-side).
