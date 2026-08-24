# Show Unconfirmed Bookings in Groomer/Vet Queues - Filter Toggle

Type: Custom fix (not tracked against a specific sprint/epic backlog item)
Branch: `dev`

Reported symptom: a booking made through `/staff/bookings/queue` (the
Receptionist Bookings Queue) sat at status `Pending` and never showed up when
logging in as the assigned Groomer or Veterinarian. Investigation (see below)
found this was working as designed for the payment gate, but the design left
staff with **zero visibility** into cash/pay-at-counter clients who are still
coming in today - which is itself a gap worth closing.

## Root Cause (why a booking sits at `Pending`)

`bookings.status = 'Pending'` does **not** mean "awaiting staff approval" -
there is no approval step anywhere in this codebase
(`server/src/features/booking/services/booking.service.ts` lines ~205-321,
issue #51). It means **"awaiting payment confirmation"**:

- Veterinary bookings always auto-`Confirmed` (no payment gate).
- Grooming/Hotel/Daycare bookings auto-`Confirmed` only when
  `payment_confirmed` is true at creation (e.g. GCash/Maya paid online at
  booking time). Cash/pay-at-counter bookings are inserted as `Pending` and
  stay there until a cashier confirms payment - a flow that doesn't exist yet
  (`TODO(Sprint 5, M08)` in `booking.service.ts`).

Separately, `listGroomingQueue`
(`server/src/features/grooming/services/grooming.service.ts`) and
`listConsultationQueue`
(`server/src/features/veterinary/services/consultation.service.ts`) both
hardcode `.eq('status', 'Confirmed')` when building today's queue - by design,
since there's nothing to _service_ yet for an unpaid booking. But that also
means a Groomer/Vet had no way to see a cash client was coming in today until
the (non-existent) M08 cashier flow confirmed payment.

## Fix

Booking creation and the payment gate are unchanged throughout. This landed
in two passes - a first pass added bare visibility into `Pending` bookings
behind a checkbox, then a second pass (below) generalized that into a proper
filter bar shared across all three staff queues, per follow-up feedback that
the checkbox should instead look and work like the Receptionist Bookings
Queue's existing Date/Status filters, with the date filter expanded to
preset ranges (Today/This week/This month/All dates).

**Shared client component** (new):

- `client/src/shared/components/QueueFilterBar/dateRangePreset.ts`:
  `resolveDateRangePreset('today' | 'this_week' | 'this_month' | 'all')` -
  resolves a preset to an inclusive `{ from, to }` YYYY-MM-DD range, computed
  in UTC calendar terms (Monday-Sunday weeks) to match the server's own
  day-boundary queries. `'all'` returns `{ from: null, to: null }` (unbounded).
- `client/src/shared/components/QueueFilterBar/QueueFilterBar.tsx`: the
  toolbar itself - a Date preset `<select>` plus a Status `<select>` (options
  passed in as props, so each page supplies its own vocabulary), with a
  `children` slot for page-specific extra filters (Service type/Branch on the
  Receptionist page). Used by all three queue pages below.

**Backend** - every date-scoped queue query gained an optional inclusive
date range, defaulting to today when omitted (so every pre-existing caller/
test is unaffected):

- `GET /bookings` (`booking.validator.ts`/`booking.service.ts`/
  `booking.controller.ts`): new `date_from`/`date_to` query params,
  independent of the pre-existing exact-day `date` param (still used as-is
  by Daycare Check-in's own booking lookup). `listBookings`'s `filters` gained
  `dateFrom`/`dateTo`.
- `GET /grooming/queue` and `GET /veterinary/consultations/queue`
  (`grooming.service.ts`/`consultation.service.ts` + their controllers): same
  `date_from`/`date_to` params, threaded into `listGroomingQueue`,
  `listUnconfirmedGroomingBookings`, `listConsultationQueue`, and
  `listUnconfirmedVeterinaryBookings` via a shared `resolveDateRangeUtc()`
  helper (one copy per file, mirroring the existing `todayRangeUtc()`
  duplication pattern already present in both files).

**Client pages** - all three now render `<QueueFilterBar>` instead of their
own ad hoc date/status controls:

- `ReceptionistBookingsQueuePage.tsx`: the old single `<input type="date">`
  is replaced by the shared date-preset select (default "Today", matching
  prior behavior); Status moved into `QueueFilterBar`'s own select; Service
  type and (Superadmin-only) Branch remain as page-specific `children`.
- `GroomerDashboardPage.tsx` / `VeterinaryConsolePage.tsx`: the old "Show
  unconfirmed bookings" **checkbox is gone**, replaced by folding
  `'Unconfirmed (awaiting payment)'` into the shared Status dropdown
  alongside each page's own session/consultation statuses (`All`, then
  `Unconfirmed`, then `Waiting`/`In Progress`/`Completed` for Grooming or
  `Pending`/`Ongoing`/`Completed` for Veterinary). `All` shows the normal
  session/consultation list **and** the unconfirmed cards together (see
  Revision 2 below for why this changed from an earlier pass); selecting a
  specific session/consultation status narrows to just that status (hiding
  unconfirmed); selecting `Unconfirmed` shows only the unconfirmed cards.
  `listGroomingQueue`/`listConsultationQueue` on the client now also accept
  an optional `{ dateFrom, dateTo }` and always pass `includePending=true`
  as before.

**Tests updated/added** (no unrelated behavior changes):

- `dateRangePreset.spec.ts` / `QueueFilterBar.spec.ts` - new, cover each
  preset's boundary math (including Sunday/Monday edge cases and short
  months) and the component's rendering/callback wiring.
