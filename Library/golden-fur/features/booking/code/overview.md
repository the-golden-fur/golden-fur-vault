---
title: Booking — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, booking]
project: golden-fur
---

The booking feature is the operational heart of Golden Fur: it's where a customer or receptionist picks a pet, branch, service(s), a date/time (plus staff or a cage), and confirms an appointment. It also owns the business rules layered on top — minimum-notice windows, down payments, reschedule fees, cancellation credit, and the admin screen that configures all of it.

**Part of:** [[M03-appointment-booking]] (also backs [[M09-policy-enforcement]] — its policy config, cancellation logging, and credit-review queue live in this same code)

## Client-side (`client/src/features/booking/`)

### Top-level files

- **`booking.types.ts`** — every shared type/enum for the feature: `BookingStatus`, `PaymentStatus`, `BookingSource` (Online/Walk-in), `PaymentScheme`, `PolicyConfiguration`, the full `Booking`/`BookingGroup`/`BookingDetails` shapes, and role lists like `BOOKING_MARK_PAID_ROLES`. This is the client's mirror of the server's own `booking.types.ts`.
- **`bookingConfirmation.ts`** — `deriveBookingConfirmationState()` collapses a booking's independent `status`/`payment_status`/`booking_source` fields into one label a receptionist actually cares about (Unconfirmed, Confirmed, In service, Completed, Expired, Cancelled, No-show). It's a pure derivation, never stored, so it can never drift from the underlying fields.
- **`bookingErrors.ts`** — `friendlyBookingError()` rewrites a raw server error into something a user can read: it hides internal database-sounding messages and adds a helpful hint when the rejection looks like a slot/capacity conflict.
- **`booking.routes.tsx`** — wires up every booking URL (`/portal/book`, `/portal/bookings`, `/staff/bookings/*`, `/staff/assessment/queue`, `/staff/admin/maintenance/policies`) behind the customer or staff auth guard. `CustomerBookingFlowPage` is mounted twice — once for customer self-service, once for receptionist walk-ins — and the component itself figures out which mode it's in from the URL.

### pages/

- **`CustomerBookingFlowPage.tsx`** — the big one: a multi-step wizard (Branch → Customer [staff only] → Pet → Service Type → Services → Booking Type [staff only] → Date & Time/Staff/Cage → Care Instructions [Hotel/Daycare] → Your Bookings → Promos & Coupons → Review). Same component serves customers booking themselves and receptionists booking walk-ins/phone-ins. Supports a "multi-booking checkout" — several independent bookings (different pets/categories/times) bundled into one cart that shares a single discount/promo/payment decision (submitted via `createBookingGroup`). Autosaves the in-progress draft to `localStorage` so a closed tab doesn't lose it. Calls `createBooking`/`createBookingGroup` on submit.
- **`CustomerBookingsPage.tsx`** — "My bookings" list for a logged-in customer. Supports Reschedule (re-opens the Slot/Staff Picker scoped to the existing booking) and Cancel (always behind an explicit `ConfirmDialog`, so a stray click never actually cancels). Payment itself moved to a separate Transactions page.
- **`ReceptionistBookingsQueuePage.tsx`** — the branch-wide queue every staff role (except Cashier, who gets no "New booking" button) uses to see today's (or a filtered range of) bookings, in a list or month/week calendar view. Read-only for status now — Start/Complete moved into each category's own execution queue — but still owns View details, Reschedule, Cancel, Check-In (Pending → In Progress for a walk-in-eligible Online booking), and Extend Stay (Hotel only, staff-only).
- **`AssessmentQueuePage.tsx`** — the dedicated queue for the "Assessment" category (Initial Assessment/Reassessment bookings, which have no staff/capacity contention). Clicking a row opens `AssessmentModal` to record a pet's weight/coat type, then advances the booking straight to Completed.
- **`CreditReviewQueuePage.tsx`** — for branches in "Manual" credit-review mode: shows every cancellation still awaiting a staff decision on whether the down payment converts to credit, via `CreditReviewCard`.
- **`BookingDetailsPage.tsx`** — read-only staff-facing "View details" page for one booking, rendering the shared `BookingDetailsView`.
- **`PolicyConfigurationPage.tsx`** — Admin/Superadmin-only form (Settings > Config > Policies) covering every `policy_configurations` field: notice periods, lunch break, reschedule fee, downpayment, cancellation credit + its review mode, credit expiry, staff concurrency, and email notification toggles. Editable system-wide or per branch.

