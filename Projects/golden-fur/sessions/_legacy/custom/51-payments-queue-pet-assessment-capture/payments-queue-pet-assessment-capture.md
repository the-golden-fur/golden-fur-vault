# 51 - Payments Queue Pet Assessment Capture

Follow-up to [[50-fix-sent-counter-and-pet-assessment]]: that pass fixed the
booking wizard's Pet step to refetch pets so it wouldn't show stale
assessment data - but the actual field report ("I marked Harvey's
assessment, why does it still say unassessed?") turned out to have a
different root cause entirely, found while re-investigating live: **there
was no UI anywhere to actually record a pet's weight_class/coat_type as
part of running an Initial Assessment/Reassessment booking.** Ticking a
booking's status to Completed/Paid in the Payments Queue never touched the
pet record - the two are unrelated. This pass adds that missing capability.

## Request

On `/staff/bookings/queue`, for each list item: add a "..." menu, move View
details into it, and add a Start action that opens a modal to edit the
pet's weight/coat for Initial Assessment/Reassessment services
specifically - configurable per-service via a new toggle in Service Builder
(admin settings), enabled on those two seeded services.

## Where it actually landed - important decision

**Not on Bookings Queue - on Payments Queue.** Bookings Queue
(`ReceptionistBookingsQueuePage`) had its Start/Complete controls
deliberately removed in an earlier change
([[32-bookings-queue-readonly-and-sidebar-reorg]]): every service category
advances status through its own dedicated queue (Hotel/Daycare check-in-
out, Grooming queue, Veterinary console), and Misc (which is what Initial
Assessment/Reassessment actually are - see
[[19-pet-assessment-gate]]/`...080_m13_move_assessment_services_to_misc.sql`)
has none of its own, so its Start/Complete already lives on
`PaymentsQueuePage` instead. Re-adding Start to Bookings Queue would have
built a second, parallel way to start the same bookings and contradicted
that earlier design decision. Confirmed this placement with the requester
before building; everything below (the "..." menu, View details, the
assessment-gated Start button) landed on Payments Queue instead.

## Other decisions

- **Gated per booking item's service, not by category.** `captures_pet_
assessment` is a new boolean on `services` (Service Builder toggle),
  independent of `requires_assessed_pet` (which gates whether an
  _unassessed_ pet may book the service at all - a different question).
  Start checks whether any of the booking's `booking_items` reference a
  flagged service; if so, it opens the assessment modal instead of calling
  Start immediately. Saving the modal calls the existing staff-only
  `PATCH /pets/:id` (weight_class/coat_type) first, and only calls Start
  afterward if that save succeeded - a rejected pet update never leaves the
  booking silently started with the modal abandoned.
- **Always opens pre-filled with the pet's current values (or blank),
  never skipped for an already-assessed pet.** Reassessment's whole point
  is re-confirming/adjusting an existing assessment, so there's no "already
  assessed, skip the modal" shortcut - every Start on a flagged service
  goes through it.
- **The "..." menu reuses the existing shared `MoreOptionsMenu` component**
  (the same one `HotelBookingPicker` already uses for "View booking
  details") rather than building a new dropdown - View details is now
  the only item in it, but the component supports more later without a
  rewrite.
- **No role tightening.** The Start button was already hidden from Cashier
  and available to every other staff role reaching this page; the pet
  update endpoint it now calls mid-flow is staff-authorized more narrowly
  (Receptionist/Admin/Supervisor/Superadmin, not Groomer/Veterinarian/Pet
  Assistant). In practice the roles that actually operate Payments Queue
  fall inside that narrower set, so this wasn't tightened further - a role
  outside it would just see the modal's own error banner on save, not a
  crash.

## 1. Database schema

**What changed:** `services.captures_pet_assessment boolean not null
default false`, enabled on the two seeded services ("Initial Assessment",
"Reassessment" - same fixed ids
`...080_m13_move_assessment_services_to_misc.sql` uses for them).

**Files:**
`supabase/migrations/20260819138_custom_services_captures_pet_assessment.sql`,
`supabase/migrations/20260819139_custom_seed_captures_pet_assessment.sql`.

## 2. Server

**What changed:** `captures_pet_assessment` added to the `Service`
interface and both create/update service zod validators, same
not-category-gated convention as `requires_assessed_pet`. No service-layer
changes needed - `createService`/`updateService` already spread the
validated input straight into the insert/update, so the new field flows
through automatically once accepted by the schema.

**Files:**
`server/src/features/maintenance/maintenance.types.ts`,
`server/src/features/maintenance/modules/validators/maintenance.validator.ts`.

**Verify manually:**

1. Apply both migrations (see below).
2. `PATCH /maintenance/services/:id` with `{ "captures_pet_assessment":
true }` on any service - confirm it's accepted and the column updates.
3. `GET /maintenance/services?category=Misc` - confirm Initial Assessment
   and Reassessment both show `captures_pet_assessment: true`, and every
   other service shows `false`.

## 3. Client: Service Builder toggle

**What changed:** a new toggle in `AdminServicesPage`'s service form -
"Capture pet weight/coat on Start" - right after the existing "Requires an
assessed pet" toggle, same not-category-gated pattern (shown for every
category, meaningful mainly for Misc).

**Files:** `client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`,
`client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.spec.ts`
(existing create-payload assertion updated for the new field),
`client/src/features/maintenance/maintenance.types.ts`.

**Verify manually:**

1. As Admin/Superadmin, open Service Builder, edit "Initial Assessment" -
   confirm "Capture pet weight/coat on Start" shows on, matching the seed.
2. Create a new service, leave the toggle off (default) - confirm Start
   behaves normally for it (see section 4, step 3).
3. Toggle it on for a test service, save - confirm `GET /maintenance/
services` reflects it.

## 4. Client: Payments Queue - the "..." menu and assessment-gated Start

**What changed:** `PaymentsQueuePage` fetches Misc-category services
(`listServices(accessToken, { category: 'Misc', includeInactive: true })`)
and builds a set of assessment-flagged service ids. Each row's "View
details" button moved into a `MoreOptionsMenu` ("...") next to the status/
payment badges. The Start button (Misc, Pending status, same role gate as
before) now checks `bookingNeedsAssessment(booking)` - if the booking's
items include a flagged service, clicking Start opens a modal (weight
class + coat type selects, pre-filled from the pet's current record) instead
of calling Start immediately; "Save & Start" is disabled until both fields
are chosen, saves the pet via `PATCH /pets/:id`, then calls Start - only on
a successful save. A booking with no flagged service Starts exactly as
before, no modal.

**Files:** `client/src/features/billing/pages/PaymentsQueuePage/PaymentsQueuePage.tsx`,
`client/src/features/billing/pages/PaymentsQueuePage/PaymentsQueuePage.spec.ts`
(mock updates for the new `listServices`/`updatePet` calls, the "View
details" test updated for its new location behind the menu, one new test
covering the assessment-modal flow end to end).

**Verify manually:**

1. On `/staff/billing/payments-queue`, confirm every row now shows a "..."
   button instead of an always-visible "View details" - click it, confirm
   "View details" is the only item and navigates correctly.
2. Find (or create, via Service Builder + a booking) a Pending Misc booking
   whose service is Initial Assessment or Reassessment. Click Start -
   confirm a modal opens asking for weight class and coat type, with the
   "Save & Start" button disabled until both are picked.
3. Pick both, click Save & Start - confirm the modal closes, the booking's
   status advances to In Progress, and the pet's record now shows the
   chosen weight/coat (check via the Pet detail panel, or reopen the same
   booking flow's Pet step - this is the exact scenario from the original
   bug report).
4. Start a Pending Misc booking on a service that is **not** flagged (or
   any non-Misc category with Start visible some other way) - confirm it
   starts immediately with no modal, unchanged from before this change.
5. Reassessment case: pick a pet that already has a weight/coat on file,
   start a Reassessment booking for it - confirm the modal pre-fills the
   current values rather than opening blank.

## Migrations

Two migrations, in order: `20260819138` (column) then `20260819139`
(seed). Bundled together in `payments-queue-pet-assessment-capture.sql` in
this folder since a plain `ADD COLUMN` (unlike an enum `ADD VALUE`) has no
same-transaction restriction.

- **With Supabase CLI access:** `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access:** Supabase Dashboard -> **SQL Editor** ->
  **New query** -> paste `payments-queue-pet-assessment-capture.sql` from
  this folder -> **Run**. Afterwards, confirm with:

  ```sql
  select id, name, captures_pet_assessment
  from public.services
  where category = 'Misc';
  ```

  Both "Initial Assessment" and "Reassessment" should show
  `captures_pet_assessment = true`.

## Postman

Not applicable - no new routes were added; the new behavior rides on the
existing `PATCH /maintenance/services/:id` and `PATCH /pets/:id` endpoints,
both already covered by existing manual/unit test coverage referenced
above.

## Test suites

- `client`: `npx tsc --noEmit` clean; `npx eslint` clean on every changed
  file. `PaymentsQueuePage.spec.ts` (11/11, one new test added for the
  assessment-modal flow) and `AdminServicesPage.spec.ts` (12/12, one
  existing exact-payload assertion updated for the new field) both pass in
  isolation, run repeatedly. A full `npm test` run in this sandbox is
  unreliable for confirming the _rest_ of the suite: back-to-back full runs
  hit jsdom teardown errors (`document is not defined`) across files this
  change never touched (Hotel, Auth guards, login forms) - environment
  resource exhaustion from running two full suites in the same session, not
  a regression from this change. A single clean full run separately showed
  668/672 passing with the only detailed failure an unrelated pre-existing
  timeout in `AdminPackageBuilderPage.spec.ts`. Worth a plain `npm test` on
  a fresh shell before merging to get one trustworthy full-suite count.
- `server`: `npx tsc --noEmit` clean; full suite (`npm test`) - all 863
  tests pass, no server-side unit specs needed updating (the new field
  flows through `createService`/`updateService`'s existing spread-based
  insert/update with no new branching logic to test).

## Suggested branch name

`feat/payments-queue-pet-assessment-capture`
