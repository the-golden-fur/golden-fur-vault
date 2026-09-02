# Staff queue overhaul: advance rights, payment stage, Hotel/Daycare queue merge, assigned filter

Branch: `21-staff-queue-overhaul`

## Why

A single request bundled a live-bug report plus four follow-up asks about
the staff queue surfaces:

1. **Start Consultation button appeared broken** at
   `/staff/veterinary/console`. Investigated end-to-end (client wiring,
   `PATCH /veterinary/consultations/:id`, CORS, Vite proxy, the
   `startBooking` transition) by replaying the exact request the button
   sends against the live backend - every layer worked correctly. Turned
   out to be a stale dev build; confirmed fixed after a refresh. No code
   change needed for this item.
2. **Groomer/Pet Assistant advance rights**: Hotel and Daycare have no
   dedicated assigned-staff role (unlike Grooming/Veterinary), so Groomer
   and Pet Assistant should be able to check pets in/out of those two
   services too. Vet stays Vet-only; Cashier/Receptionist get nothing new.
3. **New payment-stage track**: cashiers (and other money-handling staff)
   need to record Unpaid → Paid in Advance → Paid, independent of the
   existing Pending → In Progress → Completed → Paid service-lifecycle
   status. An "Advance" button prompts whether a payment is being collected
   in advance or normally onsite; only Admin/Superadmin can revert it.
4. **Queue redesign**: no more separate Hotel Check-in / Hotel Checkout /
   Daycare Check-in / Daycare Checkout pages - each pair becomes one Hotel
   Queue / Daycare Queue page.
5. **Assigned-staff filter**: "assigned to me" / "no preference" filter on
   the Bookings Queue.

Two scope calls made while implementing (both explained inline below,
flagged here since they're judgment calls, not literal readbacks of the
request):

- **Payment-stage design**: found two _already-existing, independent_
  "payment complete" mechanisms in this codebase - the queue's own
  "Mark as Paid" (flips `bookings.status` to `Paid`, no transaction row)
  and Cashier Checkout (`/staff/billing/checkout`, writes a real
  `transactions` row, never touches `bookings.status`). The new
  `payment_stage` column is deliberately additive and touches neither -
  it's a separate, independent field for tracking _when_ money was
  collected relative to the service, not a replacement for either existing
  mechanism (reconciling those two would be a much larger, separate
  architectural change, out of scope here).
- **Queue redesign scope**: Grooming Queue and Consultation Queue were
  _not_ touched. Both already share the same `QueueFilterBar`/
  `SearchSortBar`/design-token components as the Bookings Queue restyle
  target, so there was no actual visual inconsistency to fix. Also,
  Grooming's queue already hard-scopes a Groomer viewer to their own
  bookings server-side, and the Veterinary console is explicitly
  documented as having "no per-vet scoping" by design (M07 spec) - so an
  "assigned to me" filter doesn't fit either page's existing model.
  Consequently the assigned-staff filter (item 5) only landed on the
  general Bookings Queue, not on Grooming/Consultation.

## What changed

### 1. Schema (`supabase/migrations/`)

- `20260803081_m05_m06_hotel_daycare_advance_roles.sql`: extends
  `hotel_stays` and `daycare_sessions` RLS (SELECT/INSERT/UPDATE policies)
  to include `Groomer`/`Pet Assistant` alongside the existing
  `Receptionist`/`Admin`/`Supervisor` roles. Defense-in-depth only - staff
  writes to these tables go through the service-role Supabase client
  (bypasses RLS), so the real enforcement boundary is the Express
  `requireRole` middleware change below; this migration keeps RLS in sync
  with it, matching the pattern already used elsewhere in this app.
- `20260803082_m08_booking_payment_stage.sql`: new `payment_stage` enum
  (`'Unpaid' | 'Paid in Advance' | 'Paid'`) and `bookings.payment_stage`
  column, `not null default 'Unpaid'`, plus an index.

### 2. Server (`server/src/features/...`)

- `hotel/hotel.types.ts`: new `HOTEL_ADVANCE_ROLES` (front desk + Groomer +
  Pet Assistant). `hotel/hotel.routes.ts`: check-in, checkout, and the
  supporting browse routes (cage-suggestion, current-prescription,
  cages/available, care-log/today, cages, stays) now gate on
  `HOTEL_ADVANCE_ROLES` instead of `HOTEL_FRONT_DESK_ROLES` /
  `frontDeskAndAssistants`. `/hotel/cage/:id/status` (Admin-only) and
  `/hotel/care-log/flagged` (supervisory) are unchanged.
