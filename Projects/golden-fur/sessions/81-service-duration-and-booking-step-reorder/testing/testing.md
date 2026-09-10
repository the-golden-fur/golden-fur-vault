# Service average time, derived booking end time, and reordered booking steps

Branch: `feat/service-duration-and-booking-step-reorder` (golden-fur), commit `536f06b`
Vault branch: `docs/golden-fur-session-81`

## The request, verbatim

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

Scope note: the user confirmed the Hotel "3/5 nights" quick buttons and the
Hotel/Daycare care-instruction "10/15/20/30 min" quick buttons are **left
alone** — only the Date & Time step changes. They also confirmed the reorder
applies to **both** the customer portal and the receptionist flow (one shared
component).

## Root cause / Context

- `services.duration_minutes` (integer, nullable, `CHECK > 0`) has existed
  since the maintenance schema was created (`20260715032`). It is consumed
  end-to-end already: `booking.service.ts` snapshots it per item, the client
  `slotDurationMinutes` sums it, and `derivePackageDuration.ts` /
  `Package.total_duration_minutes` roll it up for packages. Only the admin
  **form** hid the input for non-Hotel/Daycare categories, so Grooming/Vet rows
  stayed `NULL` and every consumer fell back to 60.
- The Date & Time step (`case 'availability'`) previously ran **before** the
  Services step. With no items chosen it had no real duration, so it fed
  `SlotPicker` a fixed `DEFAULT_DURATION_MINUTES` stand-in (Grooming/Vet/Daycare
  60, Hotel 1440). That was introduced in the "#22 follow-up" precisely because
  re-deriving duration after item selection was wiping an already-picked slot.
  Reversing the order (Services first) removes the reason for the stand-in.
- Reusing `duration_minutes` rather than adding a parallel "average time"
  column keeps the one concept in one place (matches the project's
  collapse-redundant-models preference).

## What changed

### Database

- **edited** `supabase/migrations/20260715034_m13_seed_maintenance_data.sql` —
  the 10 seeded Grooming rows and 6 seeded Veterinary rows now carry
  first-draft `duration_minutes` instead of `NULL` (Bath 45, Blow-dry 30,
  Brushing 20, Nail Trim / Teeth Brushing / Ear Cleaning / Anal Drain 15, Face
  Trim 20, Dematting 60, Poodle Feet 20; Wellness Exam 30, Vaccination 15,
  Laboratory Test 20, Dental Cleaning 60, Surgery 120, Emergency Consultation
  45). Only affects a from-scratch `db reset`. (Also normalised this file's
  line endings from CRLF to LF per `.gitattributes`.)
- **new** `supabase/migrations/20260910183_m13_backfill_service_average_duration.sql`
  — idempotent `UPDATE public.services SET duration_minutes = <v> ... WHERE
id = '<fixed a13… id>' AND duration_minutes IS NULL` for the same 16 rows,
  so an already-provisioned dev/prod database picks the values up on
  `supabase db push`. The `IS NULL` guard means a re-run never clobbers a
  hand-tuned value.

Reference copy: `testing/service-average-duration.sql`.

### Server

No server code changed. `createServiceValidator` / `updateServiceValidator`
already accept `duration_minutes` for every category;
`services.service.ts` already persists it; `derivePackageDuration.ts` /
`booking.service.ts` already roll it up. Server suite stays green.

### Client

- `features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx` (+ CSS)
  — the duration `<input>` is no longer gated to Hotel/Daycare; the label is
  category-aware ("Average service time (minutes)" for Grooming / Veterinary /
  Assessment). A hint line explains it drives booking length and packages, and
  that blank = 60-minute default. The create/update payload builders already
  sent `duration_minutes` generically — untouched.
- `features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx`
  — a read-only "Estimated total time: Xh Ym" line under the included-services
  list, summing the picked services' `duration_minutes` (mirrors the server's
  `derivePackageDuration`); notes when a picked service has no time set.
- `shared/utils/formatDuration.ts` — **new** shared helper, `"1h 30m"` /
  `"45m"` / `"2h"`. Used by the booking caption and the package builder.
