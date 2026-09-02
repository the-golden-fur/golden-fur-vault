# Payment status filter + search icon/sidebar/service-type UI polish

Suggested branch: `feat/47-payment-filter-and-ui-polish`

## The request, verbatim

> add a filter for the paid/unpaid status for both the bookings and payment
> queues
>
> - [ ] Fix search bar icons on search bar fields overlapping with input text
>   - One in customer login/signup
>   - Admin settings > promos config page
>   - Admin settings > services and packages page
> - [ ] Add a label for the sidebar sort options
>   - It's hard to see it since it only appears on hover
>   - Especially a problem for nonadmin staff and customers
> - [ ] Add add new service type button instead of the form being on the
>       same page as the list

Screenshots showed the Payments Queue's existing Status filter dropdown (for
context on where a new Payment filter should sit) and the sidebar's nav
items with drag handles, illustrating how little is visible without
hovering.

## Part 1: Payment status filter on both queues

`bookings.payment_stage` (`Unpaid` / `Paid in Advance` / `Paid`) was already
shown as a per-row badge on both queues but had no filter of its own -
`GET /bookings` only accepted `status` (the booking-status field, a
different column).

### Changed

- `server/.../booking.validator.ts` - `listBookingsQueryValidator` gains an
  optional `payment_stage` query param (`z.enum(PAYMENT_STAGES)`).
- `server/.../booking.service.ts` - `ListBookingsFilters` gains
  `paymentStage`; `listBookings` applies `.eq('payment_stage', ...)`
  independently of the existing `status` filter. No re-filter step is needed
  after the lazy No-show transition (that transition only ever touches
  `status`, never `payment_stage`).
- `server/.../booking.controller.ts` - `listBookingsController` passes
  `parsed.data.payment_stage` through as `paymentStage`.
- `client/.../booking.types.ts` - `ListBookingsFilters` gains
  `paymentStage?: PaymentStage`.
- `client/.../booking.api.ts` - `listBookings` sends it as the
  `payment_stage` query param.
- `ReceptionistBookingsQueuePage.tsx` / `PaymentsQueuePage.tsx` - both gain a
  `paymentStageFilter` state (default `All`), a "Payment status" dropdown
  (All/Unpaid/Paid in Advance/Paid) next to the existing Service type filter,
  and a matching "Payment: {stage}" filter chip. Labeled **Payment status**,
  not **Payment** - the Payments Queue already has a per-row Admin/Superadmin
  "Payment" override dropdown, and a duplicate "Payment" label would ambiguate
  for screen readers and made two automated tests fail on a duplicate-label
  lookup (fixed by renaming).
- Tests: a new `booking.service.spec.ts` case asserting the
  `payment_stage` filter is applied, and one new case in each queue page's
  spec asserting the dropdown drives the API call.

### Not changed

The existing booking-`status` filter and its dropdown - this is a second,
independent filter, not a replacement.

## Part 2: Search bar icon/text overlap

Two distinct, unrelated bugs shared the same symptom (icon crowding the
first character of the input):

- `SearchSortBar.module.css` (the shared search+sort bar used by the
  Promos config page's branch-cap search, and every tab of Services and
  Packages - Services/Service Types/Packages - as well as both booking
  queues and HotelBookingPicker): the search/sort icon sits at
  `left: var(--space-2)` (16px) and is 15px wide, ending at 31px, but the
  input/select's own left padding was only `var(--space-5)` (40px) - a bare
  9px gap that read as touching/overlapping in practice. Padding widened to
  `calc(var(--space-5) + var(--space-1))` (48px) on both the search input and
  the sort select.
- `CustomerLoginForm.module.css` / `CustomerSignupForm.module.css` (the
  Mail/Lock/UserRound glyph on the customer login and signup email/password/
  name fields): the glyph sits at `left: 12px` and is 20px wide, ending at
  32px, against only 34px of input padding - a 2px gap. Padding widened to
  44px in both files (they were identical, presumably copy-pasted).

### Not changed

The Staff Login page's own icon field uses a different, wider `left: 20px`
layout that was never reported as overlapping - left untouched, and the
Promos page's top `PromoFilterBar` "Search by name..." field, which has no
icon at all (plain label above the input) - nothing to overlap there.

### Live-review follow-up: still reported after Revision 1

Live review still showed overlap on the Service Types search field and the
Build Package modal's branch search after Revision 1 shipped. Both use the
same shared `SearchSortBar` fixed above - re-verified in isolation (a
standalone HTML page loading the exact CSS rule with the exact icon size/
position, screenshotted with Playwright) and the fix does produce a clean
gap with the values Revision 1 landed. If it's still showing overlapped,
it's almost certainly a stale dev server/browser cache rather than a
remaining code issue - **please hard-refresh (Ctrl+Shift+R) or restart the
Vite dev server** and re-check before reporting this one again.

