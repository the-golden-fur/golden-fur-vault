# Config row menus (Configure / Rename / Archive) + customer My Bookings controls

Branch: staged on `dev` (no branch created yet - the user calls branch/commit/PR).

## The request, verbatim

> Make … button options consistent alongside all rows in admin config settings, it should usually contain configure, rename, archive
> Remove deactivate, rename edit to configure
> Deactivate is removed since that's already handled by branch availability section in configure form modal or via archive
>
> As a customer, I want to be able to cancel my bookings instead of waiting for it to be confirmed, I want to be able to cancel it even when it's confirmed in my bookings page
> Add … button options
> Add search, sort, filter, group by and view options

Source: the In Progress / Matthew item in `shared/context/Architectural-Change-History.pdf`.

## Decisions made with the user during planning

- **Archive works on active rows.** Archiving deactivates and archives in one step, behind a confirm dialog. The old "deactivate before archive" server guard was removed for products, branches, rewards, reward pools, promos, discounts and packages (staff, customers and pets keep it).
- **Archive was added for five more things** that had none: cages, pet types, breeds, services, service types (new `archived_at` column + Config > Archive tabs).
- **Branches:** Configure opens **one modal** (not a page) for that branch - its details (name, address, contact, timezone, vet flag, operating hours) and its booking policies together. The separate Details item is gone. Rename only renames. (Each half keeps its own Save button, since they write to different tables.)
- **Cages:** Configure opens a **modal** (label, size, pet types) instead of editing the row inline.
- **Branch Availability is gone from every admin config menu** (Services, Service Types, Packages, Promos, Discounts). Which branches an item is available at is edited inside Configure ("Available at"); the separate modal component was deleted.
- **Promos have no enable/disable toggle** (table, list, gallery card). Archive is the only "off" switch and Restore is the way back on.
- **My Bookings:** a visible "..." on table and list rows; right-click / press-and-hold on gallery, board and calendar cards.

## Deliberate deviations from the plan (worth knowing)

- **Promo restore re-activates the promo** (there is no toggle any more to do it). A spin-wheel promo re-runs the reward-pool check first and the restore is refused (400) if the pool is archived, inactive, or has nothing landable. Everything else that isn't derived from branch availability (products, branches, rewards, reward pools, pet types) is also re-activated on Restore; services, service types, packages and discounts recompute it from branch availability.
- **Government-mandated discounts (Senior Citizen / PWD) can now be renamed like any other.** Checkout used to find them by exact name, so the name was locked. New migration `20260928220_custom_discounts_add_mandated_kind.sql` adds `discounts.mandated_kind` (`senior_citizen` / `pwd`, backfilled from the seeded names); the eligibility gate (booking and misc-sale paths) now reads that, the server no longer rejects a rename, and the seed trio sets it. A renamed mandated discount still applies only to eligible customers.
- **Promos default to the Table view** (was Gallery). **List views** on Promos, Pet Types, Breeds, Services, Service Types and Packages now have a visible "..." AND right-click / press-and-hold (new shared `CardRowWithMenu`); Board and Gallery keep right-click / hold only.
- **Promo Cap Configuration** got the shared controls: search, Filter (cap type, cap value range), Sort (branch, cap value, cap type), Group by (cap type, in Board) and Table / List / Board views (new `PromoCapBrowser`).
- **Existing inactive rewards, reward pools and branches** can no longer be reactivated in place (Deactivate/Activate is gone); Archive then Restore re-activates them.
- **Cages and breeds only got `archived_at`** (no `is_active`) - cages already have their own `status`, breeds never had a toggle.
- The **hotel/cage capacity count now ignores archived cages**, and so do the cage grid, cage picker, cage assignment and `get_cage_occupancy_report`.
- The Reward Pools archive is refused (409) while a live spin-wheel promo still uses the pool; Services are refused (409) while a live package, promo or discount still uses them.
- Migration `20260927217` (misc-sale discount scope, from the earlier merged session 115) had never been pushed to the dev database; it was applied together with this session's two.

## What changed

### Database (applied to dev `hikgijuipymfghfuyrjv`; prod not touched)

