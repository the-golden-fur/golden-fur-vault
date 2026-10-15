# Choose when the checkout reminder fires, and a "Late" booking status before No-show

Branch: `feat/late-status-checkout-reminder-lead`

## The request, verbatim

> At settings > preferences > notifications > checkout > add modification options (e.g. remind in 15min, 1h, 1d, etc.)
> late for booking (when booking date/time is exceeded, but can still follow up, maybe add an admin config to set the time threshold for when it should turn to no show, e.g. no show if still not present until 15min, 30min, 1h, end of operating hours, etc.)

These choices were confirmed while planning:
- The checkout options are a "how early" dropdown, not a snooze button.
- `Late` is a real database status.
- The default no-show threshold is 30 minutes.

## Root cause / Context

**Checkout reminder.** `stayCheckout.job.ts` sent the checkout reminder at a hard-coded `CHECKOUT_REMINDER_LEAD_MINUTES = 15`. The Booking reminder already had a per-customer `reminder_offset_minutes`. This change reuses that same mechanism for `checkout_reminder`.

**No-show.** `applyNoShowTransition` flipped every `Pending` booking to `No-show` the instant `scheduled_start` passed, with no grace period.

## What changed

### Database

- `20261015266_custom_booking_status_add_late.sql` adds `'Late'` to the `booking_status` enum. It sits in its own file because an enum value added with ADD VALUE can't be used in the same transaction.
- `20261015267_custom_policy_configurations_no_show_threshold.sql` adds two columns to `policy_configurations`: `no_show_after_minutes` (default 30) and `no_show_at_closing` (default false).
- `20261015268_custom_booking_status_late_rpcs.sql` adds `'Late'` to two things:
  - `get_staff_availability()`'s Check 2 status list. The body is otherwise copied verbatim from 20260908179.
  - The `bookings_staff_active_idx` partial index.

### Server

**Checkout reminder**
- `notifications.types.ts`: new `CHECKOUT_REMINDER_OFFSET_MINUTES_OPTIONS` (15 / 60 / 180 / 1440, default 15) and `REMINDER_OFFSET_OPTIONS_BY_EVENT`.
- `customerAuth.routes.ts`: the controller now accepts `reminder_offset_minutes` for `checkout_reminder`, checked against that event's own presets.
- `stayCheckout.job.ts`:
  - Batch-loads each owner's chosen lead time, and sends once `now >= checkout − lead`.
  - Skips the reminder when that moment fell before `stays.check_in_at`.
  - The title and message come from `formatReminderLead` (e.g. "Checkout in 1 hour").
- `stayCheckoutEmail.ts`: takes `reminderLead` in place of the fixed "15 minutes".

**Late status: types and policy**
- `booking.types.ts`:
  - `Late` is added to `BookingStatus`, `BOOKING_STATUSES`, `ACTIVE_BOOKING_STATUSES` and `CANCELLABLE_BOOKING_STATUSES`.
  - New `NOT_STARTED_BOOKING_STATUSES` and `isNotStartedStatus`.
  - The two new policy fields are added.
- `staffPicker.service.ts`: the new fields are added to `DOCUMENTED_DEFAULTS` and to the new-row baseline.
- `booking.validator.ts`: `no_show_after_minutes` accepts only 15, 30, 60 or 120; `no_show_at_closing` is a boolean.

**Late status: the transition**
- `booking.service.ts`: `applyNoShowTransition` is replaced by `applyLateAndNoShowTransition`.
  - It resolves each branch's policy once per call.
  - For "End of operating hours", it reads the branch's hours through the new `closingInstantOn` in `availability.service.ts`.
  - It moves bookings Pending → Late, then Late → No-show.
  - Its bulk updates are guarded by `.in('status', NOT_STARTED_BOOKING_STATUSES)`, so a concurrent Start wins.

**Late treated like Pending**
- `startBooking`, the slot-conflict list, the down-payment expiry sweeps, the first-payment side effects and duplicate-booking prevention all now accept `Late`.
- So do Daycare and Hotel check-in (`daycareCheckIn.service.ts`, `careInstructions.service.ts`).
- The Grooming queue, Vet queue, assessment reprice, extend-stay and pencil-booking (`capacity.service.ts`) lists include `Late`.
- **Deliberately unchanged:** `RESCHEDULABLE_BOOKING_STATUSES` stays Pending-only. Rescheduling already refuses any booking whose start time has passed.
- **Deliberately unchanged:** `appointmentReminder.job.ts` only sends "coming up" reminders for Pending bookings.

### Client

**Checkout reminder**
- `preferences.api.ts`: new checkout lead constants. `updateReminderOffset` now takes an `eventType`.
- `NotificationPreferencesGrid.tsx`:
  - The row is renamed **Checkout reminder**.
  - A per-event `REMINDER_OFFSET_CONFIG` drives the "Send the reminder" dropdown for both the Booking reminder and the Checkout reminder.

