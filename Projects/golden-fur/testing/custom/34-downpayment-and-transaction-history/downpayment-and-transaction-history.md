# Downpayment (services/packages) and transaction history

Branch: `34-downpayment-and-transaction-history`

## The request, verbatim

- When creating services/packages, include requires downpayment checkbox -
  specify downpayment amount.
- When paying for booking services that has downpayment, option for
  customer/receptionist to pay downpayment or in full.
- Services that requires downpayment and are unpaid should not show in
  grooming, hotel and daycare, vet queues - downpayment is required before
  service can start. Usually applied on hotel services.
- Update supabase/ files if needed.
- Add a transactions history, visible to customer, cashier, supervisor,
  admin and superadmin.

This is a P-1 "Roadmap / Not Yet Implemented" item from
`temp/context/Modules-Features.docx`'s Architectural-Change-Suggestions
tracker (matches the request almost word-for-word), listed as affecting
modules M1, M3, M5, M6, M8, M9, M13.

## Design revision (live follow-up feedback)

The first draft (below) kept the pre-existing branch-wide Hotel
`policy_configurations.downpayment_percentage` field as a fallback for
whenever no catalog item was flagged, and the catalog's `downpayment_amount`
was flat-PHP only. Live follow-up feedback on `/staff/admin/maintenance/
policies` asked: "should we remove the branch wide hotel downpayment? since
it's already applied by service. instead, make it so that when creating
services... allow the downpayment amount to be either flat PHP or
percentage (of base price)." Applied in place (no schema had shipped to a
real environment yet, so this is one combined migration set, not a second
layer on top):

- `policy_configurations.downpayment_percentage` is **dropped entirely**
  (migration `20260808112`). It turned out to already be fully dead code -
  `booking.service.ts`/`CustomerBookingFlowPage.tsx` both used a separate
  hardcoded `HOTEL_DOWNPAYMENT_RATE = 0.5` constant instead of ever reading
  this column - so dropping it is not a behavior change to any booking
  logic, only the removal of an admin-editable field on the Policies page
  that never actually did anything.
- `services.downpayment_type`/`packages.downpayment_type` (`'Flat'` |
  `'Percentage'`) is added alongside `downpayment_amount` - `'Percentage'`
  means the figure is 0-100, resolved against that item's own
  `price_at_booking` at booking time (not a flat PHP figure).
  `HOTEL_DOWNPAYMENT_RATE`'s Hotel-category fallback is removed from both
  `booking.service.ts` and `CustomerBookingFlowPage.tsx` in the same
  change - downpayment is now driven **exclusively** by the catalog flag,
  for every category, with no Hotel special-case left anywhere.
- To keep the seeded Hotel service's real-world behavior unchanged, it is
  backfilled to `requires_downpayment = true, downpayment_type =
'Percentage', downpayment_amount = 50` - i.e. the exact same effective
  50%-of-total downpayment it already had, now expressed as an ordinary
  catalog flag instead of a special branch-wide rule.

Design decision #1 below and "Known limitations"' `downpayment_percentage`
bullet are both superseded by this revision - left in place below (struck
through in spirit, not literally) since the migration history and the rest
of this document still refer to the original "catalog wins, Hotel-percentage-
is-the-fallback" precedence, which is worth understanding before reading the
revision.

## Design decisions (read this before reviewing the diff)

The codebase already has a Hotel-only downpayment mechanism (a hardcoded
50%-of-total, computed at booking creation, `bookings.downpayment_amount`)
and a generic three-state payment tracker (`bookings.payment_stage`: Unpaid
→ Paid in Advance → Paid, independent of the booking's own status
lifecycle). Neither is amount-aware beyond that one snapshot, and there is
no "real" partial-payment charge anywhere in this codebase - even Hotel's
existing 50% is never actually charged through a payment processor at
booking time, it's simply netted as a negative line item at final cashier
checkout. Given that, this change is intentionally **additive, not a
replacement**:

1. **Catalog flag is independent of the Hotel percentage.** A service or
   package can now be flagged `requires_downpayment` with a flat PHP
   `downpayment_amount`, in any category (not category-gated, same
   convention as `min_nights_for_free_package`). At booking creation, if
   any selected item is flagged, the booking's `downpayment_amount` is the
   **sum of those items' catalog amounts** - the Hotel-only 50% fallback
   only ever applies when **no** item is flagged, so a booking made before
   this feature (or against an un-flagged service) behaves exactly as
   before.
