# Notion-style search/filter/sort/group/view controls - Batches A+B+C, DataCalendar, Tier 2, and Tier 3 complete

Branch: `feat/notion-style-data-views`

This is a big, multi-part change (see `../plan.md` for the full rollout).
This file covers exactly what's been **built and tested so far** in this
session: the five new shared pieces every later page reuses (including the
calendar piece, `DataCalendar`), all 11 pages of Batch A (maintenance/
config), all 3 pages of Batch B (customer-facing), both Batch C items (the
booking-process services/packages step and cage selector step - each given
a deliberately **lighter, search-only** treatment, not the full pill/sort/
group/view stack - see "What changed" below for why), the Monthly
Schedule page's calendar view (refactored onto `DataCalendar` with no
behavior change), all seven Tier 2 items (the six full pages - Staff
Management, Customer Management, Credit Management/Credit History, Vet
Catalog, My Patients, Activity Log - plus `StaffPickerList`, a lighter
search+sort-only remaster since it's a single-choice booking-flow picker,
not a browse list), and now **Tier 3, the chip-styling-only pass on the
live operational queues** - see "What changed" below for how one shared-
component edit covered every named Tier 3 page at once. The only thing
left from the whole plan is one carried-over gap from Batch A's own scope:
folding `TransactionHistoryTable`/`TransactionBoard` onto the shared
`DataTable`/`DataBoard` (planned, never actually done) - it's **not**
part of this file yet - each batch gets this same file updated in
place when it lands, per the session-documentation skill.

## The request, verbatim