- `features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
  (+ CSS):
  - Step list rebuilt to Branch → Customer (staff only) → Pet → Service Type →
    Services → Booking Type (staff only) → Date & Time (+ Staff/Cage) → Care
    Instructions (Hotel/Daycare only) → Your bookings → Review.
  - `DEFAULT_DURATION_MINUTES` deleted; `SlotPicker` now gets the real
    `slotDurationMinutes`.
  - New caption under `SlotPicker`: `Ends <time> · <formatDuration>` for
    same-day categories, `Check-out <date> · <n> night(s)` for Hotel. Built
    from the existing `finalScheduledEnd` memo (which already applies the
    Hotel nights multiplier).
  - `StaffPickerList` now receives `finalScheduledEnd` as `scheduledEnd`
    (accurate window, now known at this step).
  - Follow-ons: initial `currentStepKey` / `reachedStepKeys` and
    `handleStartOver` start at `'branch'`; `goBack` from the cart and the
    `commitCurrentBookingDraft` doc point at `'availability'` (the new last
    configured step for same-day categories); draft storage key bumped
    `booking-draft:{staff,customer}` → `…:v2:` so an old-order draft lapses.
  - `CustomerBookingFlowPage.spec.ts` rewritten to walk the new order
    (helpers plus ~20 flow tests); one obsolete "#22 follow-up" regression
    repurposed, one new "changing services drops the picked slot" added.
- `features/veterinary/components/ScheduleFollowUpModal/ScheduleFollowUpModal.tsx`
  — comment-only: its `STAND_IN_DURATION_MINUTES` no longer references the
  deleted constant by name.

## Manual test — step by step

Start the app first: in the `golden-fur` folder run `npm run dev`, wait until
both the client (`http://localhost:5173`) and server (`http://localhost:3000`)
are up. The dev database is the `dev` Supabase project. If you rebuilt or
provisioned the database, apply the new migration
(`npm run supabase:push`) so the seeded Grooming/Vet services have durations —
otherwise they'll still show blank and the booking caption will read `1h 0m`.

### A. Admin can set a service's average time

1. Go to `http://localhost:5173`. Click **Staff Login** (top-right). Sign in as
   an **Admin** (staff test logins are in `golden-fur/server/.env`). You land on
   a page headed **Dashboard**.
2. Click the **gear / Settings** icon in the sidebar. In the settings panel
   click the **Services and Packages** tile, then the **Services** tab. You see
   a list of services (Bath, Blow-dry, …).
3. Click the **…** button on the **Bath** row → **Configure**. A dialog headed
   **Edit service** opens.
4. Confirm there is a field labelled **Average service time (minutes)** with a
   hint under it ("How long a booking for this service runs…"). Before this
   change, Grooming had no duration field at all.
   - Failure: no such field, or it's labelled "per block/night".
5. Change the value to `90`. Click **Save service**. The dialog closes and a
   green "Service updated." message shows.
6. Reopen **…** → **Configure** on **Bath**. The field still reads `90`.
   - Failure: it reverted to blank or 60.
7. Switch the **Category** dropdown in the dialog to **Hotel**. The label
   changes to **Duration per night (minutes)** and the hint disappears. Switch
   to **Daycare** → **Duration per block (minutes)**. (Cancel out without
   saving.)

### B. A package shows its derived total time

1. Still in **Services and Packages**, click the **Packages** tab.
2. Click **New package** (or **…** → **Configure** on the **Golden Package**).
3. In **Included services**, tick two services that have a time set (e.g.
   **Bath** = 90 from step A, **Blow-dry** = 30).