- `daycare/daycare.types.ts`: new `DAYCARE_ADVANCE_ROLES` (same idea, all
  3 Daycare routes now use it instead of `DAYCARE_ROLES`).
- `booking/booking.types.ts`: new `PaymentStage` type,
  `PAYMENT_STAGES`/`OVERRIDABLE_PAYMENT_STAGES` consts,
  `PAYMENT_STAGE_ADVANCE_ROLES` (= `BOOKING_MARK_PAID_ROLES`), and
  `Booking.payment_stage`.
- `booking/services/booking.service.ts`: `advancePaymentStage()` (Unpaid →
  Paid in Advance/Paid depending on a required `choice`; Paid in Advance →
  Paid, no choice needed; 409 if already Paid) and `overridePaymentStage()`
  (Admin/Superadmin-only direct set, mirrors `overrideBookingStatus`). New
  `ListBookingsFilters.assignedStaffId` (a staff UUID, or the sentinel
  `'unassigned'` for `assigned_staff_id IS NULL`) wired into `listBookings`'s
  query builder.
- `booking/modules/validators/booking.validator.ts`:
  `advancePaymentStageValidator` (`choice` optional), `overridePaymentStageValidator`
  (`payment_stage` required), and `listBookingsQueryValidator` gained
  `assigned_staff_id`.
- `booking/booking.controller.ts` / `booking.routes.ts`: new
  `POST /bookings/:id/payment-stage/advance` (gated like Mark as Paid) and
  `PATCH /bookings/:id/payment-stage` (gated like the status-override
  dropdown, Admin/Superadmin only).

### 3. Client (`client/src/features/...`)

- **RBAC**: `HotelCheckInPage`/`HotelCheckoutPage`/`DaycareCheckInPage`/
  `DaycareCheckoutPage`'s `ALLOWED_VIEWER_ROLES` gained `Groomer`/
  `Pet Assistant` (superseded by the queue-merge below, same role set
  carried into `HotelQueuePage`/`DaycareQueuePage`).
  `staff/config/staffDashboard.config.ts`: Groomer and Pet Assistant
  dashboards gained Hotel Queue/Daycare Queue tiles.
- **Payment stage**: new `PaymentStageBadge` component
  (`booking/components/shared/PaymentStageBadge/`, mirrors
  `BookingStatusBadge`, reuses the pending/in-progress/paid color tokens).
  `booking.types.ts`/`booking.api.ts` mirror the server additions
  (`advancePaymentStage`, `overridePaymentStage`). `ReceptionistBookingsQueuePage.tsx`:
  every row now shows a Payment badge alongside the Status badge; an
  "Advance" button (visible whenever `payment_stage !== 'Paid'`) opens an
  inline "Advance payment / Normal onsite payment" prompt when Unpaid (new
  `activeAction` type `'advance-payment'`, mirrors the existing
  reschedule/cancel inline panels), or advances straight to Paid with one
  click when already Paid in Advance. Admin/Superadmin get a second
  `<select>` dropdown (payment_stage) next to their existing status
  dropdown. `BookingDetailsPage.tsx` also shows the Payment badge.
- **Queue redesign**: `HotelCheckInPage`/`HotelCheckoutPage` and
  `DaycareCheckInPage`/`DaycareCheckoutPage` are deleted. Replaced by
  `hotel/pages/HotelQueuePage/` (`HotelQueuePage.tsx` - role gate + Check
  In/Check Out tabs; `HotelCheckInPanel.tsx`/`HotelCheckoutPanel.tsx` - the
  former pages' bodies, unchanged logic, now taking `accessToken`/`role`/
  `branchId` as props instead of fetching their own; `HotelLegacyRedirects.tsx`)
  and the equivalent `daycare/pages/DaycareQueuePage/`. Checking a pet in
  switches the tab to Check Out with that stay/session preselected
  (in-page state, no navigation) instead of the old cross-route link.
  `hotel.routes.tsx`/`daycare.routes.tsx`: the old `/check-in` and
  `/checkout(/:id)` paths now redirect into `/queue?tab=...&stayId=...` (or
  `sessionId`) instead of disappearing, so `HotelBookingPicker`'s own
  "already checked in → go to checkout" link and any old bookmarks keep
  working. `staffDashboard.config.ts`: the two Hotel/two Daycare tiles per
  role collapsed into one "Hotel Queue"/"Daycare Queue" tile each.