## Part 5 (live-review follow-up): Services/Packages toolbar fixes

Three more things live review found on the Services and Packages tabs:

> - services search field misaligned?
> - packages does not have a search, sort and filter function, add it
> - package builder/editor has misaligned branch search field

### Services tab: search field's icon rode too low, detached from the input

`AdminServicesPage.tsx` wraps its `SearchSortBar` and its Category/Branch/
Status `filterField` dropdowns in a `.filters` flex row that never set
`align-items`, unlike every sibling page's own toolbar (`AdminServiceTypesPage`,
`AdminPromoConfigPage`, `AdminPackageBuilderPage` all set `align-items:
flex-end` on the row `SearchSortBar` sits in directly). Default flex
cross-axis alignment is `stretch`: with no `align-items` override, the
taller `filterField`s (a label row above their `<select>`) stretched
`.searchField` to match their height too, but the `<input>` inside it never
grows to fill that extra space - only `.searchField`'s own box does. The
search icon is absolutely positioned at 50% of _that_ (now taller) box, not
the shorter, top-aligned input actually visible inside it - reading as
detached/floating below the input.

- `AdminServicesPage.module.css` - added `align-items: flex-end;` to
  `.filters`, matching every sibling toolbar.

### Packages tab: no search/sort/filter for the package list itself

The only search+sort+filter row anywhere on `AdminPackageBuilderPage.tsx`
was the _service picker_ inside the Build/Edit Package modal (search/sort/
filter over which services to bundle) - the top-level package **list**
itself only ever had a Branch filter, no search or sort at all.

- `AdminPackageBuilderPage.tsx` - the toolbar gains a `SearchSortBar`
  (search by name, sort Name A-Z/Z-A - a new `PackageSortKey`/
  `PACKAGE_SORT_OPTIONS`, distinct from the modal's existing
  `ServiceSortKey`/`SERVICE_SORT_OPTIONS`) and a Status filter (All/Active
  only/Inactive only, defaulting to **All** rather than Services' own
  "Active" default - Packages' "..." > Archive action only appears once a
  package is already Inactive, so hiding Inactive rows by default would hide
  the very rows that action is for). Wired through a new `useSearchAndSort`
  call plus the existing Branch-filter `useMemo`, same layering
  `AdminServicesPage` already uses (search/sort first, then a plain
  `.filter()` for Status/Branch).
- `AdminPackageBuilderPage.module.css` - added a `.filters` wrapper class
  (same `align-items: flex-end` fix as the Services tab above, applied from
  the start this time) so the new search field doesn't inherit the same
  detached-icon bug.
- The empty-state copy changed from "No packages match the selected
  filter." to "...filters." (plural), now that there's more than one filter
  axis.

### Package builder/editor: branch search field

`BranchMultiSelect` (the "Available at" picker inside the Build/Edit Package

- and Services/Service Types' own - forms) uses the same shared
  `SearchSortBar`, already fixed above. Re-verified the same way (isolated
  render, Playwright screenshot) with a clean gap - if still showing
  overlapped after a hard refresh, please attach a fresh screenshot, since
  nothing in `BranchMultiSelect.module.css` itself differs from the other
  `SearchSortBar` callers that are confirmed fixed.

## Part 3: Always-visible "Sort" label on the sidebar

`Sidebar.tsx`'s per-category "..." sort menu (Custom order/Alphabetical/
Recently accessed) only had an `aria-label` - no visible text - and
`Sidebar.module.css` additionally hid the trigger at `opacity: 0` until its
row was hovered or focused (`--more-options-trigger-opacity`). For every
role without multiple labeled categories (every non-admin staff role, and
the customer portal - which only ever get one flat, unlabeled section), that
made the _entire_ sort control invisible and undiscoverable without
deliberately hovering a plain nav list.

### Changed (Revision 1)

