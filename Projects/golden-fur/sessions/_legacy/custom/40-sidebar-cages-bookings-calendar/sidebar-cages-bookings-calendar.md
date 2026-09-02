# Sidebar Categories, Receptionist Cage View, Bookings Calendar

Type: Custom, three independent additions bundled in one batch (unrelated to
each other, so verify each separately). No DB migration.
Branch: `40-sidebar-cages-bookings-calendar` (suggested; based off `dev`).

## Scope

### 1. Collapsible sidebar categories + per-category sort

`Sidebar.tsx`'s labeled categories (Admin/Superadmin's grouped view -
Management, Receptionist, Groomer, Veterinarian, Cashier, Pet Assistant,
Supervisor) each get:

- Their own collapse/expand toggle (a chevron next to the category name),
  independent of the whole-sidebar icon-rail collapse that already existed.
  Persisted per staff/customer session in `localStorage`
  (`sidebar-section-collapsed-{role}-{label}`).
- A small "Sort" dropdown per category with three modes: **Custom order**
  (the config's own tile order, default), **Alphabetical**, and **Recently
  accessed** (most-recently-visited item first, tracked via a new
  `sidebar-recent-{role}` localStorage entry updated on every route visit).
  Also persisted per category (`sidebar-section-sort-{role}-{label}`).

Unlabeled categories (every non-admin role's own single flat list, and the
customer portal) render exactly as before - no toggle, no sort control, since
there's only one "category" there to begin with. When the whole sidebar is
collapsed to its icon rail, a category's items always show in full
(ignoring that category's own collapsed state) - there'd be no room for a
chevron to un-collapse it from the icon rail otherwise.

### 2. Receptionist read-only occupied/vacant cages view

Reused the existing **Cage Occupancy** report (`/staff/reports/cage-occupancy`,
a real-time per-size-category Available/Occupied/Reserved/Under Maintenance
snapshot, already fully read-only - no CRUD anywhere on that page) instead of
building a new page: Modules-Features (both the current and prior edition)
is explicit that this report is "Available to receptionists, admins, and
supervisors," but the shipped code only allowed Admin/Supervisor/Superadmin -
Receptionist added on both sides of the gate:

- **Server**: new `CAGE_OCCUPANCY_READ_ROLES` (`reports.types.ts`) =
  `REPORTS_READ_ROLES` (Superadmin/Admin/Supervisor) + `Receptionist`, used
  only by `GET /reports/cage-occupancy`'s own middleware chain
  (`reports.routes.ts`). The DSR and analytics routes are untouched and stay
  on the narrower `REPORTS_READ_ROLES`/`ANALYTICS_READ_ROLES` - Receptionist
  does not gain access to sales/financial reports, only cage status.
- **Client**: `CageOccupancyReport.tsx`'s `ALLOWED_VIEWER_ROLES` now includes
  `'Receptionist'`.
- **Sidebar**: new **Cage Occupancy** tile added to Receptionist's own
  dashboard (`staffDashboard.config.ts`), reusing the same tile title/icon
  (`DoorOpen`) the Admin/Supervisor grouped view already uses for the same
  page - not duplicated under Admin's "Receptionist" section, since Admin can
  already reach the same route via the existing "Supervisor" section.

### 3. Calendar view for the Bookings Queue

`ReceptionistBookingsQueuePage` (`/staff/bookings/queue`) gets a **List /
Calendar** toggle (same tab-pill pattern as Hotel Queue's Check In/Check Out
tabs) above the results. List is unchanged (the existing card-per-booking
view with View details/Reschedule/Cancel). Calendar is a hand-rolled month
grid (no calendar library was installed; followed the same
day-cell-and-chip pattern already used by `MonthlySchedulePage`'s staff
schedule calendar) showing every booking that matches the filters/search
above as a small colored chip (color matches `BookingStatusBadge`'s own
per-status tokens) on its scheduled date; clicking a chip navigates to that
booking's details page, same as List's "View details" button. Prev/Next
month buttons page the calendar independently once you're on it; changing
the Date filter (e.g. to "This month") re-syncs the calendar back to that
filter's month. The calendar reads from the same already-fetched/filtered
booking list as List view - it doesn't do its own separate fetch, so (as
called out in a copy line on the page itself) a narrow Date filter like the
default "Today" will only populate one day's worth of chips; switch Date to
"This month" to see a full month at once.

## Files changed

**Client**:

- `shared/components/Sidebar/{Sidebar.tsx,Sidebar.module.css,Sidebar.spec.ts}` -
  per-category collapse/sort/recently-accessed (new tests added).
- `shared/components/AppShell/AppShell.tsx` - now passes `role` through to
  `Sidebar` (needed to scope the new localStorage keys).
- `features/reports/components/CageOccupancyReport/CageOccupancyReport.tsx` -
  `ALLOWED_VIEWER_ROLES` gains `'Receptionist'`.
- `features/staff/config/staffDashboard.config.ts` - new "Cage Occupancy"
  tile on Receptionist's own dashboard section.
- `features/booking/pages/ReceptionistBookingsQueuePage/{ReceptionistBookingsQueuePage.tsx,.module.css,.spec.ts}` -
  List/Calendar toggle + month grid (new test added).

**Server**:

- `features/reports/reports.types.ts` - new `CAGE_OCCUPANCY_READ_ROLES`.
- `features/reports/reports.routes.ts` - `GET /reports/cage-occupancy` now
  uses `CAGE_OCCUPANCY_READ_ROLES` instead of the shared `REPORTS_READ_ROLES`
  middleware; DSR/analytics untouched.

## New API surface

None - no new routes. `GET /reports/cage-occupancy` (existing route) now
additionally accepts the `Receptionist` role; every other route's role gate
is unchanged.

## Automated Verification

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
npx vite build
```

Expected: typecheck clean, **597/597 tests pass** (128 files, includes 3 new
Sidebar tests + 1 new calendar-toggle test), lint clean, build clean
(pre-existing >500kB chunk-size warning, unrelated to this batch). Confirmed
as of this writing. Note: `CreateStaffAccountForm.spec.ts` timed out once
under full-suite load during this work but passed cleanly on its own and on
a full-suite re-run - a pre-existing flake unrelated to any file this batch
touched, not a regression.

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
npx eslint .
```

Expected: typecheck clean, **817/817 tests pass** (83 files), lint clean
(only pre-existing `no-console` warnings, none in `reports.types.ts`/
`reports.routes.ts`). Confirmed as of this writing.

## Manual Verification

You'll need the `server/` and `client/` dev servers running (`npm run dev`
from the repo root) and at least an Admin/Superadmin login (for the sidebar
categories) and a Receptionist login (for the cage view + calendar). No
migrations to apply for this batch.

