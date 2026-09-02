# Boarding Checklist Kanban redesign, checkout gating, Groomer UI polish

Branch: `48-boarding-checklist-kanban-redesign`

## The request, verbatim

> on http://localhost:5173/staff/hotel/care-log:
> make it so that the boarding checklist (after cehcking in), looks like todoist kanban (see attachments)
> task checkbox is circle, statuses can be pending, in progress, completed, missed (auto checked if not done by deadline)
> categorize them too (e.g. feeding, medical instructions, play/walk time, etc.)
> add dates to them as well, since hotel is multidate
> and filter and sort options like todoist
> checking off these tasks notifies the pet owner
>
> on http://localhost:5173/staff/hotel/queue > checkout:
> should not be able to checkout pets if tehre are still boarding checklist tasks
>
> overall, beautify the groomer UI
> the hotel queue, boarding checklist, daycare queue, grooming queue, etc.
> imagine that you're the client and you're looking it

## What was already there

The screenshots attached to the request were taken as Superadmin, which - it
turned out - was showing the _wrong_ view: a Todoist-style Kanban board
(`BoardingChecklistKanban.tsx`, Pending/In Progress/Completed columns,
category badges, circular checkbox complete/reopen, search, group-by-time)
already existed for Pet Assistant/Groomer, and `care_log_completed`
notifications on completion were already fully wired
(`careLogNotifications.service.ts`). Admin/Supervisor/Superadmin instead saw
a separate, older flat "Uncompleted care actions" list
(`UncompletedCareFlagPanel.tsx`) - that's what the screenshots showed.

## Design decisions (confirmed with the requester before implementation)

1. **Kanban becomes the one view for every role** on `/staff/hotel/care-log`.
   The old admin-only flag panel is retired.
2. **Missed** is a 4th status, computed lazily (no cron infra exists in this
   app) the same way `bookings.status = 'No-show'` already works: a
   Pending/In Progress task whose `scheduled_date` is strictly before today
   flips to Missed the next time it's read. Boundary case: a task scheduled
   for _today_ is not Missed yet, even late in the day.
3. **Checkout gating**: only Pending/In Progress tasks block checkout;
   Missed is terminal (nobody can act on a past task anymore) and does not
   block, same as Completed.

## Follow-up: interaction & UX fixes (round 2)

Live testing after round 1 surfaced a real bug plus a set of interaction
requests, all addressed in this pass:

- **Root-cause fix - "Start"/"Back to Pending" didn't visibly update the
  list.** The `complete`/`start`/`reopen` mutation endpoints only ever
  returned `select('*')` - no `stays` join. The client's board filters cards
  by `stays.stay_type`/`pet_id`, so the instant a card's own entry object
  lost that field (replaced wholesale by the mutation response), it silently
  failed the Hotel/Daycare filter and vanished from every column instead of
  visibly moving to its new one. Fixed on both sides: the server now returns
  the same joined shape `getCareLogEntries` already uses from all three
  mutation endpoints (`CARE_LOG_ENTRY_SELECT` constant in
  `careLogCompletion.service.ts`), and the client's `replaceEntry` merges
  the mutation response into the existing entry instead of replacing it
  outright, as defense in depth.
- **Start/Back-to-Pending buttons removed.** The circular checkbox is now
  the only control. Clicking it advances the task one step at a time
  (Pending → In Progress → Completed); clicking a Completed (fully filled)
  checkbox reopens straight back to Pending (not to In Progress - there's no
  intermediate "unchecked" state to land on, since In Progress is its own
  distinct visual, not a checked/unchecked binary). In Progress renders as a
  partially-filled ring (`.checkboxInProgress`, a radial-gradient dot) so
  the three states read as three states, not two.
- **Missed is now fully read-only** (checkbox `disabled`, no actions at
  all) - this **supersedes round 1's decision** to let a Missed task still
  be completed late or reopened. Verification section 3 below is updated to
  match.
- **Click-to-expand.** Clicking anywhere on a card's body (not the
  checkbox) toggles an expanded detail panel - the full scheduled date, and
  (once Completed) who completed it and when. The checkbox and the
  expand-toggle area are implemented as separate sibling controls (a real
  `<button>` and a `role="button"` div), not nested interactive elements.
