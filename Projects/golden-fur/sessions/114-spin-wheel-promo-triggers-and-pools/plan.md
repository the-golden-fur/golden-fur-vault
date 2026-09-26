---
title: Coupon spin wheel becomes a promo type, with trigger conditions, reward pools, and a pop-up for customers
date: 2026-09-25
tags: [session-plan, golden-fur]
project: golden-fur
session: 114-spin-wheel-promo-triggers-and-pools
branch: feat/spin-wheel-promo-triggers-and-pools
---

# 114: Coupon spin wheel becomes a promo type, with trigger conditions, reward pools, and a pop-up for customers

## What you asked for

The goal: an admin can build spin-wheel campaigns the same way they build any promo. Each campaign has its own rules for when a customer earns a spin, and its own set of possible rewards. Customers see the wheel pop up when they earn a spin.

> As an admin, I want to be able to set conditions that will make the coupon spin wheel pop-up
>
> - Perhaps something like: after every X completed bookings, daily login, consecutive logins per week, consecutive logins per month
> - Some conditions should not be able to be enabled at the same time
>
> I also want to be able to create multiple reward pools, and assign trigger conditions to them (ex: monthly login triggers a reward pool that consists of only rare rewards)
>
> I want coupon spin as a type when making a new promo, not as a separate subpage in settings > config > promos
>
> - Clicking on Add New Promo > Coupon Spin Wheel will have these fields: trigger conditions, reward pool, pity system, etc.
>
> Remove coupon spin wheel subpage, perhaps add 2 new subpages: rewards and reward pools
>
> Add New Reward button > reward form > Move the title, rarity, % chance, etc.
>
> Add New Reward Pool button > reward pool builder form
>
> As an admin, I want to be able to freely add a coupon spin wheel reward and configure its rarity without having to manually adjust everything to make it total to 100%
>
> (source: `shared/context/Architectural-Change-History.pdf`, p.8, assigned to Matthew)

Clarifications you gave during planning:

- **Rarity:** each reward gets a **rarity tier** (Common / Uncommon / Rare / Epic / Legendary) plus a free **weight** number. The app works out each reward's % chance automatically.
- **Which conditions can't be combined:** within one promo, you can pick only **one** login condition: daily login, weekly streak, or monthly streak. "Every X bookings" and "big single payment" can be combined with anything. Different promos can use different login conditions.
- **Streaks:** the admin picks a number N. The customer earns a spin the first time they log in N days in a row within the current week (Monday–Sunday) or month. They get at most one spin per week or month from that promo.
- **Extra:** a customer can **skip** a pop-up spin and keep it for later. They can always see how many spins they have.

## What this part of the app does today

- **Admin > Settings > Config > Promos & Rewards** is a settings page for Admin and Superadmin accounts. It has a small tab bar with two tabs:
  - **Promos**: the list of discount campaigns. The **New promo** button opens a two-step pop-up form (a "wizard"). Step 1 asks what _type_ of promo it is: "Date range" (runs between two dates) or "Weekly recurring" (runs on certain weekdays). Step 2 shows the fields for that type.
  - **Coupon Spin Wheel**: one settings form with three numbers:
    - "give a spin every 5 completed bookings"
    - "give a spin when one payment is at least ₱5,000"
    - "pity after 10 spins"

    Below the form is one list of rewards (e.g. "10% off", "₱250 off"), each with a **rarity %**.
- **The customer's My Rewards page** (`/portal/rewards`) shows "You have N spins", a spinning wheel, and a "Spin the wheel" button. Winning gives the customer a **coupon**: a one-time discount they can pick during booking. The wheel only appears on this page, so customers have to go there to find it.
- **Behind the scenes**, the database gives a customer a spin automatically in two cases: when a booking is marked Completed and their completed-booking count hits a multiple of 5, or when one payment is fully paid for ₱5,000 or more. The app does not keep track of logins at all.

## What's wrong / what's missing

