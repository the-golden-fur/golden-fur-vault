# Discount builder branch multiselect + VSCode-style settings modal

Suggested branch: `feat/52-discount-builder-settings-modal`

## The request, verbatim

> - [ ] In admin settings > discount builder:
>       _ Make branch multiselect
>       _ New discount button should open a modal not a popup that pushes the list down
>       _ The discounts list should use list view not cards
>       _ Add a … button like in services and packages page (with a configure and branch availability options)
> - [ ] Make settings page open up as a popup modal
>       _ The navigation tiles turns into its own sidebar, in the modal
>       _ Fullscreen option on top right that turns the modal into a page
>       _ Replaces normal dashboard navbar items with settings navbar
>       _ Settings navbar items can also be sorted alphabetically, custom, or recent \* Should look like VSCode settings

## Part 1: Discount builder branch multiselect

Discounts previously carried a single `branch_id` column - a discount could
only ever belong to exactly one branch, the same MA22-era design Services and
Packages already moved off of (`service_branch_availability`,
`package_branch_availability`). "Make branch multiselect" meant discounts get
the same treatment: a real many-to-many `discount_branch_availability` table,
not a UI-only trick that fans a multiselect out into several single-branch
rows. **Clarified with you first** which approach to take - you chose the
many-to-many table (the option consistent with Services/Packages).

### Changed

- `supabase/migrations/20260820140_custom_discount_branch_availability.sql` -
  new `discount_branch_availability(discount_id, branch_id, is_available)`
  table, backfilled 1:1 from every existing discount's old `branch_id`, then
  `discounts.branch_id` is dropped. Same "staff read, Admin/Superadmin write"
  RLS shape as `discounts` itself (not the "any authenticated user" policy
  `package_branch_availability` uses - discounts aren't a customer-facing
  catalog table).
- `server/.../discounts.types.ts` - `Discount.branch_id` replaced by
  `discount_branch_availability?: DiscountBranchAvailability[]`.
- `server/.../discounts.validator.ts` - `createDiscountValidator` takes
  `branch_ids: string[]` (min 1) instead of `branch_id`; new
  `discountBranchAvailabilityValidator` (`branch_id` + `is_available`),
  mirroring maintenance's `branchAvailabilityValidator`.
