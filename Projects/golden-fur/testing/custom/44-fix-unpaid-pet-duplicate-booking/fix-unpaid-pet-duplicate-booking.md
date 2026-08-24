# Fix: pet becomes bookable again while its last booking is still unpaid

Branch: `bug/44-fix-unpaid-pet-duplicate-booking`

## The request, verbatim

> Fix being able to make another booking for pet X, when pet X booking is
> still not paid

(One item split out of a larger bundled request - see "Scope note" below.)

## Scope note

The original message also asked for three other, unrelated changes: adding
the sidebar sort control to customer/other staff roles, a "number of
promos" cap on the Promo Cap Configuration page, and a full "..."
actions-menu/modal rework of the Services/Service Types/Packages admin
pages. Two of those (the promos cap and the services/packages rework) were
already flagged as their own future requests in the verification doc for
`41-fix-service-downpayment-toggle`, the last time this same bundle was
submitted. Given how differently sized and unrelated these four items are,
and that this repo's history is one PR per cohesive feature, only the bug
fix below was implemented in this pass; the other three are deferred to
their own future requests.

## Root cause

Duplicate-booking prevention lives in `listPetBookingConflicts`
(`server/src/features/booking/services/booking.service.ts`), which backs
`GET /bookings/pet-conflicts`. The booking flow's pet-selection step
(`CustomerBookingFlowPage.tsx`, used by both customer self-service and
staff-assisted booking) calls this endpoint and disables any pet it flags,
with a link to "go manage" the conflicting booking instead.

The query only ever flagged bookings whose `status` was `Pending` or
`In Progress` (`UNRESOLVED_BOOKING_STATUSES`). `payment_stage` is a fully
independent column from `status` - a booking can sit at `status: 'Completed'`
while `payment_stage` is still `'Unpaid'` (this happens on every pay-at-counter
booking: `completeBooking` only auto-advances `payment_stage` to `'Paid'`
when the booking was paid online in advance; everything else lands on
`Completed` still `Unpaid`, waiting for a cashier to collect payment). The
moment a booking's `status` flipped to `Completed`, `listPetBookingConflicts`
stopped flagging that pet - even though it had never been paid - so the
customer (or a receptionist booking on their behalf) could immediately start
a brand-new booking for that pet.

## What changed

### Server

- `server/src/features/booking/services/booking.service.ts`
  - `listPetBookingConflicts` now also queries `status: 'Completed'` rows
    (alongside the existing `Pending`/`In Progress` ones) and additionally
    selects `status`/`payment_stage`.
  - A `Completed` row only counts as a conflict when `payment_stage` is
    still `'Unpaid'` - a Completed booking that's `'Paid'` or
    `'Paid in Advance'` does **not** block (the service happened and was
    settled, same as before).
  - `Cancelled`/`No-show` bookings are still never fetched at all and never
    block, regardless of `payment_stage` - no service was rendered on them
    and this codebase has no cancellation/no-show fee to collect.
  - Everything else about the function is unchanged: still one conflict per
    pet (the earliest-scheduled unresolved row), still category-agnostic,
    still gated the same way for staff vs. customer requesters.

### Client

No client changes were needed. `CustomerBookingFlowPage.tsx`'s conflict
UI ("Already has an unresolved booking" / "Resolve or manage that booking
before starting a new one for this pet") already reads generically off
whatever `GET /bookings/pet-conflicts` returns, so a newly-flagged
Completed-but-unpaid booking is disabled and links to "Go to My Bookings" /
"View that booking" exactly like a Pending one always did.

## Known boundary (not changed in this pass)

This check has always been - and remains - advisory/UI-level only:
`createBooking` itself does not call `listPetBookingConflicts` or reject a
booking server-side when the pet has a conflict. This was already true for
the pre-existing Pending/In Progress case, so this fix doesn't change that
architecture, only which bookings the advisory list surfaces. A staff
member (or a direct API call) could always create a booking for a
"conflicted" pet on purpose - e.g. a receptionist collecting payment for an
old booking while creating a new one in the same visit - and still can.
Turning this into a hard server-side block was out of scope for this
bug-report-sized fix.

## Verification

### 1. Client - Customer Booking Flow

1. As a customer (or as a receptionist in staff-assisted/walk-in mode), find
   a pet whose only booking is `Completed` with `payment_stage: 'Unpaid'`
   (or create one - see step 2 below via the cashier/receptionist tools, or
   the Postman collection).
2. Open the booking flow and reach the pet-selection step.
3. Confirm that pet is shown disabled/read-only with "Already has an
   unresolved booking", the same treatment a Pending booking gets.
4. Click it and confirm the "Resolve or manage that booking before starting
   a new one for this pet" prompt appears, linking to the existing booking.
5. As a cashier/receptionist, mark that old booking's payment as Paid (or
   Paid in Advance), then reload the booking flow and confirm the pet is
   now selectable again.

### 2. Reproducing the bug scenario manually (staff side)

1. As Admin/Superadmin/Receptionist, create or find a Hotel/Daycare/Grooming
   booking for a test pet with no online payment method (so it stays
   pay-at-counter).
2. Advance it through Start -> Complete (Bookings Queue actions, or
   `POST /bookings/:id/start` then `/complete`). Do **not** mark it as paid.
3. Confirm the booking now shows `status: Completed`,
   `payment_stage: Unpaid`.
4. Before the fix: that pet would be immediately bookable again. After the
   fix: repeat step 1 above and confirm it's blocked.

### 3. API-level checks (Postman)

See `fix-unpaid-pet-duplicate-booking.postman_collection.json` in this
folder.

1. Import the collection, fill in `base_url`, a customer login
   (`customer_email`/`customer_password`) and their `customer_id`, a
   Receptionist login at the same branch, `branch_id`, a `pet_id` owned by
   that customer, an active Hotel `hotel_service_id`, a `cage_id` available
   at that branch, and a `scheduled_start`/`scheduled_end` window.
2. Run requests in order, top to bottom:
   - Request 3 creates a pay-at-counter Hotel booking (no `payment_method`
     sent) and confirms it starts `payment_stage: Unpaid`.
   - Request 4 confirms the pet is already flagged while the booking is
     `Pending` (pre-existing behavior, unchanged by this fix).
   - Requests 5-6 advance it through Start -> Complete as the receptionist
     and confirm it lands on `status: Completed` with `payment_stage`
     still `Unpaid`.
   - **Request 7 is the fix under test**: confirms the pet is _still_
     flagged in `GET /bookings/pet-conflicts` now that the booking is
     Completed-but-Unpaid - before the fix, this request's conflict list
     would have been empty for that pet at this point.
   - Request 8 has the receptionist mark the booking Paid
     (`payment-stage/advance`, `choice: "onsite"`).
   - Request 9 confirms the pet is no longer flagged once paid.

## Test suites

- `server`: `npm run test` (from `server/`) - all 828 tests passing,
  including 2 new cases in `booking.service.spec.ts`
  (`listPetBookingConflicts` describe block): a Completed-but-Unpaid
  booking is flagged as a conflict, and a Completed booking that's Paid (or
  Paid in Advance) is not. The pre-existing Pending/In Progress test cases
  were also updated to include explicit `status`/`payment_stage` fields on
  their mocked rows, since the function now reads both.
- `client`: no changes made, no new tests needed.
