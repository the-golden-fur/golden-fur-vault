---
title: "M03 · Appointment & Booking"
date: 2026-08-26
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
cash-only, staff-verified ID) and any user can apply an eligible promo,
with a live running total before either is confirmed. This is a
lock-in: `selected_discount_id`/`selected_promo_id` and
`discount_amount`/`promo_amount` snapshot the applied values.
`total_price` stays the pre-discount sum of `booking_items`.

## Lunch break

A fixed daily window (default 12:00–13:00, configurable per branch/
system-wide via [[M09-policy-enforcement|M09]]) blocks a _starting_ slot inside it for every
category; slots immediately before/after remain available.

## Capacity rules

Hotel = cage-count-based. Daycare = session-count-based per branch
(shares Hotel's stays table — see [[M06-daycare-management|M06]]). Grooming = groomer-count-
based. Veterinary = staff-count-based (Makati only). Overbooking is
blocked system-wide with no manual override.

## Downpayment (per-transaction)

A single policy field per branch (or system-wide default), owned by
[[M09-policy-enforcement|M09]]: `downpayment_enabled`, `downpayment_type`
(Flat/Percentage), `downpayment_amount`. Resolved once at booking
creation against the whole transaction's `total_price` — not a
per-catalog-item flag, and not restricted to any category. When paid
online, the payer chooses downpayment-only or pay-in-full, setting
`payment_stage` accordingly. A Pending/In Progress booking that still
needs its downpayment and is Unpaid is excluded from the operational
queues ([[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]]) until paid, but stays visible in the
customer's booking list, the Bookings Queue, and the Payments Queue
([[M08-sales-billing|M08]]).

## Booking status lifecycle

`bookings.status` is a five-value enum, fully automatic — no manual
"staff confirms" step:

```
Pending → In Progress → Completed
              │
              ├── Cancelled
              └── No-show (automatic, lazy, read-time)
```

"Paid" was retired from this enum on 2026-08-03. Payment now lives on
an **independent** `bookings.payment_stage` field: `Unpaid → Paid in
Advance → Paid`. Status and payment stage can sit at different points
independently (e.g. Completed + Unpaid).

- `payment_stage` advances via its own action (an "Advance" action),
  restricted to money-handling roles: Superadmin, Admin, Supervisor,
  Receptionist, Cashier.
- No-show is a **lazy, read-time transition** — a Pending booking whose
  scheduled time has passed and was never Started flips to No-show the
  next time it's read (there's no scheduled-job infra).
- A booking whose scheduled time has passed can no longer be
  Rescheduled or Cancelled, regardless of status.
- Admin/Superadmin have a status-override action (forward or backward,
  both fields) to correct mistakes.

## Bookings Queue / Payments Queue split

The Receptionist Bookings Queue (branch-wide, all-categories, current
day) is **read-only** for status/payment: view, Reschedule, Cancel, New
booking, nothing else. Every status/payment-advancing action moved to
dedicated screens — Start/Complete on each category's own execution
queue ([[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]]), and a Payments Queue ([[M08-sales-billing|M08]]) that owns
payment-stage advancement, the Admin/Superadmin override for every
category, and all actions for the Misc category (which has no execution
queue of its own).

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

## Workflows

- [[M03-01-new-appointment-booking|New Appointment Booking]]
- [[M03-02-multi-item-booking-pricing|Multi-Item Booking Selection & Pricing]]

## Relationship to other modules

Depends on [[M01-staff-authentication-access-control|M01]] (availability, hours, lunch break), [[M02-customer-portal-pet-management|M02]] (customer/pet
data), [[M13-maintenance-packages-services-promos|M13]] (catalog, promos, Service Types), and [[M09-policy-enforcement|M09]]
(downpayment policy). Feeds [[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]] (execution), [[M08-sales-billing|M08]] (billing, payment-stage),
[[M09-policy-enforcement|M09]] (policy evaluation on change), [[M10-credit-balance-management|M10]] (credit on qualifying
cancellation), and [[M11-notification|M11]].

## Open items

- Merging all five queue surfaces (Grooming/Hotel/Daycare/Veterinary +
  Payments Queue + read-only Bookings Queue) into one is still an open
  design question — not done.
- `cage_picker_enabled` on Service Types has no effect outside Hotel.