- **Description split into two lines.** Every `care_log_entries.description`
  is generated as `"<title> — <detail>"` (e.g. "Amoxicillin 250mg 1 — 8:00
  AM", "Morning walk — 15 min"). The card now renders the two halves as
  separate lines (`splitDescription`) instead of one run-on sentence, so the
  detail - often the exact time - reads as its own line rather than being
  buried in prose.
- **Group By is now a real single-axis selector** (Status / Time of day /
  Instructions-category), replacing the old fixed "4 status columns + an
  optional time sub-group" layout. Whichever axis is chosen becomes the
  board's columns; when grouping by Time or Category, a small status pill
  is added to each card's meta row so status - no longer the column axis -
  stays visible. Column top-border tinting follows the active axis too
  (category columns pick up the same 4 care-type colors the badges use).

### Files touched (round 2)

- `server/src/features/hotel/services/careLogCompletion.service.ts`:
  `CARE_LOG_ENTRY_SELECT` constant, applied to `startCareLogEntry`,
  `reopenCareLogEntry`, and `completeCareLogEntry`'s selects.
- `client/src/features/hotel/components/BoardingChecklistKanban/BoardingChecklistKanban.tsx`:
  tri-state checkbox/click-cycle logic, expand/collapse state, description
  splitting, `GroupBy` axis + column computation, `replaceEntry` merge fix.
  Start/Back-to-Pending buttons and the old `groupByTime` boolean/nested
  time-sub-group rendering removed.
- `client/src/features/hotel/components/BoardingChecklistKanban/BoardingChecklistKanban.module.css`:
  `.checkboxInProgress`, `.columnFeeding/.columnWalking/.columnPlaying/.columnMedication/.columnNeutral`,
  `.descriptionDetail`, `.expandedDetails`, `.missedNote`, `.statusBadge` +
  4 status-tinted variants, `.groupBySelect`; `.board` now sizes columns via
  a `--column-count` custom property (set inline per the active axis) so 4-
  and 5-column layouts both work with the same responsive breakpoints;
  `.actionLink`/`.timeGroup`/`.timeGroupTitle` (dead code) removed.

## Round 3: Backlog status, activity logbook, Daycare walk-in removal & checkout parity

### The request, verbatim

> add a logbook for all hotel/daycare actions (e.g. task moved from pending > in progress, etc.)
> add a new status before pending called something like Not Started or Backlog (tasks here are readonly, tasks not due today)
> automatically move tasks out of backlog when task is due today
>
> on http://localhost:5173/staff/daycare/queue:
> remove existing book/walk-in navbar|
> what is it for? I believe receptionsit already handles those
> fix daycare checkout UI, should look more like hotel checkout

### What "book/walk-in" was, and why it's gone

`DaycareCheckInPanel`'s "Existing booking"/"Walk-in" tab switcher. "Walk-in"
created a brand-new Daycare session directly against a pet profile with no
booking at all - a capability genuinely distinct from what Receptionist does
elsewhere (Receptionist creates a same-day _booking_ on behalf of a walk-in
customer through the normal booking flow; that booking then simply shows up
here to be checked in like any other, via "Existing booking"). Since
Groomer/Pet Assistant (this page's own viewer roles) are meant to physically
check in a pet that already has a booking - mirroring Hotel Queue's Check-In
tab exactly, which has no walk-in mode either - the separate raw walk-in
creation path was redundant on this page specifically. **Removed the client
UI only** - the server's walk-in check-in path
(`checkInDaycareSession`'s `pet_id`/`branch_id` branch, no `booking_id`) is
left intact and still has its own passing test coverage, in case that
capability needs a home again later.

### Backlog status (never persisted)

A 4th (well, 5th counting Missed) computed status: a still-`Pending` task
scheduled for a day _after_ today is relabeled `'Backlog'` for display and
checkout-gating purposes - read-only (checkbox disabled), and does **not**
block checkout (if the guest is leaving today, a task scheduled for tomorrow
was never going to happen). Unlike Missed, Backlog is never written to the
database - `applyBacklogLabel` in `careLogCompletion.service.ts` relabels it
purely at read time, so a task "moves out of Backlog" automatically the
moment its own `scheduled_date` is no longer in the future, with no write
and no cron needed. `CareLogEntryStatus` gains `'Backlog'` (client + server);
the DB `status` column's check constraint is **not** touched - `'Backlog'`
never appears there.

### Activity logbook

New `activity_log` table (migration `20260819136`, unprefixed like `stays`/
`care_log_entries` since it's shared by Hotel and Daycare) recording 6
action types (`check_in`, `check_out`, `task_started`, `task_completed`,
`task_reopened`, `task_missed`) with a human-readable `description`,
optional `actor_staff_id` (null for the system-driven Missed transition),
and `branch_id` denormalized directly onto the row for RLS/listing without a
join. `recordActivity`/`recordBulkActivity`
(`server/src/features/hotel/services/activityLog.service.ts`) are best-
effort and non-blocking, same convention as
`careLogNotifications.service.ts`'s `sendCareLogCompletedNotification` - a
logging failure is caught and logged, never allowed to fail the real action
it's recording. Wired into: Hotel check-in/checkout, Daycare check-in/
checkout, and all three care-log-entry transitions (start/complete/reopen),
plus a batched write from the lazy Missed transition. New page
`/staff/hotel/activity-log` (same viewer roles as Boarding Checklist: Pet
Assistant, Groomer, Admin, Supervisor, Superadmin), reachable from a new
"Activity Log" sidebar tile placed next to "Boarding Checklist" everywhere
that tile already appears - filterable by date range and action type,
newest first.

### Daycare checkout UI parity with Hotel

`DaycareSessionPicker` was structurally simpler than `HotelStayPicker` (no
`QueueFilterBar`, no result count, no "already checked out" badge) even
though the confirm/result screens (`DaycareCheckoutPanel`/
`HotelCheckoutPanel`) were already near-identical. Brought the picker up to
the same shape: `GET /daycare/sessions` gained `date_from`/`date_to` against
`check_in_at` (a timestamptz, so - unlike Hotel's date-only
`scheduled_check_out_date` - an inclusive `dateTo` becomes an exclusive
`< dateTo + 1 day` bound, mirroring `booking.service.ts`'s own timestamptz
date-range handling) alongside the existing `status` filter, both now
validated by a new `listDaycareSessionsQueryValidator`. The picker's default
stays "All dates" / "Active" - same reasoning as Hotel's checkout list.

### Files touched (round 3)

- `supabase/migrations/20260819136_custom_create_activity_log_schema.sql`:
  new `activity_log` table + RLS.
- `server/src/features/hotel/services/activityLog.service.ts` (+ spec):
  `recordActivity`, `recordBulkActivity`, `listActivityLog`.
- `server/src/features/hotel/services/careLogCompletion.service.ts`:
  `applyBacklogLabel`; `recordActivity`/`recordBulkActivity` wired into
  `startCareLogEntry`/`reopenCareLogEntry`/`completeCareLogEntry`/
  `applyMissedTransition`; `assertChecklistComplete`'s select widened to
  join `stays(branch_id)` (needed for the activity-log write, and
  `CareLogEntry.stays`'s type gained `branch_id` to match what the join
  already returned).
- `server/src/features/hotel/services/checkout.service.ts`,
  `server/src/features/daycare/services/daycareBilling.service.ts`,
  `server/src/features/hotel/services/careInstructions.service.ts`,
  `server/src/features/daycare/services/daycareCheckIn.service.ts`: each
  gained a `recordActivity` call after its own write already succeeded;
  the two checkout services also gained an optional `requesterId` param,
  threaded through from their controllers.
- `server/src/features/hotel/hotel.controller.ts` /
  `hotel.routes.ts` / `modules/validators/hotel.validator.ts`:
  `activityLogController` + `GET /hotel/activity-log` +
  `activityLogQueryValidator`.
- `server/src/features/daycare/daycare.controller.ts` /
  `modules/validators/daycare.validator.ts`:
  `listDaycareSessionsQueryValidator` replaces the controller's manual
  status check.
- `server/src/features/daycare/services/daycareCheckIn.service.ts`:
  `listDaycareSessions` gained `dateFrom`/`dateTo`.
- `client/src/features/hotel/hotel.types.ts` / `api/hotel.api.ts`:
  `ActivityLogAction`/`ActivityLogEntry` types, `listActivityLog`.
- `client/src/features/hotel/pages/ActivityLogPage/` (new, + spec):
  the logbook page.
- `client/src/features/hotel/hotel.routes.tsx`:
  `/staff/hotel/activity-log` route.
- `client/src/features/staff/config/staffDashboard.config.ts`: "Activity
  Log" tile added next to every existing "Boarding Checklist" tile (5
  locations); `History` icon.
- `client/src/features/hotel/components/BoardingChecklistKanban/
BoardingChecklistKanban.tsx` (+ css, + spec): `'Backlog'` added to
  `STATUS_COLUMNS`, `columnBorderClass`, `statusBadgeClass`,
  `checkboxAriaLabel`; `isReadOnlyStatus` now covers Backlog and Missed.
- `client/src/features/daycare/pages/DaycareQueuePage/
DaycareCheckInPanel.tsx` (+ css, + spec): walk-in mode removed - always
  renders `DaycareBookingPicker` directly, no tab switcher.
- `client/src/features/daycare/components/DaycareSessionPicker/
DaycareSessionPicker.tsx` (+ css): rewritten to mirror `HotelStayPicker`.
- `client/src/features/daycare/api/daycare.api.ts`: `listDaycareSessions`
  widened from a bare status string to a filters object; updated the one
  other call site (`DaycareQueueWidget.tsx`).

## What changed

### Database

- `supabase/migrations/20260819135_custom_care_log_entries_missed_status.sql`
  - widens `care_log_entries.status`'s check constraint to add `'Missed'`.

### Server

- `server/src/features/hotel/hotel.types.ts`: adds `CareLogEntryStatus`
  (previously only existed client-side) and a `status` field on the server's
  `CareLogEntry` interface (was missing entirely); removes the now-unused
  `HOTEL_PET_ASSISTANT_ROLES` role list.
- `server/src/features/hotel/services/careLogCompletion.service.ts`:
  - `applyMissedTransition` - mirrors `booking.service.ts`'s
    `applyNoShowTransition` (bulk `UPDATE ... WHERE id IN (...)` for every
    stale row in one call, not one query per row).
  - `getTodayCareLogEntries` renamed to `getCareLogEntries`, widened from a
    single `date` to optional `dateFrom`/`dateTo` (both omitted = today
    only, unchanged default), and now applies the Missed transition before
    returning.
  - `assertChecklistComplete(stayId)` - throws 409
    (`"Boarding checklist has N incomplete task(s)"`) if the stay still has
    Pending/In Progress tasks after applying the same lazy transition.
- `server/src/features/hotel/modules/validators/hotel.validator.ts`: new
  `careLogEntriesQueryValidator` (`date_from`/`date_to`, both optional).
- `server/src/features/hotel/hotel.controller.ts`:
  `todayCareLogEntriesController` renamed `careLogEntriesController`, now
  parses the date-range query; `flaggedCareLogEntriesController` removed.
- `server/src/features/hotel/hotel.routes.ts`:
  - `PATCH /hotel/care-log-entry/:id/{complete,start,reopen}` widened from
    `HOTEL_PET_ASSISTANT_ROLES` to `HOTEL_ADVANCE_ROLES` (every role that can
    now see the unified Kanban can also act on it).
  - `GET /hotel/care-log/flagged` removed.
- `server/src/features/hotel/services/careLogFlagging.service.ts` and its
  spec: deleted (superseded by the unified Kanban's own Pending/Missed
  columns).
- `server/src/features/hotel/services/checkout.service.ts`: calls
  `assertChecklistComplete(stayId)` before completing a Hotel checkout.
- `server/src/features/daycare/services/daycareBilling.service.ts`: calls
  the same `assertChecklistComplete(sessionId)` before completing a Daycare
  checkout (Hotel and Daycare share the same `stays`/`care_log_entries`
  tables, so one gate covers both).

### Client

- `client/src/features/hotel/hotel.types.ts`: `CareLogEntryStatus` gains
  `'Missed'`.
- `client/src/features/hotel/api/hotel.api.ts`: `getTodayCareLogEntries` →
  `getCareLogEntries(accessToken, { dateFrom?, dateTo? })`;
  `getFlaggedCareLogEntries` removed.
- `client/src/features/hotel/pages/BoardingChecklistPage/BoardingChecklistPage.tsx`:
  drops the role branch entirely - every allowed role renders
  `BoardingChecklistKanban`.
- `client/src/features/hotel/components/UncompletedCareFlagPanel/`:
  deleted.
- `client/src/features/hotel/components/BoardingChecklistKanban/BoardingChecklistKanban.tsx`
  (the core redesign):
  - 4 columns (Pending/In Progress/Completed/Missed), each with a distinct
    tinted top border.
  - `QueueFilterBar` (date-range preset against `scheduled_date`, defaulting
    to Today; a Category filter reusing the same "status" slot, labeled
    "Category") + `SearchSortBar` (search by pet/description; sort by
    soonest/latest/pet name) + `ActiveFilterChips`, matching the toolbar
    vocabulary `HotelBookingPicker`/`HotelStayPicker` already use elsewhere
    in this feature.
  - A per-card date badge appears once the date filter is widened past
    "Today" (multi-day boarding stays can then mix dates on one board).
  - Category badges now show a `lucide-react` icon (Utensils/Footprints/
    PlayCircle/Pill) and a tinted color per `care_type`.
  - A Missed card's checkbox is disabled - see "Follow-up" above, which
    supersedes this round 1 decision.
- `client/src/styles/tokens.css`: 4 new care-type badge color pairs
  (`--color-care-type-{feeding,walking,playing,medication}-{bg,text}`, each
  aliasing an existing hue family already used elsewhere - see the file's
  own comments for which) plus `--shadow-card-hover` for the new card-hover
  elevation used across the Groomer pages.
- Visual polish: hover elevation on Kanban cards and
  `GroomerDashboardPage`'s pending cards; tab hover states on
  `HotelQueuePage`/`DaycareQueuePage`/`BoardingChecklistKanban`;
  `BoardingChecklistPage`'s content max-width widened (72rem → 80rem) for
  the 4-column board.
- **Checkout UI**: no code change needed - `HotelCheckoutPanel.tsx` and
  `DaycareCheckoutPanel.tsx` already render the server's error message
  verbatim in their existing error banner, so the new 409
  ("Boarding checklist has N incomplete task(s)") surfaces automatically,
  the same way the existing checkout race-condition 409 already does.

## Verification

### 1. Boarding Checklist Kanban - visible to every role now

1. Log in as Superadmin (or Admin/Supervisor) and go to
   `/staff/hotel/care-log`. Confirm you now see the Kanban board (4 columns:
   Pending / In Progress / Completed / Missed), not the old flat
   "Uncompleted care actions" list.
2. Log in as Pet Assistant or Groomer and confirm the same board renders
   there too.

### 2. Categories, dates, filters, sort

1. Confirm each card shows a colored category badge (Feeding/Walking/
   Playing/Medication) with an icon, and a time-of-day badge when scheduled.
2. Open the Category filter and narrow to one category - confirm only
   matching cards remain, and an active-filter chip appears; clear it via
   the chip's "x".
3. Open the Date filter, switch off "Today" to "This week" or "All dates" -
   confirm tasks from other days now appear, each showing a date badge (the
   badge only appears once the date filter is off "Today").
4. Use the search box and the sort select (Soonest/Latest/Pet name) -
   confirm results update and chips reflect the active search/sort.

### 3. Missed status (read-only, per round 2)

1. Find (or create via a past-dated stay in a local/seed environment) a
   care log entry with `scheduled_date` before today, left Pending. Reload
   the Boarding Checklist - confirm it now appears in the Missed column.
2. Confirm the Missed card's checkbox is visibly disabled and clicking it
   does nothing - no Start/complete/reopen action fires.

### 3b. Interaction model (round 2)

1. Click a Pending card's checkbox - confirm it moves to In Progress
   **immediately** (no refresh needed) and the checkbox now shows a
   partially-filled ring, not the fully-filled Completed look.
2. Click that same checkbox again - confirm it advances to Completed (fully
   filled) and moves column again, immediately.
3. Click a Completed card's checkbox - confirm it reopens straight to
   Pending (not In Progress), immediately.
4. Confirm there is no separate "Start" or "Back to Pending" button
   anywhere on a card - the checkbox is the only control.
5. Click a card's body (pet name/description area, not the checkbox) -
   confirm a detail panel expands showing the full scheduled date (and,
   once Completed, who completed it and when); click again to collapse.
6. Confirm a card's description now shows on two lines - e.g. a Medication
   task shows the medication/dose on one line and the exact time (e.g.
   "8:00 AM") on the line below, not run together in one sentence.
7. Open the "Group by" select and switch to "Time of day" - confirm the
   columns become Morning/Noon/Afternoon/Evening/Unscheduled instead of the
   status columns, and each card now shows a small status pill (since
   status is no longer the column axis). Switch to "Instructions
   (category)" - confirm columns become Feeding/Walking/Playing/Medication,
   each tinted to match that category's badge color.

### 4. Owner notification on completion (pre-existing, re-verify unbroken)

1. Check a task complete on the board. Confirm the pet owner's account
   receives an in-app notification (and email, if their preferences enable
   it) - `care_log_completed`, unchanged by this redesign.

### 5. Checkout gating (Hotel and Daycare)

1. Go to `/staff/hotel/queue` → Check Out, select a stay whose Boarding
   Checklist still has Pending/In Progress tasks, and attempt checkout -
   confirm it's rejected with an error banner reading
   "Boarding checklist has N incomplete task(s)".
2. Complete every remaining task for that stay, then retry checkout -
   confirm it now succeeds.
3. Repeat both steps for a Daycare session at `/staff/daycare/queue` →
   Check Out.
4. Confirm a stay whose only outstanding tasks are Missed (not Pending/In
   Progress) is **not** blocked from checkout.

### 6. API-level checks (Postman)

See `boarding-checklist-kanban-redesign.postman_collection.json` in this
folder. Import it, fill in `base_url`, a staff login, an existing
`care_log_entry_id`, and a `hotel_stay_id` with outstanding tasks, then run
top to bottom. Covers the widened date-range query, its rejection of an
invalid date, the complete endpoint now reachable by a front-desk/admin
role, and checkout's 409 when tasks are incomplete. Requests 7-10 cover
round 3's activity-log endpoint and the Daycare sessions date-range/status
parity.

### 7. Backlog status (round 3)

1. Check in a Hotel stay spanning multiple days (or use one already
   checked in). Open the Boarding Checklist - confirm today's tasks show
   under Pending as usual, and tasks scheduled for a later day show under a
   new **Backlog** column (5 columns total: Backlog / Pending / In Progress
   / Completed / Missed).
2. Confirm a Backlog card's checkbox is visibly disabled (same read-only
   treatment as Missed) and clicking it does nothing.
3. Confirm a stay whose only outstanding tasks are Backlog (nothing due
   today or earlier left undone) is **not** blocked from checkout, same as
   a Missed-only stay.

### 8. Activity logbook (round 3)

1. Log in as any allowed role (Pet Assistant, Groomer, Admin, Supervisor,
   Superadmin) and confirm a new **Activity Log** sidebar tile appears
   next to Boarding Checklist; open it.
2. Check a Hotel stay in, then complete/reopen a couple of its Boarding
   Checklist tasks, then check it out. Reload the Activity Log (widen the
   date filter if needed) - confirm one row per action, newest first, each
   with a readable description, the acting staff member's name, and a
   timestamp.
3. Filter by Action (e.g. "Task completed") - confirm only matching rows
   remain, with an active-filter chip; clear it via the chip.
4. Confirm a Receptionist (or any role outside the allowed set) is
   redirected away from `/staff/hotel/activity-log`.

### 9. Daycare (round 3)

1. Go to `/staff/daycare/queue` → Check In. Confirm there is **no**
   "Existing booking"/"Walk-in" tab switcher - the booking picker (date/
   status/search filters, matching Hotel Queue's Check-In tab) is the only
   thing shown.
2. Switch to Check Out. Confirm it now shows the same toolbar Hotel
   Queue's checkout tab has - a Date filter (defaulting to "All dates") and
   a Status filter (defaulting to "Active"), alongside the existing search/
   sort - not just a bare search box as before. Widen Status to "All
   statuses"/"Completed" and confirm already-checked-out sessions appear
   with an "Already checked out" badge and no Check Out button.

## Test suites

- `server`: `npm run test` (from `server/`) - 863/863 passing. Round 3
  additions: `activityLog.service.spec.ts` (new, 8 tests),
  `careLogCompletion.service.spec.ts` (Backlog cases),
  `daycareCheckIn.service.spec.ts` (`listDaycareSessions` date-range
  tests), `DaycareCheckInPanel.spec.ts` (walk-in mode removed).
  `npx tsc --noEmit` clean.
- `client`: `npm run test` (from `client/`) - 671/671 passing. Round 3
  additions: `ActivityLogPage.spec.ts` (new, 4 tests), `BoardingChecklistKanban.spec.ts`
  (Backlog disabled-checkbox case), `DaycareCheckInPanel.spec.ts` (rewritten
  for the booking-only flow).
  `npx tsc --noEmit -p tsconfig.app.json` clean.
- All three rounds verified live against the running dev server
  (Playwright) against the real linked Supabase project, not just unit
  tests - including, in round 3, the 5-column board with Backlog, the
  Activity Log page end to end (route, sidebar tile, role gate, filters),
  the removed Daycare walk-in tab, and the Daycare checkout toolbar parity.
  Both pending migrations (`20260819135` Missed status,
  `20260819136` activity_log) are applied on the linked project as of
  round 3.
