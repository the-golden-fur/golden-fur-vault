# Scheduling & policy config: branches, lunch break, monthly schedule, reschedule notice

Branch: `24-scheduling-and-policy-config`

## Why

Five requests came in as one checklist:

1. Superadmin System Configuration only ever supported editing existing
   branches (no way to add a new one).
2. No fixed lunch break existed anywhere - a similar `branches.break_window`
   column existed once but was dropped as dead, unwired schema, not a
   working feature.
3. No way to plot staff rest days / vacation leave on a calendar, shared
   between Supervisor/Admin/Superadmin with equal CRUD access, scoped to
   their own branch (Superadmin: any branch) - plus a log of who added a
   schedule entry and when.
4. The booking-queue Staff Picker needed to exclude staff on lunch break /
   rest day / vacation leave / sick leave.
5. The Reschedule button in the Bookings Queue always rendered regardless of
   the 3-day notice policy, and there was no admin UI to configure that
   policy at all.

Investigation found most of the backend for #5 already existed and was
fully tested (`GET/PATCH /bookings/policy`, `resolveEffectivePolicy`,
`updatePolicyConfiguration`) - it just had no client consumer. Likewise,
#3's "rest day / vacation leave" data model already existed as
`staff_unavailability_blocks` (approval workflow, on-behalf-of auto-approve,
`is_full_day`) - it only needed a `leave_type` column and a calendar UI, not
a new table.

## What changed

### 1. Superadmin: add new branches

- `supabase/migrations/20260804090_m01_branches_insert_rls.sql` - INSERT RLS
  policy on `branches` (Superadmin-only, mirrors the existing UPDATE policy).
- `server/src/features/branches/`: `createBranchValidator`, `createBranch()`
  service, `createBranchController`, `POST /branches` route.
- `client/src/features/maintenance/api/branches.api.ts`: `createBranch()`.
- `client/src/features/maintenance/pages/SystemConfigurationPage/SystemConfigurationPage.tsx`:
  inline "+ Add branch" form (name/address/contact/timezone/vet-branch
  toggle) above the existing branch selector; operating hours default to
  closed every day and are set afterward via the existing edit form.

### 2. Fixed lunch break (default 12:00-13:00)

Lunch break is a **policy setting**, not a resurrected `branches` column -
it reuses `policy_configurations`' existing default-row + per-branch-override
pattern (same table already backing notice period / Staff Picker toggles).

- `supabase/migrations/20260804091_m09_policy_configurations_lunch_break.sql` -
  `lunch_break_enabled` (bool, default true), `lunch_break_start`/
  `lunch_break_end` (time, default 12:00/13:00).
- `supabase/migrations/20260804092_m03_get_staff_availability_lunch_break.sql` -
  `get_staff_availability()` gains a branch-level lunch-break check
  (resolves the effective policy row, same whole-row precedence as
  `resolveEffectivePolicy()`) right after the existing operating-hours
  check. This is the real gate for Grooming/Veterinary staff assignment.
- `server/src/features/booking/services/availability.service.ts` -
  `getDaySlots()` now also drops any candidate slot overlapping the
  effective lunch break window, for every service category (Hotel/Daycare
  included, since they share the same candidate-generation code path).
- Types/validator: `PolicyConfiguration`/`EffectivePolicy` (both server and
  client `booking.types.ts`), `DOCUMENTED_DEFAULTS`,
  `updatePolicyValidator` (new `lunch_break_*` fields, "HH:MM" pattern
  reused from `branches.validator.ts`).

### 3. Monthly Schedule (rest days + vacation/sick leave)

Reuses `staff_unavailability_blocks` end-to-end - no new table.

- `supabase/migrations/20260804093_m01_staff_unavailability_blocks_leave_type.sql` -
  new `unavailability_leave_type` enum (`Rest Day`, `Vacation Leave`,
  `Sick Leave`, `Other`, default `Other`) and `leave_type` column.