4. Under the service list a line reads **Estimated total time: 2h 0m (sum of
   the included services' average times)**.
   - Failure: no such line, or the sum is wrong.
5. Tick a service whose time is blank. The line gains a note: "… 1 service has
   no time set and count as 0; set it on the Services tab".
6. Cancel out without saving.

### C. New booking — steps are in the new order (staff flow)

1. In the sidebar open **Bookings** → **Bookings Queue**. Click **New booking**
   (top-right). The booking wizard opens.
2. The stepper across the top now reads, in order: **Branch → Customer → Pet →
   Service Type → Services → Booking Type → Date & Time → … → Review**.
   - Failure: Pet before Branch, or Date & Time before Services.
3. **Branch:** click a branch card, click **Next**.
4. **Customer:** click a client, **Next**.
5. **Pet:** click a pet, **Next**.
6. **Service Type:** click **Grooming**, **Next**.
7. **Services:** tick **Bath** (90 min) and **Blow-dry** (30 min). **Next**.
8. **Booking Type:** leave **Online Booking** selected. **Next**.
9. **Date & Time:** you're on the calendar + start-time list.

### D. New booking — the date/time step shows only start time + a derived caption

1. Continuing from C-9: the time list shows **start times only** (e.g. "9:00
   AM", "10:00 AM"), no "9:00–10:30" ranges, no duration dropdown.
2. Pick a start time from the list.
3. Directly **below the picker**, a boxed caption appears:
   **Ends 10:30 AM · 2h 0m** (start + 90 + 30 minutes).
   - Failure: no caption, or it reads "1h 0m" (means the services' durations
     didn't load — apply the migration), or the end time is inside a
     `<select>` rather than a plain label.
4. Go **Back** to **Services**, untick **Blow-dry**, **Next**, pick a start
   time again. The caption now reads **Ends 9:45 AM · 1h 30m** (just Bath).
5. Pick a **Groomer** in the Staff picker that appears under the caption.
   **Next** → you reach **Your bookings**, then **Next** → **Review**.
6. **Confirm booking**. It succeeds. (Optional DB check, Query 1 in the SQL
   file: `scheduled_end - scheduled_start` = 90 minutes;
   `booking_items.duration_minutes_at_booking` = 90.)

### E. Hotel booking — caption shows check-out + nights

1. New booking → Branch → Customer → Pet → **Service Type: Hotel** → **Next**.
2. **Services:** pick a Hotel cage service. **Next** → Booking Type → **Next**.
3. **Date & Time:** set **Number of nights** to `3` (the "3 nights" / "5
   nights" quick buttons are still there — unchanged). Pick an arrival time.
4. The caption reads **Check-out <date 3 days later> · 3 nights**.
5. Go Back to Services, back to Date & Time — nights still reads `3`.

### F. Customer portal uses the same new order

1. Log out. Log in as a **customer** (customer test login, or register one).
2. Sidebar → **Book a Service** (or the "New Booking" button). The wizard opens
   at **Branch** (was **Pet**). Order is **Branch → Pet → Service Type →
   Services → Date & Time → … → Review** — no Customer or Booking Type step.
3. The same start-time-only picker + "Ends … · …" caption appears on the Date &
   Time step.

### G. Old in-progress drafts don't break

1. As staff, start a new booking, get to the Services step, then close the
   wizard tab without confirming (this autosaves a draft).
2. Reopen **New booking**. A banner "We restored your in-progress booking."
   appears and you land back where you left off. (Drafts saved _before_ this
   change used a different storage key and are silently ignored — no error, you
   just start fresh.)

## Test suites

From this session's `ci-verifier` run (both repos) plus direct suite runs:

- `client`: **827 / 827 passing** (160 files); `tsc -b` clean; `build`
  succeeds; `eslint .` clean.
- `server`: **1027 / 1027 passing** (93 files); `lint` — 0 errors (33
  pre-existing `no-console` warnings, none in changed files).
- root `format:check` — clean; `test:seed` — 25 / 25 passing.
- `ci-verifier` VERIFY ALL: golden-fur all 7 checks green.

## Open items

- `supabase db push` to the linked **dev** project (`hikgijuipymfghfuyrjv`,
  confirmed not prod `gtqncxqsofqtzrlgxdfm`) is **not yet run** — do it as the
  closing step once the PR is green, so the seeded Grooming/Vet services get
  their durations on dev.
- The Services-step "Running total" shows 1-night Hotel pricing until nights is
  set on the later Date & Time step; the Review total is always correct. This
  is inherent to putting Services before Date & Time and was accepted.
- The `slot_duration_minutes` sent to the availability endpoint is clamped to
  `[15, 1440]`. An accumulated service pile over 1440 min (>24h of same-day
  services — not a real scenario) would be capacity-checked against a shorter
  window than the booking actually occupies. See `reviews/…-pre-pr.md`
  finding 3.
