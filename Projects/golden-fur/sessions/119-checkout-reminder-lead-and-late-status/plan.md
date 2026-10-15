---
title: Choose when the checkout reminder fires, and a "Late" booking status before No-show
date: 2026-10-15
tags: [session-plan, golden-fur]
project: golden-fur
session: 119-checkout-reminder-lead-and-late-status
branch: feat/late-status-checkout-reminder-lead
---

# 119: Choose when the checkout reminder fires, and add a "Late" booking status before No-show

## What you asked for

There are two changes. First, customers should be able to pick how early they get the "your pet's checkout is coming up" reminder. Second, a booking whose start time has passed should be marked **Late**, not **No-show** straight away. It becomes No-show only after a waiting period that an admin sets.

> At settings > preferences > notifications > checkout > add modification options (e.g. remind in 15min, 1h, 1d, etc.)
> late for booking (when booking date/time is exceeded, but can still follow up, maybe add an admin config to set the time threshold for when it should turn to no show, e.g. no show if still not present until 15min, 30min, 1h, end of operating hours, etc.)

Choices confirmed while planning:
- The checkout options are a **"how early" dropdown**, not a "snooze" button on the notice.
- **Late** is a real saved status, not just a label drawn on screen.
- The default waiting period is **30 minutes**.

## What this part of the app does today

**Checkout reminder.** A customer can open **Settings → Preferences → Notifications**. That screen is a grid of toggles: one row per kind of notice, with an *Email* column and an *In-browser* column. One row is labelled **"Checkout in 15 minutes"**.
- The server runs a small background loop (a "job") once a minute in `stayCheckout.job.ts`. It looks for pets currently checked in to Hotel or Daycare, and messages the owner exactly 15 minutes before the booking's end time.
- The 15 is written straight into the code as a fixed number, so nobody can change it.
- The **"Booking reminder"** row on the same screen already has a dropdown underneath it ("Send the reminder: 15 minutes before / 1 hour before / 1 day before …"). That is the pattern we will copy.

**No-show.** Every booking has a *status*, a word saved in the database that says where it is in its life: `Pending` (booked, not started), `In Progress`, `Completed`, `Cancelled` or `No-show`.
- Golden Fur doesn't run a timer to change statuses. Instead, whenever the server *reads* bookings (for example, when the receptionist opens the Bookings Queue page), a function called `applyNoShowTransition` checks each `Pending` booking.
- If the booking's start time is already in the past, that function changes it to `No-show` on the spot. There is no grace period at all.

## What's wrong / what's missing

- A customer who wants an hour's or a day's warning before picking up their pet can't get one. It's always 15 minutes.
- If a customer is two minutes late, the receptionist sees **No-show** immediately, even though the customer is probably just parking. Staff have nothing that says "late, but still coming". The shop also has no say in how long to wait.

## What we're going to change

### Part 1: Checkout reminder timing

1. **Add a dropdown under the checkout row.**
   - _Which files:_ `client/src/pages/SettingsPage/tabs/NotificationPreferencesGrid.tsx`, `client/src/shared/api/preferences.api.ts`
   - _Why:_ The row is renamed **"Checkout reminder"**. Below it, a "Send the reminder" dropdown offers *15 minutes / 1 hour / 3 hours / 1 day before*, built from the same code that draws the Booking reminder's dropdown. The default stays 15 minutes, so nothing changes for anyone who leaves it alone.
2. **Let the server save that choice.**
   - _Which files:_ `server/src/features/auth/customers/customerAuth.routes.ts`, `server/src/features/notifications/notifications.types.ts`
   - _Why:_ The "save my notification settings" endpoint currently refuses a timing value for anything except the Booking reminder. It will also accept one for the checkout reminder, checked against that reminder's own list of allowed values.
   - No database change is needed. These settings already live in a flexible JSON column (`notification_preferences`) that can hold the extra field.
3. **Make the background job use each customer's choice.**
   - _Which files:_ `server/src/features/hotel/jobs/stayCheckout.job.ts`, `server/src/shared/email/stayCheckoutEmail.ts`
   - _Why:_ Instead of the fixed 15, the job reads the owner's chosen lead time and sends when `checkout time − lead time` has arrived.
   - The title and email text change to match, e.g. "Checkout in 1 hour". Today the email literally says "15 minutes".
   - **Edge case:** suppose someone picks "1 day before" for a same-day daycare drop-off. The "1 day before" moment happened before the pet even arrived, so we skip the early reminder rather than sending it the instant the pet is checked in. The existing "checkout time is up" notice still covers them.

### Part 2: The "Late" status and the admin setting

