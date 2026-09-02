# Multi-item bookings, Cashier queue restriction, booking-time discounts/promos

Branch: `20-multi-item-booking-and-cashier-queue`

## Why

Four related requests came in for the booking flow and staff queue:

1. Customers/receptionists could only book exactly one service **or** one
   package per booking, plus (Grooming-only) a separate "Add-ons" step.
   Ask: let a booking hold several services and/or packages, picked from one
   merged, checkbox-based step, open to every category (not just Grooming).
2. The "Special instructions" free-text field lived on the Payment step; ask
   was to move it earlier, into the (now-merged) service step.
3. Cashier staff could already Start/Complete bookings in the queue, when
   they should only ever be able to advance Completed → Paid (the other
   transitions - Pending → In Progress → Completed - already existed as
   separate buttons; that part of the original ask was already shipped).
4. Discounts/promos only ever applied automatically at cashier checkout,
   after the service was done. Ask: let staff apply a discount (Senior/PWD/
   custom - Cash-only, staff-verified ID) and let anyone apply a promo,
   right at booking creation, with a live running total shown before either
   is applied. Chose the "applies now, not just a preview" architecture
   (locked in at booking time) over a checkout-only preview, since it needed
   the least follow-up refactoring even though it touches more files.

## What changed

### 1. Schema (`supabase/migrations/`)

- `20260803077_m03_multi_item_bookings.sql`: new `booking_items` table (one
  row per selected service **or** package per booking, `price_at_booking` +
  `duration_minutes_at_booking` snapshots, `check (num_nonnulls(service_id,
package_id) = 1)`), replacing the old `bookings.service_id`/`package_id`
  columns (dropped) and the Grooming-only `booking_addons` table (dropped).
  Backfills existing rows into `booking_items` before dropping anything.
- `20260803078_m03_m08_booking_discount_promo.sql`: adds
  `bookings.selected_discount_id`, `selected_promo_id`, `discount_amount`,
  `promo_amount` (default 0). `total_price` keeps its existing meaning
  (pre-discount sum of items) - the two `_amount` columns are the new "how
  much was taken off" snapshots, so no existing consumer of `total_price`
  needed to change.

### 2. Server (`server/src/features/...`)

- `booking/booking.types.ts`: `Booking.service_id`/`package_id` replaced by
  `booking_items?: BookingItem[]`; new `selected_discount_id`/
  `selected_promo_id`/`discount_amount`/`promo_amount` fields.
  `BOOKING_STATUS_ADVANCE_ROLES` now excludes `Cashier` (was equal to
  `BOOKING_POLICY_READ_ROLES`, i.e. all staff).
- `booking/modules/validators/booking.validator.ts`: `service_id`/
  `package_id`/`addon_service_ids` replaced by `items: Array<{service_id} |
{package_id}>` (min 1, no duplicates); new optional `discount_id`/
  `promo_id`.
- `booking/services/booking.service.ts`: `resolveBookingItem(s)` replaces
  the old single-service/single-package branch + `resolveAddons` - prices
  and validates every selected item (category/branch/active/assessed-pet),
  including a package's member services (packages have no category column
  of their own, so every member service's category must match). New
  `resolveDiscountAndPromo()`: a discount requires the requester's role to
  be in `BOOKING_MARK_PAID_ROLES` and `payment_method === 'Cash'`; a promo
  has neither restriction. Both validate scope (service/package/category)
  against the selected items and, for promos, cap the amount via
  `promo_cap_configuration`.
- `billing/services/lineItemSources.service.ts`,
  `checkoutAggregation.service.ts`, `discountPromoEvaluation.service.ts`:
  `BookingForBilling` now carries `items`, `payment_method`, and the
  selected discount/promo + amounts. Checkout (`buildCheckoutPreview`) uses
  the stored discount/promo as-is when a booking already has one selected,
  instead of re-scanning `discounts`/`promos` for a scope match - avoids two
  independent evaluations of the same rules disagreeing. `evaluateDiscounts`
  (the checkout-time auto-apply fallback, used only when nothing was
  pre-selected) now also skips entirely for a non-Cash booking, so the
  Cash-only rule holds everywhere a discount can ever be produced.
- `grooming/services/grooming.service.ts`,
  `veterinary/services/followUp.service.ts`: updated to read/copy
  `booking_items` instead of `service_id`/`package_id`/`booking_addons`.

### 3. Client (`client/src/features/booking/...`)

