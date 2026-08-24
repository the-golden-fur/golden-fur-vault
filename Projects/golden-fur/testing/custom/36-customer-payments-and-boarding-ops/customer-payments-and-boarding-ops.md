# 36 - Customer Payments, Booking Safeguards & Boarding Ops Overhaul

Ten requested changes from a screenshot-driven review pass across the
customer portal and staff portal, plus two follow-up bug-fix rounds from
live testing against the result (folded into the same items below rather
than given their own numbers, since they corrected the same code).

1. **Food & Medication catalog** - drop the "Provided by the hotel" label;
   every row is customer-owned now.
2. **Customer Settings sidebar** - remove the tile duplicated by the navbar
   gear icon.
3. **Customer online payments** - a Pay button on `/portal/bookings`,
   full-or-downpayment, via the existing PayMongo integration.
4. **Configurable booking-reminder timing** - customers choose how long
   before an appointment the reminder fires.
5. **Admin online-payments toggle** - Admin/Superadmin can disable PayMongo
   checkout per branch; the customer Pay button stays visible but disabled.
6. **Downpayment lock-in** - selecting a high-price service locks the
   booking to that service alone (kept on `services`, not `service_types`,
   per your call - see "Important decisions" below).
7. **Boarding Checklist** (rename of Hotel Care Log) - Groomer access,
   Hotel+Daycare merged, Kanban board grouped by status/time-of-day.
8. **Duplicate-booking prevention** - a pet with an unresolved booking is
   unselectable at the pet-picker step, in _any_ category (widened from an
   initial Hotel/Daycare-only pass after you found a Grooming duplicate).
9. **Hotel Queue edit form** - its own routed page instead of an inline
   popup; fields locked until Edit; cage maintenance moved under a "..."
   menu.
10. **Cage CRUD** - full create/edit/delete for cages, Admin/Superadmin
    only.

---

## Important decisions made along the way

- **Downpayment threshold**: kept `requires_downpayment` on `services`
  (not `service_types`, which you get picked first in the booking flow) -
  every seeded service **≥ ₱1,000** now requires a 50% downpayment
  (Dental Cleaning ₱1,500, Surgery ₱3,000, Emergency Consultation ₱1,000,
  joining the existing Overnight Stay ₱850). Booking a downpayment service
  locks the booking to that service alone, client- and server-side.
- **Boarding Checklist scope**: Kanban view only in this pass. List/Gallery
  views are an explicit follow-up, not built now.
- **Duplicate-booking scope**: started as Hotel/Daycare-only, then widened
  to _any_ category after you reported a duplicate Grooming booking for the
  same pet. "Unresolved" means `Pending` or `In Progress` - a `Completed`
  booking frees the pet up again.
- **A pre-existing bug got fixed along the way, not introduced by this
  batch**: booking creation was 400ing (`Could not find the
'downpayment_amount' column of 'booking_items'`) because the insert
  spread every field off a resolved service/package, including three that
  only exist on `services`/`packages`, never on `booking_items`. This
  predates this session; it's fixed as part of item 6's commit since it's
  the same file.