- `booking.service.spec.ts` - new tests asserting the `gte`/`lt` bounds a
  `dateFrom`/`dateTo` range produces, and that an exact `date` still wins
  when both are given.
- `grooming.api.spec.ts` / `veterinary.api.spec.ts` - new tests asserting
  `date_from`/`date_to` are forwarded as query params.
- `ReceptionistBookingsQueuePage.spec.ts` - new tests for the default
  "Today" range and for "This week" widening the requested range.
- `GroomerDashboardPage.spec.ts` / `VeterinaryConsolePage.spec.ts` - the
  checkbox test was replaced with a status-dropdown equivalent; two
  pre-existing tests needed `{ selector: 'span' }` added to a `getByText`
  lookup, since the new Status `<option>` elements now share text with the
  status badges (e.g. both an `<option>In Progress</option>` and the session's
  status badge render the literal text "In Progress").

## Revision 2: Date Presets, Name Resolution, and "All" Including Unconfirmed

Manual testing of Revision 1 surfaced four more issues, all fixed here:

1. **Date filter needed a "Tomorrow" option and a way to pick an arbitrary
   day** (the original single `<input type="date">` the filter bar replaced
   let you pick any day; the preset-only version didn't). Fixed in
   `dateRangePreset.ts`/`QueueFilterBar.tsx`:
   - `DateRangePreset` gained `'tomorrow'` and `'custom'`.
   - `resolveDateRangePreset` takes an optional third `customDate` (YYYY-MM-DD)
     argument, only consulted for `'custom'`.
   - `QueueFilterBar` gained required `customDate`/`onCustomDateChange` props
     and renders a `<input type="date" aria-label="Custom date">` immediately
     after the preset select, but only when `dateRangePreset === 'custom'`.
   - All three pages now hold a `customDate` state (defaulting to today's
     ISO date) and pass it through to `resolveDateRangePreset`.

2. **Receptionist Bookings Queue showed raw `customer_id`/`pet_id` prefixes**
   (`Customer 786140bd - Pet e2222660`) instead of names -
   `ReceptionistBookingsQueuePage.tsx` never resolved them, unlike the
   Groomer/Vet pages. Fixed by adding the same `getPet`/`getCustomerProfile`
   resolution pattern already used on those two pages (fetch by id after
   the bookings list loads, keyed `Record<string, Pet | CustomerProfile>`),
   and rendering `{pet.name} - Owner {owner.full_name}` (falling back to
   "Unknown pet"/"Unknown owner", matching the other two pages).

3. **Groomer/Veterinary Console showed "Unknown pet"/"Unknown owner" even
   though the pet/customer clearly existed** (service names resolved fine,
   only pet/owner names didn't). Root cause: `getPetController`
   (`server/src/features/customers/pets/pet.controller.ts`) and
   `getCustomerProfileController`
   (`server/src/features/customers/customer.controller.ts`) both gated
   non-owner staff access on `CUSTOMER_MANAGER_ROLES` (`Receptionist`,
   `Admin`, `Supervisor`, `Superadmin`) - **Groomer and Veterinarian weren't
   in that list**, so every `GET /pets/:id`/`GET /customers/:id` call from
   those roles 403'd, and the client's enrichment code silently fell back to
   "Unknown pet"/"Unknown owner" on any error. Fixed by adding a narrower,
   read-only `PET_LOOKUP_ROLES`/`PROFILE_LOOKUP_ROLES` (each
   `CUSTOMER_MANAGER_ROLES` plus `Groomer`/`Veterinarian`) consulted **only**
   by the single-record GET actions - list/create/update/delete on
   `/customers`/`/pets` still gate on the original `CUSTOMER_MANAGER_ROLES`
   unchanged, mirroring the existing `VACCINATION_MANAGER_ROLES` precedent
   (`vaccinationRecord.service.ts`) of extending one specific role for one
   specific already-legitimate need, rather than broadening blanket staff
   permissions.

4. **Unconfirmed bookings never showed under "All statuses"** in the
   Grooming Queue/Veterinary Console - the original design only revealed
   them when `Unconfirmed` was explicitly selected, which meant a queue with
   zero Confirmed sessions but several cash-paying walk-ins today looked
   completely empty under the default filter. Fixed: `'All'` now shows the
   session/consultation list **and** the unconfirmed cards together;
   `GroomerDashboardPage.tsx`'s `showSessions`/`showPending` and
   `VeterinaryConsolePage.tsx`'s `showPendingSection` were reworked so only
   picking one specific session/consultation status hides the unconfirmed
   cards (there's nothing to service yet for an unpaid booking under a
   specific in-progress status).

**Tests added/updated:**

- `dateRangePreset.spec.ts` - new cases for `'tomorrow'` (incl. a month
  rollover) and `'custom'` (with and without a `customDate`).
- `QueueFilterBar.spec.ts` - new cases: the custom-date input is hidden
  unless `'custom'` is selected, and shown/wired when it is.
- `ReceptionistBookingsQueuePage.spec.ts` - mocks `customers/api/customer.api`
  now; assertions switched from the old `/Customer cust-123/` text to the
  resolved pet/owner names.
- `customer.integration.spec.ts` / `pet.integration.spec.ts` - new tests
  asserting a Groomer and a Veterinarian can each `GET` a single
  customer/pet record belonging to someone else (the fix), while the
  existing tests asserting Groomer still gets `403` from `GET /customers`
  (list) and `DELETE /pets/:id` are untouched (the fix is scoped to
  single-record `GET` only).
- `GroomerDashboardPage.spec.ts` / `VeterinaryConsolePage.spec.ts` - the
  "hides unless Unconfirmed" test was replaced with one confirming
  unconfirmed bookings show under "All", stay visible under "Unconfirmed",
  and disappear under a specific session/consultation status.

## Automated Verification

From `server/`:

```powershell
npm.cmd run test
npx tsc --noEmit
```

From `client/`:

```powershell
npm.cmd run test
npx tsc -b
```

Expected: all tests pass (511 server, 317 client as of this revision), both
typechecks clean.

## Manual Verification

You'll need: a real Groomer account, a real Veterinarian account, a real
customer account with a pet, and a Grooming service at a branch - plus both
`server/` and `client/` dev servers running (`npm.cmd run dev` in each).

1. **Seed a cash (unconfirmed) Grooming booking for today.** Easiest via
   Supabase's Table Editor (`bookings` table, matching the screenshot in this
   conversation): set `service_category = Grooming`, `status = Pending`,
   `payment_method = Cash`, `payment_confirmed = false`,
   `assigned_staff_id` = your test Groomer's staff id, and
   `scheduled_start`/`scheduled_end` somewhere later today (UTC). Or use the
   Postman collection's steps 1-3, which do it through the real booking API
   (`POST /bookings` with `payment_confirmed: false`).
2. **Log into the Groomer dashboard** (`/staff/dashboard/groomer/queue` /
   Grooming Queue tile) as that Groomer.
3. **Confirm it shows up under the default "All statuses".** With Date on
   "Today", the seeded pet should appear tagged "Awaiting payment", with no
   status badge or action button (you can't mark it in-progress) - alongside
   any Confirmed sessions, if you have some.
4. **Select "Unconfirmed (awaiting payment)" in the Status dropdown.**
   Confirm the card is still there, and any Confirmed sessions are now
   hidden (this view is unconfirmed-only).
5. **Select a specific session status (e.g. "Waiting").** Confirm the
   unconfirmed card disappears - narrowing to a session status is about
   what's actively being serviced, which an unpaid booking isn't yet.
6. **Exercise the Date filter.** With Status still "All statuses": switch to
   "Tomorrow" and confirm only tomorrow's bookings show; switch to "This
   week"/"This month" and confirm other days this week/month appear (seed a
   second booking a day or two out if needed); switch to "Custom date", pick
   an arbitrary day (e.g. July 24, then July 23) via the date input that
   appears, and confirm the queue narrows to exactly that day each time;
   switch to "All dates" and confirm bookings from any date show up; switch
   back to "Today" and confirm it narrows back down.
7. **Confirm names resolve, not IDs.** The seeded pet/owner should show by
   name (e.g. "Buddy" / "Owner Jane Doe"), not a truncated UUID, in both the
   main session list and the unconfirmed card.
8. **Repeat steps 3-7 on the Veterinary Console**
   (`/staff/veterinary/console`) using the same Status dropdown pattern
   (`Pending`/`Ongoing`/`Completed`/`Unconfirmed (awaiting payment)`). Note a
   `Pending` **booking** (Unconfirmed) can't be seeded through normal booking
   creation - Veterinary always auto-Confirms (#51 AC-4) - so use the Sprint 3
   follow-up flow (`POST /veterinary/consultations/:id/follow-up`, #67) or a
   direct Table Editor edit to get one. Selecting a single consultation
   status (e.g. just "Ongoing") should narrow the kanban view down to that
   one column plus hide the unconfirmed cards; "All statuses" restores all
   three columns side by side plus the unconfirmed cards.
9. **Repeat steps 6-7 on the Receptionist Bookings Queue**
   (`/staff/bookings/queue`) - confirm the Date dropdown now offers all six
   options (Today/Tomorrow/This week/This month/Custom date/All dates,
   replacing the old single date picker) and still defaults to "Today";
   confirm booking rows show pet/owner names, not IDs; Service type and
   Branch (Superadmin only) filters are unchanged.
10. **Confirm nothing else broke.** Advancing a grooming session's status,
    starting/completing a consultation, and the Receptionist's
    reschedule/cancel actions all still work exactly as before.

Daycare and Hotel were checked and don't have an equivalent "queue" list to
extend: Hotel Check-in has no backend/route wired up yet (dashboard tile has
no link), and Daycare Check-in
(`server/src/features/daycare/services/daycareCheckIn.service.ts`) is a
single-booking check-in _action_ gated on `status = 'Confirmed'`, not a
browsable list - out of scope for this filter-visibility fix.
