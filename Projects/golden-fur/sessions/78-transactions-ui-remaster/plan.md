---
title: Rebuilding the "Transactions" screen — a Customer column, tidier filters, and a board view
date: 2026-09-08
tags: [session-plan, golden-fur]
project: golden-fur
session: 78-transactions-ui-remaster
branch: feat/transactions-ui-remaster
---

# 78 — Rebuilding the "Transactions" screen

## What you asked for

Make the cashier's **Transactions** screen easier to use: let them see whose
transaction each row is, and cut down the crowded row of filter/sort boxes to
a single pair of buttons that add small removable "chips" (like Notion). Also
add a second way to look at the data — a board — and apply the same treatment
to the customer's own transactions page.

> Remaster cashier > transactions UI:
>
> - Currently they cannot see transaction owners
> - Add col that specifies the customer
> - The filters and sort are too complex
> - Reduce it to 1 sort and filter controls, adding sorts/filters creates
>   round tiles like in Notion (you may look it up)
> - Each sort/filter tile instance can be removed via X button on hover
> - perhaps add different views for it too, but default table — you can think
>   of other views like those in Notion

## What this part of the app does today

**Golden Fur** is a booking-and-billing system for a pet-care business. Staff
sign in and get a role (Cashier, Receptionist, Admin, …). A **transaction** is
one payment record — a down payment, a full payment, a balance payment, or a
one-off "miscellaneous sale" — and it is linked to the **booking** it paid for.

- The **cashier** opens **Transactions** (`/staff/reports/transaction-history`)
  — a plain table of every transaction for their branch, used to take payments
  ("Mark as paid") and to top up partly-paid bookings.
- The **customer** has their own version, **Transaction History**
  (`/portal/transactions`) — the same table, but only their own rows, with a
  "Pay" button for anything still owed.

Both pages are the same React component family and share one stylesheet
(a **CSS Module** — a `.module.css` file whose class names are scoped to the
components that import it).

Before this change, above the table sat: a text search box, a "sort by"
dropdown, a "Due payments only" checkbox, **and** seven more dropdowns
(customer, pet, date-from, date-to, service, transaction type, payment kind).
Nine controls, all visible all the time.

## What's wrong / what's missing

1. **No owner shown.** The table never displayed the customer's name. A
   cashier looking at a list of "Booking payment — Hotel — PHP 1,275" rows had
   no way to tell which client each belonged to.
2. **Filter overload.** Nine always-on controls is a wall of boxes. Most are
   unused most of the time.
3. **One shape only.** A flat table. A cashier working the "money still owed"
   pile has to eyeball the Status column row by row.

## What we're going to change

1. **Show the customer's name.** — _Which files:_
   `server/src/features/reports/services/transactionHistory.service.ts`,
   `server/src/features/reports/reports.types.ts`,
   `client/src/features/reports/reports.types.ts` — _Why:_ every transaction
   row already stores a `customer_id` (a pointer to a customer record) but not
   the name. The server now does one extra database lookup — fetch the names
   for all the `customer_id`s in the result in a single query — and attaches a
   `customer_name` field to each row. (This follows the exact pattern the
   booking-details screen already uses; we do **not** use a database "join"
   here, matching the rest of this codebase.) The cashier table then shows a
   **Customer** column; a customer whose record was archived still resolves to
   a name.

2. **Replace the nine boxes with a "Filter" button and a "Sort" button.** —
   _Which files:_ new `client/src/shared/components/FilterSortBar/` (the
   component, its styles, a `FilterTile` sub-component, a `filterField.types.ts`
   describing each filterable field as plain data) — _Why:_ this is the
   "Notion" pattern. You click **Filter**, pick a field (Customer, Date,
   Service, Status, …), and a rounded **tile** appears reading e.g.
   `Status: Due payment`. Click the tile to change its value in a little
   popup; hover the tile (or tab to it) and an **✕** appears to remove it.
   **Sort** works the same way and produces one `Sort: Amount (High to low)`
   tile. The search box stays as a permanent box (it is used constantly).

3. **Add a "Board" view.** — _Which files:_ new
   `client/src/shared/components/ViewSwitcher/` (a small Table/Board toggle),
   new `client/src/features/reports/components/TransactionHistoryTable/TransactionBoard.tsx`
   — _Why:_ **Table** stays the default. **Board** shows the same rows as three
   columns — **Due payment**, **Partially Paid**, **Fully Paid** — each a stack
   of cards with the customer, amount, and the same "⋮" actions. A cashier can
   now see the whole "owed" column at a glance. (A calendar view was
   considered and left for later.)

4. **Do all of the above on the customer page too.** — _Which files:_
   `client/src/features/reports/pages/CustomerTransactionHistoryPage/CustomerTransactionHistoryPage.tsx`
   — _Why:_ consistency. It reuses the same new components with a smaller set
   of filter fields (no Customer/Pet/Transaction-type — a customer only ever
   sees their own bookings) and hides the redundant name on its board cards.

The two payment pop-ups, the "add a balance payment" buttons, and all the
role checks are **not touched**.

## Words you might not know

- **transaction** — one payment record in the database. Linked to a booking.
- **CSS Module** — a stylesheet (`*.module.css`) whose class names only apply
  to the files that import it, so two components can both have a `.card` class
  without clashing.
- **component** — a reusable piece of UI in React (a button, a table, a whole
  page). "Shared" components live in `client/src/shared/` and are used by many
  features.
- **descriptor / config-driven** — instead of writing the filter UI by hand
  for each field, we describe each field as a small data object
  (`{ id, label, type, options }`) and one component renders whatever it's
  given.
- **hydrate / hydration** — take a bare id (`customer_id`) and look up the
  human-readable thing it points to (the name).
- **archived customer** — a customer record that was soft-deleted; normal
  lists hide them, but their old transactions still exist and must still show
  a name.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (staff and customer,
Table and Board), the filter-tile add/remove flow, and the test-suite counts.