### 1. Sidebar categories - collapse

1. Log in as Admin or Superadmin. In the sidebar, confirm each labeled
   section (Management, Receptionist, Groomer, Veterinarian, Cashier, Pet
   Assistant, Supervisor) has a small chevron next to its name.
2. Click a category's chevron (e.g. Groomer). Confirm that category's items
   (Grooming Queue, Hotel Queue, Daycare Queue, Boarding Checklist)
   disappear, and the chevron rotates to indicate collapsed. Other
   categories are unaffected.
3. Reload the page. Confirm that category is still collapsed (persisted).
   Click it again to expand, reload, confirm it stays expanded.
4. Log in as a non-admin role (e.g. Groomer). Confirm their own flat list
   has no chevrons/sort dropdowns anywhere - unchanged from before.
5. Collapse the whole sidebar to its icon rail (existing top-of-sidebar
   toggle). Confirm every category's icons still show in full, even if
   you'd previously collapsed that category while expanded (icon rail always
   shows everything).

### 2. Sidebar categories - sort

1. As Admin/Superadmin, expand a category with 2+ items (e.g. Groomer:
   Grooming Queue, Hotel Queue, Daycare Queue, Boarding Checklist). Confirm
   a small "Sort" dropdown appears under that category's name, defaulted to
   "Custom order".
2. Change it to "Alphabetical". Confirm the items in that category
   re-order to A-Z (Boarding Checklist, Daycare Queue, Grooming Queue, Hotel
   Queue). Confirm other categories are unaffected.
3. Reload the page. Confirm that category is still sorted Alphabetical
   (persisted) while an untouched category is still on Custom order.
4. Click a couple of links inside a category (e.g. Hotel Queue, then Daycare
   Queue), then set that category's sort to "Recently accessed". Confirm
   the two you just visited float to the top, most-recent first.

### 3. Receptionist cage occupancy view

1. Log in as **Receptionist**. Confirm a new **Cage Occupancy** tile appears
   on their dashboard/sidebar (after Bookings Queue).
2. Click it. Confirm `/staff/reports/cage-occupancy` loads and shows the
   same real-time per-size (S/M/L/XL) Available/Occupied/Reserved/Under
   Maintenance counts an Admin/Supervisor already sees there - no create/
   edit/delete controls anywhere on the page.
3. Confirm Receptionist still cannot reach `/staff/reports/dsr` or
   `/staff/reports/transaction-history` directly (redirects to Settings) -
   this change is scoped to cage occupancy only.