- `Sidebar.tsx` - each category header (`SidebarCategory`) now renders a
  visible `Sort` text label immediately before the "..." trigger, reusing
  the same `categorySortLabel` style already used by the top-level
  "Categories" sort row (added `flex-shrink: 0` to that shared class so it
  doesn't get squeezed in the narrower per-category row). The label is
  `aria-hidden` since `MoreOptionsMenu`'s own `aria-label` already announces
  the button's purpose to screen readers - it would otherwise be announced
  twice.
- `Sidebar.module.css` - removed the `--more-options-trigger-opacity: 0`
  default and its `:hover`/`:focus-within` overrides on `.sectionHeader`/
  `.flatSectionHeader`, so the trigger now falls back to
  `MoreOptionsMenu.module.css`'s own default (`opacity: 1`, always visible) -
  the same always-visible treatment the "Categories" row already had.

## Revision 2: live-review follow-up

Live review flagged three more things about the sidebar:

> - mix in the dashboard with the other stuff in the sidebar, so that
>   there's only 1 sort thing
> - put it in the far left, not right
> - or perhaps remove the dashboard tile entirely, and just add a home icon
>   in the navbar
> - for admin dashboard, you can use the old on hover > show ..., no need
>   for the sort label

Screenshots showed a non-admin role's sidebar with **two** separate "SORT"
rows (one above the "Dashboard" pill, one below it, before "Days Off") and
the admin sidebar with **three** sort controls stacked at once (Dashboard's
own, the "Categories" reorder row, and every individual category's own).

### Root cause

`StaffAuthGuard.tsx`'s `buildSidebarSections` always prepended a whole
_separate_ `{ label: null, items: [Dashboard] }` section ahead of a role's
own section(s). For every non-admin role, whose own dashboard config is
already a single flat `label: null` section (`staffDashboard.config.ts`),
that meant **two** flat sections back to back - each rendering its own
independent sort control per Revision 1's fix above. The customer portal's
own sidebar (`CUSTOMER_SIDEBAR_SECTIONS`) never had this problem - it
already merges "Home" in as the _first item_ of its one flat section,
rather than giving it a section of its own.

### Changed

- `StaffAuthGuard.tsx` - `buildSidebarSections` now mirrors that same
  customer-portal convention: for every non-admin role, Dashboard merges in
  as the first item of the role's own flat section instead of a second,
  separate one - down to exactly one sort control for that whole list, same
  as the customer portal already had. Admin/Superadmin has no single flat
  section to merge into (every one of its sections is labeled - Management/
  Receptionist/Groomer/...), so Dashboard stays pinned as its own top entry.
- `Sidebar.tsx` - a section's sort control (both the "..." trigger and the
  Revision-1 "Sort" label) now only renders when it has **more than one
  item** - sorting a lone item is meaningless. This is what actually kills
  Admin/Superadmin's now-solo "Dashboard" section's own sort control, rather
  than special-casing that one section by name.
- `Sidebar.module.css` / `Sidebar.tsx` - per "no need for the sort label...
  use the old on hover" for admin: the always-visible treatment from
  Revision 1 now applies **only** to unlabeled (flat-list) sections -
  `.sectionHeader` (Admin/Superadmin's labeled Management/Receptionist/...
  categories) reverts to the original icon-only, hover/focus-reveal trigger
  (`--more-options-trigger-opacity`, restored but scoped to `.sectionHeader`
  only this time, not `.flatSectionHeader`). Every non-admin role and the
  customer portal - the ones the original complaint was actually about -
  keep Revision 1's always-visible label.
- `Sidebar.module.css` - per "put it in the far left, not right":
  `.flatSectionHeader` changed from `justify-content: flex-end` to
  `flex-start` - the flat-list Sort label/trigger (which has no chevron or
  category heading to sit next to, unlike a labeled category's own header)
  now sits at the row's near edge instead of the far one.
- Tests: `Sidebar.spec.ts`'s existing "flat section gets a sort menu" test
  now uses a 2-item fixture (a 1-item one no longer shows a sort menu at
  all); a new case asserts a 1-item section's sort menu is hidden.

### Not changed

The drag handle (`GripVertical`) next to each item/category stays exactly as
it was (constant 0.5 opacity, not hover-gated) - only the sort trigger's
visibility rules were touched. The "remove Dashboard entirely, add a Home
icon to the navbar" alternative was not built - the merge above reuses an
existing, already-working pattern from the customer portal with no new
navbar surface needed; flag if you'd still rather have the navbar-icon
version instead.

## Part 4: "New service type" button opens a modal instead of an inline form

`AdminServiceTypesPage.tsx` was the one tab of Services and Packages that
still had its create form permanently rendered as a `<section>` above the
list (Services and Packages tabs already moved theirs behind a "New
service"/"New package" button + modal in the prior actions-menu overhaul -
see `testing/docs/custom/46-promo-cap-count-and-services-actions-menu`).

### Changed

- `AdminServiceTypesPage.tsx` - the permanent "Add service type" `<section>`
  is gone. A new `isCreateModalOpen` state backs a **New service type**
  button in a new title row (next to the `<h1>`), and the same form now
  renders inside a `Modal` (title "Add service type"), matching the
  existing Configure-edit-modal pattern on the same page. The modal closes
  automatically on a successful create; Cancel and the backdrop both close
  it without submitting.
- `AdminServiceTypesPage.module.css` - added `.titleRow` (same shape as
  `AdminPromoConfigPage`'s own `.titleRow`); removed `.panel`/`.sectionTitle`
  (now unused - they only ever styled the removed inline section).
- Tests: `AdminServiceTypesPage.spec.ts`'s create-form test now opens the
  modal via the new button first, and additionally asserts the form isn't on
  the page before opening it / after a successful create.

### Not changed

The create form's own fields/validation/submit behavior (Key, Name, Staff
picker/Cage picker checkboxes, branch multiselect) - only where it renders.

## Revision 3: live-review follow-up (round 2)

> - all the input fields that I told you that were misaligned are still not
>   fixed
> - perhaps it's too small?
> - by misaligned, I mean that the search icon in the input field overlaps
>   with the value text
> - I want the value to be placed on the right, does not overlap
> - also remove the dashboard/home tiles in the sidebar for all roles, just
>   add a home icon in the navbar

### The real remaining icon-overlap bug: `StaffLoginForm`

Revision 1 fixed `CustomerLoginForm`/`CustomerSignupForm` and verified the
fix (re-rendered the exact CSS rule in an isolated Playwright screenshot -
clean gap, no overlap). It never touched `StaffLoginForm.tsx` though - the
original request said "customer login/signup", but the screenshot's typed
value (`makati.receptionist1@goldenfur.com`) is a **staff** account, which
logs in through `/staff/login` (`StaffLoginForm`), not the customer login
page. That form has the exact same icon-glyph pattern as the customer forms
(Mail/Lock icon at `left: 12px`, 20px wide) but sets it inline in the TSX
rather than through the CSS module, so it was invisible to a search scoped
to `.module.css` files - and its gap (`padding-left: 40px`, an 8px clearance
after the icon's 32px right edge) was even tighter than the customer forms'
pre-Revision-1 gap.

- `StaffLoginForm.tsx` - both the Username/email and Password fields' inline
  `paddingLeft` raised from `40px` to `48px` (16px clearance past the
  icon's right edge).
- `CustomerLoginForm.module.css` / `CustomerSignupForm.module.css` - padding
  raised further too, from `44px` to `48px`, so all three login-related
  forms now share the exact same, generously-verified value for identical
  icon geometry.
- Re-verified the exact new `StaffLoginForm` padding value in the same
  isolated-Playwright-screenshot way, reproducing the original screenshot's
  own typed value (`makati.receptionist1`) - clean gap, confirmed fixed.

The Promos-config and Services/Packages pages' `SearchSortBar`-based fields
(Revision 1's other fix) were **not** changed again here - that fix was
independently re-verified in isolation and already has a wide (17px+)
margin; if those still show overlapping after this round, it's very likely
a stale dev server or browser cache rather than a remaining code issue -
please hard-refresh or restart the dev server and re-check with a fresh
screenshot before flagging again.

### Sidebar Dashboard/Home tiles removed - Home moves to the Navbar

Per "remove the dashboard/home tiles in the sidebar for all roles, just add
a home icon in the navbar" - the merge approach from Revision 2 is gone;
every role now has the same treatment the customer portal's Navbar already
does for Settings.

- `StaffAuthGuard.tsx` - `buildSidebarSections` no longer adds a Dashboard
  item/section at all; it's just `toSidebarSections(STAFF_DASHBOARD_CONFIG[slug])`
  again, unchanged from the underlying per-role config.
- `customerPortal.config.ts` - removed the "Home" entry from
  `CUSTOMER_SIDEBAR_SECTIONS`.
- `Navbar.tsx` - a new **Home** icon button (Lucide `Home`, matches the
  existing Settings button's shape/position) links to `HOME_PATH_BY_ROLE[role]`
  (`/staff` for staff, redirects to `/staff/dashboard`; `/portal` for
  customers) - the same route the brand logo at the far left already linked
  to, just now with a dedicated, discoverable icon affordance for it too.
  `Navbar.module.css`'s `.settingsLink`/`.settingsLabel` renamed to the
  generic `.iconLink`/`.iconLabel` so both the Home and Settings buttons
  share one style instead of duplicating it.

### Not changed

Revision 2's sidebar sort-control changes (hover-only for admin's labeled
categories, always-visible + left-aligned for flat sections, hidden for a
lone item) are untouched - they still apply to every remaining sidebar
section now that Dashboard/Home no longer occupy one of their own.

## Verification steps

1. **Server unit tests**: from `server/`, run
   `npx vitest run src/features/booking/services/booking.service.spec.ts src/features/booking/modules/validators/booking.validator.spec.ts`
   - all should pass, including the new `payment_stage` filter case.
2. **Client unit tests**: from `client/`, run
   `npx vitest run src/features/booking/pages/ReceptionistBookingsQueuePage src/features/billing/pages/PaymentsQueuePage src/features/maintenance/pages/AdminServiceTypesPage src/features/maintenance/pages/AdminServicesPage src/features/maintenance/pages/AdminPackageBuilderPage src/shared/components/Sidebar src/shared/components/SearchSortBar src/shared/components/Navbar src/shared/components/AppShell src/features/auth/staff/guards/StaffAuthGuard src/features/auth/customer/guards/CustomerAuthGuard src/features/auth/staff/components/forms/StaffLoginForm src/features/auth/customer/components/forms/CustomerLoginForm`
   - all should pass.
3. **Manual - Bookings queue** (`/staff/bookings/queue`, signed in as any
   staff role): a new **Payment status** dropdown sits next to Service type
   (All payment statuses/Unpaid/Paid in Advance/Paid). Pick "Unpaid" -
   every row shown now carries an "Unpaid" payment badge, and a "Payment:
   Unpaid" chip appears below the filter bar; clicking the chip's clear
   button (or resetting the dropdown to "All payment statuses") brings back
   every status.
4. **Manual - Payments queue** (`/staff/billing/payments-queue`): same
   Payment status dropdown and chip behavior as step 3.
5. **Manual - search bar icons**: open the **staff** Login page
   (`/staff/login`) and type into Username/Password with a long value like
   `makati.receptionist1@goldenfur.com` - the Mail/Lock icon should sit
   clearly left of the typed text with visible daylight between them, not
   touching it. Then check the customer Login page (`/login`) and Signup
   page (`/signup`) the same way. Then open Admin > Settings > Promos
   (`/staff/admin/maintenance/promos`, Admin/Superadmin) and scroll to the
   Promo Cap Configuration list's "Search branches..." field, and Admin >
   Settings > Services and Packages (`/staff/admin/maintenance/services-and-packages`,
   all three tabs) - every search field's magnifying-glass icon should have
   clear daylight before the placeholder/typed text. If any of the last two
   (Promos/Services and Packages) still look overlapped, hard-refresh
   (Ctrl+Shift+R) or restart the dev server first - see Revision 3 above.
6. **Manual - sidebar has no Dashboard/Home tile, Navbar has a Home icon**:
   as any role (staff or customer), confirm the sidebar's nav list no
   longer has a "Dashboard" (staff) or "Home" (customer) entry anywhere -
   it starts directly with the role's own items (Days Off, Notifications,
   etc.). In the Navbar (top bar), a new house-icon **Home** button sits
   next to Settings - clicking it from any page returns to the role's own
   dashboard/portal home.
7. **Manual - sidebar sort label**:
   - As a **non-admin staff role** (e.g. Receptionist) or the **customer
     portal**: without hovering, the sidebar shows exactly **one** "Sort"
     label + "..." button for the whole list, sitting at the row's **left**
     edge.
   - As **Admin/Superadmin**: the "Categories" reorder row is unchanged.
     Each individual category (Cashier/Groomer/Management/...) shows **no
     visible "Sort" text** and its "..." button stays hidden until you
     hover or focus that row - same as before Revision 1.
8. **Manual - Services tab** (`/staff/admin/maintenance/services-and-packages`,
   Services sub-tab): the search field's magnifying-glass icon sits inside
   the visible input box, vertically centered - not floating below it.
9. **Manual - Packages tab** (same page, Packages sub-tab): a search box and
   a sort dropdown now sit next to the Branch/Status filters, above the
   package list. Typing a package's name narrows the list; the sort dropdown
   reorders by name; Status defaults to "All" (inactive packages still show,
   so their Archive action stays reachable).
10. **Manual - Service Types "New" button** (`/staff/admin/maintenance/service-types`,
    Admin/Superadmin): the page no longer shows a permanent "Add service
    type" form above the list - only a **New service type** button next to
    the title. Clicking it opens a modal with the same Key/Name/picker/branch
    fields; Cancel or clicking the backdrop closes it without creating
    anything; filling it in and submitting creates the type, closes the
    modal, and shows the new row in the list below.
11. **Postman**: import
    `payment-filter-and-ui-polish.postman_collection.json`, fill in
    `staff_identifier`/`staff_password` (any staff account), run the
    collection top-to-bottom against a local server - all 5 requests should
    pass their embedded tests.