- **Assigned-staff filter**: `ReceptionistBookingsQueuePage.tsx` gained an
  "Assigned" `<select>` (All / Assigned to me / No preference) next to the
  Service type filter, wired to the new `assignedStaffId` API param.

## Known limitations / follow-ups

- The payment_stage track and the existing `status`/Cashier-Checkout
  mechanisms are intentionally not reconciled (see "Why" above) - a
  booking can be `payment_stage: 'Paid'` and `status: 'Pending'`
  simultaneously, or vice versa. This is by design for this change, but a
  future pass may want to unify them.
- Grooming Queue and Consultation Queue were not restyled or given an
  assigned-staff filter (see "Why" above for the reasoning).
- `HotelCheckoutPanel`/`DaycareCheckoutPanel`, once reached via a
  preselected stay/session id, have no "choose a different stay/session"
  escape hatch back to the picker - this is unchanged, pre-existing
  behavior carried over from the original `HotelCheckoutPage`/
  `DaycareCheckoutPage` (not a regression introduced by this change).

## Round 2: retire the old status-level 'Paid', rename Advance to "Mark as Paid", modal prompt

Follow-up feedback after the first pass landed, live-testing the queue:

1. **`'Paid'` removed from `BookingStatus` entirely.** The old status
   lifecycle is now just Pending → In Progress → Completed (→ Cancelled/
   No-show) - payment is tracked exclusively via `payment_stage` now, with
   no overlap between the two. This retires the old status-level
   `markBookingPaid` action (Completed → Paid) and its route
   (`POST /bookings/:id/mark-paid`) entirely - the payment*stage track's own
   action is now the \_only* "Mark as Paid" action in the app.
