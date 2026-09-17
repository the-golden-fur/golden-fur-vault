---
title: Daycare — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, daycare]
project: golden-fur
---

Daycare lets staff check a pet in for the day (from an advance booking or as
a walk-in), track feeding/walking/playtime/medication instructions while
the pet is there, and check the pet back out with a time-based charge.
Under the hood it shares almost all of its machinery with Pet Hotel — a
Daycare visit is a row in the same `stays` table, just with
`stay_type: 'Daycare'`.

**Part of:** [[M06-daycare-management]]

## Client-side (`client/src/features/daycare/`)

### pages/

- **`DaycareQueuePage/DaycareQueuePage.tsx`** — the main screen. Loads the
  branch's Daycare bookings (via `listBookings` with
  `serviceCategory: 'Daycare'`), then loads each booking's pet and owner so
  the list can show names instead of IDs. Staff can filter by date range and
  status, search by pet/owner name, and sort. Clicking a row does something
  different depending on status: a `Pending` row opens
  `DaycareCheckInFormPage` to finalize the check-in; an `In Progress` row
  opens the shared Boarding Checklist (`/staff/hotel/care-log?petId=...`);
  anything else just shows a "View details" link. There's deliberately no
  per-row action button — the whole row is the action.
- **`DaycareCheckInFormPage/DaycareCheckInFormPage.tsx`** — the routed page
  reached by clicking a `Pending` row (`/staff/daycare/queue/check-in/:bookingId`).
  Checks the signed-in staff member's role against
  `DAYCARE_QUEUE_VIEWER_ROLES`, loads the booking by ID, and renders
  `DaycareCheckInPanel`. On success it navigates back to the queue with
  `?checkedIn=success`.
- **`DaycareQueuePage/DaycareCheckInPanel.tsx`** — the actual check-in form,
  rendered inside the page above. Fetches a suggested cage
  (`getCageSuggestion`) for the pet's weight class and lets staff override
  it via `CageStatusGrid`. Pre-fills feeding/walking/playing/medication
  fields from whatever the customer entered at booking time
  (`booking.hotel_preferences`), but everything stays editable — plain text
  inputs rather than Hotel's catalog-autocomplete version. On submit, it
  calls `checkInDaycareSession` with all of that plus a `notify_opt_in`
  flag; an "unavailable after [cutoff]" error is shown as a permanent
  blocked message rather than something to retry.
- **`DaycareQueuePage/DaycareCheckoutPanel.tsx`** — a small "ready to check
  out?" confirmation panel used by the Boarding Checklist's per-pet view. On
  success it shows a charge breakdown (first hour + N succeeding hours),
  computed client-side only for display — the total shown is always the
  server's own `computed_charge`, never recalculated locally.
- **`DaycareQueuePage/DaycareLegacyRedirects.tsx`** — three tiny components
  (`DaycareCheckInRedirect`, `DaycareCheckoutRedirect`,
  `DaycareCheckoutSessionRedirect`) that just bounce old bookmarked URLs
  (from before the queue redesign removed the separate check-in/checkout
  tabs) back to `/staff/daycare/queue`.
- **`DaycareQueuePage/daycareQueueRoles.ts`** — exports
  `DAYCARE_QUEUE_VIEWER_ROLES`, the set of staff roles allowed to view the
  queue and check-in page (Admin, Supervisor, Superadmin, Groomer, Pet
  Assistant).

### api/

- **`daycare.api.ts`** — thin `fetch` wrappers around the server routes:
  `checkInDaycareSession`, `listDaycareSessions` (with status/date-range
  filters), and `checkOutDaycareSession`. Each returns a
  `{ data, error }` shape rather than throwing.

### Types & routing

- **`daycare.types.ts`** — `DaycareStatus` (`'Active' | 'Completed'`),
  `CheckInPayload`, and `DaycareSession` — which is just a type alias for
  `HotelStay` from the hotel feature, not a separate shape. This is the
  clearest signal of the Daycare/Hotel unification: every existing
  `DaycareSession` call site keeps compiling unchanged even though it's
  really a Hotel stay row underneath.
- **`daycare.routes.tsx`** — defines the four staff-guarded routes (queue,
  routed check-in form, and the three legacy redirects) described above.

## Server-side (`server/src/features/daycare/`)

### Controller & routes

