---
title: Record a pet's real weight and work out its size class from that number
date: 2026-09-10
tags: [session-plan, golden-fur]
project: golden-fur
session: 82-pet-weight-derived-class
branch: feat/pet-weight-derived-class
---

# 82 — Record a pet's real weight and work out its size class from that number

## What you asked for

Two related changes to how a pet's size is recorded and shown:

> - When updating a pet's weight via an assessment type booking, automatically update its weight class
>   - No longer need to manually select the weight class
>   - It should derive from actual weight value
>   - Perhaps make it readonly, but still can be overridden
>   - Should be able to set it to lbs or kg
> - Add settings whether to view pet's weight as lbs or kg (per user, not admin control)
>
> see `Projects/golden-fur/shared/context/Architectural-Change-History.docx` for full task context.
> make sure to include it in commits in the end.

## What this part of the app does today

**A "pet" record** in Golden Fur stores the animal's name, type (Dog/Cat),
breed, and two fields that come from a physical check-up the shop calls an
**assessment**:

- **`weight_class`** — one of four sizes: **S**, **M**, **L**, **XL**
  ("small / medium / large / extra-large"). This is an **enum**: a column that
  may only hold one of a fixed list of values.
- **`coat_type`** — **SC** (short coat) or **LC** (long coat).

These two fields drive money and space decisions elsewhere in the app: the
Grooming price list charges more for a bigger or longer-coated dog, and the
Pet Hotel / Daycare pick a cage size from the weight class.

**Who records an assessment.** Only staff — specifically the roles
Receptionist, Supervisor, Admin, Superadmin. A customer can never set these
fields on their own pet (if a customer could, they'd under-report the size to
get a cheaper Groom or a smaller-cage rate). This rule is enforced in two
places: the server rejects the fields on a customer request, and a database
**trigger** (a small piece of code the database runs automatically on every
insert/update to the `pets` table) rejects them as a last line of defence.

**Where an assessment is entered today.** Three screens, all staff-only:

- The **Assessment Queue** page — a list of booked "Initial Assessment" /
  "Reassessment" appointments. Starting one opens a small pop-up
  (**AssessmentModal**) that asks for weight class + coat type, saves them to
  the pet, then starts the booking.
- The **staff pet form** (add a new pet) and the **pet detail panel**
  (edit an existing pet) — both had a plain drop-down to pick S/M/L/XL by eye.

**What's missing today:** there is **no field anywhere for the pet's actual
weight as a number.** Staff look at the animal and guess a class. There is
also no way for a staff member or customer to choose whether they see weights
in kilograms or pounds.

## What's wrong / what's missing

1. **The size class is guessed, not measured.** Two staff can weigh the same
   dog on the same scale and still disagree on whether it's "M" or "L",
   because they're eyeballing it. That directly moves the Grooming price.
2. **No number is ever stored.** Even if staff weigh the pet, there's nowhere
   to write "14.2 kg". The vet console has its own separate "weight" box for a
   single consultation, but nothing on the pet's own profile.
3. **No kg/lb choice.** The business is in a metric market but some staff and
   customers think in pounds. Everyone sees the same unit.

## What we're going to change

1. **Store the pet's real weight in kilograms.** — _Which files:_ new
   migration `supabase/migrations/20260910185_m02_pets_add_weight_kg.sql` —
   _Why:_ add a `weight_kg` column (a decimal number) to the `pets` table.
   Kilograms is the one **canonical** ("single source of truth") unit stored;
   anything shown in pounds is converted on the way out. The column is allowed
   to be empty (`NULL`) for a pet that hasn't been weighed yet.

2. **Make the four size cut-offs an Admin-editable setting.** — _Which files:_
   new migration
   `supabase/migrations/20260910186_m13_create_pet_weight_class_configuration.sql`,
   new server service + controller + route, new client "Weight Classes" config
   page — _Why:_ "how many kg is a Medium?" is a business rule the client
   wants to own, not a number baked into the code. It's stored as a
   **singleton** — a table that always has exactly one row — with three
   numbers: the minimum kg for M, for L, and for XL. Seeded at 9.5 / 22 / 41
   as a deliberately non-round starting point for the client to review. Only
   Admin / Superadmin can change it; all staff can read it.

