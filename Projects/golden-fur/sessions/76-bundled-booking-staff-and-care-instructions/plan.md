---
title: Let admins allow one staff member to take several pets at once, and stop the Hotel "Care Instructions" step from crashing
date: 2026-09-08
tags: [session-plan, golden-fur]
project: golden-fur
session: 76-bundled-booking-staff-and-care-instructions
branch: fix/bundled-booking-staff-and-care-instructions
---

# 76 — Configurable staff concurrency + the Hotel "Care Instructions" crash

## What you asked for

Three things, two from the project backlog
(`Architectural-Change-History.docx`, "In Progress") and one found while
checking the first two.

**1. Bundled booking let the same staff member be double-booked.** The
"bundled booking" feature (session 72 — one checkout, several bookings, one
payment) let a customer pick **the same groomer** for two different pets at
**the same time on the same day**. Verbatim:

> Currently, the new bundled booking feature allows selection of the same
> staff (from staff picker) on the same date/time
> - Determine if staff assignment is 1 = 1 (e.g. 1 groomer = 1 pet only) or
>   1 = many (e.g. 1 groomer = 2 pets)
> - Sample booking chose groomer 1 for both Luna and Cooper on same date 11 AM
>
> Perhaps add a config in admin settings that will allow admins to set how
> many times a staff can be chosen by a booking customer at the same time on
> the same date

**2. The Hotel "Care Instructions" step crashed on submit.** Verbatim:

> Fix booking > new booking > hotel type service > step 8 care instructions:
> - When unchecking same instructions every night, and instructions in other
>   nights are not configured, booking fails
> - Should set the first night instructions the default for other nights (so
>   no need to set)
>
> Changing instructions for a specific night will only overwrite the
> instructions for that night
> - Or perhaps add a new tab that says default instructions, which will be
>   applied to all nights
> - Then apply overwrite on nights that are edited

**3. "No Hotel services available at this branch."** While reproducing #2,
every service category showed as unavailable in the booking flow on the dev
database. This turned out to be missing data, not a code bug (see below).

## What this part of the app does today

### The booking wizard

A customer books at `/portal/book` ("Book a service"); a receptionist books
for someone at `/staff/bookings/new`. Either way it is a step-by-step wizard
(the "New Booking wizard"): pick a pet → pick a branch → pick a service type
(Grooming, Hotel, Daycare, Veterinary, Assessment) → pick a date and time and
(for Grooming/Veterinary) a **preferred staff member** in the **Staff
Picker** → pick the actual services → for Hotel/Daycare, a **Care
Instructions** step → **Review** and confirm.

### The Staff Picker

On the date/time step for Grooming and Veterinary, the wizard shows a
**Staff Picker** — a list of the staff members who are free for that window,
plus a "No preference" option (the server auto-assigns someone free). "Free"
is decided by a database function called `get_staff_availability`. Until now
that function hard-coded a rule: **a staff member is free only if they have
zero overlapping bookings.** One pet at a time, always, with no way to change
it.

### The "Care Instructions" step (Hotel/Daycare)

For a Hotel stay the customer can record feeding times, walks, playtime and
medications. A checkbox, **"Same instructions every night"**, is ticked by
default. If you untick it, a row of tabs appears — one per night of the stay,
plus an "All nights" tab — and each newly-added row is attached to whichever
tab is showing. A row attached to "Tuesday" is only visible while the
Tuesday tab is selected.

When you click Next, the wizard packages every row and sends it to the
server. The server runs a strict check (a "validator"): a feeding row needs
both a food type **and** a quantity, a medication row needs a name **and** a
dose, and so on. If any row fails, the whole request is rejected with the
unhelpful message **"Invalid payload"**.

### Where service availability comes from

Which services a branch offers is stored in two tables,
`service_branch_availability` and `service_type_branch_availability`. The
rule is **"opt-out, not opt-in"**: a service is offered at a branch unless
there is a row saying otherwise. Those rows are created by a **seed** (a
script that fills a fresh database with starter data). Crucially, that seed
only runs on a full database **reset**, not on a routine **push** of new
migrations.

## What's wrong / what's missing

1. **No knob for staff concurrency.** A salon might genuinely want one
   groomer to bathe two small dogs at once. There was no way to allow it —
   and, worse, the bundled-booking checkout let a customer *pick* the same
   groomer twice for the same time even though the booking would then fail
   (or, in the reported case, slip through and create a real double-booking).

2. **The Care Instructions step throws "Invalid payload".** If you untick
   "Same instructions every night", start adding a row on one night's tab,
   then switch to another tab without finishing it, that half-finished row is
   still hidden on the first tab — but it is still submitted, still fails the
   server validator, and the customer sees only "Invalid payload" with no
   idea which row or which night is the problem.

3. **The dev database had *no* availability rows at all.** Because the seed
   only runs on reset and the dev DB is kept current with `push`, a Hotel
   service added by a later migration ended up with zero availability rows.
   The code reads "no row" as "not offered here" and hides the service, so
   the booking flow said "No Hotel services available at this branch" for
   every category.

## What we're going to change

### 1. A configurable "Staff concurrency" setting

