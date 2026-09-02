# Daycare/Hotel parity + Hotel fixed pricing + free-package trigger

Branch: `27-daycare-hotel-parity-and-fixed-pricing`

## Why

Two requests from `temp/context/Architectural-Change-Suggestions.docx` (P-1):

1. **Make Daycare the same as Hotel.** Daycare had no cage assignment and no
   structured feeding/walking/playing/medication instructions - it was just
   `check_in_at`/`check_out_at`/`computed_charge`. Hotel had all of that via
   `hotel_stays` + four `care_*_instructions` tables + a Care Log. "The only
   difference will be their services."
2. **Remove the cage-size services from Hotel booking.** Hotel was four
   separate services, one per cage size (₱500-₱1000). The request: Hotel and
   Daycare each get exactly one service at a fixed price; cage size becomes
   a pure capacity/assignment concern, never a price input. Plus: when a
   Hotel stay reaches a configurable night threshold, auto-award a free
   package, notify the customer + receptionist, and reflect it on the
   receipt (the pricing board shows "5+ nights with free Golden Package").

## What changed

### 1. DB: `hotel_stays` generalized into a shared `stays` table

`supabase/migrations/20260807104_m05_m06_unify_stays.sql` - rather than
duplicating `hotel_stays` and its four `care_*_instructions` child tables for
Daycare, `hotel_stays` is renamed to `stays` and gains `stay_type` ('Hotel' |
'Daycare'), a direct `branch_id`, a reintroduced `status` column (needed
because Daycare walk-ins have no booking to derive status from), and
`computed_charge` (Daycare's per-hour billing figure). Every
`care_*_instructions` table's `hotel_stay_id` FK is renamed to `stay_id`,
still pointing at the same table. `daycare_sessions` is dropped outright - no
production data to preserve, matching this repo's existing from-scratch
migration posture (`20260803077`, `20260728058`). RLS is rewritten to the
same role shape it already had, now scoped directly by `stays.branch_id`
instead of joining through `cages`.

### 2. DB: Hotel collapses to one fixed-price service + free-package fields

`supabase/migrations/20260807105_m13_hotel_fixed_price_service.sql` - the
four seeded `Hotel Stay - Small/Medium/Large/XL Cage` services are
soft-disabled (`is_active = false`, not deleted - `booking_items.service_id`
is `ON DELETE RESTRICT`), replaced by one active `Overnight Stay (Aircon
Room)` service at ₱850/night. `services` gains two nullable columns,
meaningful only for Hotel: `min_nights_for_free_package` (int) and
`free_package_name` (text, matched against a `packages.name` **at the
booking's own branch** at award time - not a direct FK, since `packages` are
seeded one row per branch while `services` are branch-independent, so one
FK column couldn't correctly point at both branches' own "Golden Package"
row at once). Seeded: 5 nights, `'Golden Package'`.

### 3. Server: Daycare check-in/checkout now share Hotel's cage + care-instruction codepath

- `server/src/features/hotel/services/careInstructions.service.ts` - the
  cage-resolution logic is extracted into an exported `resolveAndClaimCage()`
  (auto-suggest + claim, same as Hotel's original inline logic), and
  `insertFeedingInstructions`/`insertWalkingInstructions`/
  `insertPlayingInstructions`/`insertMedicationInstructions`/
  `generateCareLogEntries` are all exported (previously module-private).
  `checkInHotelStay` itself is otherwise unchanged in behavior - just writes
  `stay_type: 'Hotel'` + `branch_id` and targets `stays` instead of
  `hotel_stays`.
- `server/src/features/daycare/services/daycareCheckIn.service.ts` -
  `checkInDaycareSession` now calls the same exported helpers: claims a cage
  via `resolveAndClaimCage`, inserts into `stays` with `stay_type: 'Daycare'`,
  writes feeding/walking/playing/medication rows, and generates Care Log
  entries for today (Daycare has no scheduled multi-night length the way
  Hotel does, so the log is generated for the check-in date only, not a
  date range). A failed check-in after the cage claim releases it, mirroring
  Hotel's own compensating-action pattern.
- `server/src/features/daycare/services/daycareBilling.service.ts` -
  `checkOutDaycareSession` now also releases the claimed cage back to
  `Available` (new - Daycare never held a cage before this change). Billing
  math (`computeDaycareCharge`, the ₱100 first-hour + ₱50/succeeding-hour +
  overnight-fee formula) is untouched.
- `server/src/features/hotel/services/careLogCompletion.service.ts` /
  `careLogFlagging.service.ts` - simplified to filter on `stays.status`/
  `stays.branch_id` directly instead of joining through `bookings`/`cages`;
  this also makes them work correctly for Daycare walk-ins, which have no
  booking row.
- `server/src/features/daycare/modules/validators/daycare.validator.ts` -
  `checkInValidator` now accepts `cage_id`/`feeding`/`walking`/`playing`/
  `medications`/`notify_opt_in`, built from the exact same Zod schemas
  `server/src/features/hotel/modules/validators/hotel.validator.ts` exports
  (no shape drift between the two).

### 4. Server: Hotel fixed pricing + free-package trigger

- `server/src/features/booking/services/booking.service.ts` -
  `resolveFreePackageAward()` runs for every Hotel booking: reads the
  selected Hotel service's `min_nights_for_free_package`/
  `free_package_name`, computes nights the same way `resolveQuantity()`
  already does (scheduled window ÷ item duration), and - if the threshold is
  met and a matching active package exists at the booking's branch - adds it
  to `booking_items` as a ₱0 line. If awarded, a `booking_confirmed`
  notification fires to both the customer and every Receptionist at that
  branch (a new `notifyStaffRoleAtBranch()` helper in
  `notifications/services/notification.service.ts` - no existing helper
  could notify "the receptionist" as a role, only single known recipient
  ids). Reuses the existing `booking_confirmed` event type rather than
  adding a ninth (the enum is documented as "exact 8 values per
  Modules-Features").
- `server/src/features/billing/services/lineItemSources.service.ts` -
  `getHotelLineItems()` now also emits a `Free: <package name>` line (₱0)
  for any package-type `booking_items` row, so a free package shows on the
  receipt.

### 5. Client: Daycare check-in/checkout panel parity

- `client/src/features/daycare/pages/DaycareQueuePage/DaycareCheckInPanel.tsx`
  - once a pet is identified (existing booking or walk-in), the panel now
    suggests/assigns a cage (`CageStatusGrid`, same component Hotel uses) and
    captures feeding/walking/playing/medication instructions and a
    notify-opt-in checkbox, submitting the same shape Hotel's check-in does.
    Intentionally simpler UI than `HotelCheckInPanel.tsx`: plain text inputs
    instead of the catalog-autocomplete `CatalogComboBox`, no M07
    current-prescription pre-fill, and a part-of-day-select + minutes field
    for walk/play blocks instead of the time-range/duration toggle - the
    **stored data shape is identical either way**, so this is a UI
    simplification, not a functional gap (see Known limitations below).
- `client/src/features/daycare/pages/DaycareQueuePage/DaycareCheckoutPanel.tsx`
  - `check_out_at` → `actual_check_out_at` (renamed field, matches the
    shared `stays` shape).
- `client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`
  - a Hotel-only form section for `min_nights_for_free_package`/
    `free_package_name`, plus a badge on the service row showing the
    configured threshold.
- `client/src/features/hotel/hotel.types.ts` / `daycare.types.ts` - `HotelStay`
  gained `stay_type`/`branch_id`/`status`/`computed_charge` and several
  fields became nullable (`booking_id`, `scheduled_check_out_date`,
  `downpayment_amount` - null for Daycare rows); `DaycareSession` is now a
  type alias of `HotelStay`, not a separate shape. A few Hotel-only
  components (`HotelStayPicker`, `HotelCheckoutPanel`, `HotelBookingPicker`)
  needed a non-null assertion or guard at the few spots that read those
  fields, since those components only ever handle Hotel-type stays where the
  fields are always populated.

### 6. Customer booking flow: no changes needed

Checked `CustomerBookingFlowPage.tsx` carefully before touching it: Hotel's
service selection is already a category-filtered list of whatever `services`
rows exist (now one instead of four) with no hardcoded assumption about
count; the `deriveHotelCageSize()` "Recommended" badge helper just returns
`null` for the new service's name (no size keyword in it) instead of
crashing, so the badge silently stops appearing - correct, since there's
nothing to recommend among a single fixed-price service. No code change was
required for the pricing collapse to work end-to-end.

## Known limitations / deliberate scope cuts

Disclosed up front rather than silently dropped:

- **No customer-facing "cage config" step for Daycare at booking time.** The
  Hotel booking flow's `CagePicker` step is purely informational even for
  Hotel today (no schema field for "customer's chosen cage" - the real
  assignment happens at staff check-in). Daycare's booking-time capacity
  check is also still a flat stub number (`capacity.service.ts`'s
  `getDaycareSessionCapacity`), not per-cage-size like Hotel's, so a
  per-size `CagePicker` grid would show data that doesn't reflect the real
  availability check. The **substantive** "cage config" ask - a real cage
  getting assigned and tracked - is fully delivered via the staff check-in
  flow (section 5 above), which is exactly where Hotel's real cage
  assignment already lived too.
- **No pre-booking "Care Instructions" preview step for Daycare** (Hotel's
  `hotelDetails` wizard step / `bookings.hotel_preferences` jsonb). The
  authoritative feeding/walking/playing/medication record for Hotel is
  always the one captured at physical check-in, not the booking-time
  preview - Daycare now has that authoritative record too. Adding a
  matching preview step is a reasonable follow-up but wasn't required to
  meet the request as written.
- **DaycareCheckInPanel's care-instruction UI is simpler than Hotel's**, as
  described in section 5 - same captured data, less UI machinery (no
  catalog autocomplete, no M07 prescription pre-fill, no time-range
  toggle).
- Neither of the above touches the DB schema or the server API contract, so
  either can be added later purely as client work if wanted.

## Bug found and fixed (live follow-up feedback)

Reported as "the overnight stay hotel service is not showing?" on the staff
booking flow (Services step showed "No Hotel services available at this
branch."). Root cause: `20260807105_m13_hotel_fixed_price_service.sql`'s
`insert into public.services (...) values ('a1300000-0000-4000-a000-000000000022', 'Hotel', 'Overnight Stay (Aircon Room)', ...) on conflict (id) do nothing`
reused id `...-022`, which an earlier migration
(`20260802074_m13_services_requires_assessed_pet.sql`) had already assigned
to the unrelated "Initial Assessment" Misc service. The `on conflict (id) do
nothing` silently no-op'd the entire insert - the Hotel service never
actually existed, even though its own `service_branch_availability` rows
happened to get seeded anyway (they matched module-3-maintenance's blanket
`'a1300000-%'` wildcard, which doesn't check the service's category). Fixed
by changing the new service's id to the next free slot, `...-024` (`...-023`
is "Reassessment") - both in the migration itself and in this folder's
bundled `.sql` copy. Verified live against this session's linked Supabase
project by querying `services` for `category = 'Hotel'` before and after the
fix.

## Verification

### 1. Migrations

If your local/remote Supabase project doesn't already have these applied:

- **With Supabase CLI access**: `supabase db reset` (fresh local db) or
  `supabase db push` (linked remote project) from the repo root.
- **Without CLI/push access**: Supabase Dashboard → **SQL Editor** → **New
  query** → paste the contents of
  `daycare-hotel-parity-and-fixed-pricing.sql` in this folder → **Run**.
  Afterwards, confirm with:
  ```sql
  select stay_type, count(*) from public.stays group by stay_type;
  select name, is_active, min_nights_for_free_package, free_package_name
  from public.services where category = 'Hotel';
  ```
  The second query should show four inactive `Hotel Stay - *` rows and one
  active `Overnight Stay (Aircon Room)` row with `min_nights_for_free_package
= 5` and `free_package_name = 'Golden Package'`.

### 2. Daycare check-in now assigns a cage and captures care instructions

1. As a receptionist/admin, open `/staff/daycare` (Daycare Queue), Check In
   tab.
2. Pick "Walk-in", search a customer by email, select a pet.
3. Once a pet is selected, a **Cage assignment** section should appear below
   showing a suggested size and the cage grid (same component Hotel's
   check-in uses) - one cage should already be pre-selected.
4. Add a feeding time, a walk time, and a playtime; check "Owner opted in to
   pet status notifications".
5. Click **Check in** - should succeed and offer "Go to checkout".
6. In Supabase, confirm a `stays` row exists with `stay_type = 'Daycare'`,
   a non-null `cage_id`, and that `care_feeding_instructions`/
   `care_walking_instructions`/`care_playing_instructions` rows exist with
   `stay_id` pointing at it, plus `care_log_entries` rows for today.
7. On `/staff/hotel` (Hotel Queue's Care Log tab, or the Pet Assistant's
   "Care Log > Today" view) - the feeding/walk/play entries from this
   Daycare check-in should appear alongside any Hotel ones, since both now
   share the same Care Log.
8. The cage picked in step 3 should now show **Occupied** on the Hotel
   cage grid (`/staff/hotel`, Cages).

### 3. Daycare checkout releases the cage

1. From the Daycare Queue's Check Out tab, select the session checked in
   above and confirm checkout.
2. The charge breakdown should show as before (unchanged billing math).
3. Back on the Hotel cage grid, that same cage should now show
   **Available** again.

### 4. Hotel booking is a single fixed-price service

1. Start a new booking (`/staff/bookings/new` or `/portal/book`), pick
   Hotel as the category.
2. The Services step should show exactly one option: **Overnight Stay
   (Aircon Room)**, ₱850.00/night - no more Small/Medium/Large/XL Cage
   cards.

### 5. Free package trigger at the night threshold

1. Continue (or start fresh) a Hotel booking for the same pet, choosing
   **5 nights** (the 3/5-night preset buttons, or type 5).
2. Complete the booking.
3. Open the booking's details page (or check the API response) - it should
   include a second `booking_items` row with a `package_id` (Golden
   Package) and `price_at_booking: 0`, alongside the paid Hotel service
   item.
4. As the customer, check notifications (bell icon / inbox) - a "Free
   package unlocked!" notification should appear.
5. As a Receptionist at that branch, check staff notifications - a "Free
   package unlocked for a Hotel booking" notification should appear too.
6. Repeat with **3 nights** (below the 5-night threshold) - no free package
   item should appear, no notification should fire.
7. Complete the 5-night booking's full lifecycle (check-in → checkout) and
   pull up its cashier checkout preview - the free package should appear as
   its own ₱0 line item on the reconciliation, not silently folded into the
   aggregate Hotel stay line.

### 6. API-level checks (Postman)

See `daycare-hotel-parity-and-fixed-pricing.postman_collection.json` in this
folder.

1. Open Postman (or the VS Code Postman/Thunder Client extension) and
   import the collection file.
2. Open the collection's **Variables** tab and fill in:
   `receptionist_identifier`/`receptionist_password` (a seeded
   Receptionist/Admin login), `branch_id` (that receptionist's own branch),
   `customer_id` (a seeded customer), `daycare_pet_id` and `hotel_pet_id`
   (two staff-assessed pets owned by that customer - use two different pets
   so the Hotel booking's capacity check doesn't collide with the Daycare
   walk-in). Leave the token/id variables blank.
3. Make sure the server is running locally (`npm run dev` in `server/`).
4. Run each request **in numeric order** - later requests depend on
   tokens/ids captured by earlier ones. Check the **Test Results** tab on
   each request - all should be green.

## Test suites

- `server`: `npm run test` (from `server/`) - 734/734 passing. Updated:
  `daycareCheckIn.service.spec.ts` (added cage-resolution mocks + explicit
  `feeding`/`walking`/`playing`/`medications`/`notify_opt_in` fields on the
  now-shared `CheckInInput` shape), `careLogCompletion.service.spec.ts`
  (renamed `hotel_stays`/`hotel_stay_id` fixture keys to `stays`/`stay_id`).
  No other spec needed changes - the existing mock harnesses are
  table-name-agnostic (they dequeue results per `.from()` call regardless of
  the table string), so most renamed-table/column references in specs were
  comment-only.
- `client`: `npm run test` (from `client/`) - 538/538 passing. Updated:
  `DaycareCheckInPanel.spec.ts` (mocks `getCageSuggestion` +
  `CageStatusGrid`, asserts the new `cage_id` in the check-in payload),
  `DaycareCheckoutPanel.spec.ts` (`check_out_at` → `actual_check_out_at`
  fixture field). `npx tsc -b` clean - a handful of Hotel-only components
  (`HotelStayPicker`, `HotelCheckoutPanel`, `HotelBookingPicker`) needed a
  non-null assertion/guard where they read fields that became nullable on
  the shared `HotelStay` type but are always populated in their own
  Hotel-only context.