1. **The rarity %s must add up to exactly 100.** The database checks this after _every single change_, so adding a new reward always fails: the total jumps to more than 100 for a moment and the change is rejected. Switching a reward off also fails. In practice the reward list can't be changed from the app.
2. **There is only one wheel.** An admin can't say "monthly loyal customers spin a wheel of only rare rewards."
3. **Logins don't count for anything.** There are no daily-login or login-streak rewards because nothing records when a customer visits.
4. **The spin wheel is a separate settings page** rather than a kind of promo, even though it is a promotion.
5. **Customers only find out about spins if they go to My Rewards.** Nothing pops up.
6. **Archived rewards can't be restored.** The "restore" and "delete forever" actions exist on the server, but the Archive page has no tab for rewards.

## What we're going to change

This is a large session. It starts on a **new branch off `dev`**, not the unrelated vet-queue branch that is checked out right now.

### Database

1. **Add "Coupon spin wheel" as a third promo type.** It runs in its own migration file because Postgres needs a new enum value saved before anything else can use it.
   - _Which files:_ new `supabase/migrations/20260925208_custom_promos_promo_type_add_spin_wheel.sql`
   - _Why:_ this is the literal "coupon spin as a type when making a new promo" ask.

2. **Replace "rarity %" with a rarity tier plus a weight, and remove the must-equal-100 rule.**
   - A reward's chance is now worked out as _its weight ÷ the total weight of all rewards in the same pool_. For example, a pool with weights 50, 30 and 20 gives chances of 50%, 30% and 20%. Adding a fourth reward with weight 50 just changes the chances to 33%, 20%, 13% and 33%, with nothing for the admin to rebalance.
   - Existing rewards keep their exact current odds: each old % becomes its weight, and its tier is derived from how rare it was.
   - _Which files:_ new migration `..._209_custom_rewards_rarity_tiers_and_weights.sql`
   - _Why:_ this is the "freely add a reward without making it total 100%" ask, and it also fixes problem 1 above.

3. **Add reward pools.** A **reward pool** is a named group of rewards (e.g. "Standard" or "Rare Rewards"). One reward can be in several pools. There are two new tables: `reward_pools`, and `reward_pool_rewards`, which records which rewards are in which pool.
   - _Which files:_ new migration `..._210_custom_rewards_create_reward_pools.sql`
   - _Why:_ this is the "multiple reward pools" ask.

4. **Store each spin-wheel promo's settings.** A new table, `spin_wheel_promo_settings`, holds one row per spin-wheel promo:
   - which pool it uses
   - its pity number
   - its trigger conditions: every X bookings, payment ≥ ₱X, and one login condition with its N days

   The login condition is a _single_ column, so the database itself makes it impossible to have two login conditions on one promo. Spin-wheel promos have no discount amount of their own (the rewards do), so a promo's discount fields become optional _only_ for this type.
   - _Which files:_ new migration `..._211_custom_promos_spin_wheel_settings.sql`
   - _Why:_ this gives the "trigger conditions, reward pool, pity system" fields somewhere to live, and enforces "some conditions can't be enabled at the same time."

5. **Start recording customer logins.** A new table, `customer_login_days`, stores one row per customer per day they visited, using Philippine time. Existing spin records also learn _which promo_ they belong to. The database also refuses to hand out the same spin twice: for example, the same promo can't grant two daily-login spins on the same day.
   - _Which files:_ new migration `..._212_custom_rewards_login_days_and_credit_sources.sql`
   - _Why:_ daily-login and streak conditions need a record of logins.

6. **Convert today's setup into the new shape automatically, in every database.**
   - A pool called **"Standard"** is created, containing every current reward.
   - A spin-wheel promo called **"Loyalty Spin"** is created with today's settings (every 5 bookings, ₱5,000 payment, pity 10).
   - Every spin a customer already has is attached to "Loyalty Spin", so nobody loses a spin.

   This is done in a migration, not a seed script, because seed scripts only run when a database is wiped and rebuilt. The shared dev and live databases never get wiped.
   - _Which files:_ new migration `..._213_custom_rewards_backfill_standard_pool_and_loyalty_promo.sql`
   - _Why:_ nothing breaks and nobody loses spins on the real databases.