- `20260928218_custom_config_entities_add_archive_columns.sql` - `archived_at` + partial index on `cages`, `pet_types`, `breeds`, `services`, `service_types`.
- `20260928219_custom_cage_occupancy_report_exclude_archived.sql` - `get_cage_occupancy_report()` skips archived cages.
- Reference copies of all three migrations are in `config-row-menus-and-my-bookings-controls.sql` next to this file. No seed changes needed (only `cages` is seeded; the new column is nullable).

### Server

- New archive / restore / list-archived / permanent-delete for cages (`/hotel/cage/...`), pet types, breeds, services, service types (`/maintenance/...`). `DELETE /:id` now archives; `DELETE /:id/permanent` is the real delete, only allowed once archived.
- `archivePatch()` helper in `server/src/shared/archive/archiveGuard.ts`; the deactivate-first guard removed for the seven entities above.
- Fixed a latent bug: the branch-availability toggles for services, service types, packages and discounts would have silently un-archived a row by recomputing `is_active`; they now refuse an archived row (409).
- Archived rows are excluded from booking, catalog, cage and capacity reads; the public catalog still resolves names of archived services inside packages.
- Archived pet types can't be attached to new cages, breeds or price overrides.

### Client

- New shared `RenameModal` and `useRenameAndArchive` hook (rename pop-up + archive confirm dialog).
- Every admin Config page now shows **Configure / Rename / Archive** (plus Mark Under Maintenance on Cages). Deactivate/Activate/Delete are gone. Pages: Cages, Pet Types, Breeds (now has Configure), Services, Service Types, Packages, Promos (+ promo card), Discounts, Rewards, Reward Pools, Branches, Product Catalog (now has a "..." menu).
- Config > Archive has new tabs: Cages, Pet Types, Breeds, Services, Service Types.
- `BreedSelect` keeps showing a pet's breed even after it is archived.
- **My Bookings** (`/portal/bookings`): search, Filter (status, service, branch, pet, payment, appointment date), Sort (appointment date, booked on, price, status), Group by (board), and five views (table, list, gallery, board, calendar). Reschedule now opens as one panel above the results instead of inside a row.
- Cancel needed **no server change**: the server already allows cancelling Pending (shown "Unconfirmed" or "Confirmed") and In Progress ("In service") bookings.

## Verification run