### components/

- **`AssessmentModal.tsx`** — modal used by `AssessmentQueuePage` to capture a pet's weight (any unit, converted to kg) and coat type; weight class is derived from admin-configured cut-offs, with a manual override.
- **`SlotPicker.tsx`** — the date/time picker. Two render modes (`customer`/`staff`) off one component: customers see available/unavailable only, staff also see a 3-color coverage overlay. Handles the walk-in "locked to now" mode, floors the calendar to the branch's minimum-notice window, and can exclude windows another booking in the same multi-booking cart already occupies for this pet.
- **`TimeSlotInput.tsx`** — the hybrid `<input type="time">` + dropdown of real slots that `SlotPicker` renders; a typed time that doesn't land on an actual bookable slot is flagged rather than silently accepted.
- **`StaffPickerList.tsx`** — searchable/sortable grid of eligible staff (plus "No preference") for a branch/category/time window; greys out a staff member already claimed too many times by other bookings in the same cart.
- **`CagePickerList.tsx`** — interactive (staff-only) cage picker for Hotel bookings, filtered to the pet's own pet type; a size mismatch is shown but disabled for a customer-restricted booking.
- **`CageAssignmentStatus.tsx`** — the customer-facing read-only counterpart: just answers "is a cage available for my pet" with no picking.
- **`CustomerPicker.tsx`** — the receptionist's searchable/sortable list of existing customers used at the "Customer" step of a walk-in booking; can be restricted to only customers a Veterinarian has actually treated.
- **`PromoCouponMultiSelect.tsx`** — searchable, sortable checkbox list combining applicable promos and the customer's own unredeemed coupons, respecting a branch's promo cap and showing a live capped running total.
- **`BookingStepper.tsx`** — the step-progress bar; steps before the furthest-reached one are clickable to go back without losing later selections.
- **`BookingCountBadge.tsx`** — small "N bookings in this checkout" indicator for the multi-booking cart.
- **`NightTabs.tsx`** — tab strip for a Hotel stay's per-night care instructions (or the read-only equivalent on the details view).
- **`BookingDetailsModal.tsx`** / **`BookingDetailsView.tsx`** — the modal wrapper (customer "View details") and the shared presentational view it (and `BookingDetailsPage`) render: schedule, items, Hotel care instructions, pricing, payments, and status timeline, all off one hydrated `GET /bookings/:id/details` response.
- **`CreditReviewCard.tsx`** — one pending cancellation on the Credit Review Queue, with Approve/Deny actions.
- **`PayMongoFeeNotice.tsx`** — placeholder notice shown when an online payment method is chosen; explicitly documented as illustrative copy, not a computed fee.
- **`shared/BookingStatusBadge.tsx`**, **`shared/PaymentStatusBadge.tsx`**, **`shared/BookingConfirmationBadge.tsx`** — one shared pill component each for the raw service-lifecycle status, the independent payment rollup, and the receptionist-facing "Unconfirmed/Confirmed/..." derived label, reused across every booking-related screen.

### api/

- **`booking.api.ts`** — every booking HTTP call: create/list/get a booking (and its hydrated details), day availability, the catalog read-through, staff/cage picker options, reschedule/cancel, extend-stay, pay/balance-payment, pet-conflict and slot-conflict lookups, and the credit-review queue actions.
- **`policy.api.ts`** — reads and updates `policy_configurations`, plus `resolveEffectivePolicy()` (branch override wins whole-row over the system default) mirrored from the server.

### utils/