- `server/.../discounts.service.ts` - `createDiscount` inserts the discount
  row, then one `discount_branch_availability` row per requested branch, then
  re-fetches via `getDiscountById` (which now selects the joined
  availability). `listDiscounts`'s `branchId` filter moved from a DB-level
  `.eq('branch_id', ...)` to a post-fetch filter over the joined array (same
  pattern as `services.service.ts`'s `listServices`). New
  `setDiscountBranchAvailability` (upsert, `onConflict: 'discount_id,branch_id'`)
  backs a new endpoint.
- `server/.../discounts.controller.ts` / `discounts.routes.ts` - new
  `PATCH /discounts/:id/branch-availability`.
- `server/.../booking.service.ts` (`resolveDiscountAndPromo`) - the
  "discount belongs to another branch" check now reads
  `discount.discount_branch_availability` instead of comparing `branch_id`
  directly; error message updated to "is not available at this branch".
- `server/.../discountPromoEvaluation.service.ts` (`evaluateDiscounts`, the
  cashier-checkout auto-apply path) - same change: joins
  `discount_branch_availability(branch_id, is_available)` and filters on it
  instead of a `.eq('branch_id', ...)` query.
- `supabase/seeds/module-3-maintenance/module-3-maintenance.seed.ts` (+ the
  `.sql` alternative) - `seedMandatedDiscounts` now creates **8** rows
  (Senior Citizen + PWD x 4 categories), each with an availability row for
  every branch, instead of the old **16** (2 names x 2 branches x 4
  categories). A discount can still be toggled off at just one branch (via
  Branch Availability) without a duplicate row - `is_active` is the
  project-wide switch, `is_available` is the new per-branch one.
- Client: `discounts.types.ts`, `discounts.api.ts` (new
  `setDiscountBranchAvailability`), and a full rewrite of
  `AdminDiscountManagementPage.tsx` (see below).
- `client/src/features/discounts/components/DiscountCard/` deleted - fully
  superseded by the list-row markup below.

### AdminDiscountManagementPage.tsx rewrite (all four bullets)

Rebuilt to match the existing Services/Packages pages exactly (same shared
components, not a new pattern):

- **Branch multiselect**: the create/edit form's single "Branch" `<select>`
  is now `BranchMultiSelect` (checkbox list, reused as-is from
  `features/maintenance/components/`) bound to `formBranchIds: string[]`.
  Creating submits `branch_ids` directly; editing diffs the selection against
  the row's current availability and calls the new endpoint only for
  branches that actually changed (`applyBranchSelection`, same shape as
  `AdminServicesPage`'s own helper of the same name).
- **New discount opens in a modal**: the create/edit form now renders inside
  the shared `Modal` component instead of an inline `<section>` that pushed
  the list down.
- **List view, not cards**: `DiscountCard`/`.discountGrid` replaced by
  `<ul>`/`<li>` rows (`.discountList`/`.discountRow`), matching
  `AdminServicesPage`'s row markup. The Government-Mandated/Custom Discounts
  section split is unchanged, just each section is now a list.
- **"..." button**: `MoreOptionsMenu` per row offers **Configure** (opens the
  edit modal), **Branch Availability** (opens `BranchAvailabilityModal`,
  reused from maintenance), and **Archive** (only once the discount is
  inactive and not mandated - same condition as before).

### Not changed

Discount value/scope editing rules (mandated name lock, exactly-one-of scope
shape, percentage-can't-exceed-100), the archive/restore flow, and the
branch **filter** dropdown in `DiscountFilterBar` (still a single-select -
that's a list filter, not the entity's own branch scope, so it stayed as-is;
its matching logic against a discount now checks the availability array
instead of an exact `branch_id` equality).

## Part 2: Settings page as a VSCode-style modal

### Changed

- `client/src/pages/SettingsPage/SettingsPage.tsx` - the route now renders a
  backdrop + centered panel (`role="dialog"`, `aria-label="Settings"`)
  instead of a plain page. The panel header has a **Sort** button (reusing
  `MoreOptionsMenu`, exactly like the dashboard `Sidebar`'s own category-sort
  menu - see below), a **Fullscreen** toggle (`Maximize2`/`Minimize2`, top
  right), and a **Close** button (`X`) that navigates to `/staff` or
  `/portal`. Clicking the backdrop also closes it (unless fullscreen, which
  has no backdrop).
- The old horizontal tab strip (Profile/Preferences/Account/Security/Config)
  is now a vertical sidebar down the left side of the panel - still
  `role="tab"`/`role="tablist"` (ARIA's tablist pattern doesn't require a
  horizontal layout; `aria-orientation="vertical"` is set), so every existing
  test/behavior around tab switching, the Config tab's admin gate, etc. is
  unchanged.
- **Sort: Custom order / Alphabetical / Recently accessed** - same three
  modes, same wording, and the same localStorage-persisted-per-role pattern
  as the dashboard `Sidebar`'s own section sort (`Sidebar.tsx`). This is a
  separate, smaller implementation rather than reusing `Sidebar` directly -
  `Sidebar`'s items are route `NavLink`s with full drag-and-drop + FLIP
  animation; this sidebar switches a `?tab=` query param instead, so under
  Custom order each item gets a simple Move-up/Move-down button pair
  instead of drag-and-drop. Flagged here as a deliberate scope call: real
  drag-and-drop would mean porting `Sidebar`'s ~150-line DnD/FLIP
  implementation for 4-5 items that rarely need reordering.
- `client/src/shared/components/Navbar/Navbar.tsx` - while the current route
  is the settings route (`/staff/settings*` or `/portal/settings*`), the
  persistent app Navbar swaps its usual Home/Settings icons, identity chip,
  notifications, and compose button for a minimal bar (brand + "Settings"
  label + Sign out) - those shortcuts are redundant once the modal's own
  header already covers navigating around/out of it.

### Not changed

Every settings **redirect target** in the app (`<Navigate to="/staff/settings" />`,
used by ~25 admin pages as their "you don't have access" fallback) still
works unchanged - `/staff/settings` and `/portal/settings` are still real
routes, they just render the modal shell now instead of a plain page. The
Config tab's own tile grid (linking out to Discounts/Services/Promos/etc. as
real full-page routes) is unchanged - clicking one of those tiles still
navigates away from Settings to that page, same as before; only the
Settings shell itself (tabs -> sidebar, page -> modal) changed.

### A framing note on "popup modal"

This app is a single React Router outlet - the Settings route replaces
whatever page was showing, it doesn't render on top of it. So "popup modal"
here means the _visual_ result (a dimmed backdrop + a centered, elevated
panel, exactly like the app's existing `Modal` component), not a literal
overlay on top of the previous page's still-rendered content. Functionally
this is indistinguishable from a true overlay to the user - and Fullscreen
(bullet 2) still means exactly what it says: the same panel expanding to
fill the viewport.

## Verification steps

1. **DB**: apply the new migration (`supabase db reset` locally re-runs the
   updated seed too). In the Supabase SQL Editor, run
   `discount-builder-settings-modal.sql` section by section and confirm each
   section's stated expectation (`discounts.branch_id` gone,
   `discount_branch_availability` exists and is backfilled, the mandated
   seed is 8 rows not 16, RLS matches `discounts`' own shape).
2. **Server unit tests**: from `server/`, run
   `npx vitest run src/features/discounts src/features/billing/services/discountPromoEvaluation.service.spec.ts src/features/booking/services/booking.service.spec.ts`
   - all should pass (93 discount-related tests + the updated booking-service
     discount-application tests).
3. **Seed unit tests**: from the repo root, run
   `npx vitest run supabase/seeds/module-3-maintenance` - all should pass
   (8 mandated discounts, each available at every branch).
4. **Client unit tests**: from `client/`, run
   `npx vitest run src/features/discounts src/pages/SettingsPage src/shared/components/Navbar`
   - all should pass.
5. **Postman**: import `discount-builder-settings-modal.postman_collection.json`,
   fill in `admin_identifier`/`admin_password`, `staff_identifier`/`staff_password`,
   and two distinct branch ids (`branch_id`/`branch_id_2`), run the collection
   top-to-bottom against a local server - all 10 requests should pass their
   embedded tests.
6. **Manual - Discount builder** (`/staff/admin/discounts`, signed in as
   Admin/Superadmin):
   - The list renders as rows (not a card grid), split into
     Government-Mandated / Custom Discounts sections.
   - "New custom discount" opens a centered modal - the list behind it does
     not shift/push down. Fill it out, tick two branches in the "Available
     at" checklist, save - the new row appears in the list.
   - Each row's "..." menu offers **Configure**, **Branch Availability**, and
     (once inactive) **Archive**. Branch Availability opens a modal listing
     every branch with its own toggle; flipping one off and reopening the
     row's Configure modal shows the branch multiselect reflecting the
     change.
7. **Manual - Settings modal** (click the Settings icon in the navbar, or
   visit `/staff/settings` or `/portal/settings` directly):
   - Settings opens as a centered dialog over a dimmed backdrop, not a full
     page. The left side is a vertical list of sections (Profile,
     Preferences, Account, Security, and - Admin/Superadmin only - Config),
     not a horizontal tab strip.
   - Clicking the Fullscreen icon (top right) expands the panel to fill the
     browser window (no backdrop); clicking it again restores the windowed
     modal.
   - The "..." Sort button offers Custom order / Alphabetical / Recently
     accessed. Alphabetical reorders the sidebar immediately. Recently
     accessed puts whichever section you clicked last, first. Under Custom
     order, small up/down chevrons appear next to each section for manual
     reordering, persisted across a reload.
   - While Settings is open, the app's top navbar shows only the brand,
     "Settings", and Sign out - no Home/Settings icons or identity chip.
     Closing Settings (the X, or clicking the backdrop while windowed)
     returns to the dashboard and the normal navbar reappears.
   - From Settings > Config (Admin/Superadmin), clicking any tile (e.g.
     Discounts) still navigates to that full admin page as before.

## Revision 2: live-review follow-up

After reviewing the shipped UI, two further changes:

> - make the admin config settings as subtiles under config just like how
>   vscode does it
> - selecting a tile in admin settings > config will open it in the modal,
>   it navigates to the page itself when changed to fullscreen
> - also no need for enable slider on discounts, since you already
>   implemented the by branch enable/disable slider

### Config subtiles, embedded inline (VSCode-style)

Every admin-config page (Discounts, Services and Packages, Promos, ...) now
also appears directly under **Config** in the sidebar as its own indented
subitem, not only reachable via the tile grid - Config gets a chevron
(collapsed/expanded state persisted in localStorage, same pattern as the
top-level sort) that shows/hides them, matching the reference VSCode
screenshot (Text Editor > Cursor/Find/Font/...).

Selecting a tile - from the tile grid **or** the new sidebar subitems, both
now go through the same handler - embeds that page's real component directly
in the Settings modal's content pane instead of navigating away. Fullscreen
then means something different while one of these is active: instead of just
resizing the panel, it's a real `navigate()` to that page's own route (the
button's label changes to "Open as a full page"). This works because these
are ordinary React components with no props - rendering
`<AdminDiscountManagementPage />` inline is no different from rendering it
via its route; nothing about the page itself changes.

- New `client/src/pages/SettingsPage/configTiles.config.ts` - single source
  of truth for the tile list, now carrying each tile's actual page component
  alongside its `to` route (previously this list lived only in
  `ConfigTab.tsx`). Both `ConfigTab` (the tile grid) and `SettingsPage` (the
  sidebar subitems) import from here, so there is exactly one list to keep
  in sync going forward.
- `ConfigTab.tsx` - tiles are no longer `<Link>`s; they call a new
  `onSelectTile` prop instead (`DashboardTile` gained an `onSelect` variant
  for this - it still renders as a real `<Link>` everywhere else, e.g. the
  staff dashboard's own tiles, which should keep navigating normally).
- Not changed: the target pages themselves. Each one's own auth/role gate,
  data fetching, and any modals it opens (e.g. Discounts' own Configure/
  Branch Availability modals) work unmodified - a nested nested nested
  `Modal` inside the Settings modal is still just a `position: fixed`
  overlay, so it still paints correctly over both.

### Discounts: no more row-level Active toggle

Branch Availability (Part 1, above) already gives per-branch enable/disable;
per your note, the always-visible row toggle was redundant with it and is
gone. Unlike Services (which defaults `is_active: true` forever and never
exposes it again), Discounts default to **inactive** project-wide on
purpose (Modules-Features' "switched off by default" rule) and had no other
way to turn one on - so `is_active` didn't just move off the row into
nothing, it moved into the Configure modal as a toggle (edit-only; the
create validator's `.strict()` schema doesn't accept `is_active` at all, so
a brand-new discount is still always created off, same as before).

- `AdminDiscountManagementPage.tsx` - the row's `ToggleSwitch` is replaced by
  a plain `StatusBadge` (Active/Inactive, non-interactive - the same
  component the pre-rewrite `DiscountCard` used). The Configure modal gained
  a `ToggleSwitch` ("Enable/Disable {name} for checkout"), shown only when
  editing (not on create), submitted as part of the normal Save - so
  activating a discount is now one Save alongside any other edits, not a
  separate immediate-apply action like before.
- The page's own explanatory copy line updated to point at Configure instead
  of "toggle a row".

## Verification steps (Revision 2)

8. **Client unit tests**: from `client/`, run
   `npx vitest run src/pages/SettingsPage src/features/discounts/pages/AdminDiscountManagementPage src/features/staff/components/dashboard/DashboardTile`
   - all should pass.
9. **Manual - Config subtiles**: open Settings > Config - the sidebar's
   Config node has a chevron; expanding it lists every admin-config page
   underneath. Click "Discounts" there (or the "Discounts" tile in the grid) -
   the Discounts page renders inline, inside the Settings panel, with the
   sidebar's "Discounts" subitem now highlighted. Click "Open as a full page"
   (top right, where Fullscreen used to be) - the browser navigates to
   `/staff/admin/discounts` as a normal full page, Settings closed. Going
   back to a plain section (e.g. Profile) and clicking Fullscreen there still
   just resizes the panel in place, no navigation.
10. **Manual - Discounts row**: no toggle switch on any discount row any
    more, just an Active/Inactive badge. Open "..." > Configure on an
    inactive discount, flip "Enable ... for checkout" on, Save - the row's
    badge flips to Active and the success message reads "Discount updated."

## Revision 3: live-review follow-up

> - fix clicking on services types and packages redirecting to profile
>   instead of the actual subpage
> - also the fullscreen button should open the settings modal as A PAGE,
>   not just make it bigger, it redirects to it
> - you may make the sidebar resizable by dragging, both the settings
>   sidebar and the actual dashboard sidebar
> - also config subpages should get sort options (e.g. custom,
>   alphabetical, etc.)

### Bug: selecting a subitem inside an embedded Config page (e.g. Services and Packages > Service Types) reset Settings to Profile

Root cause: `AdminServicesAndPackagesPage` (and others) own their own
`?section=` query param and call `setSearchParams({...})` as a wholesale
replace. Revision 2's `target`/`tab` state lived in the same `?tab=`/
`?target=` query string, so any embedded page's own param change wiped it.

The first fix attempt moved that state to router `location.state` instead
(a channel those pages don't read/write) - but this turned out to have the
_exact same failure mode_: React Router's `navigate()`/`setSearchParams()`
build a **new** location for every call, and `state` defaults to `null` on
it unless the caller explicitly forwards the previous one. An embedded
page's own `setSearchParams({foo: 'bar'})` still stomped Settings' `state`,
just one level removed from the original bug. Confirmed by writing a test
that reproduces exactly this (a stub embedded page with its own
`useSearchParams`) - it failed against the `location.state` version too.

**Real fix**: `activeTab`, `configTarget`, and `isFullscreen` are now plain
`useState` in `SettingsPage.tsx` - not the URL, not router state, so no
navigation anywhere else in the tree (embedded or not) can touch them. The
trade-off: Settings no longer supports deep-linking to a specific tab via
URL (visiting `/staff/settings` always opens on Profile) - flagged here
since it's the one behavior Revision 2 had that this drops.

### Fullscreen: now structurally a different element, not a bigger modal

For the generic case (no Config subitem active), entering fullscreen swaps
out the whole `.backdrop`-wrapped `.modalPanel` for a separate, `position:
fixed; inset: 0` element with no backdrop, no dimming, no rounded corners,
no padding - previously it was the same wrapper just given a bigger child,
which could still read as "the modal got bigger" rather than "you're on a
page". It still isn't a real URL navigation for this generic case, for the
same reason as the bug above (anything URL-based doesn't survive an
embedded page's own independent navigation) - `handleFullscreenToggle` in
`SettingsPage.tsx` documents this trade-off inline. The **Config-subitem**
case is unaffected and was already a real navigation: clicking "Open as a
full page" while e.g. Discounts is embedded still does a real
`navigate('/staff/admin/discounts')`, leaving Settings entirely.

### Config subitems: independent Custom/Alphabetical/Recent sort

Config's own subitem list now gets the same three-mode sort as the
top-level sections, via its own `MoreOptionsMenu` ("Sort Config", next to
the Config row, visible whenever it's expanded and has more than one
subitem) - entirely separate state/localStorage keys
(`settings-config-sort/order/recent-{role}`) from the top-level sort, since
there's no reason picking "Alphabetical" for Profile/Preferences/etc. should
also reorder Discounts/Services and Packages/etc. underneath Config. Under
Custom order, the same per-item Move-up/Move-down buttons from the top
level appear next to each subitem.

### Resizable sidebars (opted in - "you may")

New shared hook `client/src/shared/hooks/useResizableWidth/useResizableWidth.ts`

- pointer-drag (with pointer capture, so the drag keeps tracking even if the
  cursor leaves the thin handle) plus arrow-key resizing for keyboard users,
  clamped to a min/max, persisted to localStorage. Applied to:

- The dashboard `Sidebar.tsx` (only while expanded - the collapsed icon-rail
  stays a fixed width), persisted per role as `sidebar-width-{role}`.
- The Settings modal's own sidebar, persisted per role as
  `settings-sidebar-width-{role}`.

Both get a `role="separator"` drag handle (WAI-ARIA's pattern for this) at
their right edge - hidden until hover/drag (a thin highlighted strip), with
`aria-valuenow/min/max` reflecting the current width for assistive tech.

## Revision 4: live-review follow-up - unify active/available

> - why does it say inactive when it's on for both branches?
> - it seems it's because of the enable discount for checkout slider. this
>   should be automatic and integrated to the branch availability of the
>   discount instead.
> - just make activated and available into one, if a discount is not
>   available in a branch, then it's not activated, simple as that, do the
>   same for promos as well if it doesn't use this model, as well as the
>   services, service types and packages since they're all multibranch
> - no more active/inactive tags as well beside the list items
>
> Clarified with you: mandated discounts (Senior Citizen/PWD) also fully
> unify (no separate compliance gate); Promos keep `is_active` **separate**
> (Recommended) because it also drives the date-based auto-expiry job -
> something none of the other four entities have.

### Root cause

Revision 2 gave Discounts a Configure-modal `is_active` toggle _alongside_
the Branch Availability modal from Part 1 - two independent switches
covering overlapping ground. A discount available at both branches could
still read "Inactive" because the manual toggle was never flipped, which is
exactly the bug reported. Services/Packages/Service Types had the same
latent redundancy (a DB `is_active` column plus per-branch availability),
just without a live UI control surfacing it as visibly.

### Fix: `is_active` is derived from availability, not set directly

For **Discounts, Services, Packages, and Service Types**: `is_active` is no
longer client-settable at all - `update{Entity}Validator` schemas (`.strict()`)
no longer accept it, and every `set{Entity}BranchAvailability` service
function now re-derives it after each upsert:

```
rows = all branch-availability rows for this entity
is_active = rows.some(r => r.is_available)
UPDATE {entity} SET is_active = <derived>
```

`createDiscount` still inserts with `is_active: true` (matching each new
branch row being available by default) rather than the old hardcoded
`false` - a discount with at least one available branch is active the
moment it's created, same as Services/Packages/Service Types already
behaved.

**Promos are the one exception, kept separate on purpose**: `promos.is_active`
still drives `promoExpiry`-style date logic independent of branch
availability, so `setPromoBranchAvailability` does **not** touch it - a
promo can be branch-unavailable everywhere and still be "active" in the
date-window sense, or vice versa. Promos did, however, get the same
many-to-many branch model as the other four: the old `branch_scope` enum
(`'makati' | 'southwoods' | 'both'`) is replaced by a real
`promo_branch_availability` table and a new
`PATCH /maintenance/promos/:id/branch-availability` endpoint, matching
Discounts/Services/Packages/Service Types exactly - `promos.is_active` is
just never written by that endpoint.

### Changed

- `supabase/migrations/20260820141_custom_promo_branch_availability.sql` -
  new `promo_branch_availability(promo_id, branch_id, is_available)` table,
  backfilled from the old `branch_scope` column (`'both'` -> a row per
  branch, `'makati'`/`'southwoods'` -> one row), then `promos.branch_scope`
  is dropped. Same RLS shape as `discount_branch_availability`.
- `server/.../discounts.service.ts`, `services.service.ts`,
  `packages.service.ts`, `serviceTypes.service.ts` - each
  `set{Entity}BranchAvailability` now re-derives and writes `is_active`
  after the upsert, per the pseudocode above.
- `server/.../{discounts,maintenance}.validator.ts` - `is_active` removed
  from every update validator (Discounts, Services, Packages, Service
  Types); `createPromoValidator` now takes `branch_ids: string[]` (min 1)
  instead of `branch_scope`; `updatePromoValidator` keeps `is_active`.
- `server/.../promos.service.ts` - `createPromo` seeds
  `promo_branch_availability` rows from `branch_ids`; new
  `setPromoBranchAvailability` (upsert only - deliberately does not touch
  `is_active`); `listPromos`'s branch filter is now a post-fetch check over
  the joined array, same pattern as the other four.
- `server/.../maintenance.controller.ts` / `maintenance.routes.ts` - new
  `PATCH /maintenance/promos/:id/branch-availability`.
- `server/.../discountPromoEvaluation.service.ts`,
  `server/.../booking.service.ts` - both discount and promo branch checks
  (auto-apply at checkout, and booking-time eligibility) now read the
  respective `*_branch_availability` join instead of a `branch_id`/
  `branch_scope` equality check; `booking.service.ts`'s
  `resolveBranchScope` helper (an extra DB round-trip to resolve a promo's
  scope name) is deleted entirely - no longer needed once the join is
  selected up front.
- `server/.../publicCatalog.service.ts` - `getPublicPackagesPromos` now
  resolves each public promo's `branch_names` from
  `promo_branch_availability`, mirroring how it already does this for
  packages.
- Client: `AdminDiscountManagementPage.tsx` - row-level `StatusBadge` and
  the Configure modal's `is_active` `ToggleSwitch` are both gone; a
  `deriveIsActive()` helper (mirrors the server) drives the Archive-menu-item
  gating instead. `AdminPackageBuilderPage.tsx` - same removal, same
  `deriveIsActive()` helper.
- Client: `AdminPromoConfigPage.tsx`, `PromoFilterBar.tsx`, `PromoCard.tsx` -
  the "Branch scope" `<select>` is replaced by `BranchMultiSelect` (create)
  and a new "Branch Availability" action opening `BranchAvailabilityModal`
  (edit), matching the other four exactly. `PromoCard` keeps its
  `ToggleSwitch`/`StatusBadge` for `is_active` unchanged - Promos are the
  one entity where that control still means something on its own.
- Client: `CustomerBookingFlowPage.tsx`, `PackagesPromosPage.tsx`,
  `publicCatalog.api.ts` - updated to read `promo_branch_availability`/
  `branch_names` instead of `branch_scope`.
- `supabase/seeds/module-3-maintenance/...` - mandated discount seeding
  unaffected by this revision (already unified in Part 1); no seed changes
  were needed since `is_active: true` there already matched every seeded
  discount's availability rows.

### Not changed

Promos' date-based auto-expiry job and its `is_active` semantics - per your
explicit answer, that stays independent of branch availability. The promo
cap configuration feature (branch-scoped spending caps) is unrelated to
this and untouched.

## Verification steps (Revision 4)

16. **DB**: apply the new migration
    (`20260820141_custom_promo_branch_availability.sql`). Confirm
    `promos.branch_scope` is gone, `promo_branch_availability` exists and is
    backfilled 1:1 from every existing promo's old scope.
17. **Server unit tests**: from `server/`, run `npx vitest run` - all 876
    tests should pass, including the updated
    `discounts.service.spec.ts`, `services.service.spec.ts`,
    `packages.service.spec.ts`, `serviceTypes.service.spec.ts`,
    `promos.service.spec.ts`, `discountPromoEvaluation.service.spec.ts`,
    `booking.service.spec.ts`, and `publicCatalog.service.spec.ts`.
18. **Client unit tests**: from `client/`, run `npx vitest run` - all 691
    tests should pass.
19. **Client build**: from `client/`, run `npm run build` - should complete
    with no type errors.
20. **Postman**: re-import the updated
    `discount-builder-settings-modal.postman_collection.json` - items 11-13
    cover the unify-active/available behavior and the new promo
    branch-availability endpoint.
21. **Manual - the original bug**: open Discounts, create/find a discount
    available at both branches - it must read "Active" (or, since row
    badges are gone per your note, simply must not be offered an Archive
    action). Open its Branch Availability modal, turn off its only
    remaining branch - the Archive action now appears for it, with no
    separate toggle involved anywhere.
22. **Manual - Promos branch availability**: open Promos, create a promo,
    tick two branches in the new "Available at" checklist (in place of the
    old "Branch scope" dropdown), save. Use its new "Branch Availability"
    button to flip one branch off - the promo's own Active/Inactive switch
    is untouched by this action (Promos are the one entity where flipping
    branch availability does _not_ change `is_active`).

## Verification steps (Revision 3)

11. **Client unit tests**: from `client/`, run
    `npx vitest run src/pages/SettingsPage src/shared/components/Sidebar src/shared/hooks`
    - all should pass, including a regression test that reproduces the
      original bug directly (an embedded stub page calling its own
      `setSearchParams`, asserting Settings' own selection survives it).
12. **Manual - the original bug**: open Settings > Config > Services and
    Packages (embedded inline). Click the "Service Types" or "Packages"
    sub-tab _inside_ that embedded page. Settings must stay exactly where it
    was (Services and Packages still embedded, "Services and Packages" still
    highlighted in the Settings sidebar) - it must not jump back to Profile.
13. **Manual - Fullscreen as a page**: from a plain section (e.g. Profile),
    click Fullscreen. The panel should fill the entire browser viewport with
    no dimmed backdrop visible anywhere around its edges and no rounded
    corners - visually indistinguishable from a normal full page. Click it
    again (now "Exit full screen") to return to the windowed modal.
14. **Manual - resizable sidebars**: hover the right edge of the dashboard
    sidebar (outside Settings) - a thin gold handle should appear; drag it
    to resize, reload the page, and confirm the width persisted. Repeat
    inside the Settings modal for its own sidebar.
15. **Manual - Config subitem sort**: open Settings > Config, expand it,
    click the "..." next to "Config" (only visible when there's more than
    one subitem) - Custom order / Alphabetical / Recently accessed. Alphabetical
    should immediately reorder the subitems A-Z, independent of whatever
    sort the top-level Profile/Preferences/etc. sidebar is using.
