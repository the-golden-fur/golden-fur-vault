---
title: Let a Superadmin move a cage to a different branch
date: 2026-09-30
tags: [session-plan, golden-fur]
project: golden-fur
session: 118-cage-branch-reassignment
branch: staged on dev
---

# 118 — Let a Superadmin move a cage to a different branch

## What you asked for

Give an admin a way to change which branch a cage belongs to, from the same
"Configure" popup already used to edit a cage's size and pet types.

> As an admin, I want to be able to configure what branches certain cages
> are available at, via ... button > configure

## What this part of the app does today

Golden Fur's staff side has a **Settings > Config > Cages** page listing
every "cage" (a physical kennel/enclosure used for Hotel and Daycare stays)
at your branch. Each cage row has a "..." menu with a **Configure** option
that opens a popup letting you change the cage's **label** (e.g.
"Makati-S-01"), **size** (Small/Medium/Large/XL), and which **pet types**
(Cat/Dog) it can hold.

Every cage belongs to exactly one **branch** (Golden Fur currently has two:
Makati and Southwoods) - that's baked into the cage's own record in the
database (a column called `branch_id`). The Cages page only ever shows you
*your own* branch's cages - this is true for every staff role, including
Superadmin (the highest-privilege role, who can normally do anything at any
branch). There is currently no button or field anywhere that changes which
branch a cage belongs to - once created, a cage is stuck at that branch.

## What's wrong / what's missing

If a branch physically moves a cage to a different location, or the two
branches need to redistribute their kennel inventory, there's no way to
reflect that in the system - someone would have to delete the cage
record entirely and manually recreate it as a new cage at the other branch,
losing its history.

## What we're going to change

This only unlocks the new "change branch" control for the **Superadmin**
role. Regular Admins and Supervisors keep managing only their own branch's
cages exactly as they do today - matching how a few other admin screens in
this app (like the sales reports) already show a branch-switching control
only to Superadmin.

1. **Let the Configure popup accept a new branch, but only checked
   server-side for Superadmin.** - _Which files:_
   `server/src/features/hotel/modules/validators/hotel.validator.ts`,
   `server/src/features/hotel/hotel.controller.ts` - _Why:_ the server must
   never trust the button on screen alone - it double-checks the real,
   freshly-looked-up role of whoever is sending the request before allowing
   a branch change through, and rejects it (with a clear "Only Superadmin
   can reassign a cage" message) for anyone else.
2. **Actually change the stored branch when asked.** - _Which files:_
   `server/src/features/hotel/services/cageStatus.service.ts` - _Why:_ this
   is the piece that writes the new branch into the database row.
3. **Add a "Branch" dropdown to the Configure popup, shown only to
   Superadmin.** - _Which files:_
   `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx`,
   `client/src/features/hotel/api/hotel.api.ts` - _Why:_ this is the actual
   on-screen control the ticket asks for. It reuses the same branch-list
   lookup that other admin screens (like the Services page's branch picker)
   already use, so no new backend list endpoint is needed.
4. **Make a moved cage disappear from your current view.** - _Which
   files:_ `AdminCagesPage.tsx` - _Why:_ since the page only ever shows your
   own branch's cages, a cage you just gave to the other branch shouldn't
   still show up in your list afterward.

## Words you might not know

- **Branch** - one of Golden Fur's physical locations (Makati or
  Southwoods). Most things in this app - bookings, cages, staff - belong to
  exactly one branch.
- **RLS (row-level security)** - a Postgres/Supabase feature that decides,
  per database row, who's allowed to read or change it. The cages table's
  RLS rules already fully allow Superadmin to change any branch's cages -
  the missing piece was purely in the app's own code, not the database
  rules, so no database migration is needed for this change.
- **Validator** - a piece of server code that checks an incoming request's
  data is shaped correctly (right fields, right types) before anything
  acts on it.

## How you'll know it worked

See `testing/testing.md` (to be filled in once this is implemented) for the
click-by-click checks: logging in as Superadmin, reassigning a cage, and
confirming it disappears from the original branch's list; then logging in
as a regular Admin and confirming the Branch field never appears for them.
