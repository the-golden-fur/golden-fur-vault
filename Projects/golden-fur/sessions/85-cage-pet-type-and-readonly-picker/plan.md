---
title: Cage pet-type filtering and readonly cage view for customers
date: 2026-09-12
tags: [session-plan, golden-fur]
project: golden-fur
session: 85-cage-pet-type-and-readonly-picker
branch: feat/cage-pet-types-and-readonly-picker
---

# 85 — Cage pet-type filtering and readonly cage view for customers

## What you asked for

> Customers should not be able to choose cages during booking process, only
> receptionist. Make it readonly for customers.
>
> As a customer, I want to see what cage is assigned to my pet based on his
> size and pet type, I don't care how many other cages are there, I only want
> to know if there's a cage for my pet and perhaps the ID of that cage. If
> there's no available cage, I want it to be indicated immediately.
>
> Specify if cages are for cats or dogs. Should also affect which cages are
> shown on booking process depending if pet is dog or cat. As an admin, I
> want to be able to specify what pet type a specific cage is for. As a
> developer, I want these seeded into the remote database.
> — task description, referencing `Architectural-Change-History.docx`
> ("Specify if cages are for cats or for dogs" / advisor session items 20-21)

> As an admin, I want to be able to set multiple pets when configuring a
> cage (cage should be usable by different pet types).
> — follow-up clarification given mid-session

## What this part of the app does today

When a customer books a Hotel stay, there's a step called the **Cage
Picker** — a grid of clickable cage cards the customer can pick from (or
leave as "No preference"). This pick is only ever **advisory**: the real
cage assignment always happens later, when staff physically check the pet
in, using a separate matching function (`suggestCage`) that looks at the
pet's **weight class** (S/M/L/XL, derived from its weight in kg) and finds
a same-size `Available` cage. A customer's cage cards are already shown as
disabled if the size doesn't match their pet — but staff can override that
and pick a mismatched size anyway (e.g. in a pinch).

Cages themselves only ever declare a **size**. There's no concept of "this
cage is for cats" or "this cage is for dogs" anywhere in the database.

Separately, this same branch just finished turning "pet type" (today: Dog
and Cat) into a real admin-manageable list — a `pet_types` table, with a
dedicated Settings screen — instead of a hardcoded 2-item enum
(`supabase/migrations/20260912191_custom_pet_types_admin_crud.sql`).

## What's wrong / what's missing

1. **Customers can actively click and pick a specific cage.** The advisor
   session was explicit that this should be a staff-only action — a
   customer should never be choosing which physical cage their pet goes
   in, only being told whether one exists for their pet.
2. **A customer only finds out about cage availability while picking a
   date/time**, because the Cage Picker only appears once a slot is
   selected. There's no immediate "yes, a cage exists" / "no, none
   available" signal as soon as the pet is known.
3. **Cages have no pet-type data at all.** Nothing stops (or even
   describes) a cat being matched to a cage that's only ever meant to
   hold dogs, and admins have no way to declare which pet type(s) a given
   cage supports.

## What we're going to change

1. **Give a cage the ability to support one or more pet types.** — _Which
   files:_ a new migration,
   `supabase/migrations/20260913_custom_cage_pet_types.sql`, creating a
   new table `cage_pet_types` that links a cage to a pet type (a cage can
   have several rows — one per pet type it supports). Existing cages get
   both Dog and Cat added automatically, so nothing that already works
   breaks the moment this ships. — _Why:_ this was explicitly asked to be
   many-to-many ("cage should be usable by different pet types"), which a
   single column can't represent — it needs its own small linking table
   (a "junction table," the same kind of table used anywhere one thing can
   relate to several of another, like a pet having several bookings).

