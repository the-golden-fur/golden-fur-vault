---
title: "M03 · Appointment & Booking"
date: 2026-08-29
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M03 · Appointment & Booking

**Layer:** Foundation
**Code:** `features/booking` (client + server) — also hosts [[M09-policy-enforcement|M09]]'s policy config and cancellation/reschedule logging
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The operational core: booking creation, the Slot Picker, the Staff
Picker, the Cage Picker, capacity enforcement, and reschedule/cancel.

## Multi-item bookings

A single booking can hold several services/packages from one merged,
checkbox-based selection step open to every service category. Each line
is its own `booking_items` row (service _or_ package, never both),
snapshotting `price_at_booking`/`duration_minutes_at_booking` so later
catalog price changes never retroactively touch an existing booking.
Downpayment (see below) is resolved once per transaction against the
whole booking, so it no longer restricts which items can be combined.

## Merged Date/Time + Staff step

A hybrid text/dropdown time input (constrained to branch operating
hours, can't commit a time in the past) is followed immediately by the
available-staff list, which re-fetches on date/time change. Hotel and
Daycare have no staff assignment — they show the time input plus a Cage
Picker instead. Choosing "No preference" auto-assigns **randomly** among
eligible available staff (`staffPicker.service.ts` —
`pickRandomAvailableStaff`/`autoAssignStaff`, previously deterministic
first-alphabetically) — shared by Grooming ([[M04-grooming-management|M04]]) and
Veterinary ([[M07-health-veterinary-management|M07]]) staff assignment, resolved here at booking
creation rather than in either execution feature's own code.

## Cage Picker

For Hotel bookings: a list of Available cages grouped by size, plus a
"No preference" default. Stored on `bookings.preferred_cage_id` — it's
advisory only, re-validated at confirmation, and the real assignment
happens at Hotel check-in ([[M05-pet-hotel-boarding-management|M05]]). Currently only ever enabled for
Hotel regardless of the Service Types config flag meant to govern it
(see [[M13-maintenance-packages-services-promos|M13]]).

## Booking-time discounts and promos

A staff member can apply a standing discount (Senior/PWD/custom,
restricted to money-handling roles who verify the ID onsite) and any user
can apply an eligible promo, with a live running total before either is
confirmed. This is a lock-in: `selected_discount_id`/`selected_promo_id`
and `discount_amount`/`promo_amount` snapshot the applied values.
`total_price` stays the pre-discount sum of `booking_items`. The old
**Cash-only** restriction on the discount picker went away with the
payment/transactions rework — no payment method is chosen at booking time
any more, it's picked per transaction later.

## Lunch break

A fixed daily window (default 12:00–13:00, configurable per branch/
system-wide via [[M09-policy-enforcement|M09]]) blocks a _starting_ slot inside it for every
category; slots immediately before/after remain available.

## Capacity rules

Hotel = cage-count-based. Daycare = session-count-based per branch
(shares Hotel's stays table — see [[M06-daycare-management|M06]]). Grooming = groomer-count-
based. Veterinary = staff-count-based (Makati only). Overbooking is
blocked system-wide with no manual override.

## Online vs. walk-in booking (`booking_source`)

`bookings.booking_source` (`'Online'` | `'Walk-in'`, default `'Online'`,
added in #122) is an explicit flag — **not** a same-day-vs-future time
comparison. `'Online'` is the only value a customer can send; `'Walk-in'`
is receptionist-only (403 otherwise) and is chosen via an Online/Walk-in
toggle on the booking wizard's availability step. A walk-in locks the slot
to the next available time today, **skips the down payment policy entirely**
(see below), and is created straight at `In Progress` with `started_at` set;
an online booking is created `Pending` and a receptionist hits **Check In**
on the Bookings Queue when the customer arrives. The Grooming/Veterinary
execution queues vivify only `In Progress` bookings, so a checked-in online
appointment and a fresh walk-in look identical there.

## Downpayment (per-transaction, online only)

A single policy field per branch (or system-wide default), owned by
[[M09-policy-enforcement|M09]]: `downpayment_enabled`, `downpayment_type`
(Flat/Percentage), `downpayment_amount`, `downpayment_hold_hours`. Resolved
once at booking creation against the whole transaction's **discounted net
total** (after any discount/promo — advisor fix) — not a per-catalog-item
flag, and not restricted to any category. **It applies to `booking_source
= 'Online'` bookings only** — `createBooking` guards the whole resolution
with `if (bookingSource === 'Online')`, so a walk-in never calls
`resolveDownpaymentPolicy` and `downpayment_required` stays `false` (the
customer/pet is already at the counter, paying in full).

### Down-payment slot gate (advisor addendum A1–A4)

When the down payment is enabled, an Online booking that hasn't paid any
of it is a **"pencil booking"**: created `Pending`, `payment_status =
'Pending'`, but it **reserves no capacity/staff-time slot** — the capacity
queries and `get_staff_availability()`'s Check 2 exclude
`downpayment_required AND payment_status = 'Pending'` rows (retargeted from
`payment_stage = 'Unpaid'` by migration `20260901156`), so the slot stays
bookable by other customers. `createBooking` skips the pre/post-insert
capacity checks for it. It also carries a `downpayment_due_at`
(`now + downpayment_hold_hours`, default 24h); once that passes,
`applyDownpaymentExpiry` (a lazy read-time sweep, No-show precedent) flips
it to `Cancelled`. Settling the first `booking_payment` transaction turns
it into a real reservation. Both payment paths run
`applyFirstBookingPaymentSideEffects`: it re-checks capacity and sends the
deferred `booking_confirmed` / `staff_assigned` alerts. The customer webhook
path 409s and rolls the payment back on a capacity conflict; the staff
counter-payment path keeps the payment and leaves the booking overbooked for
staff to reschedule (see [[M08-04-recording-a-counter-payment|M08-04]]). A still-unpaid pencil
booking is excluded from the operational queues
([[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]])
but stays visible in the customer's booking list, the Bookings Queue, and
the Transactions page ([[M08-sales-billing|M08]]).

## Booking status lifecycle

`bookings.status` is a five-value enum, fully automatic — no manual
"staff confirms" step. An `'Online'` booking starts `Pending`; a
`'Walk-in'` starts `In Progress` (see "Online vs. walk-in booking" above):

```
Pending → In Progress → Completed
              │
              ├── Cancelled
              └── No-show (automatic, lazy, read-time)
```

"Paid" was retired from this enum on 2026-08-03. Payment lives on an
**independent** `bookings.payment_status` field — `Pending → Partially
Paid → Fully Paid`, the **same enum as `transactions.payment_status`**
(the bespoke `payment_stage` enum was dropped in the 2026-09-01
payment/transactions rework, migration `20260901150`). Status and payment
status can sit at different points independently (e.g. Completed +
Pending).

- `payment_status` is **not** advanced by a dedicated action any more —
  it is a **rollup** of the booking's `booking_payment` transactions,
  recomputed by `settle_transaction()` (SQL) / `recomputeBookingPaymentStatus`
  (app) every time one settles. Payment is collected **per transaction**
  on the Transactions page ([[M08-04-recording-a-counter-payment|M08-04]]);
  no payment method is taken at booking creation.
- No-show is a **lazy, read-time transition** — a Pending booking whose
  scheduled time has passed and was never Started flips to No-show the
  next time it's read (there's no scheduled-job infra).
- A booking whose scheduled time has passed can no longer be
  Rescheduled or Cancelled, regardless of status.
- Admin/Superadmin have a status-override action (forward or backward,
  both fields) to correct mistakes.

## Bookings Queue (Payments Queue folded in)

The **Payments Queue was removed** in the 2026-09-01 rework. The
Receptionist Bookings Queue (`ReceptionistBookingsQueuePage`, branch-wide,
all-categories, current day) absorbed its non-payment responsibilities and
is **no longer read-only for status**: it now owns Start/Complete, the
Misc-category (Initial Assessment/Reassessment) Start/Complete plus
pet-assessment capture, and the Admin/Superadmin status override.
Recording a payment moved to the per-transaction **Transactions page**
([[M08-04-recording-a-counter-payment|M08-04]]). Each category's own
execution queue ([[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]])
still offers Start/Complete too.

## Booking safeguards

A pet with any unresolved booking (Pending/In Progress, any category)
can't be booked again — the pet-selection step disables the conflicted
pet and links to the existing booking. Replaced an earlier, narrower
check that only covered Hotel/Daycare.

## Slot Picker

Customers see available time slots only (no staff names/schedule
detail). A slot is available only if it's within operating hours,
outside the lunch break, at least one eligible staff member is free, and
capacity isn't exhausted.

The browsable date range starts at the branch's **minimum-notice
lead time** (`policy_configurations.notice_period_days`, default 3),
not today: `getDaySlots` returns nothing for any date inside the notice
window and the picker floors its calendar to `min_notice_days` (reported
on `GET /bookings/availability`), auto-advancing past the window on
first load. The same floor is asserted by `createBooking` and by
`rescheduleBooking` for the new slot (422). Walk-ins bypass it. See
[[M09-policy-enforcement|M09]].

## Workflows

- [[M03-01-new-appointment-booking|New Appointment Booking]]
- [[M03-02-multi-item-booking-pricing|Multi-Item Booking Selection & Pricing]]

## Relationship to other modules

Depends on [[M01-staff-authentication-access-control|M01]] (availability, hours, lunch break), [[M02-customer-portal-pet-management|M02]] (customer/pet
data), [[M13-maintenance-packages-services-promos|M13]] (catalog, promos, Service Types), and [[M09-policy-enforcement|M09]]
(downpayment policy, minimum-notice lead-time floor). Feeds [[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]] (execution), [[M08-sales-billing|M08]] (billing, `payment_status` rollup),
[[M09-policy-enforcement|M09]] (policy evaluation on change), [[M10-credit-balance-management|M10]] (credit on qualifying
cancellation), and [[M11-notification|M11]]. `createBooking` also emits the
first `booking_payment` transaction settled in
[[M08-04-recording-a-counter-payment|M08-04]].

## Open items

- Merging the remaining execution queue surfaces
  (Grooming/Hotel/Daycare/Veterinary) into the Bookings Queue — which
  already absorbed the Payments Queue — is still an open design question.
- `cage_picker_enabled` on Service Types has no effect outside Hotel.
- On a capacity conflict at first payment, the staff counter-payment /
  pay-with-credit paths keep the payment and leave the booking overbooked
  for staff to reschedule (unlike the webhook path, which 409s and rolls
  back) — see [[M08-04-recording-a-counter-payment|M08-04]].