- **`daycare.controller.ts`** — three request handlers:
  `checkInDaycareSessionController`, `listDaycareSessionsController`,
  `checkOutDaycareSessionController`. Each validates the request with a Zod
  schema, calls the matching service function, and maps thrown errors (which
  carry a `statusCode`) to an HTTP response — anything without a
  recognized status code becomes a generic 500.
- **`daycare.routes.ts`** — mounts `POST /daycare/check-in`,
  `GET /daycare/sessions`, and `POST /daycare/sessions/:id/checkout`, each
  behind `jwtMiddleware`, `sessionTimeoutMiddleware`,
  `requireRole(DAYCARE_ADVANCE_ROLES)`, and `requireBranch`.

### Service

- **`services/daycareCheckIn.service.ts`** — the most important file here.
  `checkInDaycareSession` handles both paths: an existing booking
  (`booking_id`, must be `Pending` or an already-`In Progress` walk-in
  booking) or a brand-new walk-in (`pet_id` + `branch_id` directly). Before
  writing anything, it checks the branch's daily check-in cutoff —
  **Makati's is a hardcoded 4:00 PM constant**, not read from the
  `daycare_checkin_cutoff` column even though every branch has one; only
  Southwoods' value is actually used. Past the cutoff, no `stays` row is
  created at all. It then claims a cage via Hotel's
  `resolveAndClaimCage`, resolves which Daycare service's fee schedule
  applies (`resolveDaycareServiceId` — booking's own service, an explicit
  walk-in choice, or the branch's first active Daycare service), inserts the
  `stays` row, syncs the linked booking to `In Progress` if needed, inserts
  the care instructions, and generates today's Care Log entries (Daycare
  never spans multiple nights, unlike Hotel). If anything fails after the
  cage is claimed, the whole block is wrapped so the cage is released back
  to `Available` rather than left stranded as `Occupied`. `listDaycareSessions`
  is a simple filtered/sorted read of `stays` scoped to `stay_type: 'Daycare'`.
- **`services/daycareBilling.service.ts`** — the other core file.
  `computeDaycareCharge` is the billing formula: a flat first-hour fee, plus
  a succeeding-hour fee for each hour past the first (rounding any partial
  hour up), plus a flat per-night overnight fee for every branch closing
  time the stay spans (0 for a same-day pickup). Fee amounts come from the
  session's own Daycare service (`resolveDaycareFeeSchedule`), falling back
  to documented defaults (₱100 / ₱50 / ₱850) if the service has no fee
  columns set. `checkOutDaycareSession` requires the shared Boarding
  Checklist to be complete first (`assertChecklistComplete`, same gate
  Hotel uses), then atomically sets `status: 'Completed'` and
  `computed_charge` together so a session can never end up Completed
  without a stored charge, releases the cage back to `Available`, and syncs
  the linked booking to Completed (tolerating a 409 if the booking was
  independently cancelled in the meantime, since the `stays` row is already
  the authoritative record that checkout happened).

### Types & validators

- **`daycare.types.ts`** — `DAYCARE_ROLES` (front-desk roles: Receptionist,
  Admin, Supervisor, Superadmin) and `DAYCARE_ADVANCE_ROLES` (those plus
  Groomer and Pet Assistant, since Daycare has no dedicated assigned-staff
  role of its own), plus the same `DaycareStatus`/`DaycareSession` alias as
  the client.
- **`modules/validators/daycare.validator.ts`** — `checkInValidator` (Zod):
  enforces the either/or rule between `booking_id` and `pet_id` +
  `branch_id`, and reuses Hotel's own feeding/walking/playing/medication
  schemas so both categories validate care instructions identically.
  `listDaycareSessionsQueryValidator` validates the status/date-range query
  params for the sessions list.

## How it connects

Advance Daycare bookings come from [[M03-appointment-booking]]; walk-ins are
created directly by a receptionist. Check-in and checkout both reuse Pet
Hotel's cage-assignment and care-instruction services
([[M05-pet-hotel-boarding-management]]) rather than anything
Daycare-specific, and checkout is gated by the same shared Boarding
Checklist. See [[M06-01-daycare-check-in]] and
[[M06-02-daycare-checkout-billing]] for the full step-by-step flows and
diagrams. Fee schedules are configured per service in
[[M13-maintenance-packages-services-promos]]; billing ultimately flows to
[[M08-sales-billing]].
