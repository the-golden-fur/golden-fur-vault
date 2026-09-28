---
title: One consistent "..." menu for admin config rows, and search/sort/filter/group/view tools plus a visible "..." for customer My Bookings
date: 2026-09-28
tags: [session-plan, golden-fur]
project: golden-fur
session: 116-config-row-menus-and-my-bookings-controls
branch: staged on dev (branch to be created when the user asks)
---

# 116 — One consistent "..." menu for admin config rows, and better My Bookings

## What you asked for

Two related clean-ups. First, make the "..." (three-dot) menu on every row in the admin Config settings offer the same core choices. Second, let customers cancel bookings from their My Bookings page with a proper menu and the same search/sort/filter tools the rest of the app has.

> Make … button options consistent alongside all rows in admin config settings, it should usually contain configure, rename, archive. Remove deactivate, rename edit to configure. Deactivate is removed since that's already handled by branch availability section in configure form modal or via archive.
>
> As a customer, I want to be able to cancel my bookings instead of waiting for it to be confirmed, I want to be able to cancel it even when it's confirmed in my bookings page. Add … button options. Add search, sort, filter, group by and view options.

The source is the "Tasks / Development" table in `shared/context/Architectural-Change-History.pdf` (the In Progress item assigned to Matthew).

## What this part of the app does today

A few terms first. **Admin Settings → Config** is the area where an Admin or Superadmin sets up the business: cages, pet types, breeds, services, service types, packages, promos, discounts, spin-wheel rewards, reward pools, branches, and the product catalog. Each of those pages lists its items as rows (or cards). Every row has a **"..." menu** (three dots) with actions. **Archiving** means hiding a record from normal use without destroying it, so it can be restored later; archived records live in Settings → Config → Archive.

Today those menus disagree with each other:

- Some say **Edit**, some say **Configure**, one page has both.
- Some have **Deactivate / Activate**, some don't.
- Some have **Archive**, but only when the row is already deactivated (the server refuses to archive something still active).
- Cages, Pet Types and Breeds have **Delete** (a permanent removal) but no Archive at all.
- Services and Service Types have no archive or delete.
- Rename exists only on Pet Types and Breeds.

The customer-facing **My Bookings** page (`/portal/bookings`, file `client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`) is a plain list of the customer's bookings. Actions (View details, Reschedule, Cancel) are hidden behind a right-click or a long press, so most people never find them. There is no search, sorting, filtering, grouping or view switching. The server already allows a customer to cancel a booking that is waiting or paid-and-confirmed ("Pending") or currently being served ("In Progress").

## What's wrong / what's missing

- An admin cannot predict what a "..." menu will offer; the same job is done differently on every page.
- Deactivating something and archiving it are two steps that overlap with the "Branch availability" section already inside each Configure form.
- Several things (cages, pet types, breeds, services, service types) cannot be archived at all.
- A customer looking at My Bookings sees no "..." button and no way to find one booking among many.

## What we're going to change

**Part A — the admin config menus**

1. **A shared Rename pop-up.** _Which files:_ new `client/src/shared/components/RenameModal/` — _Why:_ Rename needs to work the same way on every page, so we build one small pop-up (one text box, Save, Cancel) instead of ten different ones.
2. **Same three core items everywhere: Configure, Rename, Archive.** _Which files:_ the admin pages for Cages, Pet Types, Breeds, Services, Service Types, Packages, Promos (and the promo card), Discounts, Rewards, Reward Pools, Branches and the Product Catalog — _Why:_ this is the request itself. "Edit" becomes "Configure"; "Deactivate/Activate" is removed. Useful extras stay (Branch Availability, Mark Under Maintenance). On the Branches page, "Configure" keeps opening that branch's Policies page, the old "Edit" details form becomes "Details", and "Rename" renames only.
3. **Archive works on active items.** _Which files:_ the archive code in `server/src/features/*` for products, branches, rewards, reward pools, promos, discounts and packages — _Why:_ with Deactivate gone, nobody could ever archive an active item under the old "deactivate first" rule. Archiving now hides and deactivates in one step, after a "Are you sure?" confirmation.
4. **Give five more things an Archive.** _Which files:_ a new database migration `supabase/migrations/20260928218_custom_config_entities_add_archive_columns.sql` (adds an `archived_at` column to cages, pet types, breeds, services, service types), plus their server code, plus new tabs on the Archive page `client/src/features/staff/pages/AdminArchivePage/` — _Why:_ every row should really be able to do "Archive" and later "Restore" or "Delete permanently".
5. **Hide archived things where customers choose.** _Which files:_ the booking flow, cage assignment and capacity counting, and the pet/breed/service pickers — _Why:_ an archived cage must not be counted as space, and an archived service must not be bookable. Old bookings and pets that used an archived thing must still show its name.

**Part B — customer My Bookings**

6. **A visible "..." menu and the shared tools.** _Which files:_ `CustomerBookingsPage.tsx` plus a new `bookingBrowserFields.ts` next to it — _Why:_ copy the pattern already used on the pet manager page: search box, filter and sort "pills" (small removable tags), Group by, and a view switcher (table, list, gallery, board, calendar). The "..." button shows on table and list rows; on gallery, board and calendar cards it opens by right-click or press-and-hold. It offers View details, Reschedule and Cancel.
7. **Cancel stays available for confirmed bookings.** _Why:_ the server rules already allow it, so the change is only in the screen. No server change for cancelling.

## Words you might not know

- **migration** — a small SQL file that changes the database's structure (here, adding a column). It runs once, in order.
- **RLS (row-level security)** — database rules about which rows each user may read or change. This work does not change them.
- **archived_at** — a timestamp column; empty means "not archived", filled means "archived at that moment".
- **modal** — a pop-up box over the page that must be answered before carrying on.
- **CRUD-style guard** — a check in server code that refuses an action (here: "must be deactivated before archiving") which we are removing for most items.
- **pill** — a small removable tag showing an active filter or sort, like in Notion.
- **capacity** — how many pets a branch can take at once; cages that are archived must not count toward it.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (to be written when the work is implemented). In short: every config row shows Configure / Rename / Archive, archiving an active row moves it to the Archive page and Restore brings it back, and a customer can cancel a booking from a "..." menu on My Bookings and filter and group their bookings.
