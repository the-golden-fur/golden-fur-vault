---
title: Admin-managed pet types with a fixed-price override
date: 2026-09-12
tags: [session-plan, golden-fur]
project: golden-fur
session: 84-pet-type-admin-fixed-pricing
branch: feat/pet-type-admin-fixed-pricing
---

# 84 — Admin-managed pet types with a fixed-price override

## What you asked for

Give admins full control over "pet types" (today just Dog and Cat) and let
them set one fixed price per pet type that overrides whatever a service or
package would normally cost — with Cat pre-set to ₱800 for everything.

> Add admin config to pet types. CRUD for pet types. Make it so that they can
> set X fixed price to pet types, this will override service and package
> prices. By default, set cat type to 800 php for both services and packages
> (seed this). As an admin/superadmin, I want ALL SERVICES AND PACKAGES for
> cat type pets to be fixed price at 800.
> — Architectural-Change-History.docx, "In Progress" (Matthew)

## What this part of the app does today

Golden Fur is a booking system for a pet-care business. When a customer adds
a pet to their account, they pick a **pet type** — right now that's a fixed
choice between "Dog" and "Cat", baked into the database as what's called an
**enum** (a column that can only ever hold one of a short, hardcoded list of
values — like a multiple-choice question with no "other" option).

Prices for **services** (e.g. a bath) and **packages** (a bundle of several
services sold together at one price) are normally set by an admin per
service/package in **Admin Settings → Config → Services and Packages**. For
Grooming services specifically, there's an extra wrinkle: a service can opt
into a "pricing matrix" that adjusts the price up or down based on the pet's
**weight class** (S/M/L/XL, derived from its weight in kg) and **coat type**
(short or long coat). Today, the code has one hardcoded exception: if the pet
is a Cat, that matrix is skipped entirely and the service's plain price is
used instead — but that plain price is still whatever the admin typed in for
that specific service, not one single number for every Cat booking.

## What's wrong / what's missing

1. **Admins can't manage pet types at all.** There's no screen anywhere to
   add a new one, rename one, or turn one off — "Dog" and "Cat" are the only
   two options that will ever exist, forever, unless a developer edits the
   database by hand.
2. **There's no real "fixed price per pet type" feature.** The closest thing
   today is that one hardcoded "Cat skips the matrix" rule mentioned above,
   but it doesn't give Cats one flat number for every service and package —
   each service still charges its own individually-configured price.

## What we're going to change

1. **Turn "pet type" into a real, admin-manageable list, not a hardcoded
   2-item enum.** — _Which files:_ a new database migration
   (`supabase/migrations/20260912191_custom_pet_types_admin_crud.sql`) that
   creates a `pet_types` table (with a name, an on/off switch, and a "key"
   that Dog and Cat keep using so nothing else breaks) and converts the two
   places that used the old enum (`pets.pet_type`, `breeds.pet_type`) to
   point at this new table instead. — _Why:_ this is what "CRUD for pet
   types" means — Create, Read, Update, Delete — which an enum fundamentally
   can't support; only a real table with rows can.
2. **Add a table that stores the fixed-price override, per pet type and
   optionally per branch.** — _Which files:_ a second migration
   (`supabase/migrations/20260912192_custom_pet_type_price_overrides.sql`)
   creating `pet_type_price_overrides`, pre-loaded with one row: Cat = ₱800,
   applying everywhere unless a specific branch (Makati or Southwoods) sets
   its own number. — _Why:_ this is the actual override data the pricing
   logic will read from, and it's how the ₱800-for-Cat default gets seeded
   without writing it into code.
3. **Teach the booking price calculation to check for an override first.**
   — _Which files:_ `server/src/features/booking/services/booking.service.ts`
   (the `resolveServicePrice` and `resolvePackagePrice` functions, which run
   every time a booking is priced). — _Why:_ this removes the old hardcoded
   "if pet type is Cat" check and replaces it with "look up whether this pet
   type has a price override for this branch" — so Cat's ₱800 becomes a
   plain data row instead of special-cased code, and any brand-new pet type
   an admin creates later behaves sensibly (falls back to normal pricing)
   with zero extra code.
4. **Build the admin screen.** — _Which files:_ a new page
   `client/src/features/maintenance/pages/AdminPetTypesPage/AdminPetTypesPage.tsx`,
   registered as a new "Pet Types" tile in **Settings → Config**
   (`client/src/pages/SettingsPage/configTiles.config.ts`). One page, two
   sections: a list of pet types (add/rename/turn off/delete), and a
   price-override editor with a branch picker (or "System default") and one
   price box per pet type. — _Why:_ this is the actual UI an
   admin/superadmin uses to do everything above, restricted to those two
   roles like every other admin config page.
5. **Make every dropdown that lists "Dog"/"Cat" pull from the database
   instead of a hardcoded list**, so a newly-added pet type actually shows
   up where a real person would expect it (adding a pet, viewing a pet's
   details, the vet's patient list, the breed-management filter). — _Which
   files:_ `PetForm.tsx`, `PetDetailPanel.tsx`, `AdminBreedsPage.tsx`,
   `MyPatientsPage.tsx` on the client, plus the two server-side validators
   that currently reject anything except `'Dog'`/`'Cat'`
   (`maintenance.validator.ts`, `pet.validator.ts`). — _Why:_ without this,
   a new pet type could be _created_ but would be invisible/unusable
   everywhere else — this is what makes "full CRUD" actually mean something.

## Words you might not know

- **migration** — a numbered SQL file that changes the shape of the
  database (adds a table, a column, etc.). They run in order, once, and are
  never edited after the fact — a mistake gets fixed by a _new_ migration.
- **enum** — a database column type restricted to a fixed list of exact
  values decided when the table was created (here: only `'Dog'` or `'Cat'`,
  nothing else, ever — until this session replaces it with a real table).
- **RLS (row-level security)** — a Postgres/Supabase feature that decides,
  per database row, who's allowed to read or write it (e.g. "any logged-in
  user can read this table, but only Admin/Superadmin can change it").
- **foreign key (FK)** — a column that must match a value that actually
  exists in another table (e.g. a pet's `pet_type` must be a `key` that's
  really in the `pet_types` table) — the database itself refuses a bad value
  or a delete that would orphan something.
- **fixed price / price override** — instead of computing a price the normal
  way (a service's own listed price, possibly adjusted by the weight/coat
  matrix), just use one flat number no matter what was selected.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
