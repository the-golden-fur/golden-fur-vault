---
title: Give Staff Management and Customer Management full Gallery/Table/List/Board views
date: 2026-09-20
tags: [session-plan, golden-fur]
project: golden-fur
session: 111-staff-customer-view-options
branch: feat/staff-customer-view-options (merged into dev via PR #196)
---

# 111 — Give Staff Management and Customer Management full Gallery/Table/List/Board views

## What you asked for

A back-to-back pair of requests for the same upgrade on two pages, then two
rounds of polish once the first version was in front of a real screen:

> add the view options to staff management page
> table, list, gallery, board
> default gallery
> add ... button, move actions there
>
> extend group by options
> add group by [PROPERTY], sort options for it (e.g. alphabetical, manual, etc.)

> do the same for customer management page
> add the missing notion features, search, sort, filter, group by, view options

> board view looks a bit broken when there's too many group by options
> fix its responsiveness
> also make it so that the ... button is not visible when in board or gallery view
> replace it with a right click on desktop, or tap in mobile, both opens the options menu (from ... button)

> staff management page > board view still broken
> cards should fit inside the group by option
> also the manual sort option in group by should make the group by columns draggable to the side
> also what does the resend account email button do?
> for now move it to the ... options

## What this part of the app does today

**Settings > Staff Management** and **Settings > Customer Management** are
the two admin/receptionist-facing directories for staff accounts and
customer accounts. A previous session (110, `Projects/golden-fur/sessions/110-notion-style-list-views/`)
already gave both pages a lighter "Tier 2" pass — a search box, filter
pills, and sort, using the shared `FilterSortBar` component — but
deliberately **without** a view switcher, a Kanban-style board, or "group
by," since that earlier pass judged these two pages as directories rather
than collections that would benefit from a board.

`client/src/shared/components/` already had, from that same earlier
session: `DataTable` (a reusable spreadsheet-style table), `DataList` (a
reusable stacked-card list), `DataBoard` (a reusable Kanban board — one
column per group, cards inside), and `useGroupBy` (a hook that splits a
list into labeled buckets by whatever rule a page picks, e.g. "by Role").
`ViewSwitcher` is the small Table/List/Board/Gallery toggle control several
other pages already use. None of these four pieces were wired into Staff
Management or Customer Management yet — this session's request was to add
that missing layer to exactly those two pages, then fix what broke once
the Board view had a real number of groups (8 Role columns) on a real
screen.

## What's wrong / what's missing

- Staff Management and Customer Management only offered one fixed layout
  (a card grid for Staff, a plain list for Customers) — no way to see them
  as a spreadsheet-style table, a Kanban board grouped by Role/Branch (or
  Status/Sign-in method for customers), or to choose how those groups sort.
- Once a Board view existed with many groups (e.g. all 8 staff Roles), the
  board didn't fit the screen and cards inside a narrow column shrink-
  wrapped to their own fixed minimum width instead of using the column's
  actual space, so long names truncated even though there was visible room.
- Every card in Board/Gallery view showed a permanent "..." button for its
  actions — with several cards per column this reads as visual noise, and
  it was asked to disappear in favor of a right-click (desktop) or a
  press-and-hold (touch) gesture instead, matching how a real Kanban board
  usually works.
- "Sort groups: Manual" didn't actually let you put columns in your own
  order — it just meant "don't re-sort them," with no way to rearrange them
  at all.
- Every `StaffCard` always showed a "Resend account email" button, whether
  or not it was actually relevant to what you were doing on that card,
  further crowding the Board/Gallery cards this session was already fixing
  the fit of.

## What we're going to change

1. **View switcher + Board/group-by on both pages** — _Which files:_
   `client/src/features/staff/pages/StaffManagementPage/`,
   `client/src/features/staff/pages/CustomerManagementPage/`, each gaining
   a small `*BrowserFields.ts` adapter (group-by axes, matching the
   pattern every other migrated page already uses) — _Why:_ the actual ask,
   reusing the four shared pieces session 110 already built rather than
   writing page-specific versions.
2. **A "Sort groups" control with a real Manual mode** — _Which files:_
   `client/src/shared/hooks/useGroupBy/useGroupBy.ts` (`GROUP_SORT_MODE_OPTIONS`,
   `sortGroupByAxis`) — _Why:_ needed by both pages, so it's a shared hook
   addition, not duplicated per page.
3. **A right-click/long-press action menu for Board and Gallery cards** —
   _Which files:_ new
   `client/src/shared/components/MoreOptionsMenu/CardContextMenu.tsx` (a
   sibling of the existing button-triggered `MoreOptionsMenu`, sharing its
   menu markup/CSS, differing only in how it opens) — _Why:_ replaces the
   permanent "..." button specifically in Board/Gallery, while Table/List
   keep the original visible button (a table row doesn't have the same
   crowding problem a dense card grid does).
4. **Fix Board's fit at high group-by counts** — _Which files:_
   `client/src/shared/components/DataBoard/DataBoard.module.css` (a grid
   item defaults to refusing to shrink below its content's size, which was
   forcing the whole page to stretch instead of the board scrolling
   sideways on its own), plus
   `client/src/features/staff/pages/StaffManagementPage/StaffManagementPage.module.css`
   (a card was shrink-wrapping to its own fixed minimum width instead of
   filling its column) — _Why:_ two separate CSS bugs stacked on top of
   each other, both needed fixing for the board to actually look right
   with 8 Role columns on screen at once.
5. **Draggable columns in Manual sort mode** — _Which files:_
   `client/src/shared/components/DataBoard/DataBoard.tsx` (drag handlers on
   each column's header), `useGroupBy.ts` (`moveColumnBefore`, a small pure
   function that computes the new column order) — _Why:_ makes "Manual"
   mean something — drag a column header onto another to put it there.
6. **Move "Resend account email" into "Manage account"** — _Which files:_
   `client/src/features/staff/components/cards/StaffCard/StaffCard.tsx`
   (removed), `client/src/features/staff/components/forms/ManageStaffAccountForm/ManageStaffAccountForm.tsx`
   (added) — _Why:_ "Manage account" is already reached through every
   card's "..." menu and is already where every other account-level action
   (change role/branch, deactivate, archive) lives, so it's the natural
   home rather than inventing a new one — explicitly called out as a
   "for now" placement, not a final design decision.

## Words you might not know

- **Kanban board** — a way of showing a list as columns, one column per
  category (e.g. one column per Role), with each item as a small card —
  named after the physical sticky-note board it originally imitated.
- **Group by** — splitting a list into those labeled columns based on one
  chosen field (e.g. grouping staff by Role, or by Branch instead).
- **Adapter file** — a small file, one per page, describing that page's
  own columns/filters/sort/group-by choices to the shared, generic
  components, so the shared pieces themselves stay page-agnostic.
- **CSS Grid track / minmax()** — the layout system behind both the board's
  columns and each card's own sizing; `minmax(240px, 1fr)` means "never
  narrower than 240px, otherwise share the leftover space evenly" — the
  bug here was a card with its own fixed 260px minimum living inside a
  240px-minimum column, which didn't leave room for it.
- **Long-press** — holding your finger down on something (rather than a
  quick tap) as a deliberate, distinct gesture — used here so a normal tap
  still reaches buttons already inside a card (like "Resend account
  email" used to be) instead of a bare tap always opening a menu.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks. Implementation is
**done**: Gallery/Table/List/Board views on both pages (PR #196, merged
into `dev`), the right-click/long-press `CardContextMenu`, the DataBoard/
StaffCard fit fixes, draggable Manual-sort columns, and moving Resend
account email into Manage account are all landed and tested. Each round of
follow-up polish requested in this session's later messages updated this
same `testing.md` in place rather than creating a new session.