4. **Add `Late` to the list of allowed statuses.**
   - _Which files:_ new migration `supabase/migrations/20261015266_custom_booking_status_add_late.sql`
   - _Why:_ The database only accepts status words from a fixed list (an *enum*), so `Late` must be added to it first.
   - This migration contains only that one line. Postgres won't let a new enum value be used in the same transaction that adds it.
5. **Add the admin setting for "how long to wait".**
   - _Which files:_ new migration `20261015267_custom_policy_configurations_no_show_threshold.sql`. Server: `staffPicker.service.ts`, `booking.types.ts`, `booking.validator.ts`. Client: `PolicyConfigurationPage.tsx`, `booking.types.ts`.
   - _Why:_ Shop-wide rules already live in a table called `policy_configurations`. It has one shop-wide row, plus optional per-branch rows that override it.
   - We add two columns to that table:
     - `no_show_after_minutes`, default 30.
     - `no_show_at_closing` (yes/no). "Yes" means: wait until the branch closes that day.
   - The admin **Policy Configuration** page gets a "Mark as no-show after" dropdown with these options: *15 min / 30 min / 1 hour / 2 hours / End of operating hours*.
6. **Teach the read-time check about Late.**
   - _Which files:_ `server/src/features/booking/services/booking.service.ts`
   - _Why:_ `applyNoShowTransition` becomes `applyLateAndNoShowTransition`. For each booking whose start time has passed:
     - **Still within the waiting period:** it becomes `Late`.
     - **Waiting period over:** it becomes `No-show`.
   - "Over" means either start time + N minutes, or that branch's closing time on that day.
   - It looks up each branch's setting once, not once per booking.
7. **Make every "not started yet" check also accept Late.**
   - _Which files:_ many. Server: `booking.service.ts`, `cancellation.service.ts`, `capacity.service.ts`, `daycareCheckIn.service.ts`, grooming, vet consultation and billing services. Client: the Receptionist, Assessment and Daycare queue pages, plus `bookingConfirmation.ts`.
   - _Why:_ Lots of code asks "is this booking still `Pending`?" to decide things like *can staff press Start?*, *can it be cancelled?* and *is the cage/groomer still reserved?*. A Late booking must answer "yes" to all of these, or staff couldn't follow up on it.
   - We'll add one shared list, `NOT_STARTED_STATUSES = ['Pending', 'Late']`, and use it in those places.
   - One deliberate exception: the "your appointment is coming up" reminder should *not* go to a Late booking.
   - Moving a Late booking to a future time puts it back to `Pending`.
8. **Update the database functions that check status.**
   - _Which files:_ new migration `20261015268_custom_booking_status_late_rpcs.sql`
   - _Why:_ Some checks live inside Postgres functions rather than in TypeScript. The most important is `get_staff_availability`, which decides which time slots are still free. Each affected function is re-created so it treats `Late` like `Pending`.
   - Many of the `'Pending'` matches in old migrations refer to *payment* status. Those are unrelated and stay as they are.
9. **Show it on screen.**
   - _Which files:_ `client/src/features/booking/components/shared/BookingStatusBadge/BookingStatusBadge.tsx`
   - _Why:_ The coloured status pill gets an amber **Late** style. `Late` is also added to any status filter dropdowns.
10. **Keep the sample data in step.**
    - _Which files:_ `supabase/seeds/…` (via the seed-maintenance checklist)
    - _Why:_ The seeded `policy_configurations` row and the seed tests must match the new columns and status.

## Words you might not know

- **Migration:** a numbered SQL file that changes the database's structure (adds a column, a table, an allowed value). Migrations run in order, so every copy of the database ends up the same.
- **Enum:** a database column type that only accepts values from a fixed list. `booking_status` is one.
- **Lazy (read-time) transition:** instead of a clock changing a status at the exact second, the status is fixed up the next time someone looks at the booking. The result looks the same to the user.
- **Background job / poller:** a loop inside the server that wakes up every so often (here, every minute) to do a chore, like sending reminders.
- **Lead time:** how long *before* an event a reminder is sent.
- **Policy configuration:** the admin-editable table of shop rules. One row applies to the whole shop, and optional extra rows override it for a single branch.
- **RPC / Postgres function:** a small program stored inside the database that the server calls by name.
- **jsonb:** a database column that stores a flexible JSON object, so new fields can be added without a migration.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (written after implementation). In short:
- A customer can set the checkout reminder to "1 hour before", and it stays set after a reload.
- With the admin threshold at 15 minutes, a booking that started 5 minutes ago shows **Late** and can still be started. One that started 20 minutes ago shows **No-show**.
- Server and client test suites pass, including new tests for the reminder timing and the Late/No-show cut-off.