7. **Rewrite the "earn a spin" and "spin the wheel" database logic.**
   - The completed-booking and big-payment rules now check _every active spin-wheel promo_ instead of one global setting.
   - A new function, `record_customer_login`, records today's visit and hands out any daily or streak spins that are due.
   - The `spin_wheel` function now:
     - uses the pool of the promo the spin came from
     - picks by weight
     - applies pity per customer _per promo_
     - guarantees the pool's **rarest tier** when pity kicks in

   Streaks only count days on or after the promo started, so a brand-new promo doesn't instantly pay out for old visits. **(Planner's call. Say so if you'd rather count older days too.)**
   - _Which files:_ new migration `..._214_custom_rewards_rewrite_spin_wheel_rpc_and_grant_triggers.sql`
   - _Why:_ this is the engine behind every trigger condition and pool.

8. **Remove the old global settings table and the old rarity % column.**
   - _Which files:_ new migration `..._215_custom_rewards_drop_spin_wheel_config_and_rarity_percent.sql`
   - _Why:_ they are fully replaced, and leaving them around would confuse the next developer.

### Server (the Express API)

9. **Reward and reward-pool endpoints.**
   - Reward create and edit now take a tier and a weight.
   - New endpoints (URLs the admin screens call) can list, create, edit, archive, restore and permanently delete reward pools.
   - The server refuses two unsafe actions: switching off a pool that an active promo still uses, and deleting a pool a promo points to.
   - The old "global settings" endpoints are removed.
   - _Which files:_ `server/src/features/rewards/rewards.routes.ts`, `rewards.controller.ts`, `rewards.types.ts`, `modules/validators/rewards.validator.ts`, new `modules/rewardChance.ts`, `services/spinWheelConfig.service.ts` (renamed to `spinWheelRewards.service.ts`), new `services/rewardPools.service.ts`
   - _Why:_ the Rewards and Reward Pools tabs need these endpoints.

10. **Promo create and edit understand the spin-wheel type.**
    - A spin-wheel promo _must_ have a pool and at least one trigger condition. It _must not_ have its own discount amount.
    - It can't be switched on if its pool has no active rewards.
    - _Which files:_ `server/src/features/maintenance/modules/validators/maintenance.validator.ts`, `server/src/features/maintenance/services/promos.service.ts`
    - _Why:_ bad combinations are rejected on the server, not only hidden on screen.

11. **Spin-wheel promos never act as a discount.**
    - The booking step's promo list, the cashier's automatic promo pass, and the public price catalog all skip spin-wheel promos.
    - While in there, also fix a small existing bug: the cashier's automatic promo pass could still pick up _archived_ promos.
    - _Which files:_ `server/src/shared/services/promoEligibility/promoEligibility.service.ts`, `server/src/features/billing/services/discountPromoEvaluation.service.ts`, `server/src/features/booking/services/booking.service.ts`
    - _Why:_ a "spin the wheel" campaign must never show up as "10% off" on someone's bill.

12. **Customer endpoints: check-in, per-promo spins, per-promo wheel.**
    - `POST /rewards/check-in` records today's visit and returns any new spins.
    - "My spins" now answers "3 spins total: 2 from Loyalty Spin, 1 from Monthly Login Bonus".
    - "Spin" takes which promo to spin.
    - A new endpoint returns one promo's wheel: its rewards, with their tiers and % chances.
    - _Which files:_ new `server/src/features/rewards/services/checkIn.service.ts`, `services/spinWheel.service.ts`
    - _Why:_ the pop-up, the spin counter and the per-promo wheels need these.

### Admin screens

