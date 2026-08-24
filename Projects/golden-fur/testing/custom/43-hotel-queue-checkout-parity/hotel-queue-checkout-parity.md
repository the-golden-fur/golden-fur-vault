# Hotel Queue: drop "(checkinable)" label, give Checkout the same list as Check In

Branch: `43-hotel-queue-checkout-parity`

## The request, verbatim

> on http://localhost:5173/staff/hotel/queue > checkin:
> remove checkinable next to pending filter
>
> at checkout:
> use same list format in checkin
> should have the same search, filter and sort functions
> checkin button changes to checkout

## Scope note

Only the Hotel Queue (`/staff/hotel/queue`) was touched. The Daycare
booking picker (`DaycareBookingPicker.tsx`) has the exact same
"Pending (checkinable)" label but wasn't mentioned in this request, so it
was left alone.

## Design decisions

The Check In tab (`HotelBookingPicker.tsx`) and Check Out tab
(`HotelStayPicker.tsx`) are two independent components, not one shared list
with different props - they query fundamentally different data (`Booking`s
via `listBookings`, filtered by _booking_ status, vs. `HotelStayWithCage`s
via `listHotelStays`, filtered by the _stay's_ own `Active`/`Completed`
status and previously hardcoded to only ever fetch `'In Progress'`
bookings' stays with no filter UI at all). Rather than merging them into
one component (a much larger refactor that would blur two genuinely
different data shapes), Checkout was brought up to the same **toolbar**
Check In already has - `QueueFilterBar` (date-range preset + status select)
wrapping `SearchSortBar` - while keeping its own data source and sort keys
(checkout-due/checked-in dates aren't the same concept as a booking's
check-in date, so `HotelBookingPicker`'s "soonest/latest" comparators
don't carry over as-is).

- **"(checkinable)" removed**: `HotelBookingPicker.tsx`'s status filter
  option label is now plain `"Pending"`.
- **Checkout gets a status filter**: previously hardcoded to only request
  `'In Progress'` stays (server already supported `'In Progress'` /
  `'Completed'`, just never exposed a dropdown for it). Now defaults to
  `"In Progress"` with `"All statuses"` / `"Completed"` alongside it,
  mirroring Check In's status-select pattern. `"Pending"`/`"Cancelled"`/
  `"No-show"` aren't included - a `stays` row only ever exists once a
  booking has been physically checked in, so those booking statuses can
  never apply to a stay.
- **Checkout gets a date filter**: `GET /hotel/stays` gained optional
  `date_from`/`date_to` query params (inclusive, matching
  `scheduled_check_out_date` - the "when is this due" field, the closest
  equivalent to Check In's `scheduled_start` date filter), validated by a
  new `listHotelStaysQueryValidator`. The date preset **defaults to "All
  dates"**, not "Today" like Check In - unlike a not-yet-checked-in
  booking, an overdue stay (scheduled to check out days ago) still needs
  to be visible by default, so check-in's "Today" default would have been
  a regression here.
- **Widening the status filter surfaces already-checked-out stays**, which
  the Checkout tab previously could never show at all. Selecting one now
  displays an "Already checked out" badge in place of the "Check out"
  button (mirrors Check In's own "Already checked in" badge for a booking
  that's not currently checkinable), so the newly-visible rows aren't
  presented as actionable when they aren't.
- **"Check in" button becomes "Check out"**: this was already true before
  this change (`HotelStayPicker.tsx` already rendered a "Check out"-labeled
  button, distinct from Check In's own "Check in" button) - listed here for
  completeness since the request called it out explicitly.

## What changed

### Server

- `server/src/features/hotel/modules/validators/hotel.validator.ts`: new
  `listHotelStaysQueryValidator` (`status`, `date_from`, `date_to`).
- `server/src/features/hotel/hotel.controller.ts`:
  `listHotelStaysController` now parses the query through that validator
  instead of hand-checking `req.query.status` against a local `Set`.
- `server/src/features/hotel/services/hotelStay.service.ts`:
  `listHotelStays` accepts optional `dateFrom`/`dateTo`, filtering
  `scheduled_check_out_date` with `gte`/`lte`.

### Client

- `client/src/features/hotel/components/HotelBookingPicker/HotelBookingPicker.tsx`:
  status option label `'Pending (checkinable)'` → `'Pending'`.
- `client/src/features/hotel/components/HotelStayPicker/HotelStayPicker.tsx`
  (+ `.module.css`): adds `QueueFilterBar` (date preset + status), a
  "checked out" disabled-card state, and an "Already checked out" badge.
- `client/src/features/hotel/api/hotel.api.ts`: `listHotelStays`'s second
  parameter changed from a bare status string to a filters object
  (`{ status?, dateFrom?, dateTo? }`).
- `client/src/features/staff/components/dashboard/HotelQueueWidget/HotelQueueWidget.tsx`:
  updated call site for the new `listHotelStays` signature (no behavior
  change - still requests `'In Progress'` only).

## Verification

### 1. Check In tab - label

1. As staff, open `/staff/hotel/queue` (Check In tab). Open the STATUS
   filter dropdown - confirm the first option now reads plain "Pending",
   not "Pending (checkinable)".

### 2. Check Out tab - same toolbar as Check In

1. Switch to the "Check Out" tab. Confirm it now shows a DATE filter
   ("Today"/"Tomorrow"/"This week"/"This month"/"Custom date"/"All dates",
   defaulting to "All dates") and a STATUS filter (defaulting to
   "In Progress", also offering "All statuses" and "Completed"), in the
   same visual toolbar style as Check In's own filters, plus the same
   search box and sort control layout.
2. Widen STATUS to "All statuses" or "Completed" - confirm any
   already-checked-out stays now appear, showing an "Already checked out"
   badge with no "Check out" button (not actionable).
3. Narrow STATUS back to "In Progress" (or clear the filter chip) - confirm
   behavior matches what the tab did before this change (only currently
   checked-in stays, each still showing an active "Check out" button, an
   "Overdue" badge when applicable).
4. Confirm the primary action button on an active stay's row still reads
   "Check out" (unchanged).

### 3. API-level checks (Postman)

See `hotel-queue-checkout-parity.postman_collection.json` in this folder.

1. Import the collection, fill in `base_url` and a staff login
   (`staff_identifier`/`staff_password`).
2. Run requests in order, top to bottom. Covers the unfiltered default,
   status + date-range filtering succeeding, and an invalid status/date
   both being rejected with `400` by the new query validator.

## Test suites

- `server`: `npm run test` (from `server/`) - 826/826 passing. New/updated:
  `hotelStay.service.spec.ts` (date-range filtering case, mock query
  builder extended with `gte`/`lte`).
- `client`: `npm run test` (from `client/`) - 621/621 passing. Updated:
  `HotelStayPicker.spec.ts` (new default-filter-shape assertion, a status-
  widening case, and an "already checked out" badge/no-button case).
  `npx tsc --noEmit -p tsconfig.app.json` / server `npx tsc --noEmit` both
  clean.