- **Cage picker cleanup**: while investigating item 8/9, found that
  `/staff/bookings/new` rendered two cage-selection widgets at once - an
  old `CagePicker` component that displayed cage info but never persisted
  a selection anywhere, alongside the real `CagePickerList` (wired to
  `bookings.preferred_cage_id`). Deleted the dead one; its one useful bit
  (a "Recommended" size badge matching the pet's weight class) moved onto
  `CagePickerList`.
- **This-week queue filter bug** (found during item 9 testing): the
  `this_week` preset computed a fixed Monday-Sunday range, so on a Sunday
  the range's own upper bound was today and tomorrow's booking fell into
  "next week" - reproducible every single Sunday. Changed to a rolling
  7-day window (today through today+6) so it always agrees with the
  Tomorrow preset.

---

## 1. Food & Medication catalog - customer-owned

**What changed:** `CustomerFoodMedicationPage.tsx` no longer branches on
`owner_customer_id` to show a "Provided by the hotel" label - every row
renders the same way now. A backfill migration reassigns any pre-existing
`owner_customer_id IS NULL` hotel food/medication rows onto the seed's
demo customer so nothing is orphaned once the seed re-runs with real
ownership baked in.

**Files:** `client/src/features/catalog/pages/CustomerFoodMedicationPage/CustomerFoodMedicationPage.tsx`,
`supabase/seeds/module-4-hotel/module-4-hotel.seed.{ts,sql,spec.ts}`,
`supabase/migrations/20260809115_custom_backfill_product_catalog_customer_owner.sql`.

**Verify manually:**

1. As a customer, go to `/portal/food-medication`. Confirm no row reads
   "Provided by the hotel" anywhere.
2. Re-run the module-4-hotel seed locally and confirm every inserted
   food/medication row already has a non-null `owner_customer_id`.

---

## 2. Customer Settings sidebar - remove duplicate tile

**What changed:** removed the `Settings` entry from
`CUSTOMER_SIDEBAR_SECTIONS`. The navbar gear icon still links to
`/portal/settings` and is unaffected.

**Files:** `client/src/features/customers/config/customerPortal.config.ts`.

**Verify manually:** log in as a customer, confirm the sidebar no longer
shows a Settings tile, and the navbar gear icon still opens
`/portal/settings`.

---

## 3. Customer online payments (Pay button)

**What changed:** a new customer-facing endpoint
(`POST /bookings/:id/pay`) reuses the existing PayMongo GCash/Maya
integration (`initiatePaymongoPayment`) to create a `booking_payment`
transaction the same way the cashier checkout flow does, tagged
`initiated_by: 'customer'` so the existing webhook
(`confirmPaymongoWebhookEvent`) can additionally advance the booking's
`payment_stage` once PayMongo confirms it. `CustomerBookingsPage.tsx` gets
a **Pay** action per row (shown when `payment_stage` is `Unpaid`, or
`Paid in Advance` with a remaining balance), opening a modal to choose
full vs. downpayment (downpayment only offered if the booking's
service/package actually requires one) and GCash vs. Maya, then redirects
to PayMongo's `checkoutUrl`. Service failures (PayMongo error, network
error, payments disabled - see item 5) surface as an inline modal error,
not a silent failure.

**Files:** `server/src/features/billing/services/customerBookingPayment.service.ts` (+ spec, new),
`server/src/features/billing/services/webhookConfirmation.service.ts` (+ spec),
`server/src/features/billing/billing.types.ts`,
`server/src/features/booking/{booking.controller,booking.routes,booking.types}.ts`,
`server/src/features/booking/modules/validators/booking.validator.ts`,
`client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx` (+ spec),
`client/src/features/booking/{api/booking.api,booking.types}.ts`,
`supabase/migrations/20260809118_custom_transactions_customer_initiated_payment.sql`.

**Verify manually:**

1. As a customer with an Unpaid booking, go to `/portal/bookings` and
   click **Pay**. Confirm the modal offers full/downpayment (if
   applicable) and GCash/Maya.
2. Complete a GCash or Maya test payment against PayMongo's sandbox for
   both a full payment and a downpayment; confirm the booking's
   `payment_stage` advances once the webhook fires.
3. Trigger a failure (e.g. temporarily break the PayMongo test key) and
   confirm the modal shows an inline error instead of failing silently.

---

## 4. Configurable booking-reminder timing