- Server: `npx vitest run` - 1291 tests pass; `tsc --noEmit`, eslint (0 errors), prettier clean.
- Client: `tsc -b` clean, eslint clean, prettier clean. `npx vitest run` - 1407 pass, **4 fail in files this work did not touch**: `staffAuth.api.spec.ts` (3) and `mfa.api.spec.ts` (1). They assert exact `fetch` arguments and were left failing by the previous commit `e2551c3` (auth freeze fix, #212), which changed those calls.
- Migrations pushed with `npm run supabase:push`; 20260927217, 20260928218, 20260928219 and 20260928220 are applied on the dev project.
- Seed tests (`npm run test:seed`): 35 pass.

## Click-by-click manual test

Log in with the dev accounts. Use an **Admin** for part A and a **customer** for part B.

### A. Config menus (Admin > Settings > Config)

1. Open **Cages**. On any row click the **...** button. Expect exactly **Configure, Rename** (plus **Mark Under Maintenance** / **Mark Available**) and **Archive**. No Edit, Delete or Deactivate. **Configure** opens a "Configure cage" modal with label, size and pet types.
2. Click **Rename**. A small pop-up shows the current name. Change it, click **Save**. The row shows the new name and a "Cage renamed." banner. Saving is disabled while the name is unchanged or empty.
3. Click **...** > **Archive**. A confirm dialog appears; **Cancel** does nothing. Click **Archive** again and confirm - the cage disappears from the list.
4. Try an **Occupied** or **Reserved** cage: **Archive** is not offered.
5. Go to **Config > Archive > Cages**. The archived cage is listed. Click **Restore** - it returns to the Cages page. Archive it again and use **Delete permanently** (a cage with stay history will be refused with a clear message).
6. Repeat the menu check on **Pet Types** (Configure opens the price override modal), **Breeds** (Configure edits name + pet type), **Services**, **Service Types**, **Packages**, **Promos** (also check the card/gallery view buttons), **Discounts**, **Rewards**, **Reward Pools**, **Branches** and **Product Catalog**. Each shows Configure, Rename, Archive - and **no Branch Availability** item anywhere.
   6a. On **Services / Service Types / Packages / Promos / Discounts**, click **Configure**: the form has an **Available at** branch selection. Untick a branch, save, and confirm the item is no longer offered at that branch. (A spin-wheel promo has no branch selection - it is customer-wide.)
   6b. **Promos** have no on/off switch in the table, list or gallery. Archive a promo, then Restore it from Config > Archive: it comes back **active**.
   6c. **Discounts**: Senior Citizen / PWD show Configure and Archive only; a custom discount also shows Rename.
   6d. **Branches**: click **...** > **Configure**. One page opens: "Configure branch" with the branch's details (change the address, click **Save details**) and, below, the Policies form for that branch. **Back to branches** returns to the list. **Add branch** still opens the details form in a modal.
7. **Archive an ACTIVE row** on Rewards, Reward Pools, Branches, Product Catalog and a spin-wheel promo. It should work directly (no "deactivate first" error).
8. **Blocked archives:** archive a Reward Pool that a live spin-wheel promo uses - expect a 409 message naming the promo. Archive a Service that is inside an active package - expect a message naming the package.
9. **Hidden from customers:** archive a Service, a Service Type, a Pet Type and a Breed, then as a customer start a new booking / add a pet - none of them is offered. Open an existing booking or pet that used them - the name still shows.
10. **Capacity:** archive an Available Hotel cage, then check the hotel booking cage picker and the Cage Occupancy report - the archived cage no longer counts.
11. Restore each from **Config > Archive** and confirm it returns (a promo comes back switched off - turn it on with its toggle).

### B. Customer My Bookings

1. Log in as a customer with several bookings (mix of unpaid online, paid, and one already being served). Open **My bookings**.
2. Default view is **List**: each row has a **...** button. Open it: **View details**, **Reschedule** (only a future Pending booking) and **Cancel**.
3. Cancel a **paid (Confirmed)** booking and an **unpaid (Unconfirmed)** one: the confirm dialog appears, **Keep booking** does nothing, **Yes, cancel** cancels it and shows the credit/forfeit message when a payment was made.
4. Switch to **Table**: **...** is the last column. Switch to **Gallery** and **Board**: no **...** button - right-click (or press-and-hold on a phone) a card to get the same menu. Switch to **Calendar**: bookings appear on their day; **Calendar range** switches Month/Week.
5. Type in the search box (a pet name, "Hotel", a branch, "Cancelled") - the list narrows. Clear it.
6. **Filter** > add Status, Service, Branch, Pet, Payment, or Appointment date and edit/remove the pill - the list follows.
7. **Sort** > choose Appointment date / Booked on / Total price / Status in either direction.
8. In **Board**, use **Group by** (Status, Service, Branch, Pet, Month) - columns regroup.
9. Choose **Reschedule** on a future Pending booking: the reschedule panel opens above the results; **Cancel reschedule** closes it.
10. Open `/portal/bookings?open=<a booking id>` - that booking's details open automatically.

### C. Follow-up checks

1. **Discounts:** Senior Citizen / PWD rows show Configure, Rename, Archive. Rename one (e.g. "Golden Years"), then check out a Cash booking as a customer who is NOT flagged senior/PWD: the renamed discount must NOT apply. Flag the customer as senior and it applies.
2. **Promos:** the page opens on **Table**. Switch to **List**: each row has a "..." and right-click / hold opens the same menu; **Gallery** cards have no "...".
3. **Promo Cap Configuration** (bottom of Promos): search a branch; Filter > Cap type / Cap value; Sort by cap value; switch to List (visible "...") and Board (group by cap type, right-click a card).
4. **Pet Types / Breeds / Services / Service Types / Packages** in **List** view: each row shows a "..." and also opens the menu on right-click.
5. **Branches > ... > Configure** opens a pop-up with the details form and the policies, not a page.
