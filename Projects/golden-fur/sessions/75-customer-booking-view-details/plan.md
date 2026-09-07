---
title: "View details" for a customer's own booking, and fixing "Unknown pet/owner" for cashiers
date: 2026-09-07
tags: [session-plan, golden-fur]
project: golden-fur
session: 75-customer-booking-view-details
branch: feat/customer-booking-view-details
---

# 75 — "View details" for a customer's own booking, and fixing "Unknown pet/owner" for cashiers

## What you asked for

Two separate items from the project's change backlog (the
`Architectural-Change-History` document), both about _reading_ a booking:

> **Add new option to … in customer account > bookings page:**
>
> - Add View Details option
> - Should be able to see all details (e.g. branch, pet, date time, assigned
>   staff/cage, price, payments, etc.)
> - Currently only cancel is available (and reschedule if booking hasn't been
>   confirmed)

> **Fix unknown pet owner and unknown pet when viewing bookings as cashier**

## Words you might not know

- **Booking** — one appointment a customer made: a pet, a branch (shop
  location), a service category (Grooming / Hotel / Daycare / Veterinary), a
  date and time, a price, and a payment status.
- **Endpoint / route** — a URL on the server that the website calls to get or
  change data. `GET /bookings/123/details` means "give me the full details of
  booking 123".
- **Read-through endpoint** — an endpoint whose only job is to gather data
  from many tables and hand it back in one response, changing nothing.
- **Hydrate** — to take a record that only stores _id numbers_ (this booking
  points at `staff_id = 9`) and look up the human-friendly values (staff
  member "Makati Groomer 1") so the screen can show names, not numbers.
- **Service-role client** — a database connection the server uses that is
  _not_ limited to one customer's own rows. The server uses it only _after_
  it has already checked that the caller is allowed to see this booking.
- **Owner-or-staff check** — the permission rule: you may see a booking if it
  is _your_ booking, or if you are a staff member.
- **Role** — the job a staff account has: Receptionist, Cashier, Groomer,
  Veterinarian, Admin, and so on. Different roles can do different things.
- **Modal** — a small window that opens on top of the current page (a dialog
  box), used here to show booking details without leaving the list.
- **Booking group** — when a customer books several services in one checkout
  ("multi-booking"), the shared price and payments live on one
  `booking_groups` row that every booking in the batch points at.
- **Transaction** — one payment record against a booking (a down payment, a
  balance payment, or a full payment).
- **Component** — a reusable piece of screen in the website's code.
- **Lazy transition** — the server, when you read a booking, quietly updates
  its status if a deadline has passed (for example, an unpaid down payment
  that expired, or a missed appointment becoming a no-show).

## What this part of the app does today

There are two places a booking gets looked at in detail:

1. **The customer "My Bookings" page** (`/portal/bookings` in the customer
   portal, the menu item labelled **My Bookings**). It lists the signed-in
   customer's own bookings. Each row has a `…` ("more options") menu whose
   only entries are **Reschedule** (and only when the booking has not been
   confirmed yet) and **Cancel**. There is no way to see the full detail of a
   booking — the price breakdown, who was assigned, which cage, what was
   paid. For a Completed or Cancelled booking the `…` menu did not appear at
   all, so those rows had no actions whatsoever.

2. **The staff "Booking Details" page** (`/staff/bookings/:id`, reached from
   the **View details** button on the staff Bookings Queue). It already shows
   a lot, but it was built by making about seven separate calls from the
   browser (fetch the booking, then the pet, then the customer, then the list
   of branches, then services, then packages, then discounts, then promos)
   and stitching them together on the client. It never showed the assigned
   staff member or the preferred cage, because those need extra lookups it
   didn't do.

Separately: a **Cashier** can open the staff Bookings Queue
(`/staff/bookings/queue` — the page even has special handling for the Cashier
role) and drill into a booking to take payment. But the small per-row lookups
those pages do — `GET /pets/:id` for the pet's name and `GET /customers/:id`
for the owner's name — only allowed a fixed list of roles, and **Cashier was
not on it**. So every one of those lookups came back "forbidden" and the
screen fell back to the literal text **"Unknown pet"** and **"Unknown
owner"**.

## What's wrong / what's missing

- A customer cannot see the full story of their own booking from My Bookings.
- The staff Booking Details page is slow and fragile (many round-trips) and
  is missing assigned-staff and cage information.
- A Cashier viewing bookings sees "Unknown pet" / "Unknown owner" instead of
  real names, which makes it hard to know whose payment they are taking.

## What we're going to change

1. **Add one server endpoint that returns a fully-hydrated booking.** —
   _Which files:_ `server/src/features/booking/services/bookingDetails.service.ts`
   (new), `server/src/features/booking/booking.controller.ts`,
   `server/src/features/booking/booking.routes.ts`,
   `server/src/features/booking/booking.types.ts`. — _Why:_ one call
   (`GET /bookings/:id/details`) does the permission check via the existing
   booking lookup, then gathers branch, pet, owner, item names, assigned
   staff, cage, discount/promo names, the shared booking-group row, a price
   rollup, and the payment list — so neither screen has to make a pile of
   staff-only calls.

2. **Add the matching client API function.** — _Which files:_
   `client/src/features/booking/api/booking.api.ts`,
   `client/src/features/booking/booking.types.ts`. — _Why:_ so both screens
   call the new endpoint the same way.

3. **Build one shared "details view" component and a modal wrapper.** —
   _Which files:_ `client/src/features/booking/components/BookingDetailsView/`
   (new), `client/src/features/booking/components/BookingDetailsModal/`
   (new). — _Why:_ `BookingDetailsView` is pure display (Schedule, Items,
   Hotel care instructions, Pricing, Payments, Status timeline).
   `BookingDetailsModal` fetches on open and shows that view in a dialog.

4. **Add "View details" to the customer My Bookings row menu.** — _Which
   files:_
   `client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`. —
   _Why:_ it becomes the always-first item in the `…` menu, and the menu now
   renders for every booking including Completed and Cancelled ones.

5. **Rebuild the staff Booking Details page on the new endpoint.** — _Which
   files:_
   `client/src/features/booking/pages/BookingDetailsPage/BookingDetailsPage.tsx`
   and its `.module.css`. — _Why:_ one call plus `<BookingDetailsView>`
   replaces ~7 client fetches, and it now shows assigned staff and cage.

6. **Let a Cashier read a single pet and a single customer profile.** —
   _Which files:_
   `server/src/features/customers/pets/pet.controller.ts` (add `'Cashier'` to
   `PET_LOOKUP_ROLES`),
   `server/src/features/customers/customer.controller.ts` (add `'Cashier'` to
   `PROFILE_LOOKUP_ROLES`). — _Why:_ this is a narrow, read-only widening —
   the same precedent already set for Groomer and Veterinarian — so the
   Bookings Queue and Booking Details pages resolve real names for a Cashier
   instead of showing "Unknown". Cashiers still cannot list or edit
   customers.

There is **no database migration** in this change.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