13. **Promos & Rewards tabs become Promos | Rewards | Reward Pools.** The Coupon Spin Wheel tab is removed.
    - _Which files:_ `client/src/features/maintenance/pages/AdminPromosAndRewardsPage/AdminPromosAndRewardsPage.tsx`
    - _Why:_ this is the literal "remove coupon spin wheel subpage, add rewards and reward pools" ask.

14. **The New promo wizard gets a third type, "Coupon spin wheel".** Choosing it shows its own form:
    - a reward pool picker
    - a checkbox for "every X completed bookings"
    - a checkbox for "single payment of at least ₱X"
    - a **login condition** choice: None / Daily login / Weekly streak of N days / Monthly streak of N days. These are radio buttons, so only one can ever be picked.
    - an optional pity number, with a hint like "guarantees a Legendary reward"
    - optional start and end dates

    The promo list shows these as "Spin wheel · Standard pool · every 5 bookings, daily login".
    - _Which files:_ `client/src/features/maintenance/pages/AdminPromoConfigPage/AdminPromoConfigPage.tsx`, new `client/src/features/maintenance/components/SpinWheelPromoFields/`, `promoBrowserFields.ts`
    - _Why:_ this is the literal "Add New Promo > Coupon Spin Wheel" ask.

15. **Rewards tab.** This is today's reward list, moved and cleaned up.
    - An **Add New Reward** button opens a pop-up form: title, rarity tier, weight, discount type (% or ₱) and amount.
    - Each reward shows a tier badge and which pools use it.
    - The old three-number settings form is gone; those settings now live on each promo.
    - _Which files:_ `client/src/features/rewards/pages/AdminSpinWheelConfigPage/` moves to `client/src/features/rewards/pages/AdminRewardsPage/`
    - _Why:_ this is the "Add New Reward > reward form" ask.

16. **Reward Pools tab, with a pool builder.**
    - An **Add New Reward Pool** button opens a builder: a name and description, then a searchable checklist of rewards grouped by tier.
    - As you tick rewards, a live table shows each one's **% chance**, recalculated instantly.
    - The builder also shows a note saying which tier pity will guarantee, and a warning if the pool has no active rewards.
    - The pool list has the usual search, filter, sort, table/list/board views, and a "…" menu (Configure / Activate / Deactivate / Archive).
    - _Which files:_ new `client/src/features/rewards/pages/AdminRewardPoolsPage/`, new `client/src/features/rewards/components/RewardPoolBuilderModal/`
    - _Why:_ this is the "Add New Reward Pool > reward pool builder form" ask.

17. **Archive page gets Spin Wheel Rewards and Reward Pools tabs**, so archived items can be restored or deleted for good.
    - _Which files:_ `client/src/features/staff/pages/AdminArchivePage/AdminArchivePage.tsx`
    - _Why:_ this fixes problem 6. Archiving without a way back would be a trap.

### Customer screens

18. **Spin pop-up after login.**
    - Once a day, the customer app quietly "checks in" with the server. That visit is what counts toward daily and streak conditions.
    - If the customer has any spins, a pop-up opens showing one button per promo with its count (e.g. "Loyalty Spin ×2"), the wheel for the selected promo, and two buttons: **Spin now** and **Skip for now**.
    - Skipping keeps the spin. The pop-up stays closed until the customer earns _another_ spin.
    - The pop-up never opens on the My Rewards page itself, since the wheel is already there.
    - _Which files:_ new `client/src/features/rewards/providers/SpinCreditsProvider.tsx` (modelled on the existing `CreditBalanceProvider`), new `client/src/features/rewards/components/SpinWheelPopup/`, `client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx`
    - _Why:_ this is the "make the coupon spin wheel pop-up" ask, plus your "allow customers to skip" request.

19. **A "N spins" chip in the customer's top bar**, next to the existing credit balance chip. It is always visible and links to My Rewards.
    - _Which files:_ new `client/src/features/rewards/components/SpinCreditsIndicator/`, `client/src/shared/components/AppShell/AppShell.tsx`, `client/src/shared/components/Navbar/Navbar.tsx`
    - _Why:_ this is your "allow them to see how many spins they have" request.

