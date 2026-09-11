# Notify a customer when another customer's downpayment beats them to the same slot

Branch: not yet created — staged directly on `dev` (working tree, uncommitted)

## The request, verbatim

> When making another booking, after an online booking was made by another customer, I can no longer choose the date/time slots he chosen (even though downpayment was still not paid). As a customer, I want to be able to select the same date time, staff/cage slots as a customer who DID NOT YET pay his downpayment for his online booking. Should be able to select the same slots (date time, preferred staff, etc.) if downpayment is still not paid (unconfirmed booking status). If one of the two customers were able to pay their downpayment first, notify the other customer to adjust his booking date time, staff or cage (e.g. tell them that the selected booking time is currently unavailable, please update your booking details). As a customer who failed to pay his downpayment before another customer, I want to be notified that my chosen slot for X booking is no longer available, and I want to be prompted immediately when I open into my dashboard to adjust them. If there are multiple bookings where I failed to pay my downpayment in time, I want you to list all of them in the popup modal, and record it in my notifications. I want the list items to be linked to the actual booking record.

(Verbatim match confirmed against `Projects/golden-fur/shared/context/Architectural-Change-History.pdf`, page 5, "In Progress" list, owner: Matthew.)

**Scope note:** the request reads as two asks. Research at the start of this
session found the first one — "let two unpaid customers share a slot" — was
**already implemented app-wide** by an earlier "advisor addendum" (migrations
from 20260829, `SLOT_HOLD_PAID_OR_FILTER`). Nothing needed to change there;
see "Root cause / Context" below for how that was re-confirmed. This session
built the second ask: the reactive notification when one of the two customers
actually pays.

## Root cause / Context

- **Already working, re-confirmed, not touched this session:** every place
  that counts how full a slot is — the Slot Picker's availability endpoint,
  the Staff Picker, the pre-booking capacity check, the post-booking race
  re-check — already skips any booking that is still `Pending` + unpaid +
  downpayment-required, via one shared filter,
  `SLOT_HOLD_PAID_OR_FILTER` (`server/src/features/booking/booking.types.ts:128`),
  used consistently in `capacity.service.ts`, `staffPicker.service.ts`, and
  the `get_staff_availability` Postgres function. A code comment at
  `server/src/features/booking/services/booking.service.ts:989` already says
  this explicitly: "multiple customers may pencil-book the same slot;
  whoever pays first reserves it." This was re-confirmed by reading the
  filter's usages and the existing capacity test coverage, not by a fresh
  manual click-through this session — see "Open items."
