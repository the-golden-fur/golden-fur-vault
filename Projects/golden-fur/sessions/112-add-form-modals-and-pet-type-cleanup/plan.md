---
title: Turn always-visible "Add" forms into pop-up modals, plus a Pet Types cleanup
date: 2026-09-20
tags: [session-plan, golden-fur]
project: golden-fur
session: 112-add-form-modals-and-pet-type-cleanup
branch: feat/admin-ui-modal-cleanup (golden-fur PR #197)
---

# 112 — Turn always-visible "Add" forms into pop-up modals, plus a Pet Types cleanup

## What you asked for

A batch of small admin-UI requests from the shared change log, then one
broadening instruction once the pattern was clear:

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

Two things happened only in conversation, not written in that log: when
asked how to remove the pet type "Key" field, the answer was "do the same as
what was done for other things that has key" (pointing at Service Types,
which already had this exact treatment); and partway through, the request
broadened to "search the entire codebase where the form fields are not
accessed via a button that opens a popup modal... apply that same uniform
change to those unmentioned components" — which is why six more pages ended
up changed beyond the four named above.

## What this part of the app does today

Golden Fur's staff-facing pages under **Settings → Config** (and a couple of
plain staff pages) each manage one kind of record — pet types, cages,
breeds, branches, staff accounts, customers, promos, spin-wheel rewards, and
catalog products. Every one of these pages used to put its "Add a new one"
form in a **section that was always on the screen**, sitting either above or
below the list — so even an admin who just wanted to glance at the existing
list had to scroll past (or visually skip) a whole form every time.

A **modal** is a small pop-up box that appears on top of the page with a
dimmed background behind it — the rest of the page is still there, just
temporarily unreachable until you close the box (by clicking its "X", by
clicking outside it, or, on the pages that already used one, by clicking a
form's own "Cancel" button). Golden Fur already had a shared `Modal`
component used elsewhere (e.g. for a customer's "Manage account" pop-up);
this session's job was to move eight-then-ten pages' "Add" forms into that
same modal, triggered by a button, instead of leaving the form permanently
visible.

Separately, the **Pet Types** admin page (Settings → Config → Pet Types) let
an admin create a "pet type" (today: Dog and Cat, but admin-manageable since
an earlier session) by typing both a **Name** ("Dog") and a **Key**
(`dog`) — a short internal code used only as the actual database link that
pets, breeds, cages, and price overrides all point to. The same page also
had an always-visible "Fixed price overrides" section: pick one branch from
a dropdown, then see every pet type's price for that one branch in a list.

The **customer portal**'s sidebar (the left-hand navigation a logged-in
customer sees) had a "Notifications" link and a "Credits" tile. The
customer portal's top navbar already has its own bell icon (opens a
notifications dropdown with a "View all" link) and its own credit-balance
pill (a small clickable badge showing how many credits the customer has,
linking straight to the Credits page) — so the sidebar entries were showing
the exact same two destinations a second time.

## What's wrong / what's missing

1. **The always-visible "Add" forms crowded every list page** — an admin
   opening Pet Types, Cages, Breeds, or any of the other pages saw a form
   first, the list second, whether or not they wanted to add anything.
2. **The "Key" field on Pet Types was confusing, developer-only detail
   leaking into an admin screen.** A person adding "Rabbit" as a new pet
   type had no reason to also invent and type a machine-readable code for
   it — that's exactly the kind of thing a computer should generate on its
   own, and Service Types (a very similar admin page) had already been
   fixed this same way.
3. **The old "Fixed price overrides" section worked backwards** from how an
   admin actually thinks about it — "pick a branch, then find my pet type in
   a list" instead of "pick my pet type, then set its price at each branch."
4. **The customer sidebar duplicated two links the navbar already offered**,
   just extra clutter with no extra function.

## What we're going to change

1. **Wrap ten pages' "Add" (or "Create"/"New") forms in the shared `Modal`
   component, opened by a button.** — _Which files:_
   `client/src/features/maintenance/pages/AdminPetTypesPage/AdminPetTypesPage.tsx`,
   `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx`,
   `client/src/features/maintenance/pages/AdminBreedsPage/AdminBreedsPage.tsx`,
   `client/src/features/maintenance/pages/SystemConfigurationPage/SystemConfigurationPage.tsx`
   (its existing toggle-open "+ Add branch" section became a modal instead),
   `client/src/features/staff/pages/StaffManagementPage/StaffManagementPage.tsx`
   ("Create staff account"),
   `client/src/features/staff/pages/CustomerManagementPage/CustomerManagementPage.tsx`
   ("New walk-in customer"),
   `client/src/features/maintenance/pages/AdminPromoConfigPage/AdminPromoConfigPage.tsx`
   ("New promo" — this one already opened via a button, it just wasn't a
   modal box yet),
   `client/src/features/rewards/pages/AdminSpinWheelConfigPage/AdminSpinWheelConfigPage.tsx`
   ("Add a reward"), and
   `client/src/features/catalog/components/CatalogAdminPage/CatalogAdminPage.tsx`
   (the shared "Add {item}" form used by the Product Catalog page, and any
   future page built on this same component). — _Why:_ the actual ask for
   Pet Types/Cages/Breeds, then the same fix applied everywhere else the
   same pattern existed, per the mid-task broadening.