20. **My Rewards shows one wheel per promo.** A picker at the top lists each promo with its spin count. The wheel's slices are sized by each reward's computed % chance, and the legend shows tier and %.
    - _Which files:_ `client/src/features/rewards/pages/CustomerRewardsPage/CustomerRewardsPage.tsx`, `client/src/features/rewards/components/SpinWheel/SpinWheel.tsx`
    - _Why:_ customers can now have spins from several promos, and each promo has its own pool.

### Sample data and tests

21. **Update the seed script.**
    - Rewards get tiers and weights and are added to the "Standard" pool.
    - A demo **"Rare Rewards"** pool is added.
    - A demo **"Monthly Login Bonus"** spin promo is added (5-day streak within a month, pity 3).
    - _Which files:_ `supabase/seeds/custom-rewards/custom-rewards.seed.ts`, `.seed.sql`, `.seed.spec.ts`
    - _Why:_ a freshly built database has something realistic to click through.

22. **Tests.**
    - _Server:_ new or updated tests for:
      - the chance calculation
      - reward pools (can't delete one that's in use)
      - check-in (staff accounts are refused)
      - spinning by promo
      - the promo form rules for the spin type
      - spin promos never being applied as discounts
    - _Client:_ new or updated tests for:
      - the three tabs
      - the wizard's third type and its single-choice login condition
      - the pool builder's live %
      - the pop-up's spin, skip and reopen-on-new-spin behavior
      - check-in happening once per day
    - _Which files:_ spec files next to each changed file.
    - _Why:_ these cover the rules most likely to break silently later.

## Words you might not know

- **migration**: a small, numbered file that changes the database's structure (adds a table, a column or a rule) in a repeatable way, so every copy of the database ends up identical.
- **enum**: a column type that only allows values from a fixed list, like `date_range`, `weekly_recurring` and `spin_wheel`.
- **seed script**: a script that fills a fresh database with starter/demo rows. It only runs when a database is wiped and rebuilt, which is why step 6 is a migration instead.
- **trigger (database)**: code that runs automatically when a row changes. For example, "the moment a booking becomes Completed, check if a spin is due."
- **RPC / database function**: a named function stored inside the database that the server calls as one all-or-nothing step, so two clicks at the same moment can't hand out two spins.
- **RLS (row-level security)**: Postgres rules deciding who may read or change each row. For example, "a customer can see only their own login days."
- **weight**: a plain number saying how _likely_ a reward is compared to the others in its pool. Bigger means more likely. The % is worked out automatically.
- **rarity tier**: a label (Common … Legendary) that tells admins and customers how special a reward is. Pity uses it.
- **pity system**: a safety net. After N spins in a row without hitting the pool's rarest tier, the next spin is guaranteed to hit it.
- **reward pool**: a named group of rewards that one spin-wheel promo draws from.
- **spin credit**: one "you may spin once" token. It is earned from a trigger condition and used up when you spin.
- **idempotent**: doing it twice has the same effect as doing it once. A check-in sent twice on the same day still gives only one daily spin.
- **Manila time**: all "which day is it" decisions use Philippine time, so a login at 11pm and one at 1am the next morning count as two different days, as a customer would expect.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks, the server/client test-suite results, the Postman collection (`testing/spin-wheel-promo-triggers-and-pools.postman_collection.json`), and the reference migration copy with verification queries (`testing/spin-wheel-promo-triggers-and-pools.sql`). All 8 migrations have since been pushed to and verified live against the dev project (`hikgijuipymfghfuyrjv`) — see testing.md's "Database" and "Database-level checks" sections, including a real migration ordering bug (209's trigger drop vs. its backfill UPDATE) that was only caught by pushing for real, not by the mocked unit tests. Prod still needs the same push once this branch is promoted; see testing.md's "Open items" for what's still unverified (concurrent check-ins, a real pity hit, prod).