- **The actual gap, now closed:** nothing reacted when one of two competing
  customers actually paid. `applyFirstBookingPaymentSideEffects`
  (`booking.service.ts`) — called by both the PayMongo webhook and the
  cashier's "Mark as paid" screen after a payment settles — only re-checked
  and confirmed the *paying* customer's own booking. The other customer
  found out only if and when they themselves tried to pay (a "that slot
  filled up" 409 at that point) — nothing proactive, nothing on their
  dashboard, nothing in their notifications.
- No existing DB column meant "this booking needs a new slot," no existing
  notification type meant "your slot was taken," the Customer Portal
  dashboard had no "something needs your attention" popup pattern (staff
  have one for MFA setup — reused here as the model), and although
  notifications already stored `related_booking_id`, nothing client-side
  ever read it to navigate anywhere.

## What changed

### Database (two new migrations, both pushed to dev this session)

- `supabase/migrations/20260911188_m03_bookings_slot_conflict_columns.sql` —
  adds `bookings.slot_conflict_at timestamptz` and `bookings.conflict_notice
  text`, both nullable. `status` is left untouched (`'Pending'`) — this is a
  "please fix this" flag, not a cancellation.
- `supabase/migrations/20260911189_custom_notification_event_type_add_booking_slot_conflict.sql`
  — adds `booking_slot_conflict` to the `notification_event_type` enum, in
  its own migration (Postgres forbids using an `ADD VALUE` in the same
  transaction it was added in), following the same pattern as the existing
  `message_received`/`staff_assigned` additions.
- Pushed to the linked **dev** Supabase project (`hikgijuipymfghfuyrjv`, not
  prod `gtqncxqsofqtzrlgxdfm` — confirmed via `supabase/.temp/project-ref`)
  via `npm run supabase:push` earlier this session, and re-confirmed applied
  in this documentation pass via `npm run supabase:status` (both
  `20260911188` and `20260911189` show up in the local/remote/status
  columns).

Reference copies: `testing/slot-conflict-notifications.sql`.

### Server

- `server/src/features/booking/services/capacity.service.ts` — new
  `listOverlappingPencilBookings(...)`, the mirror image of the existing
  "who holds this slot" query: finds every *other* still-`Pending`, unpaid,
  downpayment-required booking (same branch + service category, overlapping
  window), excluding one booking id. Returns raw candidate rows only — it
  does not decide who "lost."
- `server/src/features/booking/services/booking.service.ts`:
  - `listConflictedBookingsForCustomer(customerId)` — a customer's own
    still-`Pending` bookings with `slot_conflict_at` set, joined against
    `pets`/`branches` for display names. Naturally scoped: a staff caller's
    id never matches a `bookings.customer_id`, so it returns empty for them
    without a separate guard.
  - `flagSlotConflictsForOthers(winner)` (private) — called from inside
    `applyFirstBookingPaymentSideEffects` right after a payment settles and
    the paying booking is re-confirmed to genuinely hold its own slot. Gets
    candidates from `listOverlappingPencilBookings`, narrows them
    (Grooming/Veterinary: same requested staff member only; Hotel: same
    weight-class/cage-size category, via the existing `filterSameSizeRows`
    helper; Daycare: no narrowing, shared per-branch capacity), then
    re-runs the **existing, already-tested** `checkCapacity(...)` per
    candidate as if that candidate were paying right now. Only a candidate
    that now fails `checkCapacity` gets `slot_conflict_at`/`conflict_notice`
    set and a notification sent. Wrapped in its own try/catch — a failure
    here logs but never fails the payment that triggered it. Documented
    known limitation (in the function's own doc comment): if per-slot
    capacity is ever raised above 1 and two still-unpaid candidates are
    only competing against each other, both could independently pass their
    own `checkCapacity` call and neither gets flagged — not fixed here
    since neither has paid yet, and whichever pays first still wins cleanly
    via the normal post-payment re-check.
  - `applyFirstBookingPaymentSideEffects` — restructured so the
    "does the winner still hold its slot" check and the
    revert-or-keep-and-flag logic each run exactly once, then calls
    `flagSlotConflictsForOthers` on the success path.
- `server/src/features/booking/services/bookingNotifications.service.ts` —
  new `sendSlotConflictNotification(booking, notice)`, the same shape as the
  existing `sendStaffAssignedNotification` (no email leg — meant to be seen
  immediately via the dashboard popup and the bell, not an inbox).
  `eventType: 'booking_slot_conflict'`, `relatedBookingId: booking.id`.
- `server/src/features/booking/services/reschedule.service.ts` — a
  successful reschedule now unconditionally clears
  `slot_conflict_at`/`conflict_notice` back to `null` (a no-op if they were
  already null). Also gained cage-preference support: a Hotel booking can
  now send `cage_preference` on reschedule (previously creation-only),
  re-verified the same way `createBooking` does, defaulting to the
  booking's current `preferred_cage_id` when omitted.
- `server/src/features/booking/modules/validators/booking.validator.ts` —
  `rescheduleBookingValidator` gained the optional `cage_preference` field
  (reuses the existing `cagePreferenceValidator`).
- `server/src/features/booking/booking.controller.ts` +
  `booking.routes.ts` — new `conflictedBookingsController` and `GET
  /bookings/conflicts/mine` (behind `jwtMiddleware`, not a staff/customer
  role gate — it's scoped to "whatever the caller's own id turns up," which
  is naturally empty for staff callers).
- `server/src/features/booking/booking.types.ts` — `Booking` gained
  `slot_conflict_at: string | null` and `conflict_notice: string | null`.
- `server/src/features/notifications/notifications.types.ts` —
  `NOTIFICATION_EVENT_TYPES` gained `'booking_slot_conflict'`.

### Client

- `client/src/features/customers/components/SlotConflictModal/` (new) —
  lists every conflicted booking (service, pet, branch, date/time, the
  `conflict_notice` text), each row a `<Link>` to
  `/portal/bookings?open=<id>`. Modeled on `StaffAuthGuard`'s always-mounted
  `MfaSetupModal` pattern (a boolean/list from a mount-time fetch drives an
  unconditionally-rendered modal). No "dismiss forever" — closing it only
  hides it for that visit; it reappears on the next dashboard load until
  every listed booking is rescheduled server-side.
- `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx`
  — the Customer Portal home page (`/portal`) now also fetches
  `listMyConflictedBookings` on mount (alongside the existing profile
  fetch) and mounts `SlotConflictModal`, open by default whenever the list
  isn't empty.
- `client/src/features/booking/api/booking.api.ts` — new
  `listMyConflictedBookings(accessToken)`.
- `client/src/features/booking/booking.types.ts` — new `ConflictedBooking`
  interface; `Booking` gained the same two nullable fields as the server
  type.
- `client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`
  ("My Bookings") — gained `?open=<bookingId>` deep-link support (same
  convention `NotificationsPage.tsx` already used): the URL param is read at
  render time (not synced into state via an effect) and merged with the
  existing "View details" click-state so both feed the same
  `BookingDetailsModal`; closing the modal also strips the `?open=` param
  from the URL.
- `client/src/features/notifications/components/NotificationBell/NotificationBell.tsx`
  — clicking a notification that carries `related_booking_id` now also
  navigates there (closes the dropdown first): `/portal/bookings?open=<id>`
  for a customer, `/staff/bookings/<id>` for staff (role inferred from the
  `notificationsHref` prop the bell is already given, not a new prop). This
  field existed on every notification already but nothing client-side read
  it before this change, so this fixes the same dead link for every
  existing booking-related notification type (confirmed, rescheduled,
  etc.), not just the new one.
- `client/src/features/notifications/notifications.types.ts` —
  `NotificationEventType` gained `'booking_slot_conflict'`.
- `client/src/pages/SettingsPage/tabs/NotificationPreferencesGrid.tsx` — the
  customer's notification-preferences grid gained a "Booking slot became
  unavailable" row so the new event type is toggleable, same as every other
  customer-facing notification type.

## Manual test — step by step

No live click-through against the running dev app was done this session —
everything below was verified via the automated test suites (services,
controller wiring, and the client components/pages) plus a direct check of
the two new migrations against the dev database. Treat every step below as
**not yet manually verified**; walk through it before merging.

Start the app first: in the `golden-fur` folder run `npm run dev` (check
nothing is already listening on the client/server ports first) and wait
until the client (`http://localhost:5173`) and server (`http://localhost:3000`)
are both up. The two new migrations are already applied to the linked dev
database, so no `supabase:push` is needed first.

Customer logins are the m02 seed accounts: `customer1@goldenfur.com`,
`customer2@goldenfur.com`, … password `password123`. Staff: a Cashier
account, e.g. `makati.cashier1@goldenfur.com` / `password123` (seed list:
`golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts`). You'll
need two browsers (or one normal + one private/incognito window) to be
logged in as two different customers at once.

### A. Two customers pencil-book the exact same slot (re-confirms the already-fixed half)

1. Browser 1: go to `http://localhost:5173`, click **Customer Login**, sign
   in as `customer1@goldenfur.com` / `password123`. In the sidebar click
   **Book a Service**. Walk through the wizard for a Grooming booking at the
   Makati branch, picking one of your pets, a specific groomer (not "No
   preference"), and a specific date/time. If the wizard offers a payment
   choice ("Pay downpayment now" vs. "Pay later" / "Reserve"), choose to
   leave the downpayment unpaid. Finish with **Confirm booking**.
   - Note the exact branch, groomer, date, and time you picked.
2. Browser 2 (private window): sign in as `customer2@goldenfur.com` /
   `password123`. Repeat the same wizard for a different pet, but choose the
   **exact same** branch, groomer, date, and time from step 1. Leave the
   downpayment unpaid here too.
   - **PASS:** the second booking is accepted without complaint — no "slot
     unavailable" error. This confirms the already-existing
     `SLOT_HOLD_PAID_OR_FILTER` behavior still holds.
   - **FAIL:** if customer 2 is blocked, stop — this is a regression outside
     this session's scope; report it separately rather than treating it as
     part of this feature.

### B. Customer 1 pays first — customer 2 gets flagged and notified

1. Sign in as staff at `http://localhost:5173` with
   `makati.cashier1@goldenfur.com` / `password123`. Open **Reports →
   Transaction History** (`/staff/reports/transaction-history`).
2. Find customer 1's Pending transaction for the booking from scenario A and
   click **Mark as paid**. Confirm the full amount, click **Mark as paid**
   again to submit.
   - **PASS:** the transaction settles normally, no error banner.
3. Still as staff (or via SQL), check customer 2's booking row:
   `select slot_conflict_at, conflict_notice, status from public.bookings
   where id = '<customer 2's booking id>';`
   - **PASS:** `slot_conflict_at` is now a recent timestamp, `conflict_notice`
     has a readable explanation, `status` is still `'Pending'` (not
     cancelled).
   - **PASS (customer 1's own booking):** unaffected — still confirms
     normally with no side effects.

### C. Customer 2's dashboard popup

1. In browser 2 (still logged in as customer 2, or log back in), navigate to
   `/portal` (click the **Home** icon, or the Golden Fur logo).
   - **PASS:** a pop-up titled **"A booking slot is no longer available"**
     appears immediately, unprompted, listing the affected booking (service
     type, pet name, branch, date/time, and the explanatory text).
   - **FAIL:** no pop-up appears, or it's empty.
2. Click the listed booking row.
   - **PASS:** you land on **My Bookings** (`/portal/bookings`) and that
     exact booking's details modal opens automatically (URL now reads
     `/portal/bookings?open=<id>`).
3. Close the details modal. Open the notification bell (top-right). Confirm
   there is a new, unread notification titled **"Your booking slot is no
   longer available"**.
4. Click that notification in the bell dropdown.
   - **PASS:** it's marked read (badge count drops) **and** you're navigated
     to `/portal/bookings?open=<id>` with the same booking's details open —
     this is the previously-dead `related_booking_id` link now working.

### D. Rescheduling clears the flag

1. From the open booking-details modal (either path above), use its
   **Reschedule** action to pick a genuinely free date/time (and, if it's a
   Hotel booking, optionally a different cage preference).
   - **PASS:** the reschedule succeeds.
2. Check the row again: `select slot_conflict_at, conflict_notice from
   public.bookings where id = '<id>';` — both should be `NULL`.
3. Reload `/portal` as customer 2.
   - **PASS:** the pop-up no longer appears (assuming this was the only
     conflicted booking).

### E. Multiple conflicts for the same customer

Repeat scenarios A–B for a second pair of overlapping bookings, again with
customer 1 winning and customer 2 losing (a different slot/service this
time). Reload `/portal` as customer 2 before rescheduling either one.

- **PASS:** the pop-up lists **both** conflicted bookings, not just one.

### F. Notification preferences

1. As customer 2, open **Settings → Preferences** (or wherever the
   notification-preferences grid lives) and confirm a new row **"Booking
   slot became unavailable"** is listed and toggleable, alongside the
   existing booking-related notification types.

## Test suites

Run and confirmed green in this documentation pass (re-run in full, not
just taken from an earlier report):

- `server`: `npx vitest run` — **1057 / 1057 passing** (95 files);
  `npx tsc --noEmit` clean; `npx eslint src` — 0 errors (34 pre-existing
  `no-console` warnings across the codebase, none newly introduced by this
  change).
- `client`: `npx vitest run` — **845 / 845 passing** (165 files);
  `npx tsc --noEmit` clean; `npx eslint src` — 0 problems; `npm run build`
  succeeds.
- `npm run format:check` (repo-wide) — clean.
- The four changed/added server spec files
  (`capacity.service.spec.ts`, `booking.service.spec.ts`,
  `reschedule.service.spec.ts`, `booking.validator.spec.ts`) were also run in
  isolation first: **153 / 153 passing**. New coverage there:
  `listOverlappingPencilBookings` (the mirror-image filter query, and the
  empty-window case), `flagSlotConflictsForOthers` (flags-and-notifies one
  losing candidate; flags nothing when nothing overlaps),
  `listConflictedBookingsForCustomer` (resolves pet/branch names; returns
  empty without extra queries when nothing is flagged), reschedule clearing
  the two columns, Hotel cage-preference-on-reschedule (both a new specific
  cage and an omitted one), and the validator accepting/rejecting
  `cage_preference`.
- The three changed/added client spec files
  (`CustomerPortalPage.spec.ts`, `CustomerBookingsPage.spec.ts`,
  `NotificationBell.spec.ts`) were also run in isolation first:
  **18 / 18 passing**. `NotificationBell.spec.ts` is a brand-new file — that
  component had zero prior test coverage; it now covers the customer
  `related_booking_id` navigation, the staff-side `/staff/bookings/<id>`
  navigation, and the no-navigation case for a notification with no related
  booking.
- `supabase`: both new migrations confirmed applied on the linked dev
  project (`hikgijuipymfghfuyrjv`) via `npm run supabase:status` (local,
  remote, and applied-status columns all show `20260911188` and
  `20260911189`).

## Open items

- **No manual click-through was performed this session** (see the "Manual
  test" header note above) — only automated tests and a direct DB/migration
  check. Every step in scenarios A–F needs a real run before this ships.
- **No Postman collection was added for this session.** This session's new
  API surface (`GET /bookings/conflicts/mine`, `cage_preference` on
  reschedule) is a thin controller/validator layer over service functions
  that already have direct unit coverage (see "Test suites" above), matching
  this codebase's existing pattern of service-level tests with no separate
  route/controller-level spec files anywhere in `server/src/features/booking`.
  Reproducing the actual two-customer race end-to-end via Postman would also
  require a full, multi-field `createBookingValidator` payload (branch
  eligibility, lead-time rules, staff/cage preference shapes) that's
  meaningfully more reliably exercised by actually running the two-browser
  manual test above than by a hand-built API script that was never run
  against a live server this session. Worth adding later if this area gets
  revisited and a live dev server is available to validate the collection
  against.
- `flagSlotConflictsForOthers`'s own doc comment flags one known,
  deliberately-not-fixed edge case: if a branch's per-slot capacity is ever
  raised above 1 and two still-unpaid candidates are only competing against
  each other, both could independently pass their own `checkCapacity` call
  and neither gets flagged (mirrors `confirmCapacityAfterInsert`'s own
  documented tie-break scope). Not exploitable today since every current
  branch/staff/cage capacity in this app is 1-per-slot; flagged in code for
  whoever changes that in the future.
- No git branch was created, nothing was committed, no PR was opened — the
  working tree is uncommitted/unstaged on `dev`, per this session's request.
