---
title: Give every database-record list a consistent, Notion-style browsing toolbar
date: 2026-09-18
tags: [session-plan, golden-fur]
project: golden-fur
session: 110-notion-style-list-views
branch: not yet created (a branch gets cut via the branch-naming skill once implementation starts)
---

# 110 — Give every database-record list a consistent, Notion-style browsing toolbar

## What you asked for

> As a developer, I want a consistent, Notion like interface (I want these to
> resemble Notion like interface (where adding a filter, sort, etc. creates
> pills that can be edited and removed), search, sort, filter, group by
> options to all things that reference tables from the database.
> Include view options as well inspired by Notion (table, list, board/kanban,
> calendar with month or week view if table has dates).

Plus, on scope: rather than being asked what to include, I was asked what to
exclude, and to otherwise touch everything that fits the condition (any page
whose data comes from a GET request to the database). The related "Ideas"
backlog entries in `Projects/golden-fur/shared/context/Architectural-Change-History.docx`
name specific pages this should reach: Pet Types, Cages, Breeds, Discounts,
the Coupon Spin Wheel reward pool, Food/Medication types, the customer Pets
page, the booking-process services/packages and cage-selector steps, and a
customer Rewards/Inventory page (default grouped by reward type).

## What this part of the app does today

Golden Fur has dozens of pages — mostly under Settings > Config for admins,
plus staff queues and customer account pages — that each fetch a list of
rows from the database (a "GET request": the browser asking the server for
data without changing anything) and show it as a table or a list. Right now
every one of these pages writes its own table/list markup from scratch, and
most have little or no way to search, sort, or filter what's shown.

One page has already gotten a taste of what's being asked for here: the
Cashier's **Transactions** page (and the matching customer-facing
**My Transactions** page) already has a small reusable piece,
`client/src/shared/components/FilterSortBar/FilterSortBar.tsx`, that renders
a **pill** (a small rounded button, sometimes called a "chip" — the little
"Status: Paid ✕" shape you'd see in Notion or a filter UI) for every active
filter or sort. Clicking the pill's body reopens an editor for it; hovering
reveals an "✕" to remove it. There's also
`client/src/shared/components/ViewSwitcher/ViewSwitcher.tsx`, a segmented
button group for switching between a **table view** (rows and columns, like
a spreadsheet) and a **board view** (a Kanban-style board — cards arranged
in columns, like sticky notes on a wall, one column per status).

A second page, the Admin **Archive** (deleted-records browser), already has
the equivalent on the server side — its `GET /staff/deleted-records` request
already accepts search text, a date range, a sort order, and pagination —
but its front end still uses plain HTML dropdowns instead of the pill-style
`FilterSortBar`, so it doesn't look or feel like the Transactions page.

Everywhere else — Pet Types, Cages, Breeds, Discounts, Promos, the Product
Catalog, Services & Packages, the customer's Pets page, and many more — the
page fetches its rows and just prints a plain `<ul>` list or `<table>`, with
at most a single hand-rolled search box. There is no shared "group by"
feature (splitting a list into buckets, like grouping bookings by branch)
anywhere except one very page-specific implementation inside the hotel's
Boarding Checklist kanban board. There is also no reusable "calendar" view
(a month or week grid, each day showing the items that fall on it) anywhere
except the Monthly Schedule page, and that one is written entirely for that
one page — none of its code can currently be reused elsewhere.

## What's wrong / what's missing

- A staff member using Pet Types, Cages, Breeds, or any of the ~15 similar
  admin lists gets a different, more primitive experience than they'd get on
  Transactions — no filter pills, often no sort, and no way to switch
  between a table, a card-style list, or a board.
- A customer browsing their Pets, their Food & Medication items, or their
  Rewards/Inventory has no search, filter, sort, or grouping at all once the
  list grows past a handful of items.
- There's no shared "group by" building block, so every page that might want
  one (e.g., "group my rewards by type," which is explicitly requested)
  would have to invent it from scratch, the way Boarding Checklist did.
- There's no reusable calendar component, so a "see my bookings by month"
  view can't be added anywhere without first copying and adapting the
  Monthly Schedule page's one-off calendar code.
- The Archive page has the pill-capable backend already but the old-style
  dropdown front end, so it visually doesn't match Transactions even though
  it easily could.

## What we're going to change

This plan **only covers the design** — no code changes are part of this
session. It leaves behind a rollout plan for whoever (or whichever future
session) implements it. The approach, in order:

1. **Keep it client-side.** No changes to the server's `GET` endpoints or
   how they query the database. Every page keeps using its existing
   endpoint; filtering, sorting, and grouping all happen in the browser
   after the data has already been fetched — exactly how Transactions
   already works today. This keeps the change smaller and lower-risk.

2. **Build five new small, reusable pieces** under
   `client/src/shared/components/` (each will get its own short test file,
   matching how `FilterSortBar` already has one):
   - **`DataTable`** — a generic spreadsheet-style table, so pages stop
     writing their own `<table>` markup by hand. You hand it a list of
     "columns" (what to show and how) and a list of rows; it draws the
     table.
   - **`DataList`** — a generic card-style list (Notion's "List" view) —
     the same idea as `DataTable` but as stacked rows/cards instead of
     table columns.
   - **`useGroupBy`** (a "hook" — a small reusable piece of React logic,
     not a visible component) — takes a list of items and a chosen
     "grouping rule" (e.g., "by status") and splits the list into labeled
     buckets. This is copied out of the one working example that already
     exists in Boarding Checklist's kanban board and made generic enough
     for any page to reuse.
   - **`DataBoard`** — the Kanban/board view: draws one column per group
     from `useGroupBy`, with cards inside. Generalized from the existing
     Transactions board view and Boarding Checklist's board.
   - **`DataCalendar`** — a month-grid (and new week-grid) calendar,
     generalized out of the Monthly Schedule page's existing month-grid
     code. Only usable for lists where each row has one clear date (e.g.
     a booking's date, not something with several dates).

   Two existing pieces will also gain small additions rather than being
   replaced: `FilterSortBar`'s filter system currently only understands
   "pick one option" and "pick a date range" filters — it needs a new
   "pick several options" filter (for a field like a cage's supported pet
   types, which can be more than one) and a new "pick a number range"
   filter (for things like "price between ₱X and ₱Y").

3. **Prove the new pieces on two low-risk pages first**, before touching
   anything with real business logic:
   - `client/src/features/staff/components/DeletedRecordsArchiveList/DeletedRecordsArchiveList.tsx`
     — swap its old dropdowns for `FilterSortBar` + the new `DataTable`.
     Its backend already supports everything needed, so this is the
     safest possible first step.
   - `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx`
     — the first page to get the full table/list/board treatment, and the
     first real use of the new `useGroupBy`/`DataBoard` outside the one
     page that already has something similar.

4. **Then roll out in batches**, ordered from "safe, no live business
   process at risk" to "an actual shift-critical workflow tool":
   - **Admin config pages** (Pet Types + its price overrides, Breeds,
     Discounts, Promos + the Coupon Spin Wheel reward pool, the Product
     Catalog, Services/Service Types/Packages) — full table/list/board
     treatment.
   - **Customer-facing pages** (My Pets, My Food and Medication Types, the
     Rewards/Inventory page — default-grouped by reward type, as asked).
   - **Booking-process pickers** (the services/packages step and the cage
     selector step inside the booking flow).
   - **A lighter pass** on staff directories and logs (Staff Management,
     Customer Management, Credit Management, the Vet Catalog, My Patients,
     the Hotel Activity Log) — search/filter/sort, but table/list view
     only, no board. The Activity Log, being all timestamps, is where
     `DataCalendar` gets its first real (non-Monthly-Schedule) use.
   - **Last, and lightest of all:** the live operational queues (Bookings
     Queue, Grooming/Hotel/Daycare Queues, the Veterinary Console, the
     Assessment Queue, the Credit Review Queue, Boarding Checklist). These
     already have their own filter chips, just in an older visual style —
     this pass only re-skins those chips to match the new pill look. It
     deliberately does **not** add group-by, a view switcher, a board, or
     a calendar to these pages, because they're real-time staff workflow
     tools (check-in buttons, live care logs) rather than "browse my
     records" pages, and changing their structure carries more risk for
     very little benefit.

5. **Deliberately left out of this plan**: pages that are a single settings
   form rather than a list (Pricing Configuration, Weight Class
   Configuration, System Configuration, the Daily Sales Report, the
   Analytics Dashboard); small widgets embedded inside another page (the
   notification bell dropdown, the dashboard's Goal Stats widget, the
   Vaccination/Medical Note mini-lists inside a pet's profile); pages
   nobody needs to be logged in to see (the public Branches page, the
   public Packages & Promos marketing page); and two already-orphaned
   files, `client/src/features/billing/pages/PaymentsQueuePage/` (empty,
   nothing there) and `BookingPaymentsPanel.tsx` (built once, never wired
   into any route) — both stay untouched, since reviving them wasn't part
   of what was asked for here.

## Words you might not know

- **GET request** — the browser asking the server "give me this data,"
  without changing anything on the server. Distinct from a `POST`/`PUT`,
  which change something.
- **Pill / chip** — a small rounded button representing one active filter
  or sort choice, e.g. "Status: Paid ✕" — click the body to edit it, click
  the "✕" to remove it. This is the specific Notion-style look being asked
  for, versus a plain HTML dropdown.
- **Board / Kanban view** — cards arranged into columns, one column per
  group (e.g., one column per status), like a sticky-note board.
- **Group by** — splitting a list into labeled buckets based on some field
  (e.g., grouping cages by their size).
- **Component** — a reusable, self-contained piece of the user interface in
  React (the library this app's front end is built with).
- **Hook** — a reusable bit of React logic that isn't itself a visible
  piece of UI (unlike a component) — `useGroupBy` is one.
- **Adapter file** — a small file, one per page, that describes that page's
  specific columns/filters/sort options/groups to the shared components,
  so the shared components stay generic and each page only writes the
  parts that are actually different about it.
- **Client-side vs. server-side** — "client-side" means the work happens in
  the user's browser, after data has already been fetched; "server-side"
  means the server itself does the work before sending a response. This
  plan keeps everything client-side.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks. Implementation is
**done** on branch `feat/notion-style-data-views`: all
five new shared pieces (`DataTable`, `DataList`, `useGroupBy`, `DataBoard`,
`DataCalendar`, plus multi-select/number-range filter support) are built,
and **Batch A (11 pages), Batch B (3 pages), Batch C (2 booking-flow
widgets, a deliberately lighter search-only treatment), all of Tier 2
(6 full pages plus `StaffPickerList`), and Tier 3 (the chip-styling-only
pass on the live operational queues) are all done**. `DataCalendar` has
been proven on two consumers - Monthly Schedule (behavior-preserving
refactor) and Activity Log (its first List/Calendar view switcher). The
one item left from the plan - a carried-over gap from Batch A's own
scope, not a new tier: folding `TransactionHistoryTable`/`TransactionBoard`
onto the shared `DataTable`/`DataBoard`/`useGroupBy` pieces - was raised
with the user at the end of the session and **deliberately left undone**
by their choice, since it's a pure internal dedup with no user-facing
benefit that would touch live payment/billing code; see `testing.md`'s
"Open items" for the full reasoning.
Each later batch updates `testing.md` in place
rather than creating a new file.