- **Branch-scoped equal CRUD** (mid-implementation clarification: Monthly
  Schedule access is branch-level, shared equally by Supervisor/Admin/
  Superadmin): `unavailabilityBlock.service.ts`'s `createUnavailabilityBlock`/
  `cancelUnavailabilityBlock` now enforce that an on-behalf-of action (not
  self-service) can only target a staff member at the requester's own
  branch, unless the requester is Superadmin. Closes a pre-existing gap -
  this check never existed before.
- **Rest Day is manager-only**: `createUnavailabilityBlock` rejects
  `leave_type: 'Rest Day'` with 403 when `requesterId === targetStaffId` -
  a staff member can never set their own rest day.
- **New read endpoint** `GET /staff/branches/:branchId/schedule?from=&to=` -
  `listBranchSchedule()` returns every full-day entry for a branch/date
  range, joined with the staff member's name and (a second lookup) the
  creator's display name - `created_by_name` + the existing `created_at`
  together are the "who added this schedule entry, and when" log the
  request asked for. Same branch-scope enforcement as above; every status
  is included (not just approved) so managers see pending requests too.
- **New page** `client/src/features/staff/pages/MonthlySchedulePage/MonthlySchedulePage.tsx`,
  route `/staff/admin/monthly-schedule`, gated to Admin/Supervisor/
  Superadmin (same role set as the existing Days Off Approval Queue). Month
  grid per branch (Superadmin can switch branches), a static lunch-break
  badge read from the effective policy, click-to-add (staff + type + date)
  and click-to-view/cancel (shows status, reason, "Added by X on Y").
  Linked from both the Admin and Supervisor dashboards next to "Days Off
  Approval Queue".
- `UnavailabilityBlockForm.tsx` (self-service Days Off form) gained a Type
  select (Vacation Leave / Sick Leave / Other - never Rest Day).

**Addendum (post-review feedback on the live page):** the manual add/detail
"no need to rely on their requests" capability already existed via each
day's `+` button, but the form rendered as a plain section below the entire
calendar grid - easy to miss, reading as if the feature didn't exist. Fixed:

- The add-entry and entry-detail panels are now true modals (fixed
  backdrop, centered, same visual language as the app's `ConfirmDialog`) -
  clicking `+` or a chip/badge now pops the form up immediately instead of
  requiring a scroll.
- Added a **Calendar / Staff grid** view toggle. Staff grid is the
  spreadsheet-style overview requested: one row per staff member (sticky
  left column), one column per date in the month (sticky header), each cell
  a colored abbreviation badge (`RD`/`VL`/`SL`/`O`) for that staff member's
  entry that day, or an empty `+` affordance to add one directly for that
  staff+date pair (skips the staff dropdown in the modal since it's
  pre-selected from the cell clicked). Horizontally scrollable for months
  with many staff/days.

**Addendum 2 (further UI feedback on the live page):**

- The view toggle's second option is now labeled just "Grid" (was "Staff
  grid").
- Each calendar day's `+` and each grid's empty-cell `+` are hidden until
  the cell is hovered (or focused, for keyboard use), then render as a
  small filled gold circle instead of plain text - both more discoverable
  when revealed and out of the way otherwise. Touch devices (no hover
  state) show it faintly at all times instead of never, so it stays
  reachable there too.
- New page-level **Search staff / Role / Sort** row, filtering which
  staff's entries render in both Calendar (hides chips for filtered-out
  staff) and Grid (hides whole rows) - e.g. role = Groomer, sorted Z-A.
- The Add-entry modal's staff `<select>` gained its own independent
  **search by name / role filter / sort** row (deliberately separate state
  from the page-level filter above, so narrowing the page's view to one
  role never hides someone you still need to add an entry for from the
  modal).

### 4. Staff Picker exclusion

- Rest day / vacation / sick leave: already covered by #3 - they're
  `approved` `staff_unavailability_blocks` rows, and
  `get_staff_availability()`'s existing overlap check already excludes any
  approved block regardless of `leave_type`. No further change needed.
- Lunch break: covered by #2's `get_staff_availability()` and `getDaySlots()`
  changes.

### 5. Reschedule button + Policies admin page

