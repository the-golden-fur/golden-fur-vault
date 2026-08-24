# Promo cap "number of promos" option + Services/Packages actions menu overhaul

Suggested branch: `feat/46-promo-cap-count-and-services-actions-menu`

## The request, verbatim

> - At admin > settings > promos config page, add option to number of
>   promos, not just flat PHP or %
> - At admin settings > config > services and packages, for each list item
>   in service types, services and packages, move all actions to a … button
>   - Remove disable button, since we can already disable per branch
>   - Service types rename should be edit as well that opens up a new modal
>     on screen
>   - Same thing with services, edit should open a new modal, not push the
>     list down
>   - Do the same for packages
>   - Make the packages similar to services (e.g. enable/disable per
>     branch, edit button)
>   - The enable/disable should also open a modal that shows a list of
>     branches, and whether to enable disable
>   - Name the button something convenient, not literal enable/disable
>   - Perhaps rename edit to something like configure

Screenshots showed today's Services/Service Types/Packages tabs (Settings >
Config > Services and Packages) and the Promos config page's "Promo Cap
Configuration" section with a Cap type dropdown offering only Percentage/Flat.

## Part 1: promo cap "count" type

Today `promo_cap_configuration.cap_type` is a Postgres enum with two values
(`percentage`, `flat`) and caps the combined **discount amount** all
customer-activated promos may contribute to one transaction. A third value,
`count`, now caps the **number of promos** that may combine instead.

### Changed

- `supabase/migrations/20260818132_custom_promo_cap_count_type.sql` - adds
  `'count'` to `cap_type_enum` (an `ALTER TYPE ... ADD VALUE` statement,
  standalone since Postgres won't let a new enum value be used in the same
  transaction that adds it).
- `server/.../maintenance.validator.ts` - `CAP_TYPES` gains `'count'`;
  `upsertPromoCapConfigurationValidator` now rejects a non-integer
  `cap_value` when `cap_type` is `'count'` (a fractional promo makes no
  sense).
- `server/.../discountPromoEvaluation.service.ts` (`evaluatePromos`) - a
  `'count'` cap sorts matched promos largest-value-first (same tie-break as
  the existing amount cap) and applies the first `cap_value` of them **in
  full**, dropping the rest entirely. This is a judgment call, same spirit as
  the pre-existing largest-value-first tie-break for amount caps: a "count"
  has no notion of a partial promo, so there's no trimming step for it.
- `client/.../maintenance.types.ts` - `CapType` gains `'count'`.
- `client/.../PromoCapCard.tsx` - the Cap type dropdown offers "Number of
  promos"; the value field relabels to "Cap value (promos)" and switches to
  a whole-number `step`; Save is blocked client-side for a fractional value
  under `count` (mirrors the server-side rejection).
- Tests: `maintenance.validator.spec.ts`, `PromoCapCard.spec.ts`, and a new
  `discountPromoEvaluation.service.spec.ts` (this function had no dedicated
  test file before - added baseline coverage for the existing amount-cap
  trimming behavior alongside the new count-cap tests, since introducing an
  untested branch into untested code would leave the whole function unverified).

### Not changed

Nothing about how a `percentage`/`flat` cap behaves - the new `count`
branch is additive.

## Part 2: Services/Service Types/Packages actions menu overhaul

All three tabs (Settings > Config > Services and Packages) followed the same
old pattern: several always-visible buttons/toggles per row, and an inline
edit form that expanded in place and pushed the rest of the list down. Per
the request, every row across all three tabs now uses a single "..." (kebab)
menu, reusing the existing `MoreOptionsMenu` component (already used
elsewhere in the app, e.g. queue-picker cards) instead of introducing a new
one. Two new shared components back the menu actions:

- `client/src/shared/components/Modal/` - a generic titled overlay (same
  backdrop/header/close-button shape as the existing `ComposeModal`, the
  repo's prior precedent for a form-carrying modal). Edit forms now render
  inside this instead of an inline `<section>` that grew the list's height.
- `client/src/features/maintenance/components/BranchAvailabilityModal/` -
  the "manage availability" action's modal: a list of branches, each with
  its own on/off `ToggleSwitch`. Shared by Services (one row per real
  branch) and Packages (one row, since a package always belongs to exactly
  one branch - MA22).

### Services (`AdminServicesPage.tsx`)

- Row now shows only the name/badges/status plus a single "..." menu:
  **Configure** (opens the edit form in the new `Modal`) and **Manage
  availability** (opens `BranchAvailabilityModal` listing both branches).
- Removed: the always-visible per-branch `ToggleSwitch` row, the inline
  "Edit" button, and the global "Disable {name}" toggle -
  per the request, per-branch availability already covers taking a service
  off sale, so the redundant global toggle (and its `handleActiveToggle`
  handler) is gone. `is_active` is still a real column (default `true` on
  create) and still drives the Status filter/badge - it's just no longer
  settable from this page after creation. Flagged inline in
  `AdminServicesPage.tsx` as a judgment call.

### Service Types (`AdminServiceTypesPage.tsx`)

- Row now shows name/key/status plus a single "..." menu: **Configure**
  (opens a `Modal` with Name, Staff picker, and Cage picker fields - what
  used to be an inline rename `<input>` that pushed the row's layout around,
  plus the two toggles that lived in an always-visible row) and
  **Activate**/**Deactivate** (no per-branch concept exists for service
  types, so - unlike Services/Packages - this stays a menu action rather
  than moving into a branch-list modal; it already reads as a convenient
  label, not literal "Enable/Disable").
- New test file `AdminServiceTypesPage.spec.ts` (none existed before this
  change).

### Packages (`AdminPackageBuilderPage.tsx`)

- Row now shows name/badges/status plus a single "..." menu: **Configure**
  (edit form in `Modal`), **Manage availability** (`BranchAvailabilityModal`
  with the package's one branch, toggling `is_active` - "make packages
  similar to services" per the request, even though a package's branch set
  is always a singleton rather than a real per-branch list), and **Archive**
  (unchanged condition: only offered once the package is inactive).
- Removed: separate always-visible "Edit"/"Deactivate"/"Reactivate" buttons.
  `handleActiveToggle` now takes an explicit target boolean (was an
  unconditional flip) so the branch-availability modal's toggle can set a
  specific value like Services' per-branch toggles always could.

### Naming

Per "name the button something convenient, not literal enable/disable" and
"perhaps rename edit to something like configure": every row's kebab reads
**Configure** (not "Edit") and, as of Revision 2 below, **Branch
Availability** (not "Enable"/"Disable"/"Manage availability") across all
three tabs.

## Revision 2: live-review follow-up

After reviewing the shipped UI, a further round of changes:

> - remove both branches promo config
> - just make a list of branches
> - add search, filter and sort functions
> - add a … button for each list item
> - this shows a configure option
> - opens the cap type, value, etc. as a modal
> - add search, filter and sort functions to manage availability in services
> - rename it to something like Branch Availability
> - change deactivate to branch availability in service types as well, with
>   the same search, filter and sort functions
> - do the same for packages
> - change the `derive from price...` in create new package to a slider not
>   a radio button
> - do the same for create/edit service, `derive...` and
>   `requires assessed...` also to sliders, not radio buttons

**Clarified with you first**: whether Service Types' new Branch Availability
should be backed by real per-branch data or just reuse the single existing
`is_active` flag shown as a branch list for cosmetic consistency. You chose
real per-branch data (Recommended option) - Service Types now has its own
`service_type_branch_availability` table, mirroring `service_branch_availability`.

### Promo Cap Configuration is now a list, not a card grid

- Removed the "Both branches (system-wide default)" card entirely from the
  UI - the section now lists only real branches (Makati, Southwoods). The
  underlying system-wide default DB row (`branch_id = null`) is untouched
  and still used as `evaluatePromos`' fallback when a branch has no
  branch-specific cap row yet; it's just no longer surfaced/editable here.
- Each branch is a list row (name + an inline summary badge of its saved
  cap, e.g. "Flat - 150 PHP", or "No cap saved yet") with a single "..."
  menu offering **Configure**, which opens the cap type/value form (the
  existing `PromoCapCard`, simplified to drop its own card chrome/heading
  now that the modal owns the title) in a `Modal`.
- A `SearchSortBar` (search by branch name, sort A-Z/Z-A) plus a Cap type
  filter (All/Percentage/Flat/Number of promos) sit above the list - reusing
  the existing `useSearchAndSort` hook, the same one
  ReceptionistBookingsQueue/HotelBookingPicker/CatalogAdminPage already use,
  rather than hand-rolling another filter implementation.
- `PromoCapCard.tsx` dropped its `scopeLabel` prop and outer `<article>`
  card wrapper/heading - it's rendered as the modal's body now, so the scope
  name lives in the modal's title instead.

### "Manage availability" -> "Branch Availability", now with search/filter/sort

- `BranchAvailabilityModal` (Services, Packages) renamed its title/menu
  label from "Manage availability" to "Branch Availability" and gained the
  same `SearchSortBar` (search branch name, sort A-Z/Z-A) plus a Status
  filter (All/Available only/Unavailable only) - mostly future-proofing
  today's 2-branch reality, but a consistent affordance across every caller
  per the request, including Packages' single-row case.

### Service Types: real per-branch availability replaces global Deactivate

- New table `service_type_branch_availability` (migration
  `20260818133_custom_service_type_branch_availability.sql`), mirroring
  `service_branch_availability` exactly: `(service_type_id, branch_id,
is_available)`, seeded `true` for every existing (type, branch) pair,
  same "any authenticated user can read, Admin/Superadmin write" RLS shape
  as `service_types` itself (the booking flow will eventually need to read
  this too, even though it isn't wired into booking behavior yet - same
  "documented, not hidden" caveat as the rest of this page's own copy).
- New endpoint: `PATCH /maintenance/service-types/:id/branch-availability`
  (`setServiceTypeBranchAvailabilityController` /
  `setServiceTypeBranchAvailability` service function), same shape as the
  services endpoint, reusing the existing generic `branchAvailabilityValidator`.
- `AdminServiceTypesPage.tsx` now fetches branches and swaps the
  Activate/Deactivate menu action for **Branch Availability**, opening the
  same `BranchAvailabilityModal` used by Services/Packages. `is_active`
  stays a real column (still what the booking flow's service-type list
  ultimately reads) but is no longer settable from this page - same
  precedent as Services' own Revision 1 change.

### Packages: same Branch Availability treatment (still a single-row modal)

No structural change beyond the rename/search-sort above - a Package row
still only ever has one branch (MA22), so its Branch Availability modal
still shows one row, toggling `is_active`.

### ToggleSwitch: long-label toggles could visually compress under a narrow Modal

You flagged "Derive price from weight/coat matrix..." (Packages/Services)
and "Requires an assessed pet..." (Services) as rendering like radio buttons
instead of sliders, while the much shorter "Requires a downpayment..."
toggle (identical component) rendered correctly. All three already used the
same `ToggleSwitch` component - tracing the CSS, `.trackOn`/`.trackOff`
(the 40x22px pill) had no `flex-shrink: 0` inside `ToggleSwitch`'s flex row,
so a very long label - now confined to the new, narrower `Modal` (32rem)
instead of the old full-width page - could pressure the flexbox layout into
shrinking the track down from its intended pill shape. Fixed in
`ToggleSwitch.module.css`: `flex-shrink: 0` on the track (never compress
below 40x22px) and `min-width: 0` on the label (lets it wrap freely instead
of fighting the track for space). No browser was available in this
environment to visually confirm the before/after, so please sanity-check
this live in your own dev server.

## Verification steps

1. **DB**: apply both new migrations (`supabase db reset` locally, or
   `supabase migration up` against your local Postgres). Then, in the
   Supabase SQL Editor, run
   `promo-cap-count-and-services-actions-menu.sql` section by section and
   confirm each section's stated expectation (the `count` enum value; the
   new `service_type_branch_availability` table, seeded true for every
   existing type x branch pair; its RLS policies).
2. **Server unit tests**: from `server/`, run
   `npx vitest run src/features/maintenance/modules/validators/maintenance.validator.spec.ts src/features/billing/services/discountPromoEvaluation.service.spec.ts src/features/maintenance/services/promoCap.service.spec.ts src/features/maintenance/services/serviceTypes.service.spec.ts`
   - all should pass, including the new count-cap and service-type
     branch-availability cases.
3. **Client unit tests**: from `client/`, run
   `npx vitest run src/features/maintenance/pages/AdminServicesPage src/features/maintenance/pages/AdminServiceTypesPage src/features/maintenance/pages/AdminPackageBuilderPage src/features/maintenance/pages/AdminPromoConfigPage src/features/maintenance/components/PromoCapCard src/features/maintenance/components/BranchAvailabilityModal`
   - all should pass.
4. **Manual - Promos config page** (`/staff/admin/maintenance/promos`, signed
   in as Admin/Superadmin):
   - "Promo Cap Configuration" is now a plain list of branches (Makati,
     Southwoods) - no "Both branches (system-wide default)" card.
   - Each row shows a summary badge of its saved cap (or "No cap saved
     yet"). Search narrows by branch name; the Cap type filter narrows to
     Percentage/Flat/Number of promos; sort toggles A-Z/Z-A.
   - "..." > Configure opens a modal with the Cap type/Cap value form;
     switching Cap type to "Number of promos" relabels the value field and
     enforces a whole number; Save persists and closes the modal.
5. **Manual - Services tab** (`/staff/admin/maintenance/services-and-packages`):
   - Each row shows only a single "..." button - no inline branch toggles,
     Edit button, or Disable toggle on the row itself.
   - "..." > Configure opens the edit form in a centered modal over the
     list (list does not shift/push down); Save/Cancel/backdrop-click all
     close it. Open a service with a long weight/coat-matrix or
     assessed-pet label and confirm both toggles render as a clear pill
     switch, not a compressed circle.
   - "..." > Branch Availability opens a modal listing Makati and
     Southwoods, each with its own toggle, plus search/status-filter/sort
     controls; flipping a toggle updates immediately.
6. **Manual - Service Types tab**:
   - "..." > Configure opens a modal with Name/Staff picker/Cage picker;
     saving renames and/or updates the toggles in place.
   - "..." > Branch Availability (not Activate/Deactivate anymore) opens
     the same branch-list modal as Services, with its own search/filter/
     sort; toggling Southwoods off for a type leaves Makati untouched (a
     real per-branch table now, not the shared Active flag).
7. **Manual - Packages tab**:
   - "..." > Configure opens the build/edit form in a modal, same as
     Services. Confirm the "Derive from weight/coat matrix" toggle in both
     Create and Edit renders as a clear pill switch, not a compressed
     circle.
   - "..." > Branch Availability opens a modal with the package's one
     branch and a toggle that deactivates/reactivates it, plus the same
     search/filter/sort controls (largely inert with only one row, but
     present for consistency).
   - "..." > Archive only appears once a package is Inactive.
8. **Postman**: import
   `promo-cap-count-and-services-actions-menu.postman_collection.json`, fill
   in `admin_identifier`/`admin_password` (an Admin or Superadmin account)
   and `staff_identifier`/`staff_password` (any other staff role), run the
   collection top-to-bottom against a local server - all 9 requests should
   pass their embedded tests.