4. Log in as a role with no report access at all (e.g. Groomer) and confirm
   visiting `/staff/reports/cage-occupancy` directly still redirects to
   Settings (403 server-side, matching the Postman collection's item 4).

### 4. Bookings calendar view

1. Log in as Receptionist (or Admin/Supervisor/Superadmin) and open
   **Bookings Queue** (`/staff/bookings/queue`). Confirm a **List / Calendar**
   toggle appears above the results, defaulted to List (unchanged look).
2. Set the Date filter to "This month" (so a full month of bookings loads),
   then click **Calendar**. Confirm a month grid appears (weekday headers,
   Prev/Next month buttons, a label like "August 2026") with a small colored
   chip on each day that has a booking, reading its time, pet name, and
   service category.
3. Click a chip. Confirm it navigates to that booking's details page
   (`/staff/bookings/:id`), same destination as List view's "View details".
4. Click **Prev**/**Next** month. Confirm the grid pages to the adjacent
   month (chips only show for days whose bookings are still within the
   currently-loaded Date filter range).
5. Change the Date filter back to "Today" while still in Calendar view.
   Confirm the calendar jumps back to the current month.
6. Click **List**. Confirm the original card list (with Reschedule/Cancel/
   View details) reappears exactly as it did before this batch.

## Revision 2 (same branch, follow-up feedback pass)

Four more changes from live review of Revision 1. Client-only except where
noted; no DB migration.

### 1. Six-digit OTP boxes

Every MFA code-entry form (staff login challenge, staff mandatory
enrollment, customer login challenge, Settings > Security enrollment - i.e.
`MfaChallengeForm`, `MfaEnrollForm`, `TotpChallengeForm`, `TotpEnrollPanel`)
now renders a new shared `OtpInput` (6 individual boxes, auto-advancing
focus, Backspace-to-previous, paste-splits a full code across boxes, `?`
key nav) instead of one free-text `maxLength={6}` field. Purely a rendering
swap - each form's own `code` state, `totpCodeSchema` validation, and submit
logic are unchanged (`OtpInput` is a controlled `value`/`onChange` string,
same shape the old `<input>` produced).

### 2. Week/Month calendar granularity

Bookings Queue's Calendar view (Revision 1) gets a **Week / Month** toggle
next to the Prev/Next controls, defaulting to Month. Week shows a single
row of 7 days (taller cells, more room per chip) for the week containing
the current anchor date; Month is unchanged from Revision 1. Both share the
same Prev/Next buttons (step by 7 days in Week, by 1 month in Month) and
the same underlying already-filtered booking list/chips - still no separate
fetch for the calendar.

### 3. Cage Occupancy now visible on the Admin/Superadmin grouped sidebar

Revision 1 added the **Cage Occupancy** tile to Receptionist's own
dashboard, but Admin/Superadmin's grouped view has its own separate copy of
each shared tile per section (see `staffDashboard.config.ts`) and that copy
was missed - their "Receptionist" section still only showed Customer
Management and Bookings Queue. Added there too (same route,
`/staff/reports/cage-occupancy`), mirroring the existing precedent of Hotel
Queue/Daycare Queue already appearing under both the Groomer and Pet
Assistant sections in that same grouped view.

### 4. Notion-style sidebar sort menu + drag-and-drop custom order

Two changes to how every category sorts, replacing Revision 1's always-
visible inline "Custom order ⌄" `<select>`:

- The sort control is now a **"..." menu** (reusing the existing shared
  `MoreOptionsMenu` kebab-menu component, extended with an optional
  `active` flag that renders a checkmark next to the currently-selected
  item) listing all three sort modes - clicking one applies and persists it
  exactly as the old dropdown did, just via a menu item instead of a
  `<select>` option.
- This "..." menu now also appears on **every non-admin role's flat
  (unlabeled) section** and the customer portal's own nav, not just the
  admin-grouped labeled categories - previously those had no sort control
  at all. An unlabeled section still gets no heading/chevron (it's still a
  single flat list, unchanged look), just the menu, right-aligned at the
  top of its item list.
- Under **Custom order** (now the true default everywhere, not just "the
  config's own order" - see below), items become drag-and-drop reorderable:
  native HTML5 drag (no new dependency), reordering live as you drag one
  item over another (swap triggers on entering a new item, not on every
  pointer-move, to avoid oscillating), with a lightweight FLIP-animated
  reflow (each item's old position is captured before the reorder and it
  animates from there to its new spot, ~200ms ease) so both dragging and
  switching to Alphabetical/Recently accessed reflow smoothly instead of
  snapping. The resulting order is persisted per role+category
  (`sidebar-section-order-{role}-{label}`) and layered on top of the
  config's own tile order (new tiles not yet dragged fall in at the end in
  their config order; removed tiles drop out) - so "Custom order" now means
  _your_ custom order, not just "whatever order the config happened to list
  them in." Dragging is disabled (no grip handle, not `draggable`) whenever
  sort isn't Custom order, or the whole sidebar is in its icon-rail
  collapsed state.

## Files changed (Revision 2)

**New**: `shared/components/OtpInput/{OtpInput.tsx,OtpInput.module.css,OtpInput.spec.ts}`.

**Client**:

- `features/auth/staff/components/forms/{MfaChallengeForm,MfaEnrollForm}/*.tsx`,
  `shared/components/{TotpChallengeForm,TotpEnrollPanel}/*.tsx` - swapped
  onto `OtpInput`.
- `shared/components/TotpChallengeForm/TotpChallengeForm.spec.ts`,
  `shared/components/TotpEnrollPanel/TotpEnrollPanel.spec.ts` - updated to
  type into the new per-digit boxes instead of one field.
- `features/booking/pages/ReceptionistBookingsQueuePage/{ReceptionistBookingsQueuePage.tsx,.module.css,.spec.ts}` -
  Week/Month granularity (new test added).
- `features/staff/config/staffDashboard.config.ts` - Cage Occupancy added
  to Admin/Superadmin's grouped "Receptionist" section.
- `shared/components/MoreOptionsMenu/{MoreOptionsMenu.tsx,.module.css}` -
  new optional `active` flag (checkmark), backward-compatible for its other
  existing caller (`CageStatusGrid`).
- `shared/components/Sidebar/{Sidebar.tsx,Sidebar.module.css,Sidebar.spec.ts}` -
  "..." sort menu (labeled + unlabeled sections) and drag-and-drop custom
  order with FLIP animation (tests updated/added).

No server changes in this revision.

## Automated Verification (Revision 2)

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
npx vite build
```

Expected: typecheck clean, **604/604 tests pass** (129 files), lint clean,
build clean (same pre-existing >500kB chunk-size warning). Confirmed as of
this writing.

No server changes in this revision - server's own test suite (817/817,
confirmed in Revision 1) is unaffected.

## Manual Verification (Revision 2)

### 1. Six-digit OTP boxes

1. Log out and log back in as any staff member with MFA already enrolled
   (or trigger the customer MFA challenge). Confirm the code field is now 6
   individual square boxes, not one text field.
2. Type a digit in the first box - confirm focus auto-advances to the next
   box after each digit, and the 6th box ends up focused after typing all 6.
3. Press Backspace on a filled box - confirm it clears just that box and
   stays there; press Backspace again (now empty) - confirm it moves to and
   clears the previous box.
4. Use ArrowLeft/ArrowRight to move between boxes without typing.
5. Copy a 6-digit code (e.g. from your authenticator app) and paste it while
   any box is focused - confirm it fills all 6 boxes at once and focus lands
   on the last filled box.
6. Submit a correct code - confirm login/enrollment/verification still
   succeeds exactly as before. Repeat for staff mandatory enrollment
   (`/staff/mfa/enroll`) and Settings > Security's "Set up MFA".

### 2. Week/Month calendar

1. Open Bookings Queue, switch to **Calendar** (defaults to Month, as
   Revision 1). Confirm a new **Week / Month** toggle appears next to
   Prev/Next.
2. Click **Week**. Confirm the grid collapses to a single row of 7 taller
   day cells for the current week, each showing "Mon D" (e.g. "Aug 17")
   instead of a bare day number.
3. Click Prev/Next in Week mode - confirm it pages by 7 days (not by
   month). Switch back to **Month** - confirm it returns to the full month
   grid, still on a sensible nearby month.
4. Change the Date filter (e.g. to "This month") while in either Week or
   Month mode - confirm the calendar re-syncs to that filter's date.

### 3. Cage Occupancy on the admin grouped sidebar

1. Log in as Admin or Superadmin. In the sidebar's **Receptionist** section
   (the grouped view), confirm **Cage Occupancy** now appears alongside
   Customer Management and Bookings Queue. Click it - confirm it navigates
   to `/staff/reports/cage-occupancy` and loads correctly.

### 4. Notion-style sidebar sort menu + drag-and-drop

1. Log in as Admin/Superadmin. On a labeled category (e.g. Groomer),
   confirm the old inline "Custom order ⌄" dropdown is gone, replaced by a
   small **"..."** button next to the category name.
2. Click it. Confirm a menu opens with three items - Sort: Custom order,
   Sort: Alphabetical, Sort: Recently accessed - and the currently-active
   one shows a checkmark. Click Alphabetical - confirm the category
   re-sorts, the menu closes, and reopening it shows the checkmark moved to
   Alphabetical.
3. Log in as a non-admin role (e.g. Groomer) or a customer. Confirm their
   flat nav list (still no heading/chevron) now also has a **"..."** sort
   menu at its top, with the same three options.
4. Switch a category back to **Custom order**. Confirm each item now shows
   a small grip-dots handle on its left.
5. Drag an item to a different position within the same category (mouse
   down on a row, drag over another row, release). Confirm the list
   reorders smoothly (not an instant snap) as you drag, and the new order
   sticks after you release.
6. Reload the page. Confirm the dragged order persisted.
7. Switch away from Custom order (e.g. to Alphabetical) - confirm the grip
   handles disappear and items are no longer draggable. Switch back to
   Custom order - confirm your previously-dragged order is still there
   (not reset to the original config order).
8. Collapse the whole sidebar to its icon rail. Confirm no grip handles or
   "..." menus are visible/reachable there (matches Revision 1's existing
   icon-rail behavior for the chevron/label).

## Revision 3 (same branch, live-review bug-fix pass)

Three bug fixes from live-testing Revision 2's sidebar work, plus one more
feature addition. Client-only; no DB migration.

### 1. Fixed: sidebar items twitching on category collapse/expand

`.itemList > li` (the flex row wrapping a category item's grip handle +
link) was scoped only to the _expanded_ `.itemList` class, not
`.itemListCollapsed`. The instant a category collapsed, every item's `<li>`
reverted to the browser's default `list-item` layout (`display` isn't
animatable, so this happened instantly, not smoothly alongside the
max-height transition) before snapping back to flex on expand - visibly
"twitching" the grip handle/link each time. Fixed by applying the flex rule
to both classes (`Sidebar.module.css`).

### 2. "..." sort trigger is now hover/focus-revealed

The kebab menu trigger (shared `MoreOptionsMenu`) was always fully visible
on every category, even though Revision 2's own copy called it "Notion-
style." Now hidden (`opacity: 0`) until its row (`.sectionHeader`/
`.flatSectionHeader`) is hovered or contains focus, matching Notion's own
behavior. Implemented via a CSS custom property
(`--more-options-trigger-opacity`, default `1`) that `MoreOptionsMenu`
consults but never sets itself - Sidebar is the only current caller that
redefines it (to `0`, then back to `1` on `:hover`/`:focus-within`), so
`MoreOptionsMenu`'s other existing caller (`CageStatusGrid`) is unaffected
and stays always-visible. Stays visible whenever its own menu is open too
(`[aria-expanded='true']`), even after the pointer moves off the row onto
the open menu itself.

### 3. Fixed: drag-and-drop "going crazy"

Revision 2 reordered the underlying array (and therefore moved the
_actively-dragged_ `<li>` in the DOM) on every `dragenter` event, live,
mid-gesture. Relocating a drag source's own DOM node while a native HTML5
drag is still in progress is unreliable across browsers - some cancel or
scramble the drag entirely, which is what "going crazy" was. Fixed by
deferring the actual reorder to `drop` (a single state update, once):
`dragenter` now only tracks which item the pointer is currently over (for a
dashed-outline drop-target indicator), and the real array
splice/persist/FLIP-animate happens once, on `drop`. Dragging over items
without dropping no longer touches the order or moves anything in the DOM.

### 4. Search/sort/filter on Cage Occupancy

The per-size Available/Occupied/Reserved/Under Maintenance count summary
(unchanged) now has a **"Find a cage"** section below it: a searchable
(by cage label), sortable (Label/Status/Size), and filterable (by status,
by size) list of individual cages - reusing `GET /hotel/cages`
(`getCageGrid`, already open to every role that can reach this page, same
endpoint `CageStatusGrid`/Hotel Queue's check-in flow already calls) rather
than the aggregate RPC the summary above uses. No server changes - purely
an additional client-side fetch/list. This individual list is always scoped
to the viewer's own branch (that endpoint has no branch override) - a
Superadmin's branch selector at the top only affects the summary; checking
a specific cage in a different branch is still Hotel Queue's or Admin >
Cages' job, unchanged from before.

## Files changed (Revision 3)

**Client**:

- `shared/components/Sidebar/{Sidebar.tsx,Sidebar.module.css,Sidebar.spec.ts}` -
  collapse-twitch fix, hover-reveal wiring, deferred-to-drop reordering
  (tests updated/added).
- `shared/components/MoreOptionsMenu/{MoreOptionsMenu.tsx,MoreOptionsMenu.module.css}` -
  `--more-options-trigger-opacity` custom-property hook (no prop/behavior
  change for existing callers).
- `features/reports/components/CageOccupancyReport/{CageOccupancyReport.tsx,.module.css,CageOccupancyReport.spec.ts}` -
  new "Find a cage" search/sort/filter section (new test file - this
  component had none before).

No server changes in this revision.

## Automated Verification (Revision 3)

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
npx vite build
```

Expected: typecheck clean, **611/611 tests pass** (130 files - 6 new
Sidebar tests replaced with updated drag semantics, 6 new
`CageOccupancyReport` tests), lint clean, build clean (same pre-existing

> 500kB chunk-size warning). Confirmed as of this writing.

No server changes in this revision - server's own test suite (817/817,
confirmed in Revision 1) is unaffected.

## Manual Verification (Revision 3)

### 1. Sidebar collapse/expand no longer twitches

1. Log in as Admin/Superadmin. Switch a labeled category to **Custom
   order** (so grip handles show). Click the category's chevron to collapse
   it, then expand it again several times in a row. Confirm the items no
   longer visibly jump/flash - the collapse/expand should look like a
   smooth height animation, not a snap-then-settle.
2. Repeat on a category still on Alphabetical/Recently accessed (no grip
   handles) - confirm it was already smooth-looking, unaffected either way.

### 2. Hover-reveal "..." menu

1. On any category (labeled or the flat/unlabeled kind), confirm the
   **"..."** button is not visible at rest.
2. Move the mouse over the category's header row (or, for a flat section,
   anywhere along that top row) - confirm the "..." fades in.
3. Move the mouse away - confirm it fades back out.
4. Tab to it via keyboard (Tab through the sidebar) - confirm it becomes
   visible once focused, even without the mouse over it.
5. Click it to open the menu, then move the mouse off the row onto the open
   menu itself - confirm the "..." stays visible the whole time the menu is
   open.
6. Open `AdminCagesPage` (Cage CRUD) or Hotel Queue's check-in grid -
   confirm the "..." there (view/maintenance options on each cage card)
   still shows exactly as before, always visible, unaffected by this change.

### 3. Drag-and-drop no longer "goes crazy"

1. Switch a category to Custom order. Pick up an item (mouse down + drag)
   and drag it slowly over several other items in the same category without
   releasing. Confirm each hovered item gets a dashed outline (the drop
   target indicator) but nothing actually reorders or jumps around yet.
2. Release over one of them. Confirm the list reorders once, smoothly, to
   the dropped position, and it persists after a reload.
3. Repeat several drags in a row, including dragging an item up past
   several others and back down - confirm the drag feels stable throughout
   (no items disappearing, duplicating, or the drag getting stuck/cancelled
   mid-gesture).

### 4. Cage Occupancy search/sort/filter

1. Open **Cage Occupancy** (as Receptionist, Admin, Supervisor, or
   Superadmin). Confirm the existing per-size summary is unchanged, and a
   new **"Find a cage"** section appears below it with a search box, a sort
   dropdown, a Status filter, and a Size filter, plus a list of individual
   cages (label, size, status badge) and a "N of M cages" count.
2. Type part of a cage's label into the search box - confirm the list
   narrows to matching cages and the count updates.
3. Set the Status filter to e.g. "Occupied" - confirm only occupied cages
   show. Set it back to "All statuses".
4. Set the Size filter to one size - confirm only that size's cages show.
   Combine it with a search term - confirm both apply together.
5. Change the sort dropdown between Label/Status/Size - confirm the list
   re-orders accordingly.
6. As Superadmin, switch the branch selector above the summary - confirm
   the summary counts update for that branch, while the "Find a cage" list
   below stays on your own branch (documented limitation, not a bug).

## Revision 4 (same branch, live-review bug-fix pass)

One more bug fix from live review. Client-only; no DB migration.

### Fixed: "Recently accessed" sort always one click stale

`useRecentlyAccessed`'s returned map was recomputed (read fresh from
localStorage) reactively on every route change, via a `useMemo` keyed on
`location.pathname`. That `useMemo` runs _during render_, which happens
_before_ the sibling `useEffect` that actually writes the just-navigated-to
page's timestamp to localStorage (effects run after commit). So on every
navigation, the map returned for that render was always the map from
_before_ this click - the "Recently accessed" order only ever caught up on
your _next_ navigation, one click later, matching the reported symptom.

Fixed along the lines suggested during review: visits are still recorded
into localStorage on every navigation exactly as before (the effect is
unchanged), but the map actually used for sorting is now read exactly once,
via a `useState` initializer, when the Sidebar first mounts - not
reactively on every subsequent click. Since `Sidebar`/`AppShell` mount once
per full page load and stay mounted across in-app navigation (only
`<Outlet/>`'s content swaps), "Recently accessed" order now updates on the
next full page reload rather than chasing (and lagging behind) every click.
The current page's own visit is still folded in immediately on that
initial read, so a fresh reload correctly shows the page you're currently
on as the most recent, without needing a second navigation to catch up.

## Files changed (Revision 4)

**Client**: `shared/components/Sidebar/{Sidebar.tsx,Sidebar.spec.ts}` only
(new test added).

## Automated Verification (Revision 4)

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
```

Expected: typecheck clean, **612/612 tests pass** (130 files - 1 new
Sidebar test), lint clean. Confirmed as of this writing.

## Manual Verification (Revision 4)

1. Clear your browser's localStorage for the app (or open a fresh private
   window) and log in as Admin/Superadmin.
2. Switch a category with 2+ items (e.g. Groomer) to **Recently accessed**
   sort. Confirm the order is whatever the config's own default order was
   (nothing visited yet this session).
3. Click into one of that category's items (e.g. Hotel Queue). Confirm the
   sidebar's own order does **not** reorder immediately - this is now
   expected (order refreshes on reload, not live per click).
4. Reload the page (full browser refresh). Confirm the item you just
   visited (Hotel Queue) now sorts first in that category, and that this
   took exactly one reload, not two clicks-and-a-reload.
5. Visit a different item in the same category, then reload again - confirm
   it becomes the new most-recent, and the previous one drops to second.

## Revision 5 (same branch, live-review pass)

Three more changes from live review of the admin/superadmin grouped
sidebar specifically (the only sidebar with 2+ labeled categories - every
other role's single flat section is unaffected by any of this). Client-
only; no DB migration.

### 1. Fixed: "twitching" on category collapse/expand (real cause this time)

Revision 3 fixed one twitch cause (a CSS rule not matching the collapsed
list class) but live review found the collapse/expand animation still
looked jumpy. The actual remaining cause: `isDraggable` (which controls
whether an item's grip handle renders) depended on `itemsHidden` (the
category's own collapsed state), so the instant a category collapsed or
expanded, every one of its items' grip handles mounted or unmounted
_simultaneously_ - each item's row reflowing (the link sliding over to
fill/give up the handle's space) at the same moment the height/opacity
transition started, reading as the whole category "rearranging." Fixed by
making `isDraggable` depend only on sort mode and the whole-sidebar
collapsed state, not the category's own collapse state - a collapsed
list's items are already `pointer-events: none` and invisible, so whether
they're technically `draggable` while hidden doesn't matter, but keeping
the grip handles mounted throughout removes the reflow entirely.

### 2. Icon rail: one icon per category, not one per tile

The icon-rail (whole-sidebar-collapsed) view used to flatten every tile
from every category into one long undifferentiated icon list - fine for a
role with one flat section, but Admin/Superadmin's 7 categories (~20+
tiles combined) turned the rail into a wall of icons with no grouping,
exactly the reported problem. A labeled category now collapses to a
**single icon button** in the rail (its own section icon, e.g. the same
Users/ClipboardList/Scissors/etc. icons already used for its header)
instead of every individual tile. Clicking it expands the whole sidebar
back out (same effect as the top collapse toggle) so every page under that
category becomes reachable from there - it doesn't guess which one page
you wanted. Unlabeled sections (e.g. every role's own "Dashboard" shortcut,
and every non-admin role's entire flat list) are unaffected - they still
show their own individual item icons in the rail exactly as before, since
that's already a short, unambiguous list.

### 3. Category-level sort + drag, mirroring the per-item one

Once a sidebar has 2+ labeled categories (in practice, only Admin/
Superadmin's grouped view), a new **"Categories"** row appears above them
with its own "..." menu - the same three modes as a single category's own
item sort (Custom order/Alphabetical/Recently accessed), but reordering the
_categories themselves_. Recently accessed scores a category by whichever
of its own items was most recently visited. Under Custom order, each
category gets a grip handle (in its header, before the collapse chevron)
and becomes drag-and-drop reorderable against its sibling categories - same
deferred-to-drop mechanics and FLIP-animated reflow as Revision 3's item-
level fix (dragging over another category only highlights it as the drop
target; the actual reorder happens once, on drop). The unlabeled
"Dashboard" section sits outside this reordering, always first, since it
isn't really a "category." Persisted per role
(`sidebar-category-sort-{role}` / `sidebar-category-order-{role}`), same
localStorage convention as everything else here.

## Files changed (Revision 5)

**Client**: `shared/components/Sidebar/{Sidebar.tsx,Sidebar.spec.ts}` only
(tests updated for the new rail-mode behavior; new tests added for
category-level sort/drag).

## Automated Verification (Revision 5)

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
npx vite build
```

Expected: typecheck clean, **616/616 tests pass** (130 files - one old rail-
mode test rewritten for the new one-icon-per-category behavior, 4 new
category-sort/drag tests), lint clean, build clean (same pre-existing

> 500kB chunk-size warning). Confirmed as of this writing.

## Manual Verification (Revision 5)

### 1. Collapse/expand no longer twitches (for real this time)

1. Log in as Admin/Superadmin. Expand a category (e.g. Groomer, which has
   4 tiles) while its sort is Custom order (grip handles showing). Collapse
   and expand it several times in a row.
2. Confirm the items no longer flicker/reflow at all during the
   transition - just a clean height/opacity animation, grip handles present
   the whole time.

### 2. Icon rail shows one icon per category

1. Collapse the whole sidebar (top toggle). Confirm the rail now shows: the
   Dashboard icon, then exactly **one icon per category** (7 icons for
   Management/Receptionist/Groomer/Veterinarian/Cashier/Pet
   Assistant/Supervisor) - not one icon per individual tile.
2. Click one of the category icons (e.g. the Groomer one). Confirm the
   sidebar expands back out to its full width, landing on the normal
   labeled view (the Groomer category may still be individually collapsed
   if you'd left it that way - click its own chevron to open it).
3. Log in as a non-admin role (e.g. Groomer) or a customer. Collapse the
   sidebar - confirm the rail still shows one icon per individual tile as
   before (their single flat section is unaffected by this change).

### 3. Category-level sort + drag

1. As Admin/Superadmin with the sidebar expanded, confirm a **"Categories"**
   row with its own "..." button appears above the list of categories.
2. Open it, confirm the same three sort options (Custom order/Alphabetical/
   Recently accessed) as a single category's own menu. Pick Alphabetical -
   confirm the categories themselves re-order A-Z (Cashier, Groomer,
   Management, Pet Assistant, Receptionist, Supervisor, Veterinarian).
   Reload - confirm it persisted.
3. Switch back to Custom order. Confirm each category header now shows a
   grip handle before its chevron. Drag one category above/below another -
   confirm it reorders smoothly (not instantly), and the order persists
   after a reload.
4. Log in as a role with only one section (e.g. Groomer) or a customer -
   confirm there's no "Categories" row at all (nothing to sort against).

## Revision 6 (same branch, live-review pass)

Live review reported the twitching _also_ happens on scroll, and asked for
two more changes: a genuinely sticky sidebar, and a fully bare icon rail
(no icons at all - not even the one-per-category from Revision 5, which
this revision replaces). Client-only; no DB migration.

### 1. Fixed: twitching on scroll (the actual root cause)

Two compounding bugs, both in code untouched by earlier revisions:

- `StaffAuthGuard.tsx` built the sidebar's `sections`/`items` arrays inline
  in JSX (`sidebarSections={buildSidebarSections(role)}`), uncached. Every
  re-render of `StaffAuthGuard` - for _any_ reason - created brand new
  array references. `useInactivityTimeout` (the session-timeout countdown)
  re-renders its owner once a second by design, and also resets on a
  window-level `scroll` event - so scrolling the page, or simply leaving it
  open for a second, kept re-creating those arrays. Sidebar's FLIP-reorder
  effect reacts to that array's identity changing, so it was replaying
  constantly, regardless of any real reorder. Fixed by memoizing
  `buildSidebarSections(role)` on `role` in `StaffAuthGuard`, so the array
  reference is stable across unrelated re-renders.
- Independently, the FLIP effect itself measured position with
  `getBoundingClientRect().top`, which is relative to the _viewport_ - and
  the sidebar scrolls independently (`overflow-y: auto`). If the effect
  fired (per the bug above) while the sidebar's own scroll position had
  changed since the last measurement, the resulting "delta" was
  contaminated by the scroll distance itself, misread as items having
  moved, and "corrected" with a transform - i.e., the twitch. Fixed by
  adding the scroll container's current `scrollTop` to the measured
  position at both ends (`scrollInvariantTop()`) - a standard trick: for a
  pure scroll, the rect-top decrease and the scrollTop increase cancel out
  exactly, leaving only genuine layout-change deltas (real reorders,
  category collapse/expand) to actually animate.

Both fixes apply to the item-level FLIP effect (`SidebarCategory`) and the
Revision 5 category-level one (`Sidebar`) identically.

### 2. Sidebar is now genuinely sticky

Previously, `.sidebar`/`.sidebarCollapsed` used `min-height: 100vh` with no
`position: sticky`/`fixed` - fine as long as `.main`'s content fit in one
screen, but once a page's content was taller than the viewport, there was
no independent scroll container: the whole document scrolled, and the
sidebar (an ordinary in-flow flex item) scrolled away with everything else
above the fold.

Restructured `AppShell.module.css` into a fixed-height app shell instead of
trying to coordinate two competing `position: sticky` elements (the navbar
already used `top: 0`; stacking the sidebar on the same `top: 0` would
overlap it). `.shell` is now `height: 100vh` (not `min-height`) and never
scrolls itself; `.main` gets `overflow: auto` and scrolls its own content
independently. `.sidebar`/`.sidebarCollapsed` switched from
`min-height: 100vh` to `height: 100%`, so it now fills exactly the space
below the navbar rather than potentially growing taller than it - the
sidebar (and its own internal `overflow-y: auto` for a tall nav) never
moves regardless of how tall the page content next to it gets.

### 3. Icon rail: back to nothing but the toggle (Revision 5's per-category icons removed)

Revision 5 replaced "one icon per tile" with "one icon per category" in
the rail. Live review asked for something simpler: the rail now shows
_only_ the expand toggle - no icons of any kind, labeled category or flat
list alike. `SidebarCategory`'s rail-mode single-icon-button branch (and
its `onExpandSidebar` prop) were removed; a new
`.sidebarCollapsed .itemList`/`.sidebarCollapsed .itemListCollapsed` CSS
rule now hides every item list the same CSS-hidden-not-unmounted way
`.sectionHeader` already was, so expanding the sidebar back out still
animates smoothly rather than popping tiles in.

## Files changed (Revision 6)

**Client**:

- `shared/components/Sidebar/{Sidebar.tsx,Sidebar.module.css,Sidebar.spec.ts}` -
  scroll-invariant FLIP measurement, removed the per-category rail icon
  (test updated to match).
- `features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` -
  memoized `buildSidebarSections(role)`.
- `shared/components/AppShell/AppShell.module.css` - fixed-height shell,
  independently-scrolling `.main`.

No server changes in this revision.

## Automated Verification (Revision 6)

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
npx eslint .
npx vite build
```

Expected: typecheck clean, **615/615 tests pass** (130 files - one rail-
mode test rewritten for the fully-bare rail), lint clean, build clean
(same pre-existing >500kB chunk-size warning). Confirmed as of this
writing.

**Not independently visually confirmed this revision** - the layout change
(AppShell.module.css) and the scroll-position math are both real-browser/
real-CSS concerns that automated jsdom tests can't meaningfully exercise
(jsdom doesn't do layout, so `getBoundingClientRect()` is inert there
regardless of what the code does with it). Automated tests, typecheck, and
build are all clean, and the CSS pattern (fixed-height shell + independent
`overflow: auto` panes) is a standard, low-risk one, but you should
actually scroll a tall page and watch the sidebar in a real browser before
calling this closed - see the manual steps below.

## Manual Verification (Revision 6)

### 1. No more twitching on scroll

1. Log in as Admin/Superadmin. Switch a category to Custom order (grip
   handles visible) and expand several categories so the sidebar's own
   content is taller than the viewport.
2. Scroll the sidebar up and down repeatedly. Confirm items no longer
   twitch/rearrange at all during scrolling - just a plain scroll.
3. Leave the page open and idle (don't touch anything) for several
   seconds - confirm nothing twitches on its own either (the once-a-second
   session-timeout tick used to be enough to trigger it by itself).
4. Open a tall page (e.g. Staff Management with many rows) so the _main
   content_ is taller than the viewport, and scroll that. Confirm the
   sidebar doesn't twitch from this either.

### 2. Sidebar is sticky

1. Open a page whose main content is clearly taller than one screen (e.g.
   Staff Management, or Bookings Queue with many results). Scroll down.
2. Confirm the sidebar (and the navbar) stay fixed in place while only the
   main content area scrolls - the sidebar should never move, shrink,
   scroll away, or leave visible empty space above/below it.
3. If the sidebar's own nav content is independently taller than the
   viewport (e.g. every category expanded on an Admin/Superadmin account),
   confirm the sidebar scrolls _within itself_ (its own scrollbar),
   independent of the main content's scroll position.
4. Resize to a narrow/mobile width and confirm the existing mobile
   sidebar-as-overlay behavior (`position: fixed`) still works unchanged -
   this revision's layout change doesn't touch that path.

### 3. Icon rail is bare

1. Collapse the sidebar. Confirm the rail shows **only** the expand toggle
   button - no icons for individual tiles, no icons for categories either
   (Revision 5's one-per-category rail icons are gone).
2. Click the toggle. Confirm the sidebar expands back out smoothly
   (animated, not an instant pop) to exactly where you left it - same
   categories collapsed/expanded, same sort modes, as before you
   collapsed it.