- **`applyPromoCap.ts`** — client mirror of the server's promo-cap math, used to preview a correctly capped discount total live as the customer checks boxes.
- **`hotelNights.ts`** — derives the list of calendar nights for a Hotel stay and formats a short label for each, shared by `NightTabs` and the wizard's incomplete-row banner.

## Server-side (`server/src/features/booking/`)

### Controller & routes

- **`booking.controller.ts`** — one thin controller per endpoint: parses the request with a Zod validator, calls the matching service function, and maps thrown errors (with a `statusCode`) to an HTTP response.
- **`booking.routes.ts`** — mounts every route. Booking create/read/reschedule/cancel are open to both customers and staff (ownership is checked inside the services); the policy-configuration surface is staff-read/Admin-write; Start/Complete are open to any staff role except Cashier; the status-override PATCH and Credit Review Queue are further role-restricted.

### Service — core booking lifecycle

- **`booking.service.ts`** — the largest and most important file. `createBooking()` runs the whole pipeline for a single booking: resolve the acting customer, run the Veterinary-branch-eligibility guard first (fail fast), price every selected service/package (`resolveBookingItems`/`resolveServicePrice`/`resolvePackagePrice`, size/coat pricing matrix aware, with a pet-type fixed-price override), resolve any discount/promo/coupon (`resolveDiscountAndPromos`), compute the down payment against the _discounted_ total (skipped entirely for Walk-in bookings), resolve staff assignment (`resolveStaffAssignment` — auto-assign is a random pick among eligible staff, not always the same person), run the authoritative Hotel/Daycare capacity check, insert the row, then re-verify capacity after insert (`confirmCapacityAfterInsert`) to break ties between two simultaneous submissions for the last slot. Also holds `listBookings`/`getBookingById` (which apply the lazy down-payment-expiry and no-show transitions on every read, since there's no cron job), `startBooking`/`completeBooking`/`overrideBookingStatus`, and `recomputeBookingPaymentStatus` — the function every payment path calls after a transaction settles, which re-checks capacity for a booking that held no slot while unpaid and fires the deferred "booking confirmed" alerts.
- **`bookingGroup.service.ts`** — `createBookingGroup()`, the multi-booking-checkout version of the above: resolves each sub-booking's pricing/staff/cage independently (nothing is inserted until every one has been resolved), tracks in-request "claims" so two sub-bookings in the _same_ cart can't double-book the same staff/cage/pet window before either exists in the database, then resolves ONE shared discount/promo/down-payment decision against the combined total and inserts every member booking under one new `booking_groups` row.
- **`bookingDetails.service.ts`** — `getBookingDetails()` assembles the fully-hydrated view one booking's "View details" screen needs (branch/pet/owner names, item names, assigned staff, cage, discount/promo names, the shared group row if any, and the payment list — withheld for staff roles outside billing).
- **`bookingNotifications.service.ts`** — every notification/email sender for the feature (`booking_confirmed`, the combined multi-booking confirmation email, `booking_rescheduled`, `staff_assigned`, `booking_slot_conflict`, `booking_cancelled`); every function is wrapped so a notification failure never fails the booking action that triggered it.

### Service — slots, capacity, staff & cages

- **`availability.service.ts`** — `getDaySlots()` generates a day's worth of candidate time slots from the branch's operating hours (with lunch break and minimum-notice window filtered out) and checks each one's real availability — the same read the Slot Picker calls ahead of submission. Also resolves the branch's open/close window and which walk/play time-of-day bands actually fall inside operating hours.
- **`capacity.service.ts`** — the authoritative per-category capacity check (`checkCapacity`): staff-count based for Grooming/Veterinary, cage-count based by size for Hotel, session-count based for Daycare. `confirmCapacityAfterInsert` re-runs the same logic after a row lands, to deterministically pick a winner when two submissions raced for the last slot.
- **`staffPicker.service.ts`** — `resolveEffectivePolicy()` (the single place that resolves a branch override vs. the system-default policy row) plus everything policy-related: minimum-notice lead-time assertions for new bookings and reschedules, the Staff Picker options endpoint, random "no preference" auto-assignment, and `updatePolicyConfiguration()` (which also retroactively re-stamps existing credit-expiry dates when that policy setting changes).
- **`cagePicker.service.ts`** — the Hotel-only cage picker: whether it's enabled, the filtered (by pet type) options list, re-verifying a specific preference at confirmation time, and the customer-facing read-only "is a cage available" check.
- **`veterinaryEligibility.service.ts`** — the actual server-side enforcement that Veterinary bookings only happen at a vet-eligible branch, and that a Veterinarian can only book a customer they've actually treated.

### Service — change & money

- **`reschedule.service.ts`** — `rescheduleBooking()`: checks the configured notice period against the booking's _current_ time (Strict blocks, Soft flags), separately asserts the _new_ slot clears the same minimum-notice floor a fresh booking would, re-verifies staff/capacity for the new window, calculates any reschedule fee, and writes a cancellation_logs row either way.
- **`rescheduleFee.service.ts`** — pure function `calculateRescheduleFee()`: flat or percentage fee once the configured free-reschedule allowance is used up.
- **`cancellation.service.ts`** — `cancelBooking()`: an unmet notice period never blocks a cancellation (unlike reschedule) — it only decides whether the paid amount converts to account credit or is forfeited. In "Manual" credit-review mode it instead queues the decision for a staff member.
- **`cancellationLog.service.ts`** — writes/patches the `cancellation_logs` audit row every cancellation or reschedule produces, regardless of outcome.
- **`creditReview.service.ts`** — the Credit Review Queue backend: lists pending manual-review cancellations with a preview of what approving would credit, and `decideCreditReview()` actually issues the credit on approval (recomputed fresh, at today's policy rate).
- **`extendStay.service.ts`** — staff-only `extendHotelStay()`: bumps a Hotel booking's `scheduled_end` and each item's price proportionally, then reconciles the added charge onto an existing open balance transaction or creates a new one.
- **`catalog.service.ts`** — read-through for the customer-facing booking flow to the staff-only maintenance catalog (services/packages/promos, plus a resolved pet-type fixed price and the promo cap), since the customer session can't read those tables directly.

### Types & validators

- **`booking.types.ts`** — the server's canonical types and role lists (mirrored, not shared, by the client's own copy): `BookingStatus`, `PaymentStatus`, `BookingSource`, the full `Booking`/`BookingGroup`/`PolicyConfiguration`/`BookingDetails` shapes, and constants like `ACTIVE_BOOKING_STATUSES` and the `SLOT_HOLD_PAID_OR_FILTER` predicate that excludes an unpaid "pencil booking" from capacity counts.
- **`modules/validators/booking.validator.ts`** — every Zod schema: `createBookingValidator`/`createBookingGroupValidator` (item shape, no duplicate services/promos, Hotel/Daycare-only `hotel_preferences`), reschedule/cancel/extend-stay payloads, the policy PATCH (with cross-field rules like "downpayment type and amount must be given together"), and every query-string validator for availability/catalog/staff-picker/list-bookings.

## How it connects

The client wizard (`CustomerBookingFlowPage`) walks a customer or receptionist through picking a pet/branch/service(s)/time, then calls `POST /bookings` (or `/bookings/groups` for a multi-item cart) into `booking.service.ts`'s `createBooking`/`bookingGroup.service.ts`'s `createBookingGroup`. Those touch the `bookings`, `booking_items`, `booking_promo_selections`, and (for a cart) `booking_groups` tables, read the catalog from [[M13-maintenance-packages-services-promos]], apply discounts from [[M12-category-level-discounts]], and feed the execution queues in [[M04-grooming-management]] through [[M07-health-veterinary-management]] once a booking is confirmed. Reschedule/cancel route through [[M09-policy-enforcement]]'s notice-period and fee rules, and a qualifying cancellation posts a credit to [[M10-credit-balance-management]]. `createBooking` also emits the booking's first `booking_payment` transaction, settled later on the Transactions page ([[M08-04-recording-a-counter-payment]]). See [[M03-01-new-appointment-booking]] and [[M03-02-multi-item-booking-pricing]] for the step-by-step workflows.