2. **Remove the Key field from "Add pet type," generate it on the server
   instead.** — _Which files:_
   `server/src/features/maintenance/modules/validators/maintenance.validator.ts`
   (stops accepting `key` from the client),
   `server/src/features/maintenance/services/petTypes.service.ts` (now calls
   Node's `randomUUID()` to make one), `client/src/features/maintenance/maintenance.types.ts`
   (the `CreatePetTypePayload` type drops `key`),
   `client/src/features/maintenance/pages/AdminPetTypesPage/petTypeBrowserFields.ts`
   (removes the now-pointless "sort/search by Key" options). — _Why:_ exact
   same treatment Service Types already got — `key` still exists and still
   does its real job (the internal link other tables use), it's just never
   typed in or shown by a human any more. This also is most of what
   "simplify the labels" meant in practice: with Key gone, "Add pet type"
   is down to one plain field, **Name**.
3. **Replace Pet Types' plain Rename/Deactivate/Delete buttons with a
   "..." menu, and add "Configure" to it.** — _Which files:_ same
   `AdminPetTypesPage.tsx` (now uses the shared `MoreOptionsMenu` — a small
   "..." button that opens Rename/Configure/Deactivate/Delete), and a new
   `client/src/features/maintenance/components/PetTypePriceOverrideModal/`
   (component + stylesheet) — _Why:_ "Configure" is the requested new
   action; it opens a modal scoped to **one pet type**, listing every
   branch with its own price box and a search/sort toolbar (modeled on the
   existing `BranchAvailabilityModal`) — the "pick a pet type first, then
   see all its branch prices" shape the request asked for, replacing the
   old "pick a branch first" section entirely.
4. **Drop "Notifications" and "Credits" from the customer portal's
   sidebar.** — _Which files:_
   `client/src/features/customers/config/customerPortal.config.ts` — _Why:_
   both are already one click away from the navbar (the bell icon and the
   credit-balance pill), so the sidebar entries were pure duplication. This
   turned out to be customer-portal-only — the staff sidebar never had
   either entry, so nothing there needed to change.
5. **Follow-up: collapse Cages' three always-visible row buttons into a
   "..." menu too.** — _Which files:_
   `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx` and
   `AdminCagesPage.module.css`, with matching updates to
   `AdminCagesPage.spec.ts`. — _Why:_ this came after everything above was
   already implemented — the user looked at a screenshot of the live Cages
   page and pointed out that even though "Add cage" was now a modal (item 1
   above), each cage row still showed **Edit**, **Mark Under
   Maintenance**, and **Delete** as three separate always-visible buttons —
   the exact "every action gets its own permanent button" pattern this
   whole session was already fixing everywhere else (Services, Pet Types,
   Staff Management all use a single "..." button instead). So Cages got
   the same treatment: the three buttons became one **`MoreOptionsMenu`**
   ("...") button, in both Table and List view. A cage that's currently
   **Occupied** or **Reserved** simply doesn't get a Delete item in that
   menu at all — before, the same rule existed but showed Delete as a
   grayed-out/disabled button; `MoreOptionsMenu` items have no "disabled"
   look, so the convention this app already uses elsewhere is to leave an
   inapplicable action out of the list entirely, not gray it out.
   **Board view** is handled differently: since a card-grid view is dense
   and a "..." button on every card is visual noise (the same reasoning
   already applied to Staff/Customer Management's Board and Gallery views
   in session 111), the "..." button doesn't appear on Board cards at
   all — instead, right-clicking a card (or press-and-hold on a touchscreen)
   opens that same Edit/Maintenance/Delete list, using the shared
   `CardContextMenu` component already built for that earlier session.
   Cages has no Gallery view (only Table/List/Board), so Board was the only
   view needing this second treatment. Tests in `AdminCagesPage.spec.ts`
   were updated to match — opening the "..." menu instead of clicking a
   plain "Edit"/"Delete" button, and using `fireEvent.contextMenu` to
   exercise the Board right-click menu — and a leftover
   `.smallButtonDanger` CSS class was deleted since nothing renders a red
   "Delete" button on its own any more.

## Words you might not know

- **modal** — a small pop-up box that appears on top of a page with the
  rest of the page dimmed and temporarily unreachable behind it, closed by
  an "X" button, by clicking outside it, or by a form's own Cancel button.
- **key vs. name** — two different labels for the same row in a database
  table. **Name** ("Dog") is what a person reads. **Key** (`dog`) is a
  short code other parts of the system use internally to point at that
  same row — like a product's SKU number versus its shelf label. This
  session made Pet Types' key invisible/auto-generated, the same way an
  earlier session already did for Service Types.
- **UUID** — a long, effectively-unique random ID (e.g.
  `f47ac10b-58cc-4372-a567-0e02b2c3d479`) a computer can generate on its own
  with no risk of accidentally reusing one — used here instead of asking an
  admin to type a made-up code.
- **price override** — instead of a service/package charging its normal
  price, charge one flat number instead, for a given pet type (optionally
  limited to one branch, or "all branches" as the default).
- **"..." menu / kebab menu** — a small button (three dots, or three
  vertical dots) that, when clicked, opens a short list of actions for that
  specific row/card, instead of showing every action as its own always-
  visible button.
- **right-click / long-press context menu** — the same short action list as
  a "..." menu, but opened a different way: right-clicking a card with a
  mouse, or pressing and holding it on a touchscreen, instead of clicking a
  visible button. Used on Board-view cards specifically, where a "..."
  button on every card would be too much visual clutter in a dense grid.
- **sidebar vs. navbar** — the navbar is the bar across the very top of the
  screen (present on every page); the sidebar is the vertical menu down one
  side, specific to whichever section of the app you're in (e.g. the
  customer portal has its own sidebar, separate from staff's).

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks. Implementation is
**done** and already verified by the person who made the change (client
`tsc -b` clean, server `tsc -b` clean, ESLint clean, Prettier clean, full
server suite passing, full client suite passing) — this session's job was
writing the record, not re-running those suites.