**What changed:** `notification_preferences.appointment_reminder` gained a
`reminder_offset_minutes` field (15 min, 1h, 3h, 1 day, 2 days - default
1 day, matching the old fixed behavior). The existing
`PATCH /customers/notification-preferences` endpoint accepts
`{event_type: 'appointment_reminder', reminder_offset_minutes}` as an
alternative body shape to the existing `{event_type, channel, enabled}`
one. Because a per-customer offset can't be satisfied by a single daily
8am batch, `appointmentReminder.job.ts` now polls every 15 minutes over a
lookahead window and fires each booking once `now` crosses
`scheduled_start - offset`, deduped via a new `bookings.reminder_sent_at`
column so a booking is never reminded twice regardless of how many polls
pass. The dropdown in Settings > Preferences is disabled (read-only) when
both notification channels for that event are off, since there'd be
nothing to time.

**Files:** `server/src/features/notifications/notifications.types.ts`,
`server/src/features/notifications/services/appointmentReminder.job.ts` (+ spec, new),
`server/src/features/auth/customers/customerAuth.routes.ts` (+ new unit spec),
`client/src/shared/api/preferences.api.ts`,
`client/src/pages/SettingsPage/tabs/NotificationPreferencesGrid.tsx` (+ spec, new)
and `SettingsPage.module.css`,
`supabase/migrations/20260809119_custom_bookings_reminder_sent_at.sql`.

**Verify manually:**

1. As a customer, go to **Settings > Preferences**. Confirm a "Send the
   reminder" dropdown appears directly under "Booking reminder" with
   preset offsets.
2. Turn off both Email and In-browser for "Booking reminder" - confirm the
   offset dropdown becomes greyed out/read-only.
3. Set a short offset (15 min), create a booking scheduled just past that
   window, and confirm the reminder fires once at the right time (not
   repeatedly on later polls).

---

## 5. Admin online-payments toggle

**What changed:** `policy_configurations` gained
`online_payments_enabled` (branch-overridable, same shape as the existing
`staff_picker_enabled_*` columns), editable by Admin/Superadmin on
`PolicyConfigurationPage.tsx`. A new read endpoint
(`GET /bookings/online-payments-status`) exposes the resolved flag to the
customer app, since customers have no direct `SELECT` on
`policy_configurations`. When disabled, the customer Pay button (item 3)
stays visible but is disabled with a tooltip explaining online payments
are unavailable.

**Files:** `supabase/migrations/20260809117_custom_policy_online_payments_enabled.sql`,
`server/src/features/booking/services/staffPicker.service.ts`,
`server/src/features/booking/{booking.controller,booking.routes,booking.types}.ts`,
`server/src/features/booking/modules/validators/booking.validator.ts`,
`client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`,
`client/src/features/booking/{api/booking.api,booking.types}.ts`.

**Verify manually:**

1. As Admin, go to **Settings > Config > Policies** and toggle "Online
   payments" off for a branch, save.
2. As a customer at that branch, go to `/portal/bookings` - the Pay button
   should still render but be disabled, with a tooltip/popover explaining
   why. Toggle it back on and confirm the button becomes clickable again.

---

## 6. Downpayment lock-in

**What changed:** `toggleServiceSelect`/`togglePackageSelect` in
`CustomerBookingFlowPage.tsx` now treat any service/package with
`requires_downpayment: true` the way Hotel/Daycare's existing
single-select categories already work - selecting one replaces the whole
selection with just that item and disables the other option cards, with
explanatory copy. The same rule is enforced server-side in
`createBooking` so it can't be bypassed by a direct API call. The seed now
marks Dental Cleaning, Surgery, and Emergency Consultation (all ≥ ₱1,000)
as 50%-downpayment services, alongside the pre-existing Overnight Stay
row.

**Files:** `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.{tsx,module.css,spec.ts}`,
`server/src/features/booking/services/booking.service.{ts,spec.ts}`,
`supabase/migrations/20260809116_custom_downpayment_high_price_services.sql`.

**Verify manually:**

1. Start a Veterinary booking, select "Emergency Consultation" (or Dental
   Cleaning/Surgery) - confirm the other service option cards grey out
   with an explanation, and the selection can't be widened.
2. Send a direct `POST /bookings` with two `service_id`s where one
   requires a downpayment - confirm a 400.