2. **`bookings.downpayment_required`** is a new snapshot flag (true only
   via the catalog path above - the Hotel percentage fallback alone does
   NOT set it). This is the queue-gating signal.
3. **Reused, not duplicated, `payment_stage`.** "Paid" a downpayment is
   exactly what "Paid in Advance" already meant ("money collected before
   the service happens") - so paying online with the new
   `payment_choice: 'downpayment'` option lands the booking on `'Paid in
Advance'` **at creation time** (a real gap before this change -
   `payment_stage` was previously only ever set at booking _completion_,
   which would have left a fully-paid Hotel booking stuck showing "Unpaid"
   in the queue the whole time it was Pending/In Progress). Choosing
   `'full'` (or the field being omitted) lands on `'Paid'` at creation,
   same idea. `completeBooking`'s own auto-advance-to-Paid fast path was
   narrowed so it no longer clobbers a `'Paid in Advance'` booking - the
   remaining balance still has to be collected at the counter and marked
   via the existing "Mark as Paid" flow, same as it already worked for
   every other Paid-in-Advance booking.
4. **Paying at the counter needs no new UI at all.** For every pay-at-
   counter method (Cash/Card/Bank Transfer/Grabmart/Pickaroo), nothing was
   paid at booking time before this change either - the receptionist/
   cashier already has a "Mark as Paid" action on the Payments Queue with
   an "Advance payment" (down-payment-style) vs "Normal onsite payment"
   choice. That existing action **is** the "receptionist" half of "option
   for customer/receptionist to pay downpayment or in full" - it just
   didn't previously interact with queue visibility, which is what item 2
   above wires up.
5. **Queue gating** excludes a Pending/In Progress booking from the
   Grooming/Veterinary queues (direct `bookings` queries) and from the
   Hotel/Daycare check-in pickers (an opt-in `excludeUnpaidDownpayment`
   filter on the shared `GET /bookings` `listBookings`) whenever
   `downpayment_required = true and payment_stage = 'Unpaid'`. The filter
   is **not** applied to the customer's own booking list, the receptionist
   bookings queue, or the payments queue - those need to keep showing an
   unpaid booking so it can actually be paid.
6. **Checkout netting generalized.** Hotel's own downpayment-netting line
   (keyed off `stays.downpayment_amount`) is untouched. The same
   "Downpayment already collected" negative line item is now also produced
   for Grooming/Misc/Daycare/Veterinary bookings when
   `downpayment_required` is true, off the generalized
   `bookings.downpayment_amount`.
7. **Transaction history**: the report/table already existed
   (`transactions`/`transaction_line_items`, RLS already allowed a
   customer to read their own rows) but the _server route_ only allowed
   Admin/Supervisor/Superadmin - Cashier was 403'd despite the client's own
   `TransactionHistoryTable.tsx` already assuming Cashier could see it, and
   there was no customer-facing route at all. Fixed by widening the
   existing route's role list for Cashier, and adding a new customer-facing
   `GET /reports/my-transaction-history` (scoped server-side to the
   caller's own `customer_id`, no staff role/branch involved) plus a
   `/portal/transactions` page.

## What changed

### Supabase (`supabase/migrations/`)

- `20260808110_m13_services_packages_downpayment.sql` - `services` and
  `packages` each get `requires_downpayment boolean not null default false`
  - `downpayment_amount numeric(10,2)`, with a CHECK tying the two together
    (amount required and positive iff the flag is true).
- `20260808111_m03_m08_bookings_downpayment_generalize.sql` -
  `bookings.downpayment_required boolean not null default false` (the queue
  gate), plus an updated `comment on column` for the pre-existing
  `bookings.downpayment_amount` documenting its generalized meaning, and a
  partial index on `(downpayment_required, payment_stage)`.
- `20260808112_m03_m09_m13_downpayment_flat_or_percentage.sql` (design
  revision, see above) - drops `policy_configurations.downpayment_percentage`
  entirely; adds `services.downpayment_type`/`packages.downpayment_type`
  (`'Flat' | 'Percentage'`, replacing/extending the CHECK constraints from
  `20260808110`); backfills the seeded Hotel service
  (`a1300000-0000-4000-a000-000000000024`, "Overnight Stay (Aircon Room)")
  to `requires_downpayment = true, downpayment_type = 'Percentage',
downpayment_amount = 50`.

See `downpayment-and-transaction-history.sql` in this folder for a
concatenated, annotated copy plus verification queries.

### Server

- `maintenance.validator.ts`/`maintenance.types.ts` -
  `requires_downpayment`/`downpayment_amount`/`downpayment_type` added to
  `create/updateServiceValidator` and `create/updatePackageValidator` (a
  `requireDownpaymentAmount` superRefine mirrors the DB CHECK - amount and
  type both required when the flag is true, amount capped at 100 for
  `'Percentage'`), and to the `Service`/`Package` interfaces.
  `services.service.ts`/`packages.service.ts` needed no changes (both
  already do a plain spread-insert/update of the validated input).
- `booking.service.ts`:
  - `resolveBookingItem` now carries each resolved item's
    `requires_downpayment`/`downpayment_amount`/`downpayment_type` through
    (`ResolvedBookingItem`).
  - `createBooking` computes `catalogDownpaymentAmount` - each flagged
    item's own contribution is either its flat PHP `downpayment_amount`, or
    that percentage of the item's own `price_at_booking` - and
    `downpaymentRequired`/`downpaymentAmount` from the sum. The old
    Hotel-category `HOTEL_DOWNPAYMENT_RATE` fallback is gone (design
    revision, see above) - downpayment is now driven exclusively by the
    catalog flag, for every category. A `payment_choice` field
    (`'downpayment' | 'full'`, optional) on `createBookingValidator` drives
    `payment_stage` at insert time, only when `downpaymentRequired` is true
    - see "Design decisions" #3.
  - `completeBooking`'s `onlinePrepaid` auto-advance now also checks
    `payment_stage !== 'Paid in Advance'` first - see #3.
  - `listBookings` gained an opt-in `excludeUnpaidDownpayment` filter
    (`ListBookingsFilters`), wired through `listBookingsQueryValidator`'s
    new `exclude_unpaid_downpayment` query param and the controller.
- `booking.types.ts`/`booking.validator.ts`/`staffPicker.service.ts` -
  `downpayment_percentage` removed from `PolicyConfiguration`/
  `EffectivePolicy`/`updatePolicyValidator`/`DOCUMENTED_DEFAULTS`/the
  branch-override baseline copy (design revision, see above).
- `grooming.service.ts` (`listGroomingQueue`) and
  `consultation.service.ts` (`listConsultationQueue`) both gained the same
  `.or('downpayment_required.eq.false,payment_stage.neq.Unpaid')` predicate
  on their own direct `bookings` queries (they don't go through
  `listBookings`).
- `lineItemSources.service.ts` - `BookingForBilling` gained
  `downpayment_required`/`downpayment_amount`; a new
  `downpaymentNettingLines` helper is appended to `getItemBasedLineItems`
  (Grooming/Misc), `getDaycareLineItems`, and `getVeterinaryLineItems`.
  `getHotelLineItems` is untouched (own `stays`-based netting).
- `reports.types.ts` - new `TRANSACTION_HISTORY_READ_ROLES` (adds Cashier).
  `reports.routes.ts`/`reports.controller.ts` - the existing
  `/reports/transaction-history` route now uses that role list; a new
  `GET /reports/my-transaction-history` route + controller, gated by
  `jwtMiddleware` only, scoped to `req.user.sub` as `customer_id`.

### Client

- `maintenance.types.ts` - matching `requires_downpayment`/
  `downpayment_amount`/`downpayment_type` additions to `Service`/`Package`/
  the four Create/Update payload types.
- `AdminServicesPage.tsx`/`AdminPackageBuilderPage.tsx` - a "Requires a
  downpayment" toggle (unconditional on category, unlike the Grooming-only
  pricing-matrix toggle), a "Downpayment type" select (Flat amount (PHP) /
  Percentage of base or bundled price), and an amount input whose label/max
  switches with the type (0-100 for Percentage), plus a list-row badge
  showing either "Requires PHP X downpayment" or "Requires X% downpayment".
- `booking.types.ts` (client) - `downpayment_required` added to `Booking`;
  `payment_choice` added to `CreateBookingPayload`;
  `excludeUnpaidDownpayment` added to `ListBookingsFilters`;
  `downpayment_percentage` removed from `PolicyConfiguration`/
  `EffectivePolicy`/`UpdatePolicyPayload` (design revision, see above).
- `booking.api.ts` - `listBookings` sends `exclude_unpaid_downpayment=true`
  when set.
- `PolicyConfigurationPage.tsx` - the entire "Downpayment" section (form
  state, hydration, documented default, submit payload, JSX) removed
  (design revision, see above).
- `CustomerBookingFlowPage.tsx` (shared by customer self-service and
  receptionist walk-in mode) - computes `catalogDownpaymentAmount`/
  `downpaymentRequired` from the selected services/packages (each item's
  contribution is flat-or-percentage-of-its-own-price, mirroring the
  server); when required and an online payment method (GCash/Maya) is
  chosen, a radio choice appears ("Pay downpayment only now" vs "Pay in
  full now"), sent as `payment_choice`. Pay-at-counter methods show no new
  UI - see "Design decisions" #4. The old `HOTEL_DOWNPAYMENT_RATE` fallback
  is gone (design revision, see above).
- `HotelBookingPicker.tsx`/`DaycareBookingPicker.tsx` - pass
  `excludeUnpaidDownpayment: true`.
- `reports.api.ts`/`reports.types.ts` - new `getMyTransactionHistory`.
- `CustomerTransactionHistoryPage.tsx` (new) - customer-facing transaction
  history, reusing `TransactionHistoryTable.module.css`. Routed at
  `/portal/transactions` (`reports.routes.tsx`, under `CustomerAuthGuard`)
  and added to the customer sidebar (`customerPortal.config.ts`).

## Known limitations

- A service/package can be flagged `requires_downpayment` under any
  category, including Veterinary - which never takes upfront payment at
  all (`requiresPayment = category !== 'Veterinary'` in
  `CustomerBookingFlowPage.tsx`, and `payment_confirmed` is force-false
  server-side for Veterinary). Flagging a Veterinary service this way would
  permanently gate it out of the Veterinary queue, since there is no path
  to ever pay it off. This mirrors the existing "not category-gated"
  convention for several other catalog fields (e.g.
  `min_nights_for_free_package` on a non-Hotel service is likewise
  silently meaningless rather than rejected) - not fixed here, flagged for
  awareness.
- The at-counter "pay downpayment vs pay in full" choice is made via the
  existing Payments Queue "Mark as Paid" action's Advance/Onsite buttons,
  which are not labeled with the specific downpayment amount. A nice-to-
  have (showing "Downpayment: PHP 150" in that modal) was left out to keep
  this change additive and minimal - the underlying data
  (`booking.downpayment_amount`) is already available on that page's
  booking objects if this gets picked up later.
- A `'Percentage'` downpayment resolves against `price_at_booking` (the
  actual tiered/matrix price the pet was charged, server-side) rather than
  a flat catalog `base_price`/`bundled_price` figure - `resolveBookingItem`
  in `booking.service.ts` already computes `price_at_booking` before the
  downpayment math runs, so this is exact server-side. The client-side
  preview in `CustomerBookingFlowPage.tsx` approximates the same thing
  using `base_price`/`bundled_price` (times `hotelNightsMultiplier`) since
  it doesn't have access to the server's pricing-matrix logic - it can
  under/overstate the downpayment shown pre-submission for a Grooming
  service whose price varies by pet size/coat; the amount actually charged
  is always the server-computed figure returned on the confirmed booking.

## Verification

### 1. Migrations

- **With Supabase CLI access**: `supabase db reset` (fresh local db) or
  `supabase db push` (linked remote project), from the repo root.
- **Without CLI/push access**: Supabase Dashboard → **SQL Editor** → paste
  `downpayment-and-transaction-history.sql` from this folder → **Run**. The
  verification queries at the bottom of that file confirm the new columns
  exist, that `policy_configurations.downpayment_percentage` is gone, that
  the seeded Hotel service was backfilled to a 50% Percentage downpayment,
  and that every other existing row defaults to "no downpayment required."

### 2. The "requires downpayment" checkbox on Services/Packages - flat or percentage

1. As Admin/Superadmin, open `/staff/admin/maintenance/services`, create or
   edit a service (any category). Check "Requires a downpayment..." -
   confirm a "Downpayment type" select and an amount field appear.
2. Leave the type as "Flat amount (PHP)", save with e.g. 150 - confirm the
   row shows a "Requires PHP 150.00 downpayment" badge.
3. Edit the same service, switch the type to "Percentage of base price",
   save with e.g. 20 - confirm the badge now reads "Requires 20%
   downpayment", and that entering a value over 100 is rejected.
4. Uncheck the toggle and save - confirm both fields disappear and the
   badge is gone.
5. Repeat steps 1-4 on `/staff/admin/maintenance/packages` (the Package
   Builder).
6. Open `/staff/admin/maintenance/policies` (Settings > Config > Policies) -
   confirm the "Downpayment" section (the old "Hotel downpayment (% of
   total)" field) is gone entirely.
7. Open the seeded Hotel service on the Services page - confirm it now
   shows "Requires 50% downpayment" (backfilled by the migration).

### 3. Booking a flagged service - paying online now

1. As a customer (or receptionist walk-in at `/staff/bookings/new`), start
   a booking against the flagged service from step 2. On the Payment step,
   pick GCash or Maya. Confirm a new "This booking requires a downpayment -
   pay it now, or pay in full?" choice appears, showing the correct
   downpayment amount and the full total.
2. Pick "Pay downpayment only now" and confirm. Open the booking (staff
   Booking Details or the Payments Queue) - confirm `payment_stage` is
   "Paid in Advance", not "Paid" or "Unpaid".
3. Repeat, picking "Pay in full now" instead - confirm `payment_stage` is
   "Paid" immediately after booking creation.
4. Pick Cash (or any non-online method) instead - confirm the new choice
   does **not** appear, and the booking's `payment_stage` stays "Unpaid".

### 4. Queue gating - unpaid downpayment blocks the service

1. Create a booking against a flagged service, paying Cash (deferred - see
   step 3.4). Note its category.
2. Open that category's staff queue (`/staff/grooming/queue`,
   `/staff/hotel/queue` or wherever the Hotel check-in picker lives,
   `/staff/daycare/queue`, or `/staff/veterinary/queue`). Confirm the
   booking does **not** appear.
3. As a money-handling staff role, open the Payments Queue
   (`/staff/billing/payments`) - the booking should be visible there (this
   queue is never gated) - click "Mark as Paid" → "Advance payment".
4. Re-open the same category queue from step 2 - confirm the booking now
   appears.
5. Confirm the customer's own "My Bookings" list (`/portal/bookings`) shows
   the booking at every point above, including before step 3 - it must
   never be gated there.

### 5. Checkout nets the downpayment for a non-Hotel category

1. Complete the flow from section 4 above (Start → Complete the booking).
2. Run Cashier Checkout for that booking. Confirm the line items include a
   "Downpayment already collected" negative line for the flagged amount,
   and the total due is reduced accordingly.

### 6. Transaction history

1. As Cashier, open `/staff/reports/transaction-history` - confirm it
   loads (previously 403'd).
2. As Supervisor/Admin/Superadmin, confirm the same page still works
   unchanged.
3. As the customer from section 3/4 above, open `/portal/transactions`
   (also in the portal sidebar as "Transactions") - confirm it shows only
   that customer's own transactions, filterable by date range and service
   type.

### 7. API-level checks (Postman)

See `downpayment-and-transaction-history.postman_collection.json` in this
folder.

1. Import the collection, fill in the variables (admin/cashier/customer
   credentials, `branch_id`, `pet_id`/`customer_id`, and two near-future
   `scheduled_start`/`scheduled_end` pairs within the branch's operating
   hours).
2. Run requests in order, top to bottom. All Test Results should be green -
   covers creating a downpayment-flagged service (and rejecting one with no
   amount), booking against it with `payment_choice`, the Grooming queue
   gate flipping once the downpayment is collected, the Cashier
   transaction-history role fix, and the new customer-scoped endpoint. (The
   collection creates a Flat-type service; the type field is otherwise
   covered by the client test suite, not this collection.)

## Test suites

- `server`: `npm run test` (from `server/`) - 759/759 passing. New/updated:
  `booking.service.spec.ts` (a `generic downpayment (custom change)`
  describe block - flat vs percentage precedence against `price_at_booking`,
  `payment_choice` → `payment_stage` at creation, and a `completeBooking`
  case confirming a `'Paid in Advance'` booking is never auto-bumped to
  `'Paid'`), `grooming.service.spec.ts`/`consultation.service.spec.ts` (mock
  query builders updated to support the new `.or(...)` call),
  `rescheduleFee.service.spec.ts` (fixture no longer sets the removed
  `downpayment_percentage`). `npx tsc --noEmit` clean.
- `client`: `npm run test` - 552/552 passing (two pre-existing
  `AdminServicesPage.spec.ts`/`AdminPackageBuilderPage.spec.ts` exact-payload
  assertions updated for the new `requires_downpayment`/`downpayment_amount`/
  `downpayment_type` fields now always present in the create/update
  payloads). `npx tsc --noEmit -p tsconfig.app.json` clean.
