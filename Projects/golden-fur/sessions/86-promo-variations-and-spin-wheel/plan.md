---
title: Promo variations, promo builder wizard, coupon spin wheel, and a multiselect Promos booking step
date: 2026-09-13
tags: [session-plan, golden-fur]
project: golden-fur
session: 86-promo-variations-and-spin-wheel
branch: feat/promo-variations-and-spin-wheel
---

# 86 — Promo variations, promo builder wizard, coupon spin wheel, and a multiselect Promos booking step

## What you asked for

> Include variations to promos. Currently there's only time limit. Add some
> sort of redemption point system, e.g. after X subsequent bookings, after X
> money spent in 1 transaction.
>
> Add new promo type: every X day of the week, get X% off of X services.
> When adding new promo type, open up a promo builder/wizard. Steps are:
> Promo Type (e.g. duration with start/end date, every X day on week, after
> X subsequent bookings, etc.) > the form fields based on that promo type.
>
> As a customer, I want X sub bookings, X money/credits spent in 1
> transaction to reward me a random %/flat PHP off coupon. I want it to
> look like a spin the wheel animation. I want each reward to have a %
> chance. I want there to be a pity system, after X coupon spins, guarantee
> a reward from the lowest % pool.
>
> As an admin, I want to be able to add and configure the coupon spin wheel
> rewards. I also want to be able to assign the % rarity. I want to assign
> the %/flat PHP off amount. I want to modify the pity requirement.
>
> Add new promo step in booking process. Receptionist/customer can choose
> their promos their before payment review step. Promos should be
> multiselect. Should still respect the promo config (e.g. max %, max
> promos selected, etc.).
> — task description, referencing `Architectural-Change-History.docx`
> (shared context doc, "Include variations to promos" / "Add new promo
> step in booking process" items)

> As a developer, I want rewards for wheel spin, the thresholds, everything
> in this request, etc. to be seeded to supabase.
> — follow-up clarification given mid-session

## What this part of the app does today

A **promo** is a discount that anyone (customer or receptionist) can apply
to a booking, like a coupon code — no staff verification needed (unlike a
**discount**, e.g. Senior Citizen/PWD, which does need a staff member to
check an ID in person). Today a promo only ever works one way: an admin
sets a **start date** and an **end date**, and the promo is available to
everyone, everywhere it's scoped to, during that window. There is no other
kind of promo.

Admins create/edit promos on one plain settings page (**Promo
Configuration**, under Settings) — a single form with fields for name,
percentage-or-flat amount, start/end date, which services it applies to,
and which branches it's available at. There's also a separate small
setting called the **promo cap** — a limit on how much total discount all
the promos on one booking can add up to (e.g. "never more than 20% off,
combined"), so promos can't be stacked without limit.

When a customer or receptionist books, the payment/review step at the end
already lets them pick **one** promo from a dropdown-style list of the
ones that currently apply. Interestingly, if nobody picks a promo at
booking time, the cashier's checkout screen already knows how to apply
**several** matching promos at once (up to the cap) automatically — that
stacking logic already exists, it's just not available to the
customer/receptionist while booking, only as an automatic fallback later.

There is also an existing, separate feature called the **Credit Balance
Ledger** — a running per-customer balance (like a gift-card balance) built
from a table of "add this much" / "subtract this much" rows, with a
database function that changes the balance and writes a ledger row in one
safe step so two people can't corrupt it by acting at the same time. This
session reuses that same safe pattern for a new kind of per-customer
running count (see below).

## What's wrong / what's missing

1. **Only one promo "shape" exists** — a fixed date window. There's no way
   to say "every Monday, 10% off Grooming" (a repeating weekly promo), and
   no way to reward a customer automatically for loyal behavior (booking
   often, or spending a lot in one visit).
2. **Adding a new kind of promo would mean cramming more fields into the
   one flat form**, which gets confusing fast — the ask is for a proper
   step-by-step **wizard**: first pick what kind of promo this is, then
   only see the fields that kind actually needs.
3. **There's no "reward" mechanic at all.** Nothing currently notices that
   a customer has booked many times, or spent a lot in one transaction,
   and nothing can hand them a surprise coupon for it.
4. **At booking time, only one promo can be picked**, even though the
   cashier's automatic fallback already knows how to combine several. The
   ask is to let the customer/receptionist pick **several** promos (and,
   new, several earned coupons) in one multiselect step, while still
   respecting the same cap so nobody can stack unlimited discounts.

## What we're going to change

This is a large session covering four connected features. It starts on a
**new branch off `dev`**, `feat/promo-variations-and-spin-wheel`, rather
than continuing on the unrelated daycare-queue branch this repo is
currently on.

1. **Add a second promo "type": weekly recurring.** — _Which files:_ new
   migration `supabase/migrations/20260913195_m_promos_add_weekly_recurring_type.sql`
   adds a `promo_type` column (`date_range` or `weekly_recurring`, existing
   promos default to `date_range` so nothing breaks) and a `days_of_week`
   column (which day(s) of the week it applies, e.g. "every Monday").
   `server/src/features/maintenance/services/promos.service.ts` and its
   validator learn the new fields; a new small shared helper
   (`server/src/shared/promoEligibility.ts`, and a client twin at
   `client/src/shared/utils/promoEligibility.ts`) answers "is this promo
   live right now" for **both** types in one place, replacing three
   separate copies of the old date-only check
   (`discountPromoEvaluation.service.ts`'s checkout fallback, the
   booking-time check, and the customer-facing preview). — _Why:_ this is
   the literal "every X day of the week" ask, built so the existing
   date-range promos keep working exactly as before.

2. **Build a Promo Builder Wizard for admins creating a new promo.** —
   _Which files:_ new component
   `client/src/features/maintenance/components/PromoBuilderWizard/PromoBuilderWizard.tsx`
   (step 1: pick "Date range" or "Weekly recurring"; step 2: the shared
   fields — name, amount, which services, which branches — plus whichever
   extra fields that type needs, like a new 7-checkbox
   `DayOfWeekPicker.tsx` component for weekly promos). The existing
   **Promo Configuration** page
   (`client/src/features/maintenance/pages/AdminPromoConfigPage/AdminPromoConfigPage.tsx`)
   uses this wizard when creating a promo; editing an existing promo keeps
   the current one-page form (a promo's type can't be changed after it's
   created, since that would mean rewriting what "eligible" even means for
   an already-running promo). — _Why:_ this is the literal wizard ask —
   "Promo Type > the form fields based on that promo type."

3. **Build the coupon spin wheel** — this is the "redemption point system"
   folded into one mechanic: instead of a separate "you've unlocked a
   promo" system, hitting a milestone hands the customer a **spin**, and
   the spin's random result becomes their reward.
   - _Earning a spin:_ two new database triggers (a trigger is code that
     runs automatically whenever a row changes) watch for (a) a booking
     being marked **Completed** — every time a customer's running
     completed-booking count crosses a multiple of an admin-set number
     (e.g. every 5th booking), and (b) a single transaction being marked
     **Fully Paid** for at least an admin-set amount. Either one hands out
     a "spin credit." New migrations:
     `supabase/migrations/20260913196_..._spin_wheel_config_and_rewards.sql`,
     `..._197_..._coupons_milestones_pity.sql`,
     `..._198_..._spin_history_and_spin_wheel_rpc.sql`,
     `..._199_..._completion_triggers.sql`.
   - _Spinning:_ a new database function (`spin_wheel()`, written the same
     safe "change the balance and record it in one step" way as the
     existing credit-ledger functions) picks a reward using each reward's
     %-chance, unless the **pity system** kicks in — after spinning some
     admin-set number of times without landing the rarest reward, the
     *next* spin is guaranteed to land in the lowest-%-chance group. The
     result becomes a **coupon**: a one-time, per-customer, already-decided
     %-or-flat-PHP-off reward, stored in a new `customer_coupons` table.
   - _Admin config page:_ new
     `client/src/features/rewards/pages/AdminSpinWheelConfigPage/` lets an
     admin add/edit/archive rewards (label, %-or-flat amount, % rarity —
     all active rewards' rarity percentages must add up to 100), and edit
     the booking-count milestone, the spend threshold, and the pity number.
   - _Customer-facing spin:_ new "My Rewards" page
     (`client/src/features/rewards/pages/CustomerRewardsPage/`) with a
     hand-drawn spinning-wheel animation component
     (`client/src/features/rewards/components/SpinWheel/SpinWheel.tsx`) —
     the wheel's landing spot always matches a result the server already
     decided, so the animation is just a visual, never the actual dice
     roll. — _Why:_ this is the literal spin-wheel, rarity-%, and
     pity-system ask, built on the same "safe against race conditions"
     pattern already proven by the Credit Balance Ledger feature.

4. **Add a multiselect "Promos & Coupons" step to the booking flow.** —
   _Which files:_ `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
   gains a new step (shown to both receptionist and customer bookings,
   right before the final Review step) using a new component
   `client/src/features/booking/components/PromoCouponMultiSelect/PromoCouponMultiSelect.tsx`
   — a checkbox list covering both applicable promos and the customer's
   unused coupons, showing a live running "you'll save ₱X" total that
   already respects the existing promo cap (so picking more than the cap
   allows just stops adding to the savings shown, it never lets someone
   see a bigger discount than they'll actually get). On the server,
   `server/src/features/booking/services/booking.service.ts`'s
   `resolveDiscountAndPromo` function is rewritten
   (`resolveDiscountAndPromos`) to accept a **list** of promo/coupon
   choices instead of just one, re-check every one of them, and re-apply
   the same cap authoritatively (never trusting whatever total the
   customer's screen showed). A new table,
   `supabase/migrations/20260913200_m_booking_create_booking_promo_selections.sql`'s
   `booking_promo_selections`, records exactly which promos/coupons were
   used on which booking, replacing the old "just one promo" column. —
   _Why:_ this is the literal "promos should be multiselect... should
   still respect the promo config" ask, and it reuses (rather than
   reinvents) the stacking-cap math the cashier's checkout screen already
   had.

5. **Seed real starting data for the spin wheel and a demo weekly promo,
   in every environment — not just a developer's own laptop.** — _Which
   files:_ the spin-wheel config's numbers (how many bookings for a
   milestone, how much spend counts, the pity number) get real starting
   values written straight into migration `196` itself (the same way the
   existing promo-cap and pricing settings already do — a single "settings
   row" is considered part of the database structure, not separate sample
   data, so it appears automatically the moment the migration runs,
   anywhere). The **reward list itself** (five example rewards, e.g. 5%
   off, 10% off, 15% off, PHP 100 off, PHP 250 off, with rarity percentages
   that add up to exactly 100) and a **demo weekly-recurring promo**
   ("Midweek Grooming Discount," every Tuesday/Wednesday) are real *rows*,
   so they go in a new seed script,
   `supabase/seeds/custom-rewards/custom-rewards.seed.ts` (plus its `.sql`
   and test-file twins, matching how `supabase/seeds/m13-maintenance/`
   already seeds two starter promos today). — _Why:_ this is the explicit
   "I want rewards for wheel spin, the thresholds, everything in this
   request... to be seeded" ask. It matters that this isn't only a local
   thing: this project keeps two real Supabase databases — a shared "dev"
   one and the live "prod" one — and **both already exist** (they weren't
   just created from scratch). Seed scripts like this one only run
   automatically when someone wipes and rebuilds a database from zero
   (`supabase db reset`), never just from pushing new migrations
   (`supabase db push`) — so after this session's migrations are pushed to
   dev, and later to prod, the seed script has to be **run again by hand
   against each one** (this already happened for a past session's cage
   data, so it's a known, expected extra step, not an oversight). Without
   that extra step, the spin wheel would technically work but start with
   zero rewards configured on the shared databases, even though the
   settings numbers above would already be there.

## Words you might not know

- **migration** — a small file that changes the shape of the database
  (adds a table, a column, a rule) in a tracked, repeatable way, so every
  copy of the database (a developer's laptop, the shared test database,
  the live one) ends up with the exact same structure.
- **trigger** — database code that runs automatically the moment a row is
  changed (e.g. "the instant a booking's status becomes Completed, run
  this"), instead of needing every part of the app that could mark a
  booking Completed to remember to call it themselves.
- **RPC (remote procedure call)** — a named function stored in the
  database that the server calls like a single command; used here (and
  already used by the Credit Balance Ledger) whenever several changes
  need to happen together as one all-or-nothing step, so two people
  spinning the wheel at the exact same moment can never corrupt the count.
- **RLS (row-level security)** — the Postgres/Supabase feature that
  decides, per row, who's allowed to read or change it (e.g. "a customer
  can see their own coupons, but not anyone else's").
- **rarity / pity system** — "rarity" is how likely a reward is to be
  picked (a 2%-chance reward is rarer than a 40%-chance one); "pity" is a
  safety net so an unlucky player isn't stuck never getting a rare reward
  — after enough spins without one, the next spin is guaranteed to land in
  the rarest group.
- **stacking cap** — the existing limit on how much combined discount
  multiple promos can give one booking (e.g. "never more than 20% off,
  even if three promos would technically add up to 35%").
- **multiselect** — a control where more than one option can be checked
  at once (a list of checkboxes), instead of a dropdown or radio buttons
  where only one choice is possible.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (written once the
implementation is done).