- **New page** `client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`,
  route `/staff/admin/maintenance/policies`, gated to Admin+Superadmin
  (unlike System Configuration's Superadmin-only gate). Branch selector
  (system default + each branch, same UX as System Configuration) editing
  notice period/enforcement mode, Staff Picker toggles, and lunch break -
  all through the already-existing `GET/PATCH /bookings/policy` endpoints.
  New tile in Settings > Config (`ConfigTab.tsx`).
- `client/src/features/booking/api/policy.api.ts` (new) -
  `listPolicyConfigurations`/`updatePolicyConfiguration`/
  `resolveEffectivePolicy` (client-side mirror of the server function).
- `ReceptionistBookingsQueuePage.tsx` - `canReschedule` now also requires
  the notice period to be satisfied: enforcement disabled, **Soft** mode
  (the server already lets a Soft-mode reschedule through with a
  `policy_violation` flag, so hiding the button would contradict that
  existing behavior), or the booking is far enough out. Only a **Strict**,
  unmet notice period hides the button - mirrors
  `reschedule.service.ts`'s own `evaluateNoticePeriod` exactly, so the
  button never promises something the server would then reject.

## Verification

### 1. Superadmin adds a branch

1. Log in as a Superadmin, go to Settings > Config > System Configuration.
2. Click "+ Add branch", fill in name/address/timezone, submit.
3. The new branch should appear in the branch dropdown on this same page,
   selected automatically, with every day showing "Closed" (set hours and
   save separately).
4. Log in as an Admin (not Superadmin) - System Configuration should
   redirect away; no "Add branch" surface should be reachable.
5. Elsewhere in the app (e.g. the booking flow's branch picker), confirm the
   new branch is selectable like any other.

### 2. Lunch break

1. As Admin/Superadmin, go to Settings > Config > Policies. Confirm "No
   bookings during this window" is checked with 12:00/13:00 by default.
2. As a customer (or receptionist walk-in), start a Grooming or Veterinary
   booking for a branch/date where lunch break is enabled - the Slot Picker
   should show no slot starting inside 12:00-13:00 branch-local time, while
   slots immediately before/after still appear.
3. Repeat for Hotel/Daycare - the same noon gap should appear in arrival
   candidates.
4. On the Policies page, uncheck "No bookings during this window" and save;
   reload the Slot Picker for the same date - the noon slot(s) should now
   be available again.
5. Change the window to e.g. 12:30-13:30 and save; confirm the Slot Picker
   gap shifts to match.

### 3. Monthly Schedule

1. As a Supervisor, open the dashboard - "Monthly Schedule" should appear
   next to "Days Off Approval Queue".
2. Open it - the calendar defaults to your own branch (no branch selector
   for non-Superadmin) and the current month.
3. Click an empty day's `+` - a modal should pop up immediately (centered,
   over the page, not a scroll away). Pick a staff member from the roster,
   choose "Rest Day", submit - the modal closes and a chip appears on that
   day immediately (no approval step).
4. Click that chip - a detail modal should show "Added by <your name> on
   <today's date/time>" (the requested log) and a Remove button.
5. As an Admin at the same branch, open the same page - the Rest Day you
   just added should be visible and removable (equal CRUD, shared view).
6. As a Superadmin, open the page - a branch selector should appear; switch
   to a different branch and confirm the calendar reloads that branch's
   entries only.
7. Click the "Staff grid" toggle - the view switches to a spreadsheet-style
   table: one row per staff member (name frozen in the left column while
   scrolling horizontally), one column per date of the month (frozen header
   row), each populated cell showing a short colored badge (`RD`/`VL`/`SL`/`O`).
   Click an empty cell - the same add modal opens, staff member already
   pre-selected to that row (no need to reselect from the dropdown). Click a
   populated cell - the same detail modal opens as clicking a calendar chip.
   Toggle back to "Calendar" - both views should reflect the same
   underlying data.
8. As a Supervisor at Branch A, attempt to hit
   `POST /staff/:idAtBranchB/unavailability` directly (e.g. via Postman,
   request 9 in the collection pointed at a Branch B staff id) - expect 403.
9. As a staff member (not Admin/Supervisor/Superadmin), open Days Off
   (`/staff/days-off`) - the Type dropdown should offer Vacation Leave/Sick
   Leave/Other, never Rest Day. Submitting a request should behave exactly
   as before (goes to the approval queue unless it's the quick action).

### 4. Staff Picker exclusion

1. Using the Rest Day added in section 3, start a Grooming booking (as a
   customer or receptionist) for that staff member's role, on that date -
   the Staff Picker should not list them for any time that day.
2. For a Grooming/Veterinary booking on any date, confirm no staff member is
   offered for a slot inside the lunch break window (covered already by
   section 2, re-confirm from the Staff Picker step specifically).

### 5. Reschedule button + Policies

1. As Admin/Superadmin, on the Policies page set the minimum notice to 3
   days, mode Strict, enforcement on. Save.
2. In the Bookings Queue, find (or create) a booking scheduled less than 3
   days out - the Reschedule button should not appear for it.
3. Find a booking scheduled 3+ days out - Reschedule should appear and work
   normally.
4. Switch the enforcement mode to Soft and save. Reload the queue - the
   less-than-3-days booking's Reschedule button should reappear (Soft still
   allows it, flagged server-side).
5. Toggle enforcement off entirely and save - Reschedule should appear for
   every eligible booking regardless of notice.
6. Confirm the Policies tile is visible to both Admin and Superadmin (unlike
   System Configuration, which stays Superadmin-only).

### 6. API-level checks (Postman)

See `scheduling-and-policy-config.postman_collection.json` in this folder.

1. Open Postman (or the VS Code Postman/Thunder Client extension) and
   import the collection file: **File → Import →** select the `.json` file
   in this folder.
2. Open the collection's **Variables** tab and fill in:
   `superadmin_identifier`/`superadmin_password` (a seeded Superadmin
   login), `supervisor_identifier`/`supervisor_password` (a seeded
   Supervisor login), `supervisor_staff_id` (that Supervisor's
   `staff_profiles.id` - staff login doesn't return it, grab it from
   Supabase or Staff Management), `branch_id` (that Supervisor's own home
   branch id), `target_staff_id` (any other active staff id at that same
   branch, e.g. a Groomer). Leave the `*_access_token`, `new_branch_id`,
   and `rest_day_block_id` variables blank - the collection fills those in
   as you run requests.
3. Make sure the server is running locally (`npm run dev` in `server/`,
   default `http://localhost:3000`).
4. Run each request **in numeric order** (or use "Run collection"). Check
   the **Test Results** tab on each request - all should be green,
   including the two 403 checks (requests 4, 7, and 8 - a non-Superadmin
   creating a branch, a non-Admin updating policy, and a self-service Rest
   Day).

### 7. Migrations

If your local/remote Supabase project doesn't already have migrations
`20260804090` through `20260804093` applied:

- **With Supabase CLI access**: `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access**: open the Supabase Dashboard for this project
  → **SQL Editor** → **New query** → paste the contents of
  `scheduling-and-policy-config.sql` in this folder → **Run**. Afterwards,
  confirm with:

  ```sql
  select column_name, data_type, column_default
  from information_schema.columns
  where table_name = 'policy_configurations'
    and column_name like 'lunch_break%';

  select column_name, data_type, column_default
  from information_schema.columns
  where table_name = 'staff_unavailability_blocks'
    and column_name = 'leave_type';
  ```

  Both queries should return rows matching the defaults above.

## Test suites

- `server`: `npm run test` (from `server/`) - all 710 tests pass. Updated:
  `availability.service.spec.ts` (lunch-break policy fetch inserted into
  every existing `getDaySlots` test's mocked query queue, plus two new
  dedicated lunch-break tests), `staffPicker.service.spec.ts` (fixture
  fields), `unavailabilityBlock.service.spec.ts` (branch-scoping added to
  every "on behalf of" test, plus new tests for Rest Day self-service
  rejection, cross-branch rejection, Superadmin exemption, and
  `listBranchSchedule`).
- `server`: `npm run typecheck` - clean.
- `client`: `npm run test` and `npx tsc -b --noEmit` - both clean.