**Late status: display**
- `booking.types.ts`: `Late` added to the status lists and the confirmation states, plus `isNotStartedStatus` and the new policy fields.
- `bookingConfirmation.ts`: new `Late` state and hint, plus `isConfirmedNotStarted`.
- Badges and colours:
  - `BookingStatusBadge` and `BookingConfirmationBadge` get an orange **Late** style.
  - The receptionist calendar chip gets the same style.
  - New `--color-booking-late-*` tokens in light and dark.

**Late status: queues**
- **Receptionist Bookings Queue:**
  - A paid Late booking still shows **Check In**.
  - There is a "Late" filter.
  - Late Hotel bookings can still be extended.
- **Assessment Queue:** has a Late filter, and paid Late bookings are assessable and startable.
- **Daycare Queue:** has a Late filter, and Late rows are clickable through to check-in.
- **Groomer dashboard and Vet console:** both have a Late status filter and a Late board column. The vet console's Start button shows for Late.
- **Hotel booking picker:** Late bookings can be checked in.

**Admin setting**
- `PolicyConfigurationPage.tsx`: new section **Late arrivals and no-shows**, with a **Mark as no-show after** dropdown: 15 min / 30 min / 1 hour / 2 hours / End of operating hours that day.

## Manual test, step by step

Before you start, apply the three new migrations to your local or dev database. Then run both dev servers (`npm run dev` in `server/` and in `client/`). The seeded accounts all use password `password123`.

### A. Checkout reminder timing (customer)

1. Open `http://localhost:5173` and sign in as a seeded customer.
2. Click your avatar, then **Settings**, then the **Preferences** tab. Scroll to **Notifications**.
3. Find the row **Checkout reminder**. It used to say "Checkout in 15 minutes".
   - Under it there should be **Send the reminder** with a dropdown showing **15 minutes before**.
   - Its options should be 15 minutes / 1 hour / 3 hours / 1 day before. There is no "2 days".
4. Choose **1 hour before**, then reload the page. It should still say **1 hour before**. If it snaps back, the save failed; check the server log for a 400 "Invalid reminder offset".
5. Switch off both the Email and In-browser toggles on that row. The dropdown should turn grey (disabled).

### B. Checkout reminder actually firing

1. As staff, check in a Daycare pet for that customer whose booking ends about 50 minutes from now.
2. Within a minute, the customer's notification bell (refresh the page) should show **"Checkout in 1 hour"**.
3. With the default setting (15 minutes before), nothing should arrive until 15 minutes before the end.

### C. Late, then No-show (staff)

1. Sign in as `admin`. Go to **Config → Policies** (Policy Configuration). Under **Late arrivals and no-shows**, set **Mark as no-show after** to **15 minutes after the start time** and click **Save**.
2. Create two Online bookings that are already paid (or Walk-in style confirmed). Using the Supabase table editor, set one's `scheduled_start` to 5 minutes ago and the other's to 20 minutes ago. Leave both at status `Pending`.
3. Open the **Bookings Queue** page.
   - The 5-minute one should show an orange **Late** pill and still have a **Check In** button.
   - The 20-minute one should show a red **No-show** pill.
4. Click **Check In** on the Late one. It should move to **In service**.
5. Back in Policies, choose **End of operating hours that day** and save. A booking that started 2 hours ago (still within opening hours) should now read **Late**, not No-show.

## Test suites

All suites were run this session.
- `server`:
  - `npx vitest run`: 1867/1867 passing (145 files).
  - `npx tsc --noEmit`: clean.
  - `eslint` on changed files: 0 errors. There are 2 `no-console` warnings that were already in `stayCheckout.job.ts`.
- `client`:
  - `npx tsc --noEmit -p tsconfig.app.json`: clean.
  - `npx vitest run`: 1892/1895 passing. The 3 failures are in `staffAuth.api.spec.ts` and `mfa.api.spec.ts`. They expect a relative `/auth/...` URL, but the local `client/.env` sets an absolute API base URL (`http://localhost:3000`). They are unrelated to this change.

**New tests:**
- `stayCheckout.job.spec.ts`: chosen lead time, waiting for the lead time, the 15-minute default, skipping when check-in came after the reminder moment, a 1-day Hotel reminder, and `formatReminderLead`.
- `customerAuth.notificationPreferences.unit.spec.ts`: checkout offset accepted; 2-day lead rejected for checkout.
- `booking.service.spec.ts`: Pending → Late, Late → No-show under a branch override, and Late left alone inside the threshold.
- `booking.validator.spec.ts`: threshold presets.
- `NotificationPreferencesGrid.spec.ts`: the checkout dropdown.
- `BookingStatusBadge.spec.ts`: Late.

## Open items

- **Migrations not pushed yet.** `supabase db push` still needs to run against the linked project after review.
- **Rescheduling a Late booking** is still blocked, as it was for any past-start booking. Allowing it would mean changing the reschedule notice rules.
- **The dashboard Assessment Queue widget** still asks the server for `status=Pending` only, so a Late assessment drops out of that widget. It is still on the full Assessment Queue page.
- **Policy Configuration page** has no spec file. The new dropdown was only type-checked, not covered by a test.