2. **"Advance" button renamed to "Mark as Paid"** on the Bookings Queue, to
   match (there's no more old Mark as Paid for it to be confused with).
3. **The Unpaid → advance/onsite choice prompt is now a modal**, not an
   inline panel below the row - matches the look of the existing
   `ConfirmDialog` shared component (a new two-choice variant, since
   ConfirmDialog's single confirm/cancel shape can't express "pick one of
   two options").

### What changed (Round 2)

- `supabase/migrations/20260803083_m03_m08_remove_paid_booking_status.sql`:
  backfills any `status = 'Paid'` row's `payment_stage` to `'Paid'` first
  (preserving the fact it was settled), then recreates the `booking_status`
  enum without `'Paid'` (backfilling those rows' `status` to `'Completed'`),
  redefines the `bookings_staff_active_idx` partial index, and
  `CREATE OR REPLACE`s `get_staff_availability()` (Check 2's hardcoded
  status list also referenced `'Paid'`).
- `server/src/features/booking/booking.types.ts`: `BookingStatus` loses
  `'Paid'`; `BOOKING_STATUSES`/`ACTIVE_BOOKING_STATUSES`/
  `OVERRIDABLE_BOOKING_STATUSES` updated to match;
  `FINISHED_BOOKING_STATUSES` is now just `['Completed']`. Client
  `booking.types.ts` mirrors all of this.
- `server/src/features/booking/services/booking.service.ts`:
  `markBookingPaid` deleted. `completeBooking` no longer sets
  `status: 'Paid'` for an already-confirmed online payment - it now sets
  `status: 'Completed'` always, and additionally auto-advances
  `payment_stage` to `'Paid'` (+ `paid_at`) in that same case, preserving
  the "already paid online" auto-settle behavior via the new field instead
  of the old status value. `overrideBookingStatus` no longer touches
  `paid_at` at all (payment_stage owns that now) and its overridable set
  shrank to Pending/In Progress/Completed.
- `server/src/features/booking/booking.controller.ts` /
  `booking.routes.ts`: `markBookingPaidController` and
  `POST /bookings/:id/mark-paid` removed.
- `server/src/features/billing/services/lineItemSources.service.ts`,
  `server/src/features/hotel/services/hotelStay.service.ts` (+ client
  mirror `hotel/api/hotel.api.ts`), `server/src/features/hotel/
hotel.controller.ts`: every hardcoded `'Completed', 'Paid'`-style status
  list/check updated to drop `'Paid'`.
- `client/.../BookingStatusBadge/BookingStatusBadge.tsx` (+`.module.css`):
  the `Paid` status-badge mapping/class removed (payment now shows via the
  separate `PaymentStageBadge`, unaffected by this change).
- `client/.../ReceptionistBookingsQueuePage.tsx` (+`.module.css`): old
  `canMarkPaid`/`handleMarkPaid`/button removed entirely. The payment_stage
  button now reads "Mark as Paid" (was "Advance"). The Unpaid choice prompt
  moved from an inline per-row `activeAction` panel to a single modal
  rendered once outside the row list (`paymentAdvanceModalBooking`, derived
  from `activeAction` + a `bookings.find()` lookup), styled with new
  `.modalBackdrop`/`.modalDialog`/`.modalTitle`/`.modalBody`/`.modalActions`
  classes mirroring `ConfirmDialog`'s existing look.
- Test files updated to match: `booking.service.spec.ts`,
  `booking.validator.spec.ts`, `currentPrescription.service.spec.ts`,
  `careInstructions.service.spec.ts` (server);
  `BookingStatusBadge.spec.ts`, `AppointmentCard.spec.ts`,
  `ReceptionistBookingsQueuePage.spec.ts` (client) - all `status: 'Paid'`
  fixtures/assertions replaced or removed, `markBookingPaid` mocks swapped
  for `advancePaymentStage`, and a new test drives the modal (opens on
  Unpaid, no modal when already Paid in Advance).

### Round 2 verification

- `cd server && npx tsc --noEmit && npx vitest run` - 72 test files / 698
  tests, all passing.
- `cd client && npx tsc --noEmit && npx vitest run` - 117 test files / 528
  tests, all passing.
- Run `npx tsc --noEmit`/`npx vitest run` from **inside** `server/` or
  `client/` respectively, not from the repo root - running `npx vitest run`
  unscoped at the repo root picks up both projects' test files under one
  mismatched config and produces spurious failures (confirmed while
  verifying this round; not a real regression).
- Apply `20260803083_m03_m08_remove_paid_booking_status.sql` (after
  `...081`/`...082` from Round 1, in numeric order).
- Manual UI: open the Bookings Queue, confirm no row's Status badge ever
  shows "Paid" (only Pending/In Progress/Completed/Cancelled/No-show).
  Confirm the payment button reads "Mark as Paid" everywhere the old
  "Advance" label used to be. Click it on an Unpaid booking - confirm a
  centered modal (dimmed backdrop) appears instead of an inline panel under
  the row, with "Normal onsite payment" / "Advance payment" / "Cancel".
  Click it on a Paid in Advance booking - confirm it advances straight to
  Paid with no modal.

## Verification steps

### 1. Automated tests

- `cd server && npx tsc --noEmit && npx vitest run` - all passing
  (confirmed: booking 131/131, hotel+daycare+grooming 66/66).
- `cd client && npx tsc -b --noEmit && npx vitest run` - all passing
  (confirmed: hotel+daycare 38/38, booking 68/68, full suite 175/175
  including staff config).

### 2. Apply the migrations

Apply `20260803081_m05_m06_hotel_daycare_advance_roles.sql` then
`20260803082_m08_booking_payment_stage.sql`, in that order (independent of
each other, but keep numbering order). `supabase db push` (remote-linked
project) or however you normally apply migrations.

### 3. Confirm the schema (SQL Editor)

Open the Supabase dashboard → SQL Editor, paste in
`staff-queue-overhaul.sql` from this folder, and run each numbered
section. Expected results are noted inline as SQL comments.

### 4. Confirm the API surface (Postman)

Import `staff-queue-overhaul.postman_collection.json` from this folder.
Fill in `groomer_identifier`/`groomer_password` (a Groomer-role staff
login), `admin_identifier`/`admin_password` (Admin/Superadmin), and
`cashier_identifier`/`cashier_password` (Cashier). Fill `booking_id` with
a Hotel/Daycare booking id and `hotel_booking_id` as needed per request
description. Run requests in order, top to bottom.

Expected highlights:

- "Groomer: Hotel check-in" (previously 403) → now succeeds (or reaches
  business validation, not a role rejection).
- "Groomer: Daycare check-in" → same.
- "Cashier: Advance payment (choice=advance)" on an Unpaid booking → 200,
  `booking.payment_stage: "Paid in Advance"`.
- "Cashier: Advance payment (no choice)" on an already-"Paid in Advance"
  booking → 200, `booking.payment_stage: "Paid"`.
- "Cashier: Advance payment with no choice" on a still-Unpaid booking →
  400 (choice required).
- "Receptionist: Advance payment" on an already-Paid booking → 409.
- "Groomer: Override payment stage" (non-admin) → 403.
- "Admin: Override payment stage" → 200, any forward/backward value
  accepted.
- "List bookings assigned to me" (`assigned_staff_id=<own id>`) → only
  that staff member's assigned bookings.
- "List unassigned bookings" (`assigned_staff_id=unassigned`) → only
  bookings with `assigned_staff_id: null`.

### 5. Manual UI smoke test - RBAC

1. Log in as a Groomer. Sidebar/dashboard now shows "Hotel Queue" and
   "Daycare Queue" tiles (previously absent). Open Hotel Queue, check a
   pet in, confirm it succeeds and the page switches to the Check Out tab
   with that stay preselected.
2. Repeat as a Pet Assistant.
3. Log in as a Veterinarian or Cashier - confirm Hotel Queue/Daycare Queue
   are NOT reachable (redirected to `/staff/settings` if navigated to
   directly).
4. Log in as Receptionist/Admin - confirm Hotel Queue/Daycare Queue still
   work exactly as before (no regression).

### 6. Manual UI smoke test - payment stage

1. Open the Bookings Queue as a Cashier. Every row shows a "Payment:
   Unpaid" badge alongside the Status badge. Click "Advance" on a Pending
   Unpaid booking - confirm the "Advance payment / Normal onsite payment"
   prompt appears.
2. Click "Advance payment" - confirm the badge updates to "Payment: Paid
   in Advance" and the Advance button is still present (now single-click,
   no prompt).
3. Click "Advance" again - confirm it goes straight to "Payment: Paid"
   with no prompt, and the Advance button disappears.
4. On a different booking, click "Advance" → "Normal onsite payment" -
   confirm it jumps straight to "Payment: Paid" (skipping "Paid in
   Advance").
5. Log in as Groomer/Veterinarian - confirm the Payment badge is visible
   (read-only context) but no Advance button appears for them on the
   general Bookings Queue (role still gates the button per
   `BOOKING_MARK_PAID_ROLES`-equivalent, same as Mark as Paid).
6. Log in as Admin/Superadmin - confirm a second "Payment" `<select>`
   dropdown appears next to the Status dropdown; use it to move a booking
   backward from Paid to Unpaid, confirm it succeeds.
7. Open `BookingDetailsPage` for any booking - confirm the Payment badge
   shows next to the Status badge in the header.

### 7. Manual UI smoke test - queue redesign

1. Navigate directly to the old URL `/staff/hotel/check-in` - confirm it
   redirects to `/staff/hotel/queue` with the Check In tab active.
2. Navigate to `/staff/hotel/checkout` - confirm redirect to
   `/staff/hotel/queue` with Check Out active.
3. From the Hotel Queue's Check In tab, check in a pet that's already
   listed as "Already checked in" in the picker (if any) - click its "Go
   to checkout" link - confirm it still resolves correctly through the
   legacy redirect route.
4. Repeat steps 1-3 for Daycare (`/staff/daycare/check-in`,
   `/staff/daycare/checkout`).
5. Confirm Hotel Care Log (`/staff/hotel/care-log`, untouched by this
   change) still works normally.

### 8. Manual UI smoke test - assigned-staff filter

1. Open the Bookings Queue as any staff role. Confirm a new "Assigned"
   filter (All / Assigned to me / No preference) appears next to Service
   type.
2. Select "Assigned to me" - confirm only bookings with
   `assigned_staff_id` equal to your own staff id remain.
3. Select "No preference" - confirm only bookings with no assigned staff
   (e.g. a Hotel/Daycare booking, or a Grooming/Veterinary one still
   awaiting auto-assignment) remain.
4. Switch back to "All" - confirm the full filtered list returns.

### 9. Regression check - Start Consultation (the original bug report)

1. Open `/staff/veterinary/console` as a Veterinarian, hard-refresh the
   page, select a Pending consultation, click "Start Consultation" -
   confirm it transitions to "In Progress" as expected (this was
   confirmed working after a stale-build refresh during investigation; no
   code change was made for it, so this is a plain regression check).