2. **Make pet type a hard, no-exceptions filter everywhere a cage gets
   matched to a pet** — unlike cage _size_ (where staff can knowingly
   override a mismatch), a wrong-pet-type cage should never even appear as
   an option, for a customer or for staff. — _Which files:_
   `server/src/features/booking/services/cagePicker.service.ts` (the
   functions behind the booking-time Cage Picker),
   `server/src/features/hotel/services/cageAssignment.service.ts` (the
   real check-in-time cage match), and the call site in
   `server/src/features/booking/services/booking.service.ts`. — _Why:_ a
   cat genuinely can't use a dog-only cage the way an oversized dog can
   still squeeze into a slightly-too-small one — it's a real constraint,
   not a soft preference, so it belongs in the database query itself
   (excluded entirely) rather than shown-but-disabled in the UI.

3. **Stop customers from clicking cage cards at all — show them a plain
   yes/no answer instead, immediately.** — _Which files:_ a new small
   component,
   `client/src/features/booking/components/CageAssignmentStatus/CageAssignmentStatus.tsx`,
   backed by a new read-only server endpoint
   (`GET /bookings/cage-assignment-status`) that just answers "is there an
   Available cage matching this pet's size and type at this branch, and if
   so what's it called?" The existing interactive Cage Picker grid
   (`CagePickerList.tsx`) stays, but only for receptionist/staff bookings
   going forward. — _Why:_ this is the literal ask — a customer only wants
   to know "will my pet have a cage," optionally with its name, without
   caring how many other cages exist or clicking anything. Showing it as
   soon as the pet is picked (instead of after a date/time is chosen)
   satisfies "indicated immediately," since cage availability doesn't
   actually depend on the date — it's a live status snapshot, the same
   reason the existing Cage Picker never had a date filter either.

4. **Let admins tick which pet types a cage supports.** — _Which files:_
   `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx`
   (the existing Cages settings page gains a checkbox group next to the
   size dropdown, both when adding a new cage and when editing one) and
   its matching server-side create/update code
   (`server/src/features/hotel/services/cageStatus.service.ts`,
   `hotel.validator.ts`). A cage must always have at least one pet type
   checked. — _Why:_ this is the actual "as an admin, I want to specify
   what pet type(s) a cage is for" screen — without it the new database
   table would only ever be editable by a developer running SQL by hand.

5. **Seed a realistic mix of pet types across the existing seeded cages,
   both locally and on the shared remote database.** — _Which files:_ the
   three linked seed files under `supabase/seeds/m05-hotel/`
   (`m05-hotel.seed.ts`, its `.sql` twin, and its test file), updated so
   most seeded cages support both Dog and Cat, one small and one medium
   cage are deliberately narrowed to a single type (so the "fewer options
   for one pet type than another" behavior is actually visible while
   testing), and the one XL cage is Dog-only (so there's a guaranteed
   real-world case of "no cage available" to see the new message for).
   After the code changes are done and tested locally, the
   `supabase-migration-push` step applies the new migration to the shared
   project, and the seed scripts are re-run there too. — _Why:_ this is
   the explicit "as a developer, I want these seeded into the remote
   database" ask, and a good mix is what actually lets anyone (customer or
   developer testing this) see every new behavior without hand-editing
   data.

## Words you might not know

- **junction table** — a small table whose only job is linking two other
  tables together when one thing can relate to several of another (here:
  one cage can support several pet types, and in principle one pet type
  could apply to many cages).
- **hard filter** — a rule with no override: the wrong-pet-type cage is
  never shown to anyone, versus a "soft" rule like cage size, where staff
  can knowingly pick a mismatched one anyway.
- **advisory-only** — the customer's/receptionist's cage pick during
  booking is just a preference; it's re-checked (and can be silently
  replaced) at the real check-in step, so nothing about it is a hard
  reservation.
- **idempotent** — safe to run more than once without creating duplicates
  or breaking anything; the seed scripts are written this way so
  re-running them against a database that already has some of this data
  is harmless.
- **RLS (row-level security)** — the Postgres/Supabase feature that
  decides, per row, who's allowed to read or change it (e.g. "any logged-in
  user can read this," but only staff can create/edit cages).

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (written once the
implementation is done).
