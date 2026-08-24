# Restrict cage size selection to staff only

Branch: `42-restrict-cage-size-selection`

## The request, verbatim

> on http://localhost:5173/staff/bookings/new > cage selector:
> make it so that only receptionist can select cage sizes that are not the
> same as the pet's size
> customer is limited to same size cage as pet

## Design decisions

`CustomerBookingFlowPage.tsx` renders the exact same cage-picker component
(`CagePickerList`) whether it's mounted at `/portal/book` (a customer
booking for themselves) or `/staff/bookings/new` (a receptionist walk-in
booking on the customer's behalf) - the page already has an
`isReceptionistMode` flag (`location.pathname.startsWith('/staff')`) used
for several other staff-vs-customer differences, but it wasn't threaded
into the cage picker.

- **Client**: `CagePickerList` gets a new `restrictToPetSize` prop. When
  true, a cage tile whose `size` doesn't match `recommendedSize` (the
  selected pet's own `weight_class`) is still shown (so the customer can
  see what's occupied/what exists) but rendered `disabled`, with a "Staff
  only" badge instead of "Recommended", and a `title` tooltip explaining
  why. "No preference" always stays selectable regardless - it doesn't
  name a specific mismatched size, it defers the choice entirely.
  `CustomerBookingFlowPage.tsx` passes `restrictToPetSize={!isReceptionistMode}`.
- **Server**: client-side disabling alone doesn't stop a customer from
  calling `POST /bookings` directly with a mismatched `cage_preference`, so
  `verifyCagePreference` (`cagePicker.service.ts`) gained an optional
  `requiredSize` parameter - when given, the cage must also match that size
  or the query returns no row, and the preference silently degrades to
  `null` (`preferred_cage_id` stays unset), **exactly the same behavior**
  the function already had for an unavailable/nonexistent cage (a cage
  preference has always been "advisory-only" here - check-in re-picks the
  actual cage regardless via `cageAssignment.service.ts`, so degrading
  rather than hard-rejecting the whole booking matches the existing
  design). `booking.service.ts`'s `createBooking` passes
  `staffRole ? undefined : pet.weight_class` as `requiredSize` - a
  receptionist/staff-created booking (`staffRole` truthy) is exempt and
  keeps free choice of any cage size, matching the client restriction.

No migration was needed - `cages.size` and `pets.weight_class` already use
the same S/M/L/XL vocabulary directly comparable with `===`.

## What changed

- `client/src/features/booking/components/CagePickerList/CagePickerList.tsx`
  (+ `.module.css`): new `restrictToPetSize` prop, disables/badges
  mismatched-size tiles.
- `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`:
  passes `restrictToPetSize={!isReceptionistMode}`.
- `server/src/features/booking/services/cagePicker.service.ts`:
  `verifyCagePreference` gains an optional `requiredSize` parameter.
- `server/src/features/booking/services/booking.service.ts`: `createBooking`
  passes the pet's `weight_class` as `requiredSize` only for a
  customer-created booking.

## Verification

### 1. Customer booking flow (`/portal/book`)

1. As a customer, start booking a Hotel service for a pet with a recorded
   size (e.g. S). On the Cage step, confirm S-size cages remain clickable
   and normal-looking (with "Recommended" on the size match), while
   M/L/XL cage tiles are visibly greyed out, show a "Staff only" badge, and
   cannot be clicked/selected.
2. Confirm "No preference" is still fully selectable.
3. Complete the booking with a same-size cage or "No preference" - confirm
   it saves normally.

### 2. Receptionist walk-in flow (`/staff/bookings/new`)

1. As a Receptionist, start a walk-in Hotel booking for the same pet. On
   the Cage step, confirm **every** cage tile (any size) is clickable,
   with no "Staff only" badges or disabled tiles.
2. Select a cage of a different size than the pet's own recorded size and
   complete the booking - confirm it saves with that cage as the preference
   (no degrade).

### 3. API-level checks (Postman)

See `restrict-cage-size-selection.postman_collection.json` in this folder.

1. Import the collection, fill in the variables (customer + receptionist
   login credentials, `branch_id`, a customer `pet_id` with `weight_class`
   `'S'`, the owning `customer_id`, an active Hotel `hotel_service_id`, and
   three near-future non-overlapping `scheduled_start`/`scheduled_end`
   pairs). The branch needs at least one `Available` S-size and one
   `Available` M-size cage, and the Hotel service type needs
   `cage_picker_enabled` on (Admin Settings > Service Types).
2. Run requests in order, top to bottom. Request 4 shows a customer's
   mismatched-size (M) preference silently degrading to
   `preferred_cage_id: null`; request 5 shows a customer's matching-size
   (S) preference being honored; request 6 shows a receptionist's
   mismatched-size (M) preference being honored (staff is exempt).

## Test suites

- `server`: `npm run test` (from `server/`) - 826/826 passing. New/updated:
  `cagePicker.service.spec.ts` (`verifyCagePreference` `requiredSize`
  match/mismatch cases).
- `client`: `npm run test` (from `client/`) - all passing. New:
  `CagePickerList.spec.ts` (created - no prior coverage existed), covering
  unrestricted selection, a disabled mismatched-size tile under
  `restrictToPetSize`, and "No preference" staying selectable regardless.
  `npx tsc --noEmit -p tsconfig.app.json` / server `npx tsc --noEmit` both
  clean.
