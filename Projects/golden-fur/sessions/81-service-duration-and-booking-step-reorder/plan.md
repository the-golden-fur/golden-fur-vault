---
title: Set a service's average time, show a booking's end time, and reorder the booking steps
date: 2026-09-10
tags: [session-plan, golden-fur]
project: golden-fur
session: 81-service-duration-and-booking-step-reorder
branch: feat/service-duration-and-booking-step-reorder
---

# 81 — Set a service's average time, show a booking's end time, and reorder the booking steps

## What you asked for

Three connected changes to how a booking is made:

> - At admin settings > services:
>   - Add config to set average time of service
>   - This will affect the duration of bookings that have this service
>   - Make packages derive from this as well
> - When making new booking > date time picker step:
>   - Remove end time presets (time blocks)
>   - Only show start time
>   - At the bottom (not in select; separate label), show end time and duration of booking
> - Rearrange booking steps:
>   - Branch > Customer > Pet > Service Type > Services/Packages > Online/Walkin > Date Time + Staff/Cage picker > Confirmation

## What this part of the app does today

**Admin Settings > Services** is a page only an Admin or Superadmin can open
(Settings gear → "Services and Packages" tile → "Services" tab). Each row is
a _service_ — one thing the shop sells, like "Bath" or "Wellness Exam" — with
a name, a category (Grooming / Hotel / Daycare / Veterinary / Assessment), a
price, and which branches offer it. A _package_ is a bundle of two or more
services sold together at a discount; those are managed on the neighbouring
"Packages" tab.

Every service row already has a database column called `duration_minutes` (how
many minutes a booking for it should run). But the edit form only _showed_ that
field for Hotel and Daycare services. For Grooming and Veterinary it stayed
empty (`NULL` in database terms — "no value"), and the app quietly fell back to
a hard-coded 60 minutes everywhere.

**Making a new booking** is a step-by-step wizard (a "wizard" is a form split
into numbered steps with Back / Next buttons). The exact same screen is used
in two places:

- the customer portal at `/portal/book` (a logged-in pet owner books their own
  visit), and
- the staff side at `/staff/bookings/new` (a receptionist books a walk-in or a
  phone-in).

The staff version has two extra steps the customer never sees: **Customer**
(pick which client this booking is for) and **Booking Type** (Online vs
Walk-in).

Inside that wizard, the **Date & Time** step is where you pick when the visit
happens. It shows a calendar date, then a list of start times for that day. A
_slot_ is one bookable start time plus the end time the system paired with it.
The Staff picker (for Grooming/Vet) and the Cage picker (for Hotel) live in
this same step, appearing under the time list once a slot is chosen.

## What's wrong / what's missing

1. **You can't tell the app how long a Grooming or Vet service takes.** The
   field exists but is hidden, so those bookings were always 60 minutes on
   screen no matter what.
2. **The Date & Time step chose the booking length for you.** Because the step
   ran _before_ you picked any services, the system had no idea how long the
   visit would be, so it used a fixed stand-in number and offered start times
   chopped into blocks of that length. You never saw the actual end time.
3. **The steps were in an odd order** — Pet before Branch, and the Date & Time
   step before you'd even chosen what you were booking.

## What we're going to change

1. **Show the "average service time" field for every category.**
   _Which files:_ `client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`
   (+ its `.module.css`) — _Why:_ the field and all the code that saves it
   already work for Hotel/Daycare; only the "is this Hotel or Daycare?" check
   around the input was hiding it. Remove that check, and word the label per
   category ("Average service time (minutes)" for Grooming/Vet/Assessment,
   "Duration per night/block (minutes)" for Hotel/Daycare). Nothing on the
   server changes — the validation and save code already accept
   `duration_minutes` for any category.

2. **Give the seeded Grooming/Vet services real durations.**
   _Which files:_ `supabase/migrations/20260715034_m13_seed_maintenance_data.sql`
   (the file that first creates the service catalogue) and a **new** migration
   `supabase/migrations/20260910183_m13_backfill_service_average_duration.sql` —
   _Why:_ the first file only runs on a from-scratch database rebuild, so a
   database that's kept up to date incrementally (dev and production) would
   still have the old `NULL` values. The new migration is a safe, re-runnable
   `UPDATE` that fills them in, and it skips any value an admin has already
   changed by hand.

3. **Show the derived total time on the Package builder.**
   _Which files:_ `client/src/features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx`
   — _Why:_ a package's duration is just the sum of its services' durations
   (the server already computes this as `total_duration_minutes`). Show that
   sum read-only under the service list, and note when a chosen service has no
   time set.

4. **Feed the real duration into the Date & Time step and show the end time.**
   _Which files:_ `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
   (+ its `.module.css`), new helper
   `client/src/shared/utils/formatDuration.ts` — _Why:_ once "Services" comes
   before "Date & Time" (change 5), the wizard already knows the total length
   (`slotDurationMinutes`, which adds up every picked service and package). Pass
   that real number to the time picker instead of the fixed stand-in
   (`DEFAULT_DURATION_MINUTES`, now deleted), and render a plain caption under
   the picker: "Ends 10:30 AM · 1h 30m" (for Hotel: "Check-out Sep 13 · 3
   nights"). The time list itself already showed only start times — no change
   there.

5. **Reorder the wizard steps.**
   _Which files:_ same `CustomerBookingFlowPage.tsx` — _Why:_ the order is
   built in one place (a `steps` list). Rebuild it as
   Branch → Customer → Pet → Service Type → Services → Online/Walk-in →
   Date & Time (+ Staff/Cage) → Confirmation, for both the customer and staff
   flows (the customer flow just skips the Customer and Booking Type steps).
   Care Instructions (Hotel/Daycare only) and the "Your bookings" multi-booking
   cart stay where they are functionally needed — right after Date & Time, before
   Confirmation. Also nudge the small things that referenced the old order: the
   first step is now "branch", the draft-restore key is bumped to `v2` so a
   half-finished booking saved under the old order lapses instead of loading
   onto the wrong step, and the "Back from the cart" and "commit this booking"
   logic point at the new last-configured step.

## Words you might not know

- **migration** — a numbered SQL script that changes the database's shape or
  seed data. They run in order; a database remembers which it has already run.
- **seed data** — starter rows inserted by a migration so the app isn't empty
  on a fresh install (the list of services, for example).
- **`NULL`** — the database's "no value here". Different from `0`.
- **enum** — a column that may only hold one of a fixed set of words (here:
  the service category).
- **slot** — one bookable start time plus its paired end time.
- **wizard / step** — a form split into Back/Next stages.
- **`useMemo`** — a React tool that recomputes a value only when its inputs
  change; the step list is built inside one.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
