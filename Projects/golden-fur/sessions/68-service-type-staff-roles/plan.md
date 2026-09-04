---
title: Service Types — pick which staff roles the Staff Picker offers, and drop the redundant Key field
date: 2026-09-04
tags: [session-plan, golden-fur]
project: golden-fur
session: 68-service-type-staff-roles
branch: feat/service-type-staff-roles
---

# 68 — Service Types: staff-role multi-select, and dropping the redundant Key field

## What you asked for

Let an admin choose which staff roles fill the **Staff Picker** for each
service type, instead of that being invisible and hardcoded, and stop asking
the admin to type in a **Key** field that should just be generated for them.

> When creating new service type > staff picker, it doesn't specify what
> staff roles are available to choose from. Extend it by adding options to
> choose staff roles (multi-select). Since grooming services > groomer, vet
> services > vets, etc. Do the same for existing service types and update
> seed scripts. Also remove the key field, this should be randomly generated
> anyway, only leave out name. Just drop key field, it seems redundant, I
> don't like it showing in the list either.

Partway through, a related, separately-worded follow-up came in from the same
person, in chat rather than in a document:

> while you're at it, I think there's a stray staff picker config at admin
> settings > policies, even though it can already be configured now at
> service type. get rid of it.

## What this part of the app does today

- **Admin Settings > Service Types** — the screen an **Admin**/**Superadmin**
  uses to manage the fixed set of service lines customers can book (Grooming,
  Hotel, Daycare, Veterinary — plus room for future ones). Each row can be
  renamed, switched on/off per branch, and has two on/off toggles: **Staff
  Picker** (does the booking flow ask "which groomer/vet?") and **Cage
  Picker** (does it ask "which cage?", Hotel-only in practice).
- **Staff Picker** — the booking-wizard step that lets a customer or
  receptionist request a specific staff member for their appointment (or
  "No preference"). It's backed by a Postgres function,
  `get_staff_availability`, that returns only staff who are actually free at
  that time (right branch, right hours, not on an approved vacation/leave
  block, not already double-booked).
- **`service_types.key`** — a short internal code (e.g. `"Grooming"`) each
  service-type row carries, used as the join between that admin-facing row
  and the fixed set of built-in categories (`ServiceCategory` in the code —
  Grooming/Hotel/Daycare/Veterinary) that the rest of the app's logic (which
  services belong to it, how pricing/availability work, which category tab a
  customer sees) is actually written against.
- **Admin Settings > Policies** — a separate settings screen for booking-wide
  rules (notice periods, lunch break, downpayment, credit expiry…), stored in
  one database table, `policy_configurations`. Until this session, it also
  carried its own, older "Staff Picker enabled for Grooming / Veterinary"
  checkboxes — a second on/off switch for the exact same thing Service Types
  already had one of.

## What's wrong / what's missing

1. **Which roles can fill the Staff Picker was invisible and hardcoded.**
   Nowhere in the admin UI could you see or change "Grooming's Staff Picker
   only offers Groomers." It was a fixed lookup table buried in server code
   (`{Grooming: 'Groomer', Veterinary: 'Veterinarian'}`), copy-pasted in two
   different files, and it meant the Staff Picker could **never** be turned
   on for Hotel, Daycare, or any new service type — even though the Service
   Types page already had a toggle that implied it could.
2. **The Key field was pointless admin busywork.** An admin had to type in a
   short internal code by hand when creating a new service type, and it also
   cluttered the list view — with no real reason a human needed to see or
   choose it, since the row already has a proper auto-generated database ID.
3. **Two places configured the same on/off switch, and they disagreed about
   which one mattered.** `policy_configurations` had its own
   Grooming/Veterinary Staff Picker checkboxes, and — surprisingly — _that_
   was the only one of the two ever actually checked by the code that decides
   whether the Staff Picker shows up. The seemingly-live toggle on the
   Service Types page was actually never read by anything.

## What we're going to change

1. **Add a "which roles" field to each service type.** — _Which files:_ a new
   database column, `service_types.eligible_staff_roles` (a list of role
   names, e.g. `['Groomer']`) — _Why:_ so "which staff roles can fill this
   category's Staff Picker" becomes a real, admin-editable, per-row setting
   instead of a hardcoded lookup table two files disagreed about.
2. **Make the server actually read that new field.** — _Which files:_
   `server/src/features/booking/services/staffPicker.service.ts`,
   `availability.service.ts` — _Why:_ one shared function,
   `resolveServiceTypeStaffConfig`, now answers "is the Staff Picker on, and
   for which roles" by reading the database row instead of the old hardcoded
   map — which means the Staff Picker can now genuinely be turned on for any
   category, not just Grooming/Veterinary.
3. **Update the database function that actually looks up available staff.**
   — _Which files:_ `supabase/migrations/20260904169_...sql` — _Why:_ it used
   to accept one role at a time; now that a service type can list several
   eligible roles, it needs to accept a list and match any of them.
4. **Add the multi-select checkbox picker to the admin screen.** — _Which
   files:_ new component
   `client/src/features/maintenance/components/StaffRoleMultiSelect/`, wired
   into `AdminServiceTypesPage.tsx`'s create and edit forms — _Why:_ this is
   the actual on-screen control an admin uses to pick roles for a service
   type, right next to the existing Staff Picker/Cage Picker toggles.
5. **Backfill the existing rows so nothing changes behaviorally today.** —
   _Which files:_ the same new migration, plus a second one dropping the old
   hardcoded map from server code — _Why:_ Grooming gets `['Groomer']` and
   Veterinary gets `['Veterinarian']`, matching exactly what the old hardcoded
   map already did; Hotel and Daycare stay empty (the Staff Picker is off for
   both today either way).
6. **Remove the Key field from the create form and the list.** — _Which
   files:_ `AdminServiceTypesPage.tsx`,
   `server/.../serviceTypes.service.ts` (generates it with `randomUUID()`
   instead), `maintenance.validator.ts` (no longer accepts it from the
   client) — _Why:_ the database column itself has to stay (it's still the
   real internal join key two other features rely on — the Cage Picker and
   the customer booking flow's category tabs — so it can't disappear), but an
   admin never needs to type it or see it again.
7. **Delete the redundant Policies-page toggle.** — _Which files:_ a third
   migration dropping
   `policy_configurations.staff_picker_enabled_grooming`/`_veterinary`, plus
   the matching type/validator/service/UI cleanup in
   `PolicyConfigurationPage.tsx` and `staffPicker.service.ts` — _Why:_ your
   mid-session follow-up — now that Service Types is the one real place this
   is configured, keeping a second, previously-the-only-one-that-worked
   toggle around would just be confusing and easy to disagree with itself
   again later.
8. **Let the Staff Picker actually appear outside Grooming/Veterinary.** —
   _Which files:_ `CustomerBookingFlowPage.tsx` (three hardcoded
   Grooming/Veterinary checks replaced with a lookup against each service
   type's own `staff_picker_enabled`), `ReceptionistBookingsQueuePage.tsx` and
   `CustomerBookingsPage.tsx` (dropped their hardcoded category check
   entirely — the Staff Picker component already knows how to hide itself
   when a category has none configured), `StaffPickerList.tsx` (its
   `serviceCategory` prop widened from a fixed two-value type to "any
   category") — _Why:_ this is the actual payoff of item 1 — an admin can now
   flip Staff Picker on for, say, Hotel, and it will really show up.

## Words you might not know

- **migration** — a numbered `.sql` file that changes the shape of the
  database (adds a column, changes a function, etc.); migrations run once,
  in order, and are never edited after the fact.
- **RPC (remote procedure call)** — here, a named function that lives inside
  the Postgres database itself (`get_staff_availability`) rather than in the
  server's own code; the server calls it like a function and gets rows back.
- **enum** — a database type restricted to a fixed list of allowed text
  values, e.g. `staff_role` only ever being one of the 8 real job titles
  (Groomer, Veterinarian, Cashier, …).
- **multi-select** — a form control that lets you tick more than one option
  at once (here, a list of checkboxes, one per staff role) instead of picking
  just one.
- **`.strict()` validator** — a rule on the server's request-checking layer
  (Zod) that outright rejects a request containing any field it doesn't
  explicitly recognize, rather than silently ignoring the extra field.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
