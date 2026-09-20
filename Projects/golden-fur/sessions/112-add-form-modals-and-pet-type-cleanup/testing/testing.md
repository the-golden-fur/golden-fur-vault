# Move ten "Add" forms into pop-up modals, plus a Pet Types Key/Configure cleanup

Branch: `feat/admin-ui-modal-cleanup` (golden-fur PR #197). The work was
implemented as uncommitted changes sitting directly on `dev` (HEAD was
`ca026d0`, the already-merged tip of PR #196) before being branched out and
committed. This is a **separate, unrelated request thread** from session
`111-staff-customer-view-options`, which used the `feat/staff-customer-view-options`
branch for its own (different) Kanban/view-options feature - that branch
still exists (already squash-merged into `dev` via PR #196, not deleted);
this session just happened to pick up from the same repo state afterward,
before its own new branch was cut.

## The request, verbatim

> As an admin/superadmin, I want the Add pet type form to only appear as a
> modal when button is clicked
>
> I want all the label captions to be simplified as well, understandable by
> laypeople
>
> As a developer, I want the Key field removed, use Name instead if it's
> referenced in the codebase
>
> Add a Configure option in … button
>
> It should open up a modal that prompts the user to set the price override
> and in what branches (apply the same search, views, … button and other
> controls to this as well)
>
> As an admin/superadmin, I want the Add Cage form to only appear as a modal
> when Add Cage button is clicked
>
> As an admin/superadmin, I want the Add Breed form to only popup as a modal
> when Add Breed button is clicked
>
> As a frontend designer, I want the Notifications page from the sidebar
> removed, since there's already one in the navbar
>
> As a frontend designer, I want the Credits tile in the sidebar removed,
> since there's already one in the navbar
> — Architectural-Change-History.docx, "In Progress" (Alarie)

**Scope note:** two things happened only in conversation, not recorded in
that log:

> [clarifying question: how should the Key field be removed?]
> do the same as what was done for other things that has key

(pointing at Service Types, which already had `key` generated server-side
rather than typed in — see "Root cause / Context" below.)

> search the entire codebase where the form fields are not accessed via a
> button that opens a popup modal... apply that same uniform change to those
> unmentioned components

which is why `SystemConfigurationPage` ("Add branch"), `StaffManagementPage`
("Create staff account"), `CustomerManagementPage` ("New walk-in customer"),
`AdminPromoConfigPage` ("New promo"), `AdminSpinWheelConfigPage` ("Add a
reward"), and the shared `CatalogAdminPage` component ("Add {item}") also
changed, beyond the four items the log explicitly named (Pet Types, Cages,
Breeds, sidebar).

Also, the "Notifications"/"Credits" sidebar removal turned out to apply only
to the **customer portal**'s sidebar — the staff sidebar never had either
entry, so nothing there needed changing.

## Root cause / Context

Ten admin/staff pages each kept their "Add a new record" form in an
always-visible section on the page (either permanently rendered, or toggled
open/closed in place) instead of behind a button that opens a pop-up. The
shared `Modal` component (`client/src/shared/components/Modal/Modal.tsx`)
already existed and was already used elsewhere (e.g. "Manage account"), so
this was a matter of moving each form's markup inside a `<Modal>` and adding
open/close state, not building anything new for that part.

Separately, Pet Types (`AdminPetTypesPage`) still asked an admin to type
both a **Name** and a **Key** when creating one — `key` is a short internal
code other tables (`pets`, `breeds`, `cage_pet_types`,
`pet_type_price_overrides`) use to reference a pet type row; it does real
work, but there's no reason an admin should ever have to invent one by
hand. **Service Types** (a very similar admin-CRUD page) had already been
fixed this exact way — `key` generated server-side via `randomUUID()`,
never shown or typed in the admin UI — so this session applied the same
fix to Pet Types.

Pet Types also had an always-visible "Fixed price overrides" section: pick
one branch from a dropdown, then see/edit a price box for every pet type at
that one branch. The request asked for the opposite shape — pick one pet
type's row (via its "..." menu's new "Configure" option), then see/edit its
price at every branch in one modal.

## What changed

### Database / Server

None — no migration. `pet_types.key` already existed as a plain text
column; this only changes **who fills it in** (the server via
`randomUUID()`, not the admin via a form field).

- `server/src/features/maintenance/modules/validators/maintenance.validator.ts`
  — `createPetTypeValidator` no longer accepts `key`, only `name`.
- `server/src/features/maintenance/services/petTypes.service.ts` —
  `createPetType` now calls `randomUUID()` (from `node:crypto`) to fill
  `key` instead of using the client-supplied value. The old
  "key already exists" 409 error is kept as defense-in-depth (practically
  unreachable with a random UUID) but no longer echoes back a
  client-supplied key in its message.

### Client — modal conversions (no behavior change to the forms themselves, only how they're reached)

Each of these ten files added a boolean `isCreateModalOpen`-style state,
wrapped the existing form (unchanged fields/validation/submit logic) in the
shared `<Modal>`, and added a title-row trigger button that opens it:

- `client/src/features/maintenance/pages/AdminPetTypesPage/AdminPetTypesPage.tsx`
  — "Add pet type" (see next section for the rest of this page's changes).
- `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx` —
  "Add cage" (cage label, size, pet types checkboxes — unchanged fields).
- `client/src/features/maintenance/pages/AdminBreedsPage/AdminBreedsPage.tsx`
  — "Add breed" (pet type dropdown, name — unchanged fields).
- `client/src/features/maintenance/pages/SystemConfigurationPage/SystemConfigurationPage.tsx`
  — "+ Add branch" used to be a button that toggled a section open/closed
  in place (its label flipped between "+ Add branch" and "Cancel"); it's
  now a fixed "+ Add branch" button that opens a modal instead, closing on
  submit.
- `client/src/features/staff/pages/StaffManagementPage/StaffManagementPage.tsx`
  — "Create staff account" is now a modal opened by a new title-row button
  (previously an always-visible section). **Deliberately does not
  auto-close on a successful create** — `CreateStaffAccountForm` shows a
  temporary-password fallback and a "Resend email" control right after
  success that the admin still needs to see/use, so closing it out from
  under them would hide that.
- `client/src/features/staff/pages/CustomerManagementPage/CustomerManagementPage.tsx`
  — "New walk-in customer" is now a modal opened by a new title-row button.
  Unlike Staff Management, this one **does** close automatically on a
  successful save, then opens the page's existing "Add a pet" follow-up
  panel (same behavior as before, just from a modal instead of an inline
  section).
- `client/src/features/maintenance/pages/AdminPromoConfigPage/AdminPromoConfigPage.tsx`
  — the "New promo" wizard (type-then-details, unchanged) already opened
  via a button and an `isFormOpen` flag; that flag now controls a `<Modal>`
  instead of an inline `<section>`.
- `client/src/features/rewards/pages/AdminSpinWheelConfigPage/AdminSpinWheelConfigPage.tsx`
  — "Add a reward" (label, discount type, value, rarity — unchanged
  fields) moved into a modal opened by a new button next to the "Reward
  pool" heading.
- `client/src/features/catalog/components/CatalogAdminPage/CatalogAdminPage.tsx`
  — the shared "Add {itemNoun}" form (name, category, service scope,
  price) moved into a modal opened by a new button — this is the component
  behind **Product Catalog** (Settings → Config → Product Catalog,
  `itemNoun="product"`); any other page built on this same shared
  component gets the same change automatically.
- Each page's `.module.css` gained the small layout classes this needed
  (`.titleRow`, `.titleRowActions`, `.button`) and lost anything that was
  only used by the old inline section (e.g. `AdminPromoConfigPage.module.css`
  dropped `.formPanel`; `AdminPetTypesPage.module.css` dropped `.itemKey`
  and `.priceInput`, both only used by things this session removed).

### Client — Pet Types page (the rest of its changes)

- `AdminPetTypesPage.tsx` — beyond moving "Add pet type" into a modal:
  - The **Key** input is gone from the Add form; the only field left is
    **Name**.
  - The **Key column** is gone from the pet types list/table, and the
    editing/list-item views no longer show a pet type's key next to its
    name.
  - Plain always-visible **Rename / Deactivate / Delete** buttons per row
    are replaced by a single `MoreOptionsMenu` ("...") offering **Rename,
    Configure, Deactivate (or Activate), Delete**.
  - The old always-visible **"Fixed price overrides"** section (branch
    dropdown + a price box per pet type + a search box) is gone entirely.
    **Configure** (new menu item) opens the new
    `PetTypePriceOverrideModal` instead, scoped to the one pet type whose
    "..." menu you opened.
- `client/src/features/maintenance/components/PetTypePriceOverrideModal/PetTypePriceOverrideModal.tsx`
  (new component) + matching `.module.css` — one modal, titled "Set price
  override – {pet type name}", listing every branch plus an "All branches
  (default)" row, each with its own price box, a **Save** button, and (only
  once that row has an override) a "..." menu with **Clear override**. Has
  its own search box (filters branches by name) and sort dropdown
  (Branch A–Z / Z–A) — modeled on the existing `BranchAvailabilityModal`.
- `client/src/features/maintenance/pages/AdminPetTypesPage/petTypeBrowserFields.ts`
  — the "sort by Key" and "search matches Key" options are removed (Key is
  no longer a thing to search/sort by, since it's never shown).
- `client/src/features/maintenance/maintenance.types.ts` —
  `CreatePetTypePayload` no longer has a `key` field (`PetTypeRow` itself
  still does — the server still returns it, since the rest of the app,
  e.g. Breeds' pet-type dropdown, still needs the key value internally).

### Client — customer portal sidebar

- `client/src/features/customers/config/customerPortal.config.ts` — the
  **Notifications** (`/portal/notifications`) and **Credits**
  (`/portal/credits`) entries are removed from `CUSTOMER_SIDEBAR_SECTIONS`.
  Both destinations are still reachable — the top navbar's bell icon
  (`NotificationBell`, with a "View all" link) and credit-balance pill
  (`CreditBalanceIndicator`) already link to the same two pages. The staff
  sidebar was not touched — it never had either entry.

### Client — Cages page (follow-up, after the rest of this session shipped)

Prompted by the user looking at a screenshot of the live Cages page and
asking for more, once every other page in this session already had its
"..." menu treatment:

- `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx` — the
  three always-visible row buttons (**Edit**, **Mark Under
  Maintenance**/**Mark Available**, **Delete**) are replaced by one
  `MoreOptionsMenu` ("...") in both **Table** and **List** view, built by a
  new `cageActionItems(cage)` helper. That helper leaves **Delete** out of
  the item list entirely for a cage whose status is **Occupied** or
  **Reserved**, instead of the old approach of still rendering a Delete
  button but disabling it — `MoreOptionsMenu` items have no disabled
  visual state, so omitting an inapplicable action is the convention this
  app already uses everywhere else (Services, Pet Types, etc).
- **Board view** specifically does not show the "..." button on its cards
  at all — a kebab button on every card in a dense grid was judged to be
  visual noise, the same call already made for Staff/Customer Management's
  Board/Gallery views in session 111. Instead, right-clicking a card
  (desktop) or press-and-holding it (mobile/touch) opens the same item list
  via the existing shared `CardContextMenu` component
  (`client/src/shared/components/MoreOptionsMenu/CardContextMenu.tsx`,
  built in that same earlier session). Cages has no Gallery view — only
  Table/List/Board — so Board was the only view that needed this second
  treatment.
- `AdminCagesPage.module.css` — the now-unused `.smallButtonDanger` class
  (only ever used by the old standalone Delete button) is deleted.
- `AdminCagesPage.spec.ts` — updated to open the "..." menu (`getByRole`
  on `Actions for {cage label}`) and click an item from it, instead of
  clicking a plain named button directly; a new test drives the Board-view
  path via `fireEvent.contextMenu` on a card instead of a click.

## Manual test — step by step

Both dev servers need to already be running (client on port 5173, server on
port 3000) — use the `dev-servers` check first rather than starting a
second copy of either. Log in as the role each section calls for.

### A. Pet Types — Add pet type modal, no more Key field

1. Log in as an Admin or Superadmin. Go to **Settings → Config → Pet
   Types** (`/staff/admin/maintenance/pet-types`).
2. Confirm the page shows a list of pet types (e.g. Dog, Cat) with **no
   "Add pet type" form visible anywhere on the page**, and no "Key" column
   in the list.
3. Click **Add pet type** (top-right of the page, next to the "Pet Types"
   heading). Confirm a pop-up box appears titled "Add pet type", dimming
   the rest of the page.
4. Confirm the modal has exactly **one** field, **Name** — no "Key" field
   anywhere.
5. Type a name (e.g. "Rabbit") and click **Add pet type** inside the
   modal. Confirm the modal closes, a "Pet type added." message appears,
   and "Rabbit" now shows up in the list — with no key visible next to it.
6. Click the "X" in a modal's corner (open "Add pet type" again first, if
   needed) — confirm it closes without saving anything.

### B. Pet Types — the "..." menu and Configure

1. Still on Pet Types, find any pet type row and click its **"..."**
   button. Confirm a small menu opens with **Rename, Configure,
   Deactivate (or Activate), Delete** — and that there are no separate,
   always-visible Rename/Deactivate/Delete buttons any more.
2. Click **Configure**. Confirm a modal opens titled "Set price override –
   {that pet type's name}", listing **All branches (default)** plus every
   real branch (e.g. Makati, Southwoods), each with its own empty or
   filled-in price box.
3. Type a number (e.g. `800`) into one branch's price box and click its
   **Save** button. Confirm a "Fixed price saved." message appears and
   that branch's row now shows a "..." menu with **Clear override**.
4. Use the modal's own search box to type part of a branch's name — confirm
   the list narrows to matching branches only. Try the sort dropdown
   (Branch A–Z / Z–A) — confirm the row order flips.
5. Click that row's "..." → **Clear override** — confirm the price box
   empties out and a "Fixed price cleared." message appears.
6. Close the modal (X or click outside it). Reopen **Configure** on a
   _different_ pet type — confirm it shows that pet type's own prices, not
   the one you just edited.

### C. Cages — Add cage modal

1. Go to **Settings → Config → Cages** (`/staff/admin/hotel/cages`), as
   Admin or Superadmin.
2. Confirm there's no "Add cage" form visible on the page itself. Click
   **Add cage** (top-right). Confirm a modal opens with **Cage label**,
   **Size**, and a **Pet types** checkbox list.
3. Fill in a label (e.g. "Makati-S-99"), pick a size, check at least one
   pet type, and click **Add cage**. Confirm the modal closes, a "Cage
   added." message appears, and the new cage shows up in the list.

### C.1 Cages — the "..." menu replaces the row buttons (Table/List), right-click replaces it on Board

1. Still on **Settings → Config → Cages**, in **Table** view, find any cage
   row that is **not** Occupied or Reserved (e.g. an Available or Under
   Maintenance one) and click its **"..."** button (far right of the row).
   Confirm a small menu opens with **Edit**, and either **Mark Under
   Maintenance** or **Mark Available** (whichever applies) — and that
   there's no longer a separate always-visible Edit/Delete/Mark button
   sitting in the row itself.
2. From that same menu, click **Edit**. Confirm the row switches into its
   inline edit form (label, size, pet-type checkboxes, Save/Cancel) exactly
   as before. Click **Cancel** to back out without saving.
3. Open the "..." menu again and click **Mark Under Maintenance** (or
   **Mark Available** if it was already under maintenance). Confirm the
   row's **Status** badge updates immediately, with no page reload.
4. Find (or put) a cage in **Occupied** or **Reserved** status. Open its
   **"..."** menu and confirm there is **no Delete option** in the list at
   all (not grayed out — simply absent). Confirm Delete _is_ present in the
   menu for a cage that's Available or Under Maintenance.
5. Switch to **List** view (via the view switcher) and repeat step 4 on the
   same two cages — confirm the "..." menu behaves identically there.
6. Switch to **Board** view. Confirm the cards are grouped into columns (by
   Status or Size, per the "Group by" dropdown) and that **no "..." button
   appears anywhere on any card**.
7. On a desktop browser, **right-click** any card. Confirm the same
   Edit/Mark/Delete menu (with the same Occupied/Reserved Delete rule from
   step 4) pops up at the click location. Pick **Edit** from it and confirm
   the card switches into the same inline edit form used elsewhere.
8. On a touchscreen device (or your browser's device-emulation mode),
   **press and hold** a card instead of right-clicking. Confirm the same
   menu appears after the hold, rather than nothing happening or the page
   scrolling/selecting text.

### D. Breeds — Add breed modal

1. Go to **Settings → Config → Breed Management**
   (`/staff/admin/maintenance/breeds`), as Admin or Superadmin.
2. Click **Add breed** (top-right). Confirm a modal opens with a **Pet
   Type** dropdown and a **Name** field.
3. Pick a pet type, type a name (e.g. "Shih Tzu"), click **Add breed**.
   Confirm the modal closes and the new breed appears in the list.

### E. System Configuration — Add branch modal

1. Go to **Settings → Config → System Configuration**
   (`/staff/admin/maintenance/system-configuration`) as a **Superadmin**
   (this page is Superadmin-only — an Admin should not see it as an
   option).
2. Click **+ Add branch**. Confirm a modal opens (previously this same
   button toggled a section open in place and changed its own label to
   "Cancel" — now it always says "+ Add branch" and opens a pop-up
   instead).
3. Fill in the branch name and other fields, submit. Confirm the modal
   closes, the new branch appears in the branch dropdown below, and a
   "Branch added..." message appears.

### F. Staff Management — Create staff account modal

1. Go to **Staff Management** (`/staff/admin/staff`) as Admin or
   Superadmin.
2. Confirm there's no "Create staff account" section always on the page.
   Click **Create staff account** (top-right, next to "View archive").
   Confirm a modal opens with the account-creation form.
3. Fill in the form and submit successfully. Confirm the **modal stays
   open** afterward (this is deliberate) and shows the temporary-password
   fallback / "Resend email" control the form already had — close the
   modal yourself with the "X" once you're done reading it.

### G. Customer Management — New walk-in customer modal

1. Go to **Customer Management** (`/staff/admin/customers`) as
   Receptionist, Supervisor, Admin, or Superadmin.
2. Click **New walk-in customer** (top-right, next to "View archive" if you
   have Admin/Superadmin). Confirm a modal opens with the walk-in customer
   form.
3. Fill it in and save. Confirm the **modal closes automatically** this
   time, a "Customer saved. Add a pet below if needed." message appears,
   and the existing "Add a pet" panel opens for that new customer, same as
   before this change.

### H. Promos — New promo modal

1. Go to **Settings → Config → Promos** (`/staff/admin/maintenance/promos`)
   as Admin or Superadmin.
2. Click **New promo** (this button already existed before this change).
   Confirm the type-selection step ("Date range" vs. "Weekly recurring")
   and the details step both now appear inside a pop-up modal rather than
   an inline page section, and that **Cancel** at either step still closes
   it without saving.

### I. Spin Wheel — Add a reward modal

1. Go to **Settings → Config → Coupon Spin Wheel**
   (`/staff/admin/spin-wheel-config`) as Admin or Superadmin.
2. Confirm the "Reward pool" section no longer has an always-visible "Add a
   reward" form beneath it. Click the new **Add a reward** button next to
   the "Reward pool" heading. Confirm a modal opens with Label, Discount
   type, Value, and Rarity fields.
3. Fill it in and submit. Confirm the modal closes and the new reward
   appears in the reward pool.

### J. Product Catalog — Add product modal

1. Go to **Settings → Config → Product Catalog**
   (`/staff/admin/product-catalog`) as Admin or Superadmin.
2. Click **Add product** (top-right, next to "View archive"). Confirm a
   modal opens with Name, Category, Service scope, and Price fields
   (including each dropdown's "Other (custom)..." option that reveals a
   free-text box).
3. Fill it in and submit. Confirm the modal closes and the new product
   appears in the catalog list.

### K. Customer portal sidebar — Notifications/Credits removed

1. Log in as a **customer** (not staff) and land on the customer portal.
2. Look at the left-hand **sidebar**. Confirm it no longer lists
   "Notifications" or "Credits" as entries — it should go straight from
   whatever's above them to "Book a Service", "My Bookings", etc.
3. Look at the **top navbar** instead — confirm the bell icon still opens a
   notifications dropdown (with a "View all" link), and the credit-balance
   pill still links to the Credits page — both destinations are still one
   click away, just not duplicated in the sidebar too.
4. As a sanity check, log in as **staff** instead and confirm their sidebar
   is unchanged — it never had a Notifications or Credits entry to begin
   with.

## Test suites

Reported by the implementer as part of this same change (not independently
re-run for this record, per this session's own scope — documentation only):

- Client: `tsc -b` — clean, no errors.
- Server: `tsc -b` — clean, no errors.
- ESLint — clean on all touched files, both client and server.
- `prettier --check` — clean.
- Server: full test suite — **1176/1176 passing**.
- Client: full test suite — reported as passing; 3 pre-existing tests
  unrelated to this change timed out under full-suite resource contention
  but passed cleanly when re-run in isolation (not caused by this change).
  No exact pass/fail count was provided for the client run in this session
  — if an exact number is needed, re-run `npx vitest run` from `client/`.
- Cages "..." menu follow-up specifically: typecheck and lint reported
  clean by the implementer, and the full `AdminCagesPage.spec.ts` file —
  **22/22 passing** — was re-run in isolation after the update (not the
  full client suite, since this was a small, scoped follow-up rather than
  the whole session).

## Open items

- The client test suite's exact pass/fail count wasn't captured verbatim
  this session (only "passed, with 3 unrelated flaky timeouts under full-
  suite load" was reported) — re-run `npx vitest run` if a precise number
  is needed before a PR.
- This work is currently **uncommitted, directly on `dev`** — no feature
  branch has been created for it yet (see "Branch" above).
