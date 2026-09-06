---
title: Let one checkout cover several bookings that share one payment
date: 2026-09-06
tags: [session-plan, golden-fur]
project: golden-fur
session: 72-multi-booking-checkout
branch: feat/multi-booking-checkout
---

# 72 — Let one checkout cover several bookings that share one payment

## What you asked for

Let a customer (or a receptionist booking on someone's behalf) add **more
than one booking** — different pets, different service types (Grooming,
Hotel, Daycare, Veterinary, Assessment), different dates/times — into one
checkout, and pay for the whole batch together instead of doing the booking
wizard over and over and paying separately each time. You explored two
designs and picked the simpler one. Verbatim, the winning design:

> OR TO MAKE THINGS EASIER, just add a step before payment confirmation
>
> - Show list of bookings, make another booking and cancel booking buttons
>   below
> - No need for that append latest booking to previous end time feature
> - This uses a much simpler model, and still allows multiple bookings to
>   share payment, downpayment, promos or discounts

And, when asked to confirm the shape of that design:

> When staff/customer click "Add another booking" ... should the wizard let
> them pick a different pet ... "Allow different pet each time"
>
> Should the branch be shared across every booking added to the list ...
> "Shared branch"
>
> For "share promos/discounts" across the list ... "One shared discount +
> promo for the whole list"
>
> How should the backend represent a group of bookings that share one
> payment? ... "New booking_groups table"

Then a real bug you found once the feature was running, from a screenshot of
the new "Your bookings" list step:

> Luna has 2 services in this bundled booking but they can both be started at
> 11 AM on the same date — that seems a bit wrong. Perhaps make it so that
> start times for the specific pet of the chosen date are not selectable or
> hidden if they already have a service for it in the current bundled
> booking? Should only apply if it's a bundled booking, and for the current
> customer. Other customers should still be able to book that time, if it's
> done via online booking not walkin.

## What this part of the app does today

The **New Booking** wizard (`Book a service` for a customer at
`/portal/book`, or `Book for a customer` for a receptionist at
`/staff/bookings/new`) walks through: pick a pet → pick a branch → pick a
service type (Grooming/Hotel/Daycare/Veterinary/Assessment) → pick a
date/time and, for Grooming/Veterinary, a preferred staff member (or for
Hotel, a cage preference) → pick the actual services/packages → for
Hotel/Daycare, Care Instructions → **Review** (choose a discount/promo and a
payment scheme, then Confirm booking). Before this session, finishing the
wizard always created exactly **one** booking, with its own single payment.

## What's wrong / what's missing

There was no way to book more than one thing in one visit to the wizard and
pay for it all together — a customer with two pets, or one pet needing two
different services, had to run the whole wizard twice and pay twice. And once
this session's feature let someone build up several bookings for the _same_
pet, nothing stopped that pet from being scheduled into two services that
overlap in time on the same day (the bug you found with Luna's Grooming and
Daycare both starting at 11 AM).

## What we're going to change

1. **A new "Your bookings" step, right before Review** — shows every booking
   already built up in this checkout as a card (pet, service type, items,
   date/time, staff-or-cage preference, its own subtotal), with a **Cancel
   booking** button per card and an **Add another booking** button that jumps
   the wizard back to the Pet step for a fresh pass (branch stays the one
   already chosen). _Which files:_
   `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
   (the whole wizard lives in this one file) — new `bookingsList` state (a
   `SubBookingDraft[]`, one frozen snapshot per booking already built),
   `commitCurrentBookingDraft`/`resetForNextBooking`/`restoreDraftFromEntry`
   functions, and a new `'bookingsList'` step case. _Why:_ this is the "OR to
   make things easier" design — a plain list instead of anything fancier.
2. **A small "N bookings in this checkout" badge** next to the step
   indicator, so it's obvious you're mid-checkout on a batch. _Which files:_
   new `client/src/features/booking/components/BookingCountBadge/`.
3. **The Review step now adds up every booking in the list** — one combined
   subtotal, one shared discount, one shared promo, one shared downpayment
   decision — instead of pricing a single booking. Confirming submits either
   the plain single-booking request (if you never clicked "Add another
   booking") or a new "booking group" request (if you did) — nothing changes
   for a normal, single booking. _Which files:_ the same wizard file's Review
   step render + `handleSubmit`.
4. **A new `booking_groups` table** holds the shared discount/promo/
   downpayment/payment-scheme choice and its own combined total; each
   `bookings` row that's part of a batch points at its group via a new
   `booking_group_id` column, but a booking never _needs_ a group — a normal,
   single booking is completely unaffected. _Which files:_
   `supabase/migrations/20260906173..175_*.sql` (the table, a matching column
   on `transactions`, and a new `create_initial_booking_group_charge`
   database function that creates the group's shared charge — a downpayment
   - remaining-balance pair, or one full-payment charge, exactly the same
     shapes a single booking already gets).
5. **A new `POST /bookings/groups` endpoint** that creates every booking in
   the batch, resolves the shared discount/promo/downpayment against the
   combined total, and — importantly — makes sure two bookings in the _same_
   batch can never grab the same staff member's time slot or the same cage
   at an overlapping time (a check that didn't need to exist before, since a
   single booking never competes with itself). _Which files:_ new
   `server/src/features/booking/services/bookingGroup.service.ts`, plus
   small additions to `booking.controller.ts`/`booking.routes.ts`/the
   validator.
6. **Paying for a batch works the same way paying for one booking does** —
   settling the shared charge, a webhook-confirmed online payment, and the
   cashier's in-branch "collect payment" screen were all extended to
   recognize a batch's shared charge and roll its paid/unpaid status back
   onto every booking in the batch. A batch that requires a down payment and
   never gets paid now expires and cancels the same way an unpaid single
   booking already did. _Which files:_ `server/src/features/billing/services/
*` (transactionPayment, webhookConfirmation, checkoutAggregation,
   bookingTransactions), plus two more database functions
   (`20260906176`/`177`) making the existing `settle_transaction`/
   `pay_transaction_with_credit` functions recognize a batch's shared charge.
7. **The Luna bug, fixed two ways:** on the date/time picker, any time slot
   that would overlap another booking _this same pet already has in the
   current batch_ is shown greyed-out/"Unavailable", exactly like a slot that
   was genuinely already taken — but only when you're building an Online
   booking (a receptionist doing a Walk-in for someone physically standing at
   the counter skips this, same as several other checks that already don't
   apply to Walk-ins). This never touches real availability for anyone
   else — another customer can still book that exact time. _Which files:_
   `client/src/features/booking/components/SlotPicker/SlotPicker.tsx` (new
   `excludedWindows` prop) and the wizard file (computes the pet's other
   booked windows from `bookingsList`). The same rule is repeated
   server-side in `bookingGroup.service.ts` as a safety net, in case the
   picker is ever bypassed.

## Words you might not know

- **migration** — a versioned SQL file that changes the database's shape
  (adds a table, a column, a rule) in a repeatable, ordered way. This
  session added five, under `supabase/migrations/`.
- **RPC (remote procedure call)** — here, a small function that lives inside
  the Postgres database itself rather than in the server's own code, used
  when several related writes need to happen together as one atomic step
  (e.g. "create the down-payment charge and its remaining-balance charge
  together, or neither").
- **race condition** — a bug where two things happening at almost the same
  time interfere with each other in a way that wouldn't happen if they ran
  one after the other — e.g. two people trying to book the very last open
  cage at the exact same moment. This app re-checks capacity right after
  inserting a booking specifically to catch this.
- **RLS (row-level security)** — a Postgres feature that restricts which
  rows a given database user is allowed to read/write, enforced by the
  database itself rather than trusted to application code.
- **rollback** — undoing every change a failed multi-step operation already
  made, so it doesn't leave the database in a half-finished state.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