3. **Derive the size class from the weight automatically.** — _Which files:_
   `server/src/features/maintenance/utils/deriveWeightClass.ts` (+ a hand-kept
   copy on the client), `server/src/features/customers/pets/pet.controller.ts`
   — _Why:_ a small pure function turns a kg number into S/M/L/XL using the
   cut-offs above (lower bound inclusive: exactly 22.0 kg is an L). When a
   staff request includes a `weight_kg`, the server looks up the cut-offs and
   sets `weight_class` itself. The staff no longer picks it.

4. **Still allow a manual override.** — _Which files:_ same controller, plus
   the three assessment screens — _Why:_ an unusually proportioned animal
   (a very stocky small breed, say) might genuinely need a different class
   than its weight implies. If a staff request sends an explicit
   `weight_class` alongside the weight, that wins. On screen the class shows
   as a **read-only** box with an **"Override the derived weight class"**
   checkbox that unlocks it.

5. **Let each person choose kg or lb.** — _Which files:_ migration
   `20260910184_shared_add_weight_unit_preference_columns.sql` (a
   `weight_unit_preference` column on both the staff and the customer profile
   tables), the staff/customer "preferences" API endpoints,
   `client/src/shared/providers/ThemeProvider/*`, a new **WeightUnitToggle**
   in **Settings → Preferences**, and a new `petWeight.ts` helper with the
   kg↔lb maths — _Why:_ this is a **per-user** display choice (like dark mode
   or font size), not an Admin control. It only changes how a stored weight is
   shown and the default unit of an input; the stored value is always
   kilograms. Every place a weight appears — the pet profile, the assessment
   pop-up, the vet console — now renders it in the viewer's chosen unit.

6. **Protect the new column the same way as the old ones.** — _Which files:_
   migration `20260910187_m02_pets_assessment_lock_weight_kg.sql` — _Why:_ the
   database trigger that already blocks a customer from setting `weight_class`
   / `coat_type` directly is extended to also block `weight_kg`, since it now
   drives the price too.

7. **Keep the seed data honest.** — _Which files:_
   `supabase/seeds/m02-customers-pets/*` — _Why:_ every already-assessed
   example pet gets a `weight_kg` that actually matches its S/M/L/XL class
   under the seeded cut-offs, so a fresh developer database looks consistent.

8. **Fix how the Assessment Queue opens the pop-up** (follow-up, commit
   `ccc6a03`, same session). — _Which files:_
   `client/src/features/booking/pages/AssessmentQueuePage/*`,
   `client/src/features/booking/components/AssessmentModal/AssessmentModal.tsx`
   — _Why:_ the pop-up only appeared on the **Start** button, i.e. the
   Pending → In Progress step. A walk-in assessment is created already
   "In Progress", so it skipped Start entirely and the receptionist only ever
   saw a **Complete** button — no way to record the weight and coat. Now the
   Start and Complete buttons are removed; **clicking the row** opens the
   pop-up, and its button is **"Confirm"**, which saves the assessment and
   moves the booking all the way to **Completed** in one go.

## Words you might not know

- **assessment** — the shop's in-person check of a pet that records its size
  and coat; only staff may do it.
- **weight class** — the S/M/L/XL size bucket; an **enum** column.
- **enum** — a column allowed to hold only one of a fixed set of values.
- **canonical unit** — the one unit actually stored (here, kilograms);
  everything else is converted from it.
- **migration** — a numbered SQL script that changes the database's shape or
  its seed data. Migrations run in order and each database remembers which it
  has run.
- **RLS (row-level security)** — Postgres rules that decide, per row, who may
  read or write it. Here: all staff read the cut-offs, only Admin/Superadmin
  write.
- **trigger** — code the database runs automatically on every insert/update to
  a table; used here as a last-line check that only staff set the assessment
  fields.
- **singleton table** — a table designed to always hold exactly one row, used
  for global settings.
- **derive** — compute one value from another (weight class _from_ weight)
  instead of storing it independently.
- **singleton / lower-bound-inclusive** — for the bands, a weight exactly on a
  cut-off belongs to the _higher_ class (22.0 kg → L, not M).
- **provider (React)** — a component mounted once near the top of the app that
  holds a piece of shared state (here `ThemeProvider`, which now also holds
  the kg/lb choice).

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