3. Complete a booking with just that one service and confirm no more 400
   on submission (see the pre-existing `booking_items` bug note above -
   this was blocking every booking, downpayment or not, before this fix).

---

## 7. Boarding Checklist (Hotel Care Log rename + Kanban)

**What changed:** `HotelCareLogPage` is replaced by
`BoardingChecklistPage`, reachable by Groomer as well as Pet
Assistant/Supervisor/Admin/Superadmin (`HOTEL_PET_ASSISTANT_ROLES` widened
to include `'Groomer'`). It now covers both Hotel and Daycare stays via
subtabs rather than a filter, reusing the existing unified `stays` table.
`care_log_entries` gained two columns: `time_block`
(Morning/Noon/Afternoon/Evening, populated at generation time and
backfilled for existing rows) and `status`
(Pending/In Progress/Completed, replacing the old binary
completed/not-completed as the Kanban's primary grouping). The new
`BoardingChecklistKanban` component renders three status columns, cards
sortable by time ascending/descending and secondarily grouped by
time-of-day, with a circular Todoist-style checkbox and small
Start/Complete/reopen actions per card, plus a search-by-pet-name box.
List and Gallery views are **not** built in this pass (explicit
follow-up). Also folded in here: the staff-set "owner opted in to pet
status notifications" checkbox is gone from the check-in/edit form - the
customer's own `care_log_completed` notification preference is now the
single source of truth for whether that email fires.

**Files:** `client/src/features/hotel/components/BoardingChecklistKanban/*` (new),
`client/src/features/hotel/pages/BoardingChecklistPage/*` (new, replaces deleted `HotelCareLogPage/`),
deleted `client/src/features/hotel/components/CareLogChecklist/*`,
`client/src/features/hotel/{hotel.routes.tsx,hotel.types.ts,api/hotel.api.ts}`,
`client/src/features/staff/config/staffDashboard.config.ts`,
`client/src/features/hotel/pages/HotelQueuePage/HotelCheckInPanel.{tsx,spec.ts}`,
`server/src/features/hotel/hotel.{controller,routes,types}.ts`,
`server/src/features/hotel/services/{careInstructions.service,careLogCompletion.service}.ts` (+ specs),
`server/src/features/hotel/services/careLogNotifications.service.ts`,
`server/src/shared/email/careLogCompletedEmail.ts`,
`supabase/migrations/20260809120_custom_care_log_entries_time_block.sql`,
`supabase/migrations/20260809121_custom_care_log_entries_status.sql`.

**Verify manually:**

1. Log in as Groomer - confirm a "Boarding Checklist" tile now appears on
   the dashboard (it did not before this fix - an earlier pass added it to
   the Pet Assistant dashboard but missed the admin oversight config's
   separate Groomer subsection).
2. Check in a pet to Hotel and one to Daycare; open the Boarding
   Checklist. Confirm both appear as cards under the right subtab, grouped
   by Morning/Noon/Afternoon/Evening, and the circular checkbox moves a
   card from Pending -> In Progress -> Completed.
3. Open a check-in/edit form and confirm the "Owner opted in..." checkbox
   is gone. Complete a care-log task for a customer who has the
   `care_log_completed` email preference on - confirm the email still
   sends regardless of what the old checkbox used to say.

---

## 8. Duplicate-booking prevention

**What changed:** `listPetBookingConflicts` (server) returns, per pet, the
most relevant `Pending`/`In Progress` booking regardless of category (this
started as a Hotel/Daycare-only check and was widened after a duplicate
Grooming booking was found in testing). On the pet-selection step of
`CustomerBookingFlowPage.tsx`, a pet with a conflict is no longer a native
`disabled` button (which never fires `onClick`) - it's `aria-disabled`
only, and clicking it opens a small prompt linking straight to the
conflicting booking ("View that booking" for staff, "Go to My Bookings"
for customers) instead of just sitting inert.

**Files:** `server/src/features/booking/services/booking.service.{ts,spec.ts}`,
`server/src/features/booking/{booking.controller,booking.routes,booking.types}.ts`,
`server/src/features/booking/modules/validators/booking.validator.ts`,
`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.{tsx,module.css,spec.ts}`,
`client/src/features/booking/{api/booking.api,booking.types}.ts`.

**Verify manually:**

1. Book a pet into Hotel, then try to book the _same_ pet into Grooming
   before the first resolves - confirm the pet card is greyed out but
   still clickable, and clicking it shows a prompt linking to the existing
   booking.
2. Mark the first booking No-show/Cancelled/Completed - confirm the pet
   becomes fully selectable again.
3. Repeat both in receptionist mode (`/staff/bookings/new`) - the prompt
   should link into the staff booking-detail view instead of
   `/portal/bookings`.

---

## 9. Hotel Queue edit form - routed page + cage overflow menu

**What changed:** the inline check-in/edit popup on `/staff/hotel/queue`
is now its own routed page (`HotelCheckInFormPage`), fields disabled by
default until an explicit, visually prominent Edit action is taken.
`CageStatusGrid.tsx` gained a "..." menu per cage that now holds "Mark as
Under Maintenance" instead of it being an always-visible button. While
investigating this item, found `/staff/bookings/new` rendered **two** cage
pickers at once - a dead `CagePicker` component (displayed info, never
persisted a selection) alongside the real `CagePickerList`
(persisted via `bookings.preferred_cage_id`). Deleted `CagePicker`
entirely; its one useful signal (a "Recommended" size badge for the pet's
weight class) was folded into `CagePickerList` via a new
`recommendedSize` prop.

**Files:** `client/src/features/hotel/pages/HotelCheckInFormPage/*` (new),
`client/src/features/hotel/pages/HotelQueuePage/{HotelCheckInPanel.tsx,HotelQueuePage.tsx,HotelQueuePage.module.css}`,
`client/src/features/hotel/components/CageStatusGrid/{CageStatusGrid.tsx,CageStatusGrid.module.css}` (+ new spec),
`client/src/features/hotel/hotel.routes.tsx`,
deleted `client/src/features/booking/components/CagePicker/*`,
`client/src/features/booking/components/CagePickerList/{CagePickerList.tsx,CagePickerList.module.css}`.

**Verify manually:**

1. From `/staff/hotel/queue`, open a stay's edit action - confirm it
   navigates to its own page (not an inline popup) with every field
   disabled and a prominent Edit button that unlocks them.
2. On the cage grid, confirm "Mark as Under Maintenance" now lives behind
   a "..." menu per cage instead of being always visible.
3. On `/staff/bookings/new`, pick Hotel and reach the cage step - confirm
   only **one** cage-selection UI renders, with a "Recommended" badge on
   the size matching the selected pet's weight class.

---

## 10. Cage CRUD

**What changed:** Admin/Superadmin can now create, edit, and delete
specific cages from **Settings > Config**, not just toggle Under
Maintenance. Two new RLS policies (branch-scoped INSERT/DELETE for
`Admin`; Superadmin already has an unrestricted `for all` policy).
Deleting a cage with an active stay is blocked in application code
(`deleteCage()`), not by the RLS policy itself. Note: like the rest of the
cages feature, there's no cross-branch override for Superadmin here - a
Superadmin managing multiple branches' cages has the same single-branch
scoping every other staff caller gets via `requireBranch`, matching the
existing limitation rather than introducing a new inconsistency.

**Files:** `client/src/features/hotel/pages/AdminCagesPage/*` (new),
`client/src/pages/SettingsPage/tabs/ConfigTab.tsx`,
`client/src/features/hotel/{api/hotel.api.ts,hotel.routes.tsx}`,
`server/src/features/hotel/services/cageStatus.service.{ts,spec.ts}`,
`server/src/features/hotel/hotel.{controller,routes,types}.ts`,
`server/src/features/hotel/modules/validators/hotel.validator.ts`,
`supabase/migrations/20260809122_custom_cages_admin_crud.sql`.

**Verify manually:**

1. As Admin, go to **Settings > Config > Cages**, create a new cage
   (label/size), confirm it appears in the operational `CageStatusGrid` at
   `/staff/hotel/queue`.
2. Edit the cage's label, confirm it updates on the grid. Try deleting a
   cage that currently has an active stay - confirm it's blocked; delete
   an empty one - confirm it disappears from the grid.
3. As a non-Admin/Superadmin role (e.g. Receptionist), confirm the Cages
   config page is unreachable.

---

## Migrations

Eight new migrations, applied in order:
`20260809115` through `20260809122` (see the list at the top of this
document). All are additive (new columns/policies) or backfills - no
destructive changes, safe to run as one batch. Bundled for reference in
`customer-payments-and-boarding-ops.sql` in this folder; source of truth
is still `supabase/migrations/`.

- **With Supabase CLI access:** `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access:** Supabase Dashboard -> **SQL Editor** ->
  **New query** -> paste `customer-payments-and-boarding-ops.sql` from
  this folder -> **Run**. Afterwards, confirm with:

  ```sql
  select online_payments_enabled from public.policy_configurations limit 1;

  select initiated_by, payment_choice
  from public.transactions
  where initiated_by = 'customer'
  limit 1;

  select id, requires_downpayment, downpayment_amount
  from public.services
  where id in (
    'a1300000-0000-4000-a000-000000000019',
    'a1300000-0000-4000-a000-000000000020',
    'a1300000-0000-4000-a000-000000000021'
  );

  select column_name from information_schema.columns
  where table_name = 'care_log_entries'
    and column_name in ('time_block', 'status');

  select column_name from information_schema.columns
  where table_name = 'bookings' and column_name = 'reminder_sent_at';
  ```

  The first query should return one row (`true`, the new default). The
  third should return three rows, all with `requires_downpayment = true`
  and `downpayment_amount = 50`. The fourth should return two rows.

## Postman

`customer-payments-and-boarding-ops.postman_collection.json` in this
folder covers the new/changed API surface: customer Pay
(`POST /bookings/:id/pay`), online-payments status
(`GET /bookings/online-payments-status`), pet booking conflicts
(`GET /bookings/pet-conflicts`), reminder-offset update
(`PATCH /customers/notification-preferences`), and cage CRUD
(`POST /hotel/cages`, `PATCH /hotel/cage/:id`,
`DELETE /hotel/cage/:id`). Fill in `customer_email`/`customer_password`,
`admin_identifier`/`admin_password`, and `branch_id` in the collection
variables before running requests 1 through 9 in order - each has a
**Tests** tab that should go green. The PayMongo payment-initiation
request will succeed up through source creation but won't complete an
actual sandbox payment from Postman - use the browser flow in item 3's
verification steps for an end-to-end payment.

## Test suites

- `server`: `npm test` (from `server/`) - **815 tests pass**. New:
  `customerBookingPayment.service.spec.ts`, `appointmentReminder.job.spec.ts`,
  `customerAuth.notificationPreferences.unit.spec.ts`.
- `client`: `npm test` (from `client/`) - **582 tests pass**. New:
  `NotificationPreferencesGrid.spec.ts`, `CageStatusGrid.spec.ts`,
  `BoardingChecklistKanban.spec.ts`, `AdminCagesPage.spec.ts`. Updated:
  `CustomerBookingFlowPage.spec.ts` (downpayment lock-in, conflict prompt,
  cage-picker cleanup), `CustomerBookingsPage.spec.ts` (Pay button),
  `HotelCheckInPanel.spec.ts` (routed edit, opt-in checkbox removal),
  `dateRangePreset.spec.ts` (this-week rolling-window fix).
- `server`: `npx tsc --noEmit` clean. `client`: `npx tsc -b` clean.

## Suggested branch name

`feat/customer-payments-hotel-ops`