- **New database column** `max_concurrent_bookings_per_staff` on the
  `policy_configurations` table (default `1`, must be `≥ 1`). _Which files:_
  `supabase/migrations/20260908178_m03_policy_configurations_max_concurrent_staff.sql`.
- **The `get_staff_availability` database function now reads that number**
  instead of assuming 1: a staff member is free if their overlapping-booking
  count is **below** the configured maximum. It uses the same
  "branch-specific row wins, otherwise the system-wide default row" rule the
  lunch-break setting already uses. _Which files:_
  `supabase/migrations/20260908179_m03_get_staff_availability_staff_capacity.sql`.
- **The server's two other staff-capacity checkpoints honour it too.** After
  a booking is inserted the server re-counts overlapping bookings to resolve
  races (`confirmCapacityAfterInsert`); it now keeps the first *N* by
  creation order instead of just the first 1. The bundled-booking service
  has an in-request guard (`claimWindowOrThrow`) that stopped two bookings in
  one checkout from sharing a staff member; it now allows up to *N*. _Which
  files:_ `server/src/features/booking/services/capacity.service.ts`,
  `bookingGroup.service.ts`, `booking.service.ts`.
- **The Staff Picker greys out a staff member you have already used *N*
  times in this checkout** for an overlapping window, with a hint
  ("Booked for another pet in this checkout"), so you cannot build a cart
  that only fails at the very end. If you go back and change a slot so a
  previously-chosen staff member is now "full", the selection quietly falls
  back to "No preference". _Which files:_
  `client/src/features/booking/components/StaffPickerList/StaffPickerList.tsx`,
  `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
  (a new `cartStaffOverlapCounts` calculation), plus the staff-picker
  endpoint now returns the number
  (`server/src/features/booking/services/staffPicker.service.ts`).
- **A new admin control**: Settings → Config → Policies → **"Staff
  concurrency"**, a number field. _Which files:_
  `client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`,
  `server/src/features/booking/modules/validators/booking.validator.ts`.
- **One extra safety fix**: if the client ever shows a Staff Picker for a
  service that the server says should not have one, and the customer picks a
  specific person, the server used to silently drop that choice (leaving the
  booking with nobody assigned and no warning). It now returns a clear
  `409` error instead. _Which files:_ `booking.service.ts`
  (`resolveStaffAssignment`).

### 2. Fix the Care Instructions step (all client-side, no schema change)

- **The "All nights" tab is renamed "Default (all nights)"** with a short
  caption explaining that entries there apply to every night unless a
  specific night overrides them. _Which files:_
  `client/src/features/booking/components/NightTabs/NightTabs.tsx` (new
  optional label prop), `CustomerBookingFlowPage.tsx`.
- **Genuinely empty rows are dropped silently before submit** (a row you
  started adding and abandoned is not something you care about). _Which
  files:_ `CustomerBookingFlowPage.tsx` (`hotelPreferencesPayload`).
- **A half-finished row now blocks Next** with a banner that names the
  section and the night ("Finish or remove the Feeding entry for Sep 12
  before continuing") and, if that night's tab is currently hidden, a **"Go
  to that night"** button. _Which files:_ `CustomerBookingFlowPage.tsx` —
  new helper functions `hotelFeedingRowStatus` / `hotelMedicationRowStatus`
  / `hotelWalkPlayRowStatus` that label each row `empty` / `partial` /
  `complete`.
- `formatNightLabel` (turns `2026-09-12` into "Sep 12") moved out of
  `NightTabs` into the shared `utils/hotelNights.ts` so both the tabs and the
  new banner can use it.

### 3. Backfill the missing availability rows

- **New migration** that idempotently inserts an `is_available = true` row
  for every active service × branch and every service type × branch, using
  `ON CONFLICT DO NOTHING` so it never touches an existing row (including a
  deliberate "not offered here" opt-out) and does nothing at all on a fresh
  reset. _Which files:_
  `supabase/migrations/20260908180_m13_backfill_branch_availability.sql`.
  Already applied to the dev database.

## Words you might not know

- **migration** — a numbered SQL file that changes the database's shape (a
  new column, a new/replaced function) in a fixed, repeatable order. This
  session adds three.
- **`policy_configurations`** — a table holding the salon's booking rules
  (notice periods, lunch break, down-payment settings, …). One row is the
  system-wide default (its `branch_id` is empty); a branch can have its own
  row that overrides the default.
- **RPC / database function** — code that runs *inside* the Postgres
  database rather than in the Node server. `get_staff_availability` is one.
- **validator** — server-side code that checks an incoming request is
  well-formed before anything acts on it. Here it is a Zod schema.
- **race condition** — two requests arriving at almost the same instant and
  both thinking a slot is free. The app inserts the booking, then re-checks,
  and deletes the loser.
- **idempotent** — safe to run more than once; running it again changes
  nothing. The backfill migration is idempotent.
- **seed** — a script that loads starter data into a fresh database. Runs on
  `supabase db reset`, not on `supabase db push`.
- **`ON CONFLICT DO NOTHING`** — a Postgres clause: "if a row with this key
  already exists, skip this insert instead of erroring".

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