- `pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`:
  - Service step: category tabs unchanged; the "Individual service"/
    "Package" sub-tabs now use **checkboxes**, and selections in both
    accumulate into one booking (switching tabs doesn't clear the other).
    The separate "Add-ons" step is gone. A running total ("before promos/
    discounts") is shown at the bottom of this step, live as items are
    checked. The "Special instructions" textarea moved here from the
    Payment step.
  - Payment step: pricing summary now itemizes every selected service/
    package. New Discount picker (radio list) - only rendered for a staff
    walk-in booking (`isReceptionistMode`) where the resolved viewer role is
    in `BOOKING_MARK_PAID_ROLES` **and** payment method is Cash; a mandated
    (Senior/PWD) pick additionally requires a "verified the ID" checkbox
    before Next enables. New Promo picker (radio list) - available to
    everyone, no gating. "Estimated total" now nets out the selected
    discount/promo.
  - `booking.types.ts`: `Booking`/`CreateBookingPayload` mirror the server
    changes (`booking_items`, `items`, `discount_id`/`promo_id`,
    `selected_discount_id`/`selected_promo_id`/`discount_amount`/
    `promo_amount`). New `BOOKING_MARK_PAID_ROLES` export (mirrors the
    server list) used to gate the discount picker.
- `pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`:
  Start/Complete buttons are now hidden (not just server-403'd) when the
  resolved viewer role is `Cashier`; Mark as Paid is untouched.
- `HotelBookingPicker.tsx`, `DaycareBookingPicker.tsx`,
  `GroomerDashboardPage.tsx`/`AppointmentCard.tsx`: updated to read
  `booking.booking_items` (a joined list of names) instead of a single
  `service_id`/`package_id` pointer.

## Follow-up round: booking-flow UX fixes, revert-capable status dropdown

After the first pass landed, live testing surfaced several follow-up
requests, all in the same booking flow / queue surfaces:

1. **Category-appropriate selection limits**: Hotel (one cage) and Daycare
   (one session) should only ever hold a single selected item, while
   Grooming/Veterinary stay multi-select. `CustomerBookingFlowPage.tsx`'s
   `toggleServiceSelect`/`togglePackageSelect` now check a new
   `singleSelectCategory` flag (`category === 'Hotel' || category ===
'Daycare'`) and replace rather than add to the selection when set.
2. **Checkbox removed**: the service/package option cards went back to
   plain clickable `<button>`s (matching the pre-multiselect visual design)
   instead of a `<label>` wrapping a visible `<input type="checkbox">` -
   selection state is shown via the existing `.selected` border/highlight
   style only, with `aria-pressed` for accessibility.
3. **Step-jump bug fixed**: picking a Date & Time slot could jump straight
   to Review & Pay instead of landing on the Staff step. Root cause: the
   wizard tracked its position as a raw numeric array index into the
   `steps` array, which shrinks reactively (removing 'Staff') once
   `StaffPickerList` mounts and discovers the branch+category's Staff
   Picker toggle is disabled. When that happened while the user was
   sitting on the Staff step, the same numeric index silently resolved to
   whatever step slid into that slot (Review & Pay), instead of advancing
   properly. Fixed by tracking the current step by a stable **key**
   (`currentStepKey`/`reachedStepKeys` state) instead of a raw index, with
   a repair effect that advances to the correct next surviving step if the
   current one ever disappears from `steps`.
4. **Queue row height**: `.bookingRow` in
   `ReceptionistBookingsQueuePage.module.css` no longer pins a fixed
   `min-height`, padding/gaps were tightened, and the controls wrapper
   `<div>` is no longer rendered at all when a row has zero actionable
   buttons (e.g. a Cashier viewing a Paid booking) - previously it always
   rendered even empty.
5. **Admin/Superadmin revert-capable status control**: their Start/
   Complete/Mark-as-Paid buttons are replaced by a single `<select>`
   showing all four overridable statuses (Pending/In Progress/Completed/
   Paid), so an accidental Mark as Paid can be undone. New server
   capability: `PATCH /bookings/:id/status`
   (`overrideBookingStatusController` → `overrideBookingStatus` in
   `booking.service.ts`), gated to `BOOKING_STATUS_OVERRIDE_ROLES`
   (Admin/Superadmin only) via a new `statusOverride` route-middleware
   chain. Unlike `startBooking`/`completeBooking`/`markBookingPaid`, this
   function never rejects based on the booking's current status - it can
   move to any of the four in either direction. Timestamps
   (`started_at`/`completed_at`/`paid_at`) are filled the first time a
   status is reached and preserved on a later revisit, but cleared once no
   longer applicable, so reverting Paid → Completed keeps the original
   `completed_at` rather than fabricating a new one, and reverting to
   Pending clears everything. Cancelled/No-show are deliberately excluded
   from the dropdown - they keep their own dedicated flows (a cancellation
   reason, the lazy no-show transition).
6. **Cashier "New booking" button removed**: Cashier should only be able to
   view the queue, not create new bookings from it - the button is now
   hidden (`viewerRole !== 'Cashier'`), on top of the existing Cashier
   Dashboard sidebar fix (added a "Bookings Queue" tile to
   `staffDashboard.config.ts`'s `cashier` section - it was missing
   entirely before, which is why Cashier couldn't reach the queue at all
   even though the route/API access already worked).

New/changed files this round: `client/src/features/booking/pages/
CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (+spec),
`client/src/features/booking/pages/ReceptionistBookingsQueuePage/
ReceptionistBookingsQueuePage.tsx` (+.module.css),
`client/src/features/staff/config/staffDashboard.config.ts`,
`client/src/features/booking/booking.types.ts`,
`client/src/features/booking/api/booking.api.ts`,
`server/src/features/booking/booking.types.ts`,
`server/src/features/booking/booking.routes.ts`,
`server/src/features/booking/booking.controller.ts`,
`server/src/features/booking/services/booking.service.ts` (+spec),
`server/src/features/booking/modules/validators/booking.validator.ts`
(+spec).

### Known unrelated pre-existing issue found while re-testing (fixed in Round 6)

`server/src/features/booking/services/availability.service.spec.ts` had 3
tests hardcoded against `date: '2026-08-03'` with no system-time mocking
(`vi.useFakeTimers()`/`vi.setSystemTime()`), so they compared a fixed
09:00-12:00 Asia/Manila window against the _real_ wall-clock time when the
suite ran. Once real time reached/passed that window on that exact
calendar date, slots inside it were (correctly) treated as already past and
filtered out, so the tests' hardcoded "expect 3 slots" assertion failed.
This was a pre-existing test-design gap, not originally caused by this
branch - initially flagged here rather than silently patched, but CI
actually failing on it in Round 6 made it in-scope; see that section for
the fix.

## Round 3: per-category selection memory, Hotel nights pricing, Misc category

A third round of feedback on the booking flow:

1. **Per-category selection memory**: switching category tabs to browse
   used to wipe out whatever you'd already selected in the tab you left.
   `CustomerBookingFlowPage.tsx` now keeps selections in a
   `selectionsByCategory` record (keyed by category) instead of one flat
   pair of arrays - `selectedServiceIds`/`selectedPackageIds` are now
   _derived_ from `selectionsByCategory[category]`. Only a branch or pet
   change clears everything (the catalog itself changes then); switching
   category tabs does not. Date/time, staff, and Hotel nights still reset
   on category change, per explicit confirmation - those depend on which
   category you're actually committing to, unlike item picks.
2. **Number of nights moved**: from the Date & Time step to the Service
   step (right under the recommended-cage note), so nights are set
   _before_ picking a cage/date, and the running total reflects them
   immediately rather than only appearing on a later step.
3. **Hotel price = rate × nights**: previously Hotel items priced at a flat
   one-time `base_price`/`bundled_price` regardless of night count, both
   client-side (the running total) and server-side (`price_at_booking`).
   Server: `booking.service.ts`'s `resolveBookingItem` now derives a
   `quantity` per item via the new `resolveQuantity()` - how many of that
   item's own `duration_minutes` fit inside the actual scheduled window
   (Hotel only; every other category always prices at quantity 1) - and
   multiplies `price_at_booking` by it. Applies to both services and
   packages. Client: `itemsTotal` and every Hotel price display (option
   cards, payment-step line items) multiply by `hotelNights` the same way,
   so the two stay in agreement.
4. **New "Misc" category**: Initial Assessment and Reassessment moved out
   of Grooming into a new top-level `service_category` value, `'Misc'`.
   Schema: `20260803079_m13_add_misc_service_category.sql` (`ALTER TYPE
... ADD VALUE` - must be its own migration, Postgres won't let a new
   enum value be used in the same transaction that added it) and
   `20260803080_m13_move_assessment_services_to_misc.sql` (moves the two
   existing seeded rows). Misc bookings get no staff-assignment or
   capacity check - `resolveStaffAssignment`/`checkCapacity` are already
   keyed only to Grooming/Veterinary and Hotel/Daycare respectively, so
   Misc falls through both automatically, no new resource logic needed.
   Every `'Grooming' | 'Hotel' | 'Daycare' | 'Veterinary'` union in the
   codebase (client and server `ServiceCategory`, the booking/maintenance/
   discounts validators' `CATEGORIES` consts, `DiscountCategory`) gained
   `'Misc'`. Billing: `lineItemSources.service.ts`'s
   `getServiceLineItems` dispatch now routes `'Misc'` to the same
   item-based line-item builder Grooming uses (renamed
   `getItemBasedLineItems` since it's no longer Grooming-specific).
   Booking-wizard gating that used to say "an unassessed pet can only book
   Grooming's Initial Assessment" now says Misc instead
   (`availableCategories`, the auto-select effect).
5. **Initial Assessment hidden once already assessed**: the Service
   step's filter changed from `isSelectedPetAssessed || !requires_assessed_pet`
   (which showed both an assessed-pet's real services AND the exempt
   Initial Assessment at the same time) to
   `service.requires_assessed_pet === isSelectedPetAssessed` - a strict
   partition. An unassessed pet sees only Initial Assessment; an assessed
   pet sees only `requires_assessed_pet = true` services (Reassessment
   included), with Initial Assessment gone entirely.

New/changed files this round: `client/src/features/booking/pages/
CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (+spec),
`client/src/features/booking/booking.types.ts`, `client/src/features/
maintenance/maintenance.types.ts`, `client/src/features/discounts/
discounts.types.ts`, `server/src/features/booking/booking.types.ts`,
`server/src/features/booking/modules/validators/booking.validator.ts`,
`server/src/features/booking/services/booking.service.ts` (+spec),
`server/src/features/maintenance/maintenance.types.ts`,
`server/src/features/maintenance/modules/validators/
maintenance.validator.ts`, `server/src/features/discounts/
discounts.types.ts`, `server/src/features/discounts/modules/validators/
discounts.validator.ts`, `server/src/features/billing/services/
lineItemSources.service.ts`, plus the two new migrations above.

## Round 4: cross-category clarity, consultation queue fix, booking details page

Live testing after Round 3 raised a question and three "booking's missing
everywhere" reports that all traced back to one root cause, plus one
genuinely unrelated bug:

1. **Not a regression - the single-category-per-booking invariant never
   changed.** `bookings.service_category` has always been one scalar value;
   Round 3's per-category selection memory (`selectionsByCategory`) only
   changed what stays _visible_ while browsing between tabs - it never made
   more than one category submittable. Submitting a booking has only ever
   sent the currently-active tab's category + that tab's own items,
   regardless of what's sitting selected under other tabs. So "the booking
   didn't show up in Hotel Check-in even though Hotel was one of the
   services", "same for Daycare Check-in", "same for Grooming Queue", and
   "multi-service category doesn't apply to the final price" were all the
   same misunderstanding: whichever tab was active at submit time is the
   _only_ category that was ever created - the picks left behind on other
   tabs were never a pending cross-category cart, they just looked like one
   because Round 3 stopped clearing them on browse-away. No rollback was
   needed (multi-item-within-one-category was already the shipped
   architecture); what was missing was making that limit visible in the UI
   before submit, which is fix #2 below.
2. **Cross-tab selection warning**: `CustomerBookingFlowPage.tsx` gained a
   `categoriesWithOtherSelections` check - whenever `selectionsByCategory`
   has a non-empty entry for any category other than the one currently
   active, a `role="alert"` notice renders under the category tab row
   naming those other categories and stating that only the active category
   will be submitted. Disappears again once you're back on the tab that
   actually holds those picks (nothing "elsewhere" left to warn about) or
   once you clear them. New `.crossCategoryNotice` style in
   `CustomerBookingFlowPage.module.css`, reusing the existing
   `--color-warning-bg`/`--color-warning-text` token pair (same pattern as
   `PayMongoFeeNotice`) rather than a one-off color.
3. **Consultation Queue embedding error fixed** (separate, pre-existing
   bug, unrelated to any multi-item/category change): the queue showed
   "Could not embed because more than one relationship was found for
   'consultations' and 'bookings'". Root cause:
   `consultations` has _two_ foreign keys to `bookings`
   (`booking_id` and `follow_up_booking_id`, both added in
   `20260719040_m07_create_veterinary_schema.sql`), so an unqualified
   `booking:bookings(*)` embed is genuinely ambiguous to PostgREST - it
   likely only started 400ing now because this branch's own DDL migrations
   reloaded PostgREST's schema-relationship cache, re-triggering the
   ambiguity check. Fixed by disambiguating with the `!booking_id` hint in
   both places that embedded it:
   `veterinary/services/consultation.service.ts`'s `CONSULTATION_SELECT`
   and `veterinary/services/followUp.service.ts`'s ad-hoc `.select()` call.
4. **New booking details page**: the Bookings Queue's one-line-per-row
   summary couldn't show a multi-item booking's full breakdown, so each row
   now has a "View details" button navigating to
   `/staff/bookings/:bookingId` (new `BookingDetailsPage.tsx`, added to
   `booking.routes.tsx` under the existing `StaffAuthGuard` block). Read-
   only - no status/reschedule/cancel actions live here, those stay on the
   queue list. Shows: pet + owner, branch, scheduled window, every
   `booking_items` row with its own price, a pricing breakdown (subtotal →
   discount if any → promo if any → total → downpayment if set), payment
   method + confirmed flag, the full status timeline
   (started_at/completed_at/paid_at, plus cancellation reason if
   cancelled), and special instructions if any. Discount/promo names are
   resolved client-side (`listDiscounts`/`listPromos`, matched by the
   booking's `selected_discount_id`/`selected_promo_id`) since no
   id-to-name resolver existed anywhere in the codebase before this.

New/changed files this round: `client/src/features/booking/pages/
CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (+`.module.css`,
+spec), `client/src/features/booking/pages/BookingDetailsPage/
BookingDetailsPage.tsx` (new, +`.module.css`, +spec),
`client/src/features/booking/pages/ReceptionistBookingsQueuePage/
ReceptionistBookingsQueuePage.tsx` (+spec), `client/src/features/booking/
booking.routes.tsx`, `server/src/features/veterinary/services/
consultation.service.ts`, `server/src/features/veterinary/services/
followUp.service.ts`.

## Round 5: selecting elsewhere clears the other category's picks

Feedback on Round 4's warning: a warning alone still left stale picks sitting
under the tab you left, and the user wanted committing to a different
category to actually drop them, not just flag them. `updateCategorySelection`
in `CustomerBookingFlowPage.tsx` now replaces the _entire_
`selectionsByCategory` map with just the category being changed, instead of
merging into it - so every `toggleServiceSelect`/`togglePackageSelect` call
(add or remove) drops any other category's picks as a side effect. Browsing
to another tab without selecting anything still doesn't clear anything (only
an actual select/deselect does), so the Round 4 cross-category warning still
has a real job: it now only ever appears in that brief window after
switching tabs and before making a new pick, and its copy was reworded from
"only X will be submitted" to "selecting under X will clear that" to match.

Example: select 2 Grooming services, switch to the Hotel tab (Grooming's
picks are still there, warning shows), select a cage - Grooming's picks are
now gone, and switching back to Grooming shows nothing checked.

New/changed files this round: `client/src/features/booking/pages/
CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` (+spec).

## Round 6: CI fixes (flaky server test, client lint errors)

The CI run on this branch failed on two unrelated fronts:

1. **`availability.service.spec.ts`'s 3 wall-clock-dependent failures,
   previously only flagged in this doc, are now actually fixed.** They
   compared a fixed 09:00-12:00 Asia/Manila window against the real system
   clock with no time mocking, so they started failing for real once CI's
   wall-clock time caught up to that window on the hardcoded `2026-08-03`
   fixture date. All 3 now call `vi.useFakeTimers()` +
   `vi.setSystemTime(new Date('2026-08-03T00:00:00.000Z'))` (08:00 Asia/
   Manila, before the branch opens) before generating slots, matching the
   pattern the suite's other time-sensitive tests already used.
2. **Client ESLint errors from `eslint-plugin-react-hooks` v7** (the
   React Compiler rule set) in `CustomerBookingFlowPage.tsx`:
   - `react-hooks/set-state-in-effect` on the discounts-fetch effect's
     `setDiscounts([])` early-return reset - removed outright, since
     `applicableDiscounts` already returns `[]` whenever
     `canApplyDiscounts` is false, so the reset was dead code.
   - The same rule on the unassessed-pet auto-select effect's
     `handleCategorySelect`/`updateCategorySelection` calls - deferred
     into a `Promise.resolve().then(...)` microtask (mirroring
     `SlotPicker`/`GroomerDashboardPage`'s existing pattern for this exact
     rule), so no state setter runs synchronously inside the effect body.
   - `react-hooks/immutability` ("accessed before it is declared") on that
     same effect's reference to `handleCategorySelect`, and in turn
     `handleCategorySelect`'s own reference to `resetHotelPreferences` -
     both function declarations were moved earlier in the component (ahead
     of the effect that needs them), since this rule requires declaration
     order to match usage order even for hoisted `function` declarations.
   - The `react-hooks/exhaustive-deps` warnings on `selectedServiceIds`/
     `selectedPackageIds` (derived with an inline ternary, so downstream
     `useMemo`s calling them a dependency saw a new array reference every
     render) - both are now wrapped in their own `useMemo`, falling back to
     a shared module-level `EMPTY_ITEM_IDS` constant instead of a fresh
     `[]` literal so the reference stays stable when there's nothing
     selected.

New/changed files this round: `server/src/features/booking/services/
availability.service.spec.ts`, `client/src/features/booking/pages/
CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`.

## Known limitations / follow-ups

- Hotel/Daycare/Veterinary checkout still bills one aggregate line (a stay,
  a session, consultation line items) regardless of how many items a
  booking has - only Grooming's checkout itemizes per `booking_items` row.
  This was already true before this change and wasn't in scope to redesign.
- Downpayment (Hotel, 50%) is still computed off the pre-discount
  `total_price`, not the post-discount amount - not asked for, and changing
  it would need a separate product decision.
- No automated tests exist for the billing/checkout files touched here
  (`lineItemSources.service.ts`, `checkoutAggregation.service.ts`,
  `discountPromoEvaluation.service.ts`) - none existed before this change
  either. Manual checkout QA (step 6 below) is the only coverage.
- The Senior/PWD "verified the ID" checkbox at booking time is, like
  `CashierCheckoutPage`'s existing eligibility checkboxes, an ephemeral
  staff attestation - never sent to the server or persisted anywhere.

## Verification steps

### 1. Automated tests (already run and passing as of this change)

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 691
  tests passing.
- `cd client && npx tsc -b && npx vitest run` - 115 test files / 518 tests
  passing.

### 2. Apply the migrations

Apply `20260803077_m03_multi_item_bookings.sql` then
`20260803078_m03_m08_booking_discount_promo.sql` (in that order - the
second references `discounts`/`promos`, unaffected by the first, but keep
the numbering order regardless). Either run a full `supabase db reset` or
`supabase migration up`, however you normally apply migrations locally.

### 3. Confirm the schema (SQL Editor)

Open your project's Supabase dashboard → SQL Editor, paste in
`multi-item-booking-and-cashier-queue.sql` from this folder, and run each
numbered section. Expected results are noted inline as SQL comments.

### 4. Confirm the API surface (Postman)

Import `multi-item-booking-and-cashier-queue.postman_collection.json` from
this folder. Fill in `customer_identifier`/`customer_password` (an existing
customer login), `cashier_identifier`/`cashier_password` (a Cashier-role
staff login), and `receptionist_identifier`/`receptionist_password` (any
non-Cashier staff login, e.g. Receptionist/Admin). Fill `branch_id` with an
existing branch id and `pet_id` with a pet already assessed
(`weight_class`/`coat_type` both set) belonging to that customer. Run
requests in order, top to bottom.

Expected highlights:

- Request "Create multi-item booking" (2 Grooming services in one `items`
  array) → **201**, and the response's `booking.booking_items` array has 2
  rows.
- Request "Create booking with duplicate item" → **400** (Invalid payload).
- Request "Create booking with empty items" → **400**.
- Request "Cashier: Start a Pending booking" → **403**.
- Request "Cashier: Mark a Completed booking Paid" → **200** (use a
  booking you've manually walked to Completed first, e.g. via the
  Receptionist login's Start/Complete requests earlier in the collection).
- Request "Apply a Cash discount as Receptionist" (booking with
  `payment_method: "Cash"` + `discount_id`) → **201**, response's
  `booking.selected_discount_id`/`discount_amount` populated.
- Request "Apply a discount with GCash (rejected)" → **400**.
- Request "Apply a promo as customer" (no discount, just `promo_id`) →
  **201**, `booking.selected_promo_id`/`promo_amount` populated - confirms
  promos need no staff role.

### 5. Manual UI smoke test - booking flow

1. Log in to the customer portal (or staff `/staff/bookings/new`), start a
   booking for an already-assessed pet. On the Service step, pick a
   category (e.g. Grooming), check 2-3 individual services, switch to the
   Package tab (if any packages exist for that branch/category) and check a
   package too - confirm the running total at the bottom updates live as
   you check/uncheck items, and confirm your individual-service selections
   are still checked when you switch back to that tab. Enter something in
   "Special instructions" (now on this step). Confirm Next stays disabled
   with 0 items checked.
2. Continue to Date & Time - confirm the slot duration reflects the summed
   duration of everything you selected (compare against the seeded
   services' individual durations).
3. On Review & Pay, confirm every selected item is listed with its own
   price line, and the special instructions you typed do NOT reappear here
   (moved to the Service step).
4. Pick "Cash" as the payment method. If logged in as a qualifying staff
   role (Receptionist/Admin/Superadmin/Supervisor/Cashier) in the walk-in
   flow, a Discount section should appear - pick one, confirm the total
   updates; if it's a Senior/PWD discount, confirm Next is disabled until
   you check the ID-verification box. Switch payment method away from Cash
   - confirm the Discount section replaces itself with the "select Cash"
     note and the discount amount drops out of the total.
5. If any promo matches your branch/selected items, a Promo section should
   appear regardless of role or payment method - pick one, confirm the
   total updates independently of the discount.
6. Submit. In Supabase, confirm the new `bookings` row has no `service_id`/
   `package_id` columns, `booking_items` has one row per selection, and (if
   you picked one) `selected_discount_id`/`discount_amount` and/or
   `selected_promo_id`/`promo_amount` are populated.

### 6. Manual UI smoke test - Cashier queue + checkout

1. Log in as a Cashier-role staff account, open the Bookings Queue - confirm
   all statuses are visible (unchanged), a Pending or In Progress row shows
   **no** Start/Complete button, and a Completed row still shows Mark as
   Paid and it succeeds.
2. Log in as a non-Cashier staff role (Receptionist/Admin/Groomer/etc.) -
   confirm Start/Complete still work as before (no regression).
3. Take the multi-item Grooming booking with a discount applied from step 5
   above through to Completed (Start, then Complete), then run it through
   Cashier checkout (`/staff/billing/checkout` or wherever
   `CashierCheckoutPage` is mounted in your build). Confirm the checkout
   screen shows the SAME discount/promo you picked at booking time (not a
   different auto-matched one), and doesn't double-apply it alongside any
   other scope-matching discount that might also exist for that branch.
4. Repeat checkout for an older booking (one created before this change, or
   via a direct API call with no `discount_id`/`promo_id`) - confirm
   checkout still auto-evaluates discounts/promos by scope exactly as it
   did before this change (the fallback path).

### 7. Follow-up round: automated tests

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 697
  tests, 694 passing. The 3 remaining failures are the pre-existing,
  unrelated `availability.service.spec.ts` time-mocking gap described
  above - not caused by this branch.
- `cd client && npx tsc -b && npx vitest run` - 115 test files / 520 tests
  passing.

### 8. Follow-up round: manual UI smoke test

1. Start a Hotel booking, select a cage, then select a different cage -
   confirm the first is deselected automatically (only one cage). Same
   check for Daycare with two sessions/services if your seed data has more
   than one Daycare option. Confirm Grooming/Veterinary still allow
   multiple simultaneous selections.
2. Confirm the service/package cards no longer show a checkbox square -
   just the card itself highlighting on click.
3. Start a Grooming or Veterinary booking for a branch+category combo
   where Staff Picker is toggled OFF (Admin → booking policy config, or
   `PATCH /bookings/policy` with `staff_picker_enabled_grooming: false`
   for your test branch). Pick a slot - confirm you land on Review & Pay
   directly (no Staff step, since it's correctly absent), rather than a
   blank/broken screen. Then re-enable the toggle and confirm a fresh
   booking DOES show the Staff step and lands there after picking a slot.
4. Open the Bookings Queue as Receptionist/Groomer/etc. and confirm rows
   are visibly shorter/tighter than before, with no dead empty space under
   a Paid/Cancelled booking's meta line.
5. Open the Bookings Queue as Admin or Superadmin - confirm each row shows
   a **Status** dropdown instead of Start/Complete/Mark as Paid buttons.
   Walk a Pending booking through Pending → In Progress → Completed →
   Paid via the dropdown, then use the SAME dropdown to revert it back to
   Completed, then In Progress, then Pending - confirm each revert
   succeeds (200) and the badge updates. Confirm Reschedule/Cancel buttons
   still appear alongside the dropdown when applicable.
6. Confirm a non-Admin/Superadmin staff role (Receptionist/Groomer/
   Cashier/etc.) still sees the original one-directional buttons, not the
   dropdown.
7. Log in as Cashier - confirm the Bookings Queue sidebar link is now
   visible (staffDashboard.config.ts fix) and that the "New booking"
   button no longer appears on the queue page itself.
8. As a non-Admin/Superadmin, staff, try `PATCH /bookings/:id/status`
   directly (e.g. via the Postman collection) - confirm 403.

### 9. Round 3: automated tests

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 699
  tests, 696 passing (same 3 pre-existing unrelated
  `availability.service.spec.ts` failures as before).
- `cd client && npx tsc -b && npx vitest run` - 115 test files / 522 tests
  passing.

### 10. Round 3: apply the two new migrations, then confirm the schema

Apply `20260803079_m13_add_misc_service_category.sql` then
`20260803080_m13_move_assessment_services_to_misc.sql`, in that order (the
first adds the enum value; Postgres won't let it be used - including by an
`UPDATE ... SET category = 'Misc'` - in the same transaction that added it,
so they must be separate migrations, applied in order). Then run the
`-- Round 3` section at the bottom of
`multi-item-booking-and-cashier-queue.sql` in the Supabase SQL Editor to
confirm `Misc` is a valid enum value and both services moved.

### 11. Round 3: manual UI smoke test

1. Start a Grooming booking, check 1-2 services (note the running total),
   switch to the Hotel tab and pick a cage (different running total),
   switch to Daycare, then switch back to Grooming - confirm your original
   Grooming services are still checked and the running total is back to
   what it was (not reset to PHP 0.00).
2. On the Hotel tab, confirm "Number of nights" now appears on the Service
   step (not Date & Time), defaulting to 1. Change it to 3 and confirm
   both the cage's own displayed price and the running total immediately
   multiply by 3. Proceed to Date & Time and confirm the picked slot's
   duration still correctly reflects a multi-night stay.
3. Complete a 3-night Hotel booking. In Supabase, confirm the created
   booking's `total_price` and its `booking_items` row's `price_at_booking`
   both equal the cage's per-night rate × 3, and `duration_minutes_at_booking`
   is still the per-night figure (1440), not the multiplied total.
4. Start a booking for a pet that has never been assessed - confirm the
   only category tab shown is now **Misc** (not Grooming), and Initial
   Assessment is pre-selected there automatically.
5. Get that pet assessed (staff PATCH via Customer Management, as in the
   original pet-assessment-gate flow), then start a new booking for the
   same pet - confirm the Misc tab now shows **Reassessment** only,
   with Initial Assessment gone from the list entirely. Confirm Grooming/
   Hotel/Daycare/Veterinary tabs are all available again too.
6. As Admin, open Services (`/staff/admin/maintenance/services`) - confirm
   Initial Assessment and Reassessment now show category "Misc", not
   "Grooming".

### 12. Round 4: automated tests

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 699
  tests, 696 passing (same 3 pre-existing unrelated
  `availability.service.spec.ts` failures as before - confirmed via `git
diff --stat` that this branch never touches that file).
- `cd client && npx tsc -b && npx vitest run` - 116 test files / 528 tests
  passing.

### 13. Round 4: manual UI smoke test - cross-category warning

1. Start a booking, on the Service step check a Grooming service, then
   switch to the Hotel tab - confirm a warning banner appears saying you
   also have items selected under Grooming and that only Hotel will be
   submitted here. Switch back to Grooming - confirm the warning is gone
   again (Grooming is now both the only category with picks and the active
   tab).
2. Submit the Hotel booking (with the Grooming picks still sitting
   unsubmitted on that other tab) - confirm only one booking is created,
   under Hotel, and the Grooming picks are simply discarded (never became
   a second booking or a cross-category one).

### 14. Round 4: manual UI smoke test - consultation queue fix

1. Log in as a Veterinarian, open the Consultation Queue for a branch with
   a Pending/In Progress Veterinary booking scheduled today - confirm the
   queue loads normally with no "Could not embed..." error.
2. If a follow-up has been scheduled from an earlier consultation for that
   pet, confirm the queue and the follow-up's own booking link both still
   resolve correctly (the `!booking_id` disambiguation only changes which
   FK is followed for the embed, not the data itself).

### 15. Round 4: manual UI smoke test - booking details page

1. Open the Bookings Queue as any staff role, confirm every row now shows
   a "View details" button alongside its status badge/controls.
2. Click it on a multi-item booking - confirm the details page lists every
   selected service/package with its own price, the pet/owner, branch,
   scheduled window, and a pricing breakdown that sums correctly to
   `total_price`.
3. Open details for a booking that had a discount and/or promo applied at
   booking time - confirm both show their resolved name (not just a raw
   id) next to their amount.
4. Open details for a Completed/Paid booking - confirm the status timeline
   shows `started_at`/`completed_at`/`paid_at` populated; open details for
   a Cancelled booking - confirm the cancellation reason (if any) shows
   next to the cancelled timestamp.
5. Use the "Back to queue" link/button - confirm it returns to
   `/staff/bookings/queue`.

### 16. Round 5: automated tests

- `cd client && npx tsc -b && npx vitest run` - 116 test files / 529 tests
  passing.

### 17. Round 5: manual UI smoke test - selecting elsewhere clears the old pick

1. Start a booking, on the Service step check 2 Grooming services - confirm
   the running total reflects both.
2. Switch to the Hotel tab without selecting anything - confirm the warning
   banner still appears naming Grooming (browsing alone doesn't clear it
   yet).
3. Select a cage on the Hotel tab - confirm the warning disappears
   immediately.
4. Switch back to the Grooming tab - confirm neither of the two services
   is checked anymore and the running total reads PHP 0.00.

### 18. Round 6: automated tests + lint

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 699
  tests, **all passing** (the 3 previously-flaky
  `availability.service.spec.ts` failures are now fixed, not just
  documented).
- `cd client && npx tsc -b && npx vitest run` - 116 test files / 529 tests
  passing.
- `cd client && npm run lint` - clean (0 errors, 0 warnings).