> As a developer, I want a consistent, Notion like interface (I want these
> to resemble Notion like interface (where adding a filter, sort, etc.
> creates pills that can be edited and removed), search, sort, filter,
> group by options to all things that reference tables from the database.
> Include view options as well inspired by Notion (table, list,
> board/kanban, calendar with month or week view if table has dates).

**Scope note:** rather than being asked what to include, the instruction was
to say what should be *excluded*, and otherwise touch everything that fits
(any page whose data comes from a GET request to the database). See
`../plan.md` for the full tier breakdown of what's in, what's partial, and
what's deliberately left out. This increment covers the shared building
blocks plus all eleven Batch A pages - see "Open items" at the bottom.

## Root cause / Context

Before this change, almost every page in the app that lists database
records (Pet Types, Cages, Breeds, Discounts, a customer's Pets, ...)
hand-wrote its own `<table>` or `<ul>` markup, with little or no way to
search, sort, filter, or group what's shown, and no way to switch between a
table, a card-style list, or a Kanban-style board. One page (Cashier /
Customer **Transactions**) had already gotten a "Notion-style" pill-based
filter/sort bar (`FilterSortBar` - a small rounded "pill" per active filter
or sort, with a hover-to-reveal "X" to remove it, same idea as a tag chip in
Notion), but nothing generalized that pattern for reuse elsewhere, and there
was no shared piece at all for a spreadsheet-style table, a card list, a
Kanban board, or "group by."

This session builds those missing shared pieces and proves them on two real
pages - one very low-risk (a settings toolbar swap where the backend already
supported everything needed), one that's the actual worked example for
every later admin page in the rollout.

## What changed

### Database

None. Every page keeps calling its existing `GET` endpoint exactly as
before; searching, filtering, sorting, and grouping all happen in the
browser, over data already fetched (see `../plan.md`'s "client-side only"
decision).

### Server

None.

### Client - new shared pieces (used by every future page in this rollout)

- `client/src/shared/components/FilterSortBar/filterField.types.ts` - added
  two new kinds of filter a page can declare: **multi-select** (pick several
  options at once - e.g. "supports Dog or Cat"; the old kind only let you
  pick one) and **number-range** (a "between X and Y" filter, e.g. a price
  range).
- `client/src/shared/components/FilterSortBar/FilterSortBar.tsx` - added the
  on-screen editor for each of those two new kinds (a checkbox list for
  multi-select, two number boxes for number-range).
- `client/src/shared/components/DataTable/DataTable.tsx` (new) - a reusable
  spreadsheet-style table: hand it a list of columns and a list of rows, it
  draws the table. This is the **Table** view option.
- `client/src/shared/components/DataList/DataList.tsx` (new) - a reusable
  card-style list (Notion's **List** view option).
- `client/src/shared/hooks/useGroupBy/useGroupBy.ts` (new) - splits a list
  into labeled buckets by whatever rule a page picks (e.g. "by Status").
  This is what powers **group by**.
- `client/src/shared/components/DataBoard/DataBoard.tsx` (new) - a reusable
  Kanban-style board: one column per bucket from `useGroupBy`, cards inside.
  This is the **Board** view option.
- `client/src/shared/components/DataCalendar/DataCalendar.tsx` (new) - a
  reusable **Calendar** view: a month grid (generalized out of the Monthly
  Schedule page's own month-grid math - same date-key bucketing, leading
  blanks, and month math, just made reusable) plus a brand-new **week**
  grid mode that didn't exist anywhere in the app before. Hand it a list of
  items, a function that returns one `'YYYY-MM-DD'` date per item, and a
  function that renders each item as a chip - it draws the grid, buckets
  items onto the right day, and (optionally) shows a small "+" add button
  on each day. Its own prev/next month or week navigation can be hidden
  (`showNav={false}`) when a page already has its own month/year control
  shared with another view, as Monthly Schedule's does.

### Client - two pages migrated onto the new pieces

**`client/src/features/staff/components/DeletedRecordsArchiveList/`** (the
Admin "Deleted Records" archive browser, inside Settings > Config >
Archive):
- `archiveBrowserFields.ts` (new) - the "adapter" file that describes this
  page's specific filters/sort to the shared `FilterSortBar`.
- `DeletedRecordsArchiveList.tsx` - swapped its plain dropdown toolbar for
  `FilterSortBar` (Table filter + a new Deleted-date-range filter + sort),
  and its `<ul>` for the shared `DataList`. No behavior change beyond that -
  it already talked to a backend that supported all of this.

**`client/src/features/hotel/pages/AdminCagesPage/`** (Settings > Config >
Cages) - the full worked example, first page with all three views:
- `cageBrowserFields.ts` (new) - filters (Size, Status, and a multi-select
  Pet type filter, since a cage can support more than one pet type), sort
  (by label or by size), a search matcher, and two "group by" choices
  (Status, Size - not Pet type, since a cage can belong to more than one
  group at once, which a board column can't represent).
- `AdminCagesPage.tsx` - added the search/filter/sort bar, a Table / List /
  Board view switcher, and a "Group by" dropdown that appears only in Board
  view. The existing "Add cage" form and the existing inline-edit-a-row
  behavior (click Edit on a row to turn its cells into input boxes) were
  kept exactly as they were - editing now also works the same way in List
  and Board view, not just Table view.

**`client/src/features/maintenance/pages/AdminPetTypesPage/`** (Settings >
Config > Pet Types):
- `petTypeBrowserFields.ts` (new) - a Status (Active/Inactive) filter, sort
  by Name or Key, and a group-by-Status axis.
- `AdminPetTypesPage.tsx` - the "Existing pet types" list gained the full
  search/filter/sort/Table-List-Board treatment (default view: Table, no
  filter applied by default so both active and inactive types still show,
  matching the old behavior). The separate "Fixed price overrides" list
  below it - which only ever lists *active* pet types, scoped to one branch
  at a time - keeps its own existing branch selector and per-row price
  inputs unchanged, but gained its own plain search box (a lighter, partial
  treatment: search only, no sort/filter/views, since it isn't really a
  "browse pet types" list in its own right).

**`client/src/features/maintenance/pages/AdminBreedsPage/`** (Settings >
Config > Breed Management):
- `breedBrowserFields.ts` (new) - a Pet type filter (built from the live
  pet-types list), sort by Name, and a group-by-Pet-type axis (its columns
  also come from the live pet-types list, so a newly added pet type gets
  its own board column immediately).
- `AdminBreedsPage.tsx` - per the Ideas backlog ("the entire breed list to
  be combined into one... table, list and board view options"), the old
  layout (one "X breeds" section per pet type) is now a single combined
  browser. Board view, grouped by Pet type, reproduces the old per-section
  look; Table/List show every breed flat with a Pet type badge, and the
  Filter pill narrows to one pet type. Add/Rename/Delete are unchanged.

**`client/src/features/discounts/pages/AdminDiscountManagementPage/`**
(Settings > Config > Discounts):
- `discountBrowserFields.ts` (new) - Branch/Scope/Status filters (replacing
  the page's old bespoke `DiscountFilterBar` dropdowns), sort by Name or
  Value, and a group-by-Type axis (Government-Mandated vs. Custom).
- `AdminDiscountManagementPage.tsx` - per the Ideas backlog ("government
  mandated and custom discounts combined into one list... search, sort,
  filter, group by, view options"), the old two-section layout
  (Government-Mandated / Custom Discounts, each its own `<ul>`) is now one
  combined browser; Board view grouped by Type reproduces the old sections.
  **Default view is deliberately List, not Table** - an earlier feature
  (#85) specifically chose a list layout over table rows/cards for this
  page, and that choice is preserved; Table and Board are now available as
  opt-in alternatives via the view switcher, not a replacement for it. No
  Active/Inactive badge was added anywhere (an existing, deliberate design
  choice - Branch Availability is the only control, and status is purely
  derived from it, not a thing to directly toggle) - the Status filter
  still works, it's just not shown as a per-row badge. The create/edit
  modal, Branch Availability modal, and "View archive" link are unchanged.
  One now-orphaned file was left in place rather than deleted: the old
  `DiscountFilterBar` component (`client/src/features/discounts/components/DiscountFilterBar/`)
  is no longer used by this page and nothing else references it - worth a
  follow-up cleanup, not done in this session to stay within scope.

**`client/src/features/maintenance/pages/AdminPromoConfigPage/`** (Settings
> Config > Promos) - a lighter treatment, by design:
- `promoBrowserFields.ts` (new) - Branch/Timing/Status filters (replacing
  the old bespoke `PromoFilterBar`), sort by Name or Value.
- `AdminPromoConfigPage.tsx` - swapped `PromoFilterBar` for `FilterSortBar`.
  **Deliberately kept the existing `PromoCard` grid, with no Table/List/
  Board view switcher** - the Ideas backlog's explicit "table, list, board"
  ask was for the Coupon Spin Wheel reward pool specifically (see below),
  not this page; `PromoCard` is a rich, bespoke component (date-range vs.
  weekly-recurring display, branch chips, an active toggle) that would lose
  real information if flattened into table columns for a request nobody
  made. The page still defaults to "Status: Active" pre-filtered, matching
  its behavior before this change. Same now-orphaned-file note as Discounts:
  `client/src/features/maintenance/components/PromoFilterBar/` is no longer
  used anywhere.

**`client/src/features/rewards/pages/AdminSpinWheelConfigPage/`** (Settings
> Config > Coupon Spin Wheel) - the reward pool, full treatment (this is the
page the Ideas backlog named explicitly: "Add search, sort, filter, group
by, view options (table, list, kanban) to the reward pool"):
- `rewardBrowserFields.ts` (new) - Status and Discount-type filters, sort by
  Label/Value/Rarity, and two group-by axes (Status, Discount type).
- `AdminSpinWheelConfigPage.tsx` - the reward pool list gained the full
  search/filter/sort/Table-List-Board treatment. The Thresholds & pity form
  and the Add-a-reward form are unchanged (still inline, not a modal - the
  backlog's modal-conversion ask for this form is a separate, not-done
  item, same as everywhere else this session).

**`client/src/features/catalog/components/CatalogAdminPage/`** (the shared
component behind Settings > Config > Product Catalog - `ProductCatalogPage`
is the only current consumer):
- `catalogBrowserFields.ts` (new) - Category and Service-scope filter
  options are derived from whichever values are actually present in the
  loaded items (category/service_scope are free text, not a fixed enum -
  see the component's own "documented, not enforced" note), plus a Status
  filter; sort by Name or Price; group-by Category or Status.
- `CatalogAdminPage.tsx` - full search/filter/sort/Table-List-Board
  treatment, replacing its old `SearchSortBar` + `ActiveFilterChips` pair.
  Since this is a shared component, any other page that starts using it
  later (there's currently only one) gets this for free.

**Settings > Config > Services and Packages** (one page,
`AdminServicesAndPackagesPage.tsx`, tabbing between three large
sub-pages - the tab shell itself is untouched, only its three children
changed):

- **`client/src/features/maintenance/pages/AdminServicesPage/`** -
  `serviceBrowserFields.ts` (new): Category, Branch, and Status filters
  (Status pre-added and defaulting to Active, matching the page's old
  default), sort by Name, group-by Category or Status. The row's several
  conditional badges (assessment requirement, pricing-matrix flag, free-
  package-after-N-nights, Daycare's hourly fees) are unchanged content,
  now rendered through a shared `renderServiceBadges` helper so Table's
  "Details" column and the List/Board card show the same information. The
  big create/edit modal form (icon picker, image uploader, Daycare/Hotel/
  Grooming-specific fields, the pricing matrix preview) is untouched.
- **`client/src/features/maintenance/pages/AdminServiceTypesPage/`** -
  `serviceTypeBrowserFields.ts` (new): a Branch filter, sort by Name,
  group-by Staff-picker-enabled or Cage-picker-enabled. The create/edit
  modals (name, staff/cage picker toggles, eligible staff roles, icon,
  image, branch multi-select) are untouched.
- **`client/src/features/maintenance/pages/AdminPackageBuilderPage/`** -
  `packageBrowserFields.ts` (new): Branch and Status filters (Status
  pre-added, defaulting to Active - inactive packages still stay visible
  by default like before, since the Archive action only appears once a
  package is already inactive), sort by Name or Price, group-by Status or
  Pricing (flat vs. varies-by-weight/coat). **Not** offered as a group-by
  axis: Branch - a package can be available at more than one branch at
  once, and a board column can only hold one grouping value per item (same
  reasoning as Cages' `pet_types`). The package **builder form itself**
  (its own internal service picker with a search/sort/service-type filter
  for choosing which services go into the bundle, the live pricing
  preview, the bundle-discount-%, the pricing matrix) is **deliberately
  untouched** - it's a selection widget for building one package, not a
  "browse packages" list in its own right, and touching its already-
  intricate pricing-derivation logic wasn't worth the risk for no real
  gain.

### Batch B - customer-facing pages

**`client/src/features/customers/pages/CustomerPetManagerPage/`**
(`/portal/pets`, "Pet Manager"):
- `petBrowserFields.ts` (new) - Pet type options derived from the viewer's
  own pets (free text, admin-managed), a fixed Weight class filter (S/M/L/
  XL), an Assessment filter (Assessed/Not yet assessed), sort by Name,
  group-by Pet type or Assessment.
- `CustomerPetManagerPage.tsx` - Table/List views are new lean rows (a
  `Link` to the pet's profile, same route the old card used); **Board view
  reuses the existing `PetCard` component directly** (photo, weight/coat
  badges, "last assessed" - it was already a well-designed, self-contained,
  bordered, linked card, so Board just drops it into each column instead of
  reinventing it). The "Add a pet" form is unchanged.

**`client/src/features/catalog/pages/CustomerFoodMedicationPage/`**
(`/portal/food-medication`, "My Food & Medication Types"):
- `customerCatalogBrowserFields.ts` (new) - a Category filter (Food/
  Medication), sort by Name, group-by Category.
- `CustomerFoodMedicationPage.tsx` - per the Ideas backlog ("combine the
  food items and medications into one list/table... move the Rename and
  Remove options to a '...' button"), the old two-section (Food /
  Medication) layout is now one combined browser, and each row's always-
  visible Rename/Remove buttons moved to a `MoreOptionsMenu` "..." button,
  matching every other list in this rollout. Board view grouped by
  Category reproduces the old two sections. The "Add a new type" form stays
  at the bottom, inline (not moved to the top or converted to a modal -
  those are separate, undone asks from the same backlog entry).

**`client/src/features/rewards/pages/CustomerRewardsPage/`**
(`/portal/rewards`, "My Rewards"):
- `couponBrowserFields.ts` (new) - a Status filter (Available/Used,
  defaulting to Available), sort by Obtained date, Expiry (soonest/latest -
  coupons with no expiry always sort last, regardless of direction), or
  Value; one group-by axis (Status). The Ideas backlog asked for a default
  group-by "type" (e.g. time-limited promo, spin-the-wheel reward) - every
  coupon this app can currently produce comes from the spin wheel, so
  Status is the only grouping with real signal today; the multi-source
  design is left for whenever a second coupon source exists.
- `CustomerRewardsPage.tsx` - the spin wheel and spin-count display are
  unchanged. The old two-section "My Coupons" / "Used coupons" lists are
  now one combined browser. Each coupon now also shows its linked
  `SpinWheelReward`'s label (resolved by `spin_wheel_reward_id`, falls back
  to "—" if the reward was since deleted), when it was obtained, and
  its expiry - covering the backlog's "see the details of when I obtained
  it... its rarity" ask (rarity itself isn't shown per-coupon since a
  coupon is a fixed already-won prize, not a still-random draw, but it's
  visible via the linked reward's own admin page).

### Batch C - booking-process pickers (lighter treatment, by design)

Both items here are single-selection widgets embedded in one booking
session, not persistent "browse my records" pages - so unlike every page
above, neither got the full filter-pill/sort/group-by/view-switcher stack.
Both got **search only**, matching the "you may still implement some of the
features but not all of them" allowance given for this rollout.

- **`client/src/features/booking/pages/CustomerBookingFlowPage/`** (the
  services/packages selection step, inside the ~4,300-line booking wizard):
  a plain search box now sits above the option grid (only shown once there's
  more than one service or package to choose from), filtering
  `servicesForCategory`/`packagesForCategory` by name before they're
  rendered. Nothing else in this enormous, business-critical file was
  touched - not the selection state (`toggleServiceSelect`/
  `togglePackageSelect`), not pricing, not the Package-tab visibility check
  (which still reads the *unfiltered* list, so the tab doesn't disappear
  just because a search hides every result).
- **`client/src/features/booking/components/CagePickerList/`**: a search
  box now appears once there are more than 3 options (that's "No
  preference" plus more than 2 real cages), filtering by cage label. "No
  preference"
  always stays visible regardless of the search text - it isn't a cage, so
  it shouldn't be searchable-away. Selection, the size-lock (Staff only)
  logic, and the recommended-size badge are all unchanged. (The backlog
  itself offered "or perhaps just add it to the Cages page instead" as an
  alternative to changing this booking-flow widget - that page,
  `AdminCagesPage`, already got the full treatment in Batch A.)

### DataCalendar - built, and proven on Monthly Schedule (behavior-preserving refactor)

**`client/src/features/staff/pages/MonthlySchedulePage/`** (Settings-area
Admin/Supervisor/Superadmin **Monthly Schedule** page) - this page's
existing **Calendar** view (one of its two existing view modes, the other
being **Grid**) now renders through the new shared `DataCalendar` instead
of its own hand-written month-grid markup:

- The page's own month/year state and its **← Month Year →** navigation
  buttons in the toolbar are unchanged and still control both Calendar and
  Grid view together (`DataCalendar` is told `showNav={false}` here, since
  building its own second set of nav buttons next to the page's existing
  ones would be redundant).
- Every schedule entry still renders as the same colored chip (Rest Day /
  Vacation Leave / Sick Leave / Other), in the same day cell, clicking it
  still opens the same detail panel, and the small "+" button on a day
  still opens the same "Add schedule entry" panel for that date - all of
  that is now `DataCalendar`'s job, driven by the page's existing data,
  not new behavior.
- The page's **Grid** view (the staff x date table) was not touched - it's
  a fundamentally different, page-specific layout (rows are staff members,
  not weeks), not something `DataCalendar` is meant to cover.
- This page had no test file before this session; it has one now
  (`MonthlySchedulePage.spec.ts`), added specifically to lock in that the
  refactor didn't change behavior.
- Week view exists in `DataCalendar` itself (with its own passing tests)
  but nothing in this app uses it yet - Monthly Schedule only ever offered
  Month/Grid, and the plan's first *real* week-view consumer is the
  Activity Log page in Tier 2, not yet started.

### Tier 2 - partial treatment (search + filter + sort, no Board/group-by)

Six pages, each given **search, filter pills, and sort** via `FilterSortBar`
(and, for two of them, a Table/List/Calendar view choice), but deliberately
**no Board view and no group-by** - these are staff directories, financial
lookups, and read-only logs, not multi-axis collections a Kanban board
would help with.

- **`client/src/features/staff/pages/StaffManagementPage/`** (Settings >
  Staff Management) - `staffBrowserFields.ts` (new): Role filter, and a
  Branch filter that's only offered to a Superadmin viewer (an Admin is
  already branch-scoped) - same gating the page's old plain dropdown used.
  Sort by Name. A search box (name/username/email) is genuinely new - the
  page never had one before. The existing card grid (`StaffCard` + its
  "Set day(s) off"/"Manage account" expandable forms per card) is
  unchanged; only the old two plain `<select>` filters were replaced.
- **`client/src/features/staff/pages/CustomerManagementPage/`** (Settings >
  Customer Management) - `customerBrowserFields.ts` (new): a Status filter
  (Active/Inactive, not applied by default - matches the old behavior of
  always showing every customer), sort by Name, and a new search box
  (name/email). The old plain `<ul>` became `DataList`; each customer's
  "..." action menu (Check Profile/View Pets/Add Pet/Deactivate/Archive)
  and its expandable detail panels are unchanged.
- **`client/src/features/credits/components/CreditHistoryTable/`** (used
  inside Settings > Credit Management, once a customer's branch balance is
  expanded) - `creditHistoryFields.ts` (new): a Type filter (Issued/
  Redeemed/Expired), sort by Date or Amount. This is the one place in this
  page that's a genuine "browse many records" list (a customer can
  accumulate an unbounded transaction history) - `CreditManagementPage`
  itself was deliberately **left untouched**: its own per-branch balance
  card list is at most a handful of cards (one per branch), not something
  that needs search/filter/sort in its own right, matching the same
  judgment call made for Promos/Package Builder in Batch A.
- **`client/src/features/veterinary/pages/VetCatalogPage/`** ("My
  Medication & Procedure Catalog", personal to each Veterinarian) -
  `vetCatalogBrowserFields.ts` (new): the Medications tab keeps search +
  sort by Name (no filterable field exists there); the Procedures tab adds
  a Type filter (Lab test/Dental/Vaccination/Surgery/Emergency/Wellness
  Exam) alongside its own search + sort by Description. Replaces the old
  `SearchSortBar` + plain `<select>` pair with `FilterSortBar`; both tabs'
  `<ul>` became `DataList`. Add/Edit/Delete via the modal form and "..."
  menu are unchanged. This page had no test coverage before this session.
- **`client/src/features/veterinary/pages/MyPatientsPage/`** ("My
  Patients", personal roster) - `myPatientsBrowserFields.ts` (new): a Pet
  Type filter (options come from the live, admin-managed pet-types list,
  not a hardcoded Dog/Cat pair), sort by Last visit or Pet name, and a
  search box (pet or owner name). Replaces the old `SearchSortBar` + plain
  `<select>` pair. The two-pane queue/detail layout, and clicking a
  patient's "..." menu to load their consultation history on the right,
  are unchanged - the one visible difference is *how* the selected patient
  is highlighted in the queue: it used to recolor the whole row's border,
  now it's an accent-tinted left border on the row's text block, because
  the shared `DataList` component (used here for consistency with every
  other migrated page) doesn't expose a way to recolor its own per-item
  wrapper. This page had no test coverage before this session.
- **`client/src/features/hotel/pages/ActivityLogPage/`** (Hotel/Daycare
  activity logbook, read-only) - `activityLogBrowserFields.ts` (new): an
  Action filter (Check-in/Check-out/Task started/completed/reopened/
  missed), a Date filter (reusing the same date-range preset system as
  `QueueFilterBar` - Today/Tomorrow/This week/This month/Custom/All dates
  - **now a removable pill** instead of the old always-on control; removing
  it lifts the date bound entirely, which is safe because the server
  already caps an unbounded query at its 200-most-recent-entries default),
  sort by Date, and a new search box (description/actor name). Replaces
  `QueueFilterBar` + `ActiveFilterChips` with `FilterSortBar`. Gained a
  **List / Calendar** view switcher (no Table/Board - a flat description
  string doesn't need columns, and there's no natural grouping) - this is
  `DataCalendar`'s first real consumer besides Monthly Schedule, and its
  month grid shows each day's log entries as small colored chips (same
  action colors as the List view's badges).

- **`client/src/features/booking/components/StaffPickerList/`** (the
  booking flow's staff-picker step, both customer and staff surfaces) -
  already had its own plain search box + sort `<select>`; swapped that
  pair for `FilterSortBar` (search + a Sort pill: Name A-Z/Z-A). No filter
  fields - there's nothing categorical to filter this single-choice picker
  by. "No preference" still always pins first regardless of search/sort,
  the auto-select-on-load and cart-capacity-disables-a-staff-member
  behaviors are unchanged.

### Tier 3 - chip-styling-only pass on the live operational queues

Deliberately the lightest touch in this whole rollout, per the plan: these
are shift-critical, real-time staff workflow tools (check-in buttons, live
care logs), not "browse my records" pages - no search/filter/sort model
change, no group-by, no view switcher, no board, no calendar. The *only*
ask was to make their existing filter chips look and behave like every
other pill in the app (hover-to-reveal "X", not an always-visible one).

- **`client/src/shared/components/ActiveFilterChips/ActiveFilterChips.tsx`**
  (+ its `.module.css`) - this one shared component is what every queue
  page's "Date: This week ✕" / "Status: Pending ✕"-style chip row is built
  from, so restyling it once re-skins every consumer at the same time,
  rather than editing eight separate pages by hand. The chip's clear "X"
  icon now starts invisible (`opacity: 0`) and only appears on hover or
  keyboard focus (`opacity: 1`), matching `FilterTile`'s exact hover-reveal
  convention used everywhere else in this rollout - touch devices still
  always show it (no hover state to reveal it on). Nothing else changed:
  each chip is still one button (click anywhere on it to clear that
  filter) - there's no popover editor here, unlike a full `FilterTile`,
  because editing already happens through each page's own
  `QueueFilterBar` date/status dropdowns elsewhere on the page. This was
  a pure CSS/visual change with no behavior change.
- This single edit reaches every named Tier 3 page at once: **Bookings
  Queue** (`ReceptionistBookingsQueuePage`), **Grooming Queue**
  (`GroomerDashboardPage`), **Daycare Queue** (`DaycareQueuePage`),
  **Veterinary Console** (`VeterinaryConsolePage`), **Assessment Queue**
  (`AssessmentQueuePage`), and **Boarding Checklist Kanban**
  (`BoardingChecklistKanban` - its board itself is untouched, exactly as
  planned). **Hotel Queue** (`HotelQueuePage`) doesn't render chips
  itself, but its two constituent pickers (`HotelBookingPicker`,
  `HotelStayPicker`) already use the same shared component, so it's
  covered too. A few other, not-explicitly-named consumers of the same
  shared component (the Groomer/Receptionist dashboard queue widgets,
  `UnavailabilityApprovalQueuePage`) got the same visual refresh as a
  natural side effect of editing a shared piece once - harmless, since
  it's purely cosmetic and makes the app more consistent, not less.
- **`CreditReviewQueuePage`** (Credit Review Queue) - checked and found to
  have **no filter/chip UI at all** today (just a plain action-card grid,
  no search/filter/sort of any kind) - there's nothing to re-skin here, so
  nothing was changed. Noted so it's clear this wasn't skipped by mistake.

## Manual test - step by step

Assumes you don't know your way around this app yet. Both dev servers need
to already be running (client on port 5173, server on port 3000) - if
you're not sure, use the `dev-servers` check before starting, rather than
launching a second copy.

### A. Deleted Records archive (lowest-risk change)

1. Open your browser to `http://localhost:5173`.
2. Click **Staff Login** (top-right corner). Log in as
   `makati.admin1@goldenfur.com`, password `password123`, click **Sign in**.
   - Admin accounts require a second step (MFA - a 6-digit code from an
     authenticator app). If this account hasn't been set up yet in your
     local environment, follow the on-screen "scan this QR code" steps once
     with any authenticator app (e.g. Google Authenticator); after that,
     logging in again only asks for the 6-digit code it shows you.
3. Once logged in, go to `http://localhost:5173/staff/admin/archive?tab=deleted-records`
   directly, or navigate: **Settings** (sidebar) > **Config** > find and
   click the **Archive** tile > click the **Deleted Records** tab at the
   top of that page.
4. You should see a row of controls: a search box, a **Filter** button, a
   **Sort** button - no plain dropdowns like before.
5. Click **Filter**. A small menu opens listing **Table** and **Deleted**.
   Click **Table**. A rounded pill appears reading something like
   "Table: bookings" (whichever table sorts first alphabetically).
6. Click the pill's text (not its X). A small popover opens listing every
   table name. Pick a different one, e.g. `pets` - the pill's text updates,
   and the list below re-loads to only that table's deleted rows.
7. Hover over the pill - an "X" appears on its right edge. Click it - the
   pill disappears and the list goes back to showing every table.
8. Click **Sort**, then **Deleted at · Oldest first** - a "Sort: Deleted at
   (Oldest first)" pill appears, and the oldest deleted row now shows first.
9. Type something into the search box - the list narrows to matching rows
   as you type.
10. Confirm **View details**, **Restore**, and **Delete permanently** on a
    row still work exactly as before (these weren't touched).

### B. Cages (full Table / List / Board example)

1. Still logged in as an Admin, go to
   `http://localhost:5173/staff/admin/hotel/cages`, or navigate: **Settings**
   > **Config** > **Cages** tile.
2. You should see the existing **Add cage** form unchanged at the top, then
   below it a search box, **Filter**, **Sort**, and - new - a small
   **Table / List / Board** switcher on the right.
3. With at least one cage already listed (add one via the form if the list
   is empty: type a label, pick a size, check at least one pet type, click
   **Add cage**):
   - Click **Filter** > **Size**. A pill appears, e.g. "Size: Small". Only
     cages of that size remain visible. Click the pill and pick a different
     size to confirm it updates live; remove it via its hover "X".
   - Click **Filter** > **Pet type**. Its popover is a checkbox list (not a
     single-choice list) - check one or more pet types; the pill's text
     lists all of them, and any cage supporting *any* checked type stays
     visible.
   - Click **Sort** > **Size · Small to large** - the list reorders.
   - Type a cage label fragment into the search box - the list narrows.
4. Click **List** in the view switcher - the same cages now render as
   stacked cards instead of a table, with all the same info and buttons.
5. Click **Board** - a **Group by** dropdown appears next to the switcher,
   defaulted to **Status**. You should see one column per cage status
   (Available, Occupied, Reserved, Under Maintenance), each cage's card
   under its own status column. Change **Group by** to **Size** - the same
   cages now regroup into S/M/L/XL columns instead.
6. Click **Table** to go back. Click **Edit** on any cage's row - its Cage,
   Size, and Pet types cells turn into editable inputs, with **Save** /
   **Cancel** in place of the usual action buttons. Change the label, click
   **Save** - confirm it updates. Repeat once in **List** view to confirm
   editing looks and works the same way there too.
7. Confirm **Mark Under Maintenance** / **Mark Available** and **Delete**
   (disabled for an Occupied or Reserved cage) still behave as before.

### C. Pet Types (two lists, one full treatment + one lighter)

1. Go to `http://localhost:5173/staff/admin/maintenance/pet-types`, or
   navigate: **Settings** > **Config** > **Pet Types** tile.
2. In the **Existing pet types** panel (below the **Add pet type** form),
   confirm both active and inactive pet types show by default (no filter
   applied), each with an **Active**/**Inactive** badge.
3. Click **Filter** > **Status** - the pill defaults to "Status: Active",
   and inactive pet types disappear. Remove the pill (hover, click its "X")
   to see them again.
4. Click **Sort** > **Key · A to Z** - the list reorders by the internal
   key instead of the display name.
5. Try **Table**, **List**, and **Board** (grouped by Status - one column
   for Active, one for Inactive) in the view switcher.
6. Confirm **Rename**, **Activate**/**Deactivate**, and **Delete** still
   work exactly as before.
7. Scroll to the separate **Fixed price overrides** panel below. Confirm it
   still only lists *active* pet types, still has its own **Branch**
   selector, and now also has its own **Search** box - type into it and
   confirm it narrows that list only (the panel above it is unaffected).
   Confirm **Save**/**Clear** on a price still work.

### D. Breeds (combined list, replacing one-section-per-pet-type)

1. Go to `http://localhost:5173/staff/admin/maintenance/breeds`, or
   navigate: **Settings** > **Config** > **Breed Management** tile.
2. Confirm there's now one combined list (no more separate "Dog breeds" /
   "Cat breeds" headings) - every breed shows with a Pet type badge next to
   its name.
3. Click **Filter** > **Pet type** - the pill defaults to the first pet
   type; only that pet type's breeds remain visible.
4. Click **Board** in the view switcher - one column per pet type
   (reproducing the old per-section layout), no Group by dropdown needed
   since there's only one grouping choice here.
5. Confirm **Rename** and **Delete** (including the "still assigned to a
   pet" error case) still work in every view.

### E. Discounts (combined list, default view stays List)

1. Go to `http://localhost:5173/staff/admin/discounts`, or navigate:
   **Settings** > **Config** > **Discounts** tile.
2. Confirm the page loads in **List** view by default (not Table) - this
   page deliberately kept its list layout from an earlier feature. You
   should see every discount (mandated and custom) in one combined list,
   each with a "Government-Mandated" or "Custom" badge - no more separate
   "Government-Mandated" / "Custom Discounts" section headings.
3. Confirm there's still no Active/Inactive badge or toggle shown directly
   on a row - only the "..." menu's **Branch Availability** controls that.
4. Click **Filter** > **Scope** - defaults to "Scope: Service"; click the
   pill and pick **Category** from its popover - the list narrows to
   category-scoped discounts only.
5. Click **Filter** > **Branch**, and separately try the **Status** filter
   (Active/Inactive) - confirm each narrows the list correctly.
6. Type into the search box - narrows by name.
7. Try **Table** and **Board** (grouped by Type: Government-Mandated /
   Custom) in the view switcher, then switch back to **List**.
8. Confirm **New custom discount**, **Configure**, **Branch Availability**,
   and **Archive** (only offered for an inactive custom discount) all still
   work exactly as before, and the **View archive** link still goes to the
   Discounts tab of the Archive page.

### F. Promos (lighter treatment - filter/sort only, cards unchanged)

1. Go to `http://localhost:5173/staff/admin/maintenance/promos`, or
   navigate: **Settings** > **Config** > **Promos** tile.
2. Confirm promos still render as the existing rounded cards (unchanged),
   and there's no Table/List/Board switcher on this page (by design - see
   "What changed" above).
3. Confirm the page loads with a "Status: Active" pill already present
   (same as before this change) - only active promos show. Click the pill
   and switch it to Inactive to see deactivated promos instead.
4. Click **Filter** > **Branch**, and separately **Filter** > **Timing**
   (Upcoming/Active now/Ended) - confirm each narrows the card grid.
5. Type into the search box - narrows by name.
6. Confirm **New promo**, the promo builder wizard, **Manage Branches**,
   and **Archive** on a card all still work exactly as before, and the
   **View archive** link still works.
7. Scroll to **Promo Cap Configuration** below - confirm it's unchanged
   (its own search/sort/cap-type filter, unrelated to this session's work).

### G. Coupon Spin Wheel reward pool (full treatment)

1. Go to `http://localhost:5173/staff/admin/spin-wheel-config`, or
   navigate: **Settings** > **Config** > **Coupon Spin Wheel** tile.
2. Confirm **Thresholds & pity** (the settings form at the top) is
   unchanged.
3. Below it, in **Reward pool**, confirm the rarity-sum note is unchanged,
   then confirm you see the new search box, **Filter**, **Sort**, and a
   **Table / List / Board** switcher above the reward list (default: Table).
4. Click **Filter** > **Status** or **Discount type** - confirm each
   narrows the list. Type into the search box - narrows by label.
5. Click **Sort** > **Rarity · High to low** - confirm it reorders.
6. Click **Board** - a **Group by** dropdown appears, defaulted to
   **Status** (Active/Inactive columns); switch it to **Discount type**
   (Percentage/Flat columns) and confirm rewards regroup.
7. Confirm **Activate**/**Deactivate** and **Archive** still work in every
   view, and the **Add a reward** form below is unchanged (still inline,
   not a modal).

### H. Product Catalog (shared component, full treatment)

1. Go to `http://localhost:5173/staff/admin/product-catalog`, or navigate:
   **Settings** > **Config** > **Product Catalog** tile.
2. Confirm the **Add product** form is unchanged, then confirm the list
   below it now has a search box, **Filter**, **Sort**, and a
   **Table / List / Board** switcher.
3. Click **Filter** > **Category** - its options come from whatever
   categories actually exist in the current product list (not a fixed
   list) - confirm picking one narrows correctly. Do the same for
   **Service scope** and **Status**.
4. Click **Sort** > **Price · Low to high** - confirm it reorders. Type
   into the search box - narrows by name or category.
5. Click **Board** - a **Group by** dropdown appears (Category or Status);
   confirm both groupings work.
6. Confirm **Edit** (inline, turns the row into input boxes), **Deactivate**/
   **Activate**, and **Archive** (only for an inactive item) still work in
   every view, and the **View archive** link still works.

### I. Services and Packages (one page, three tabs)

Go to `http://localhost:5173/staff/admin/maintenance/services-and-packages`,
or navigate: **Settings** > **Config** > **Services and Packages** tile.
The three tabs at the top (**Services**, **Service Types**, **Packages**)
are unchanged - each tab below is now independently Notion-style.

**Services tab:**

1. Confirm search box, **Filter**, **Sort**, and a **Table / List / Board**
   switcher above the list. A "Status: Active" pill is present by default
   (inactive services are hidden until you remove or change that pill).
2. Click **Filter** > **Category** or **Branch** - confirm each narrows
   correctly. Click **Sort** > **Name · A to Z**/**Z to A**.
3. Click **Board** - a **Group by** dropdown appears (Category or Status).
4. Confirm **New service** still opens the same big modal form (category-
   specific fields, pricing matrix preview, icon/image, branch multi-
   select), and each row's "..." menu still offers **Configure** and
   **Branch Availability**, working the same in every view.

**Service Types tab:**

1. Confirm search box, **Filter** (Branch only), **Sort**, and the view
   switcher. No default filter pill this time - all service types show.
2. Click **Board** - **Group by** defaults to **Staff picker** (Enabled/
   Disabled columns); switch to **Cage picker** and confirm it regroups.
3. Confirm **New service type**'s modal, and each row's "..." menu
   (**Configure**, **Branch Availability**) still work in every view.

**Packages tab:**

1. Confirm search box, **Filter** (Branch, Status), **Sort** (Name, Price),
   and the view switcher. A "Status: Active" pill is present by default,
   same as Services - inactive packages still show unless you leave that
   pill in place with its default value (this page always kept inactive
   packages visible by default before this change too, since Archive only
   ever shows up on an inactive package).
2. Click **Board** - **Group by** defaults to **Status**; switch to
   **Pricing** (Varies by weight/coat vs. Flat price) and confirm it
   regroups. There is deliberately no "group by Branch" option (a package
   can be available at more than one branch at once).
3. Confirm **New package** still opens the full builder (branch multi-
   select unlocking a searchable/sortable/filterable service picker inside
   the modal, the live price preview, the bundle-discount field, the
   pricing-matrix toggle) completely unchanged - only the outer package
   list gained the new controls, not the builder's own internals.
4. Confirm each row's "..." menu (**Configure**, **Branch Availability**,
   **Archive** once inactive) still works in every view.

### J. My Pets (customer portal)

1. Log out of staff, log in as a customer instead (or go straight to
   `http://localhost:5173/portal/pets` if already logged in as one).
2. Confirm search box, **Filter** (Pet type, Weight class, Assessment), and
   the **Table / List / Board** switcher above your pets.
3. Click **Table** - each pet's name is a link to its profile page.
4. Click **Board** - a **Group by** dropdown appears, defaulted to
   **Pet type**; try **Assessment** too (Assessed/Not yet assessed
   columns). Confirm each card here looks exactly like the pet card you
   remember (photo, weight/coat badges, last-assessed text) and is still
   clickable through to the pet's profile.
5. Confirm **Add a pet** still works the same as before.

### K. My Food & Medication Types (customer portal)

1. Go to `http://localhost:5173/portal/food-medication`.
2. Confirm there's now one combined table (no more separate "Food" /
   "Medication" sections) with search, **Filter** (Category), **Sort**,
   and the view switcher.
3. Click a row's "..." button - confirm **Rename** and **Remove** now live
   there instead of as always-visible text links.
4. Click **Board** - one column for Food, one for Medication.
5. Confirm **Add a new type** at the bottom still works the same as
   before.

### L. My Rewards (customer portal)

1. Go to `http://localhost:5173/portal/rewards`.
2. Confirm the spin wheel and spin-count display are unchanged.
3. Under **My Coupons**, confirm there's one combined list/table (no more
   separate "My Coupons" / "Used coupons" sections), each row showing the
   discount, the reward name it came from, when you obtained it, and its
   expiry (or "No expiry").
4. Confirm a "Status: Available" pill is present by default; remove it (or
   switch it to Used) to see redeemed coupons too.
5. Try **Sort** > **Expiry · Soonest first**, and **Board** view (grouped
   by Status - Available/Used columns).

### M. Booking flow - services/packages step and cage selector (light, search-only)

1. Start a new booking (customer or receptionist), pick a branch, pet, and
   a service type with several services (e.g. Grooming).
2. On the services step, confirm a plain search box appears above the
   service cards (only if there's more than one to choose from) - type
   part of a service name and confirm the grid narrows. Clear it and
   confirm everything comes back. Confirm selecting a service still works
   exactly as before, and the running total/duration are unaffected.
3. If the service type offers Packages too, switch to that tab and repeat
   with the search box there (it relabels to "Search packages...").
4. Continue to a Hotel-type booking with Cage Picker enabled (as a
   receptionist, so cage selection is available) - once there are more
   than a couple of cages, confirm a "Search cages..." box appears above
   the cage grid, narrows it by label, and that "No preference" never
   disappears regardless of what you type. Confirm picking a cage still
   works exactly as before.

### N. Monthly Schedule - Calendar view now runs on DataCalendar (no visible change)

1. Log in as an Admin/Supervisor/Superadmin, go to
   `http://localhost:5173/staff/monthly-schedule`, or navigate: sidebar
   **Monthly Schedule**.
2. Confirm the page looks exactly as before: the same month/year label and
   **←**/**→** buttons in the toolbar, the same **Calendar**/**Grid**
   toggle, and (if a Superadmin) the same Branch selector.
3. In **Calendar** view, confirm existing schedule entries still show as
   colored chips on the correct day, clicking a chip still opens the same
   detail panel (with **Remove**), and hovering a day still reveals a "+"
   button that opens the same "Add schedule entry" panel for that date -
   confirm adding a Rest Day/Vacation/Sick Leave/Other entry there still
   works and the new chip appears.
4. Click **→** to go to next month - confirm the calendar reloads for that
   month (same as before).
5. Switch to **Grid** view - confirm the staff x date table still works
   exactly as before (this view wasn't touched).

### O. Staff Management (Tier 2)

1. Log in as an Admin or Superadmin, go to
   `http://localhost:5173/staff/admin/staff`, or navigate: **Staff
   Management** (sidebar).
2. Confirm the "Create staff account" form and the staff card grid below it
   look unchanged, but the two old dropdowns are gone - replaced by a
   search box, **Filter**, and **Sort**.
3. Type a staff member's name, username, or email fragment into the search
   box - confirm the grid narrows.
4. Click **Filter** > **Role** - confirm the grid narrows to that role;
   remove the pill (hover, click its "X") to see everyone again.
5. If you're a Superadmin, confirm **Filter** also offers **Branch**; if
   you're an Admin, confirm it does not.
6. Confirm **Set day(s) off** and **Manage account** on any card still open
   their forms and work exactly as before.

### P. Customer Management (Tier 2)

1. Still as Admin/Superadmin/Supervisor/Receptionist, go to
   `http://localhost:5173/staff/admin/customers`, or navigate: **Customer
   Management**.
2. Confirm the "New walk-in customer" form is unchanged, then confirm the
   list below it now has a search box, **Filter**, and **Sort** above it.
3. Type a customer's name or email fragment into the search box - confirm
   the list narrows.
4. Click **Filter** > **Status** - defaults to "Status: Active"; confirm
   inactive customers disappear, then switch the pill to Inactive to see
   only deactivated ones.
5. Confirm each customer's "..." menu (**Check Profile**, **View Pets**,
   **Add Pet**, **Deactivate/Reactivate**, **Archive**) still works exactly
   as before, including the expandable panels underneath a row.

### Q. Credit Management - Credit History (Tier 2)

1. As a Cashier, Admin, or Superadmin, go to
   `http://localhost:5173/staff/admin/credits`, or navigate: **Credit
   Management**.
2. Search for a customer with at least a couple of credit transactions,
   select them, then click **View history** under one of their branch
   balance cards.
3. Confirm the history table now has a search-less **Filter**/**Sort** bar
   above it (this table has no free-text search, just Type and Date/Amount
   sort). Click **Filter** > **Type** - confirm it narrows to Issued (the
   default once added); try Redeemed/Expired too via the pill's popover.
4. Click **Sort** > **Amount · High to low** - confirm it reorders.
5. Confirm the balance summary and expiry text above the table are
   unaffected - only the transaction table itself changed.

### R. Vet Catalog (Tier 2)

1. Log in as a Veterinarian, go to
   `http://localhost:5173/staff/vet/catalog`, or navigate: **My Catalog**.
2. On the **Medications** tab, confirm search and **Sort** (Name A-Z/Z-A)
   work, and the list is now stacked cards (via the shared List component)
   instead of the old hand-rolled rows - same info, same "..." **Edit**/
   **Delete** menu per row.
3. Switch to the **Procedures** tab. Confirm search, **Sort** (Description
   A-Z/Z-A), and a **Filter** > **Type** pill (Lab test/Dental/Vaccination/
   Surgery/Emergency/Wellness Exam) all work.
4. Confirm **Add medication**/**Add procedure** still open the same modal
   form, and Edit/Delete on a row still work.

### S. My Patients (Tier 2)

1. Still as a Veterinarian, go to `http://localhost:5173/staff/vet/patients`,
   or navigate: **My Patients**.
2. Confirm the two-pane layout (queue on the left, detail panel on the
   right) is unchanged, but the queue's old search+sort bar and plain Pet
   Type dropdown are replaced by a search box, **Filter**, and **Sort**.
3. Type a pet or owner name into the search box - confirm the queue
   narrows. Click **Filter** > **Pet Type** - confirm it narrows further;
   remove the pill to see every pet type again.
4. Click **Sort** > **Pet name · A to Z** - confirm it reorders (default is
   Last visit, most recent first, unchanged from before).
5. Click a patient's "..." menu > **View History** - confirm the right
   panel loads their consultation history as before, and the selected
   patient's row now shows a gold accent on its left edge (a slightly
   different look than the old whole-row gold border, functionally the
   same "you're looking at this one" cue).

### T. Activity Log (Tier 2 - DataCalendar's first real use beyond Monthly Schedule)

1. As Pet Assistant, Groomer, Admin, Supervisor, or Superadmin, go to
   `http://localhost:5173/staff/hotel/activity-log`, or navigate:
   **Activity Log**.
2. Confirm a "Date: Today" pill is present by default (same as the old
   always-on "Today" default), a search box, **Filter**, **Sort**, and a
   new **List / Calendar** switcher on the right.
3. Type into the search box - confirm it narrows by description or actor
   name. Click **Filter** > **Action** - confirm it narrows by action type.
4. Click the "Date: Today" pill and try **This week**/**This month**/**All
   dates** from its popover - confirm the log re-fetches each time. Hover
   the pill and click its "X" - confirm it's removable (this is new - the
   date range used to be a fixed control) and the log still loads (the
   most recent 200 branch-wide entries, unbounded).
5. Click **Sort** > **Date · Oldest first** - confirm it reorders.
6. Click **Calendar** - confirm a month grid appears with each day's
   entries as small colored chips (same colors as the List view's action
   badges), and the **←**/**→** buttons move between months. Click
   **List** to go back.

### U. Booking flow - Staff Picker step (Tier 2, lighter search+sort remaster)

1. Start a new booking (customer or receptionist) for a service type with
   staff picker enabled (e.g. Grooming) and several staff eligible.
2. Confirm the step now shows a search box, **Filter** (with nothing
   filterable, its menu is empty - that's expected), and **Sort** above
   the staff cards, in place of the old plain search box + dropdown.
3. Type part of a staff member's name - confirm the grid narrows, and "No
   preference" stays pinned first regardless.
4. Click **Sort** > **Name · Z to A** - confirm the specific staff reorder
   while "No preference" stays first.
5. Confirm picking a staff member (or "No preference") still works exactly
   as before, and a staff member already at this cart's per-branch
   concurrency cap is still shown disabled with the same hint text.

### V. Tier 3 - operational queue chip restyle (visual only)

1. As a role with access to one of the queues (e.g. a Receptionist for
   Bookings Queue, or a Groomer for the Grooming Queue/dashboard), open
   that queue page and set at least one filter away from its default (e.g.
   change **Date** away from Today, or **Status** away from its default)
   so an active-filter chip appears below the dropdowns.
2. Confirm the chip still reads e.g. "Date: This week" and clicking
   anywhere on it still clears that filter, exactly as before.
3. Confirm the small "✕" on the chip is **not visible by default** now -
   hover your mouse over the chip (or Tab to it with the keyboard) and
   confirm the "✕" fades in, matching the same hover-reveal look as every
   filter pill elsewhere in this rollout (e.g. compare to a pill on the
   Cages or Staff Management page). On a touch device (or with your
   browser's device toolbar set to a touch profile), confirm the "✕"
   stays visible instead, since there's no hover there to reveal it on.
4. Repeat the hover check on at least one other queue (e.g. Daycare Queue
   or the Veterinary Console) to confirm the same look applies everywhere.
5. Confirm the Credit Review Queue page is unchanged (it never had a
   filter chip row to begin with).

## Test suites

Run from `golden-fur/client`:

- `npx tsc --noEmit -p .` - clean, no errors.
- `npx vitest run` - **1191/1195 passing** (211 test files, 209 fully
  green as a whole run). The same 3 pre-existing failures, all in
  `src/features/auth/staff/api/staffAuth.api.spec.ts`, a file this session
  never touched (a `fetch` base-URL assertion mismatch, unrelated to this
  change) - confirmed by reading the failures: they're about
  `/auth/staff/mfa/enroll` and `/auth/staff/forgot-password` requests
  resolving to a full `http://localhost:3000/...` URL instead of the
  relative path the test expects, nothing to do with filters, sorting, or
  any migrated page. One more failure showed up in this run,
  `AdminPackageBuilderPage.spec.ts` (a 5-second timeout on one test) - but
  re-running that file alone (`npx vitest run src/features/maintenance/pages/AdminPackageBuilderPage`)
  passes all 24 tests cleanly, confirming it's a flake from running the
  full 1195-test suite under load, not a real regression from anything in
  this session (that file wasn't touched during Tier 3 at all).
- `ActiveFilterChips.spec.ts` (3 original tests kept unmodified, plus 1 new
  locking in the hover-reveal class), all passing - the one spec file for
  the shared component behind the whole Tier 3 pass. No consumer page's
  own spec needed changes (none of them assert on the chip's CSS classes).
- `StaffPickerList.spec.ts` (10 tests - 9 kept behaviorally identical, 1
  renamed/rewritten for the Sort pill, plus every count assertion
  rescoped to just the staff-card grid now that FilterSortBar's own
  Filter/Sort buttons also carry `role="button"`), all passing.
- Tier 2 additions, all passing: `StaffManagementPage.spec.ts` (12 original
  tests kept - 2 rewritten for the pill model - plus 2 new),
  `staffBrowserFields.spec.ts` (new), `CustomerManagementPage.spec.ts` (5
  original tests kept unmodified, plus 2 new), `customerBrowserFields.spec.ts`
  (new), `CreditHistoryTable.spec.tsx` (new - no coverage before),
  `creditHistoryFields.spec.ts` (new), `VetCatalogPage.spec.ts` (new - no
  coverage before), `vetCatalogBrowserFields.spec.ts` (new),
  `MyPatientsPage.spec.ts` (new - no coverage before),
  `myPatientsBrowserFields.spec.ts` (new), `ActivityLogPage.spec.ts` (3
  original tests kept unmodified, 1 rewritten for the pill model, plus 3
  new), `activityLogBrowserFields.spec.ts` (new).
- `DataCalendar` additions, all passing: `DataCalendar.spec.tsx` (new - 8
  tests covering month mode, week mode, nav, the per-day add button, and
  `showNav`), `MonthlySchedulePage.spec.ts` (new - this page had no test
  coverage before this session; 6 tests covering the calendar chips, the
  detail panel, the add-entry panel, the Grid view switch, and the shared
  month nav, all written to prove the `DataCalendar` refactor didn't change
  behavior - every one passed on the first run).
- Batch C additions, all passing: `CustomerBookingFlowPage.spec.ts` (all
  39 original tests kept unmodified, plus 1 new for the search box - this
  is the one file in the whole session where "all original tests kept
  unmodified" actually mattered, given its size and how business-critical
  the booking flow is), `CagePickerList.spec.ts` (3 original tests kept,
  1 new).
- Batch B additions, all passing: `CustomerPetManagerPage.spec.ts` (3
  original tests kept, 3 new), `petBrowserFields.spec.ts` (new),
  `CustomerFoodMedicationPage.spec.ts` (new - no coverage before),
  `customerCatalogBrowserFields.spec.ts` (new),
  `CustomerRewardsPage.spec.ts` (new - no coverage before),
  `couponBrowserFields.spec.ts` (new).
- Batch A spec files, all passing: `DataTable.spec.tsx`,
  `DataList.spec.tsx`, `DataBoard.spec.tsx`, `useGroupBy.spec.ts`,
  `DeletedRecordsArchiveList.spec.ts` (updated in place),
  `archiveBrowserFields.spec.ts` (new), `AdminCagesPage.spec.ts` (7
  original tests unmodified, plus 4 new), `cageBrowserFields.spec.ts` (new),
  `AdminPetTypesPage.spec.ts` (new - this page had no test coverage before
  the migration), `petTypeBrowserFields.spec.ts` (new),
  `AdminBreedsPage.spec.ts` (5 original tests kept, 2 rewritten for the new
  combined-list reality, 2 new), `breedBrowserFields.spec.ts` (new),
  `AdminDiscountManagementPage.spec.ts` (6 tests kept as-is, 5 rewritten for
  the new combined-list/pill interactions, 1 new for Table/Board view),
  `discountBrowserFields.spec.ts` (new), `AdminPromoConfigPage.spec.ts` (9
  tests kept as-is, 4 rewritten for the new pill interactions),
  `promoBrowserFields.spec.ts` (new), `AdminSpinWheelConfigPage.spec.ts`
  (new - no coverage before), `rewardBrowserFields.spec.ts` (new),
  `CatalogAdminPage.spec.ts` (3 tests kept, 2 rewritten for the new
  empty-state text, 2 new), `catalogBrowserFields.spec.ts` (new),
  `AdminServicesPage.spec.ts` (5 tests kept, 2 rewritten for the pill
  model, 2 new), `serviceBrowserFields.spec.ts` (new),
  `AdminServiceTypesPage.spec.ts` (2 tests kept, 4 rewritten - mostly the
  `.closest('li')` → `.closest('tr')` change from the new Table default -
  plus 2 new), `serviceTypeBrowserFields.spec.ts` (new),
  `AdminPackageBuilderPage.spec.ts` (7 tests kept, 9 rewritten for the same
  reason, plus 1 new), `packageBrowserFields.spec.ts` (new),
  `AdminServicesAndPackagesPage.spec.ts` (3 tests, all still pass
  unmodified - the tab shell itself was never touched).

## Open items

Every tier in `../plan.md`'s rollout is now **done**: Batches A (11
pages), B (3 pages), and C (2 booking-flow widgets, light treatment); all
five shared pieces (`DataTable`, `DataList`, `useGroupBy`, `DataBoard`,
`DataCalendar`); all of Tier 2 (6 full pages + `StaffPickerList`); and
Tier 3 (the chip-styling pass, closed out via one shared-component edit
that reached every named queue at once). One thing remains open:

- **Deliberately left undone, confirmed with the user at the end of this
  session**: folding
  `features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`
  and `TransactionBoard.tsx` onto the shared `DataTable`/`DataBoard`/
  `useGroupBy` pieces (originally planned as part of Batch A). Asked
  directly whether to do it anyway now that the abstraction is proven
  everywhere else, or stop - the user chose to stop, given it's a pure
  internal dedup with no user-facing benefit, touching live
  payment/billing code (a 625-line page plus its 603-line customer-facing
  mirror, each with a substantial pre-existing test suite). They still
  have their own separate, never-touched implementation from before this
  session - functionally fine (nothing is broken), just not deduplicated
  onto the new shared pieces the way the plan intended. Worth revisiting
  in its own focused session if wanted later.
- `DataCalendar`'s week mode is built and has its own passing tests, but
  no page in the app actually uses it yet (Monthly Schedule only ever
  offered Month/Grid, and Activity Log only offers List/Calendar-month) -
  it stays available for whenever a future page wants it, not a gap to
  close.
- Two minor cleanup opportunities, not acted on to stay within scope: the
  old `client/src/features/discounts/components/DiscountFilterBar/` and
  `client/src/features/maintenance/components/PromoFilterBar/` components
  are now orphaned (nothing imports either except their own specs) after
  the Discounts and Promos migrations.
- This branch has not been committed or opened as a PR yet - that's a
  separate step once you're ready.
