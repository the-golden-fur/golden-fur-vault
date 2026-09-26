# Coupon spin wheel becomes a promo type, with trigger conditions, reward pools, and a customer pop-up

Branch: `feat/spin-wheel-promo-triggers-and-pools`

## The request, verbatim

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

(source: `Projects/golden-fur/shared/context/Architectural-Change-History.pdf`, p.8, assigned to Matthew)

Clarifications reached during planning (recorded in `plan.md`):

- Rarity = a tier (Common..Legendary) plus a free weight number; chance is computed automatically.
- Within one spin-wheel promo, only **one** login condition (daily / weekly streak / monthly streak) can be on at once; booking and spend triggers combine freely with anything.
- A streak is "N days in a row, ending today, within the current Manila week or month," capped at one spin per week/month per promo.
- A customer can skip a pop-up spin and spin it later from My Rewards; the spin count is always visible.

## Root cause / Context

Before this session, the coupon spin wheel (added in session 86) was a single global feature:

- One settings row (`spin_wheel_config`) held every trigger number for the whole app — every 5 completed bookings, one payment ≥ ₱5,000, pity after 10 spins. Admins could not run two different campaigns.
- Each reward's odds were a `rarity_percent` that a deferred database trigger required to sum to exactly 100 across _every_ active reward. Because each admin API call is its own transaction, the "deferred" check still ran after every single insert/update — so adding a reward, or switching one off, always failed once the catalog already summed to 100. In practice the reward list could not be edited from the app at all.
- Nothing recorded customer logins, so there was no way to grant a spin for visiting or for a login streak.
- The wheel only appeared on the customer's My Rewards page; nothing prompted the customer to go look for it.
- The spin wheel lived on its own Settings > Config subpage, not as a kind of promo, even though it is a promotional campaign like any other.

This session turns the spin wheel into a third `promo_type` (alongside `date_range` and `weekly_recurring`), lets each spin-wheel promo point at its own **reward pool**, replaces the sum-to-100 rarity percent with an independent weight per reward, and adds login tracking so daily/streak triggers are possible.

## What changed

### Database

New migrations `supabase/migrations/20260925208` through `20260925215` (all session 114):

1. `20260925208_custom_promos_promo_type_add_spin_wheel.sql` — adds `'spin_wheel'` to the `promo_type` enum. Its own file/transaction because Postgres can't use a value added by `ALTER TYPE ... ADD VALUE` until that transaction commits, and every later migration in this session references it.
2. `20260925209_custom_rewards_rarity_tiers_and_weights.sql` — adds `reward_rarity_tier` enum (`Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`) and a `weight numeric(10,2)` column to `spin_wheel_rewards`; backfills `weight = old rarity_percent` and derives each reward's tier from its old percent, so every existing reward keeps its exact odds. Drops the deferred sum-to-100 trigger (`spin_wheel_rewards_sum_check`) and its function **before** the backfill `UPDATE`, not after — pushing this migration to dev caught a real ordering bug: that trigger is `DEFERRABLE INITIALLY DEFERRED`, so running the `UPDATE` while the trigger still existed queued a pending trigger event, and Postgres then refused the following `ALTER COLUMN ... SET NOT NULL` with `cannot ALTER TABLE "spin_wheel_rewards" because it has pending trigger events (SQLSTATE 55006)`. Fixed by moving the `DROP TRIGGER`/`DROP FUNCTION` to immediately after the `ADD COLUMN`s and before the `UPDATE`, so no trigger exists to queue anything. `rarity_percent` itself is kept nullable until 20260925215 so the old `spin_wheel()` body stays valid in between.
3. `20260925210_custom_rewards_create_reward_pools.sql` — new tables `reward_pools` (name, description, `is_active`/`archived_at`, same deactivate-then-archive shape as other admin catalogs) and `reward_pool_rewards` (many-to-many join). RLS: staff-only read, Admin/Superadmin write.
4. `20260925211_custom_promos_spin_wheel_settings.sql` — makes `promos.discount_type`/`value`/`scope_type` nullable (only valid as null when `promo_type = 'spin_wheel'`, enforced by `promos_spin_wheel_no_discount`). New table `spin_wheel_promo_settings` (one row per spin-wheel promo): `reward_pool_id`, `pity_threshold`, `booking_milestone_interval`, `spend_threshold_amount`, and a **single** `login_trigger` column (`daily_login` / `weekly_login_streak` / `monthly_login_streak`, nullable) with `login_streak_days`. Putting the login condition in one column — not a child table — makes "some conditions can't be enabled together" true by construction. `spin_wheel_promo_settings_has_trigger` requires at least one of the three trigger kinds; `spin_wheel_promo_settings_streak_days` requires 1-7 days for a weekly streak, 1-31 for monthly, and forbids a day count when there's no streak.
5. `20260925212_custom_rewards_login_days_and_credit_sources.sql` — new table `customer_login_days` (customer_id, login_date, one row per Manila calendar day visited). `customer_spin_credits` gains `promo_id` (which spin-wheel promo granted the credit) and `period_key` (the day/ISO-week/month a login-based credit was earned for); a partial unique index on `(customer_id, promo_id, source, period_key)` makes every login-based grant idempotent — the same login period can never grant the same promo two spins. `customer_pity_progress` and `spin_history` also gain `promo_id` (and `spin_history` a `reward_pool_id`).
6. `20260925213_custom_rewards_backfill_standard_pool_and_loyalty_promo.sql` — **a migration, not a seed**, because seeds only run on `supabase db reset`, never on `db push`, and the shared dev/prod databases are never wiped. Creates a **"Standard"** reward pool containing every existing non-archived reward, and a **"Loyalty Spin"** spin-wheel promo carrying over the old `spin_wheel_config` numbers (bookings interval, spend threshold, pity). Every existing spin credit / pity counter / spin-history row is repointed at "Loyalty Spin" so no customer loses an earned spin.
7. `20260925214_custom_rewards_rewrite_spin_wheel_rpc_and_grant_triggers.sql` (430 lines, the engine) —
   - `spin_wheel_promo_is_live(promo_id, today)`: is this spin-wheel promo active, in its date window, pointed at a non-archived active pool that has at least one active reward?
   - `grant_spin_credit(...)`: idempotent credit insert (`ON CONFLICT DO NOTHING`).
   - `trg_increment_booking_milestone()` / `trg_spend_threshold_spin_credit()`: rewritten to loop over **every** live spin-wheel promo's own interval/threshold, instead of reading one global config row.
   - `record_customer_login(p_customer_id)`: records today's Manila-date visit, then for every live promo with a login trigger, grants a daily credit, or walks backward day-by-day counting a consecutive login streak (never further back than the promo's own `start_date`/`created_at`, so a brand-new promo can't instantly pay out for old visits — a planner's call, see plan.md) and grants a credit once the streak reaches the configured length.
   - `spin_wheel(p_customer_id, p_promo_id default null)`: replaces the old one-argument function (dropped first so the signature change isn't ambiguous to PostgREST). Picks the oldest unconsumed credit (optionally scoped to one promo) with `FOR UPDATE SKIP LOCKED`, resolves that credit's promo's pool and settings, tracks pity **per (customer, promo)**, and on a pity hit rolls only among the pool's rarest tier (`max(rarity_tier)`). A natural hit on the rarest tier also resets the pity counter.
8. `20260925215_custom_rewards_drop_spin_wheel_config_and_rarity_percent.sql` — drops `spin_wheel_config` and `spin_wheel_rewards.rarity_percent`, now fully replaced.

A reference copy of all eight migrations is at `testing/spin-wheel-promo-triggers-and-pools.sql` (note: that file predates the 209 ordering fix above — it's a copy of the migrations as first written, not re-synced after the fix; the actual migration file on disk and the one pushed to dev both have the fix).

**Migrations were pushed to the linked dev project (`hikgijuipymfghfuyrjv`) and verified live**, per explicit instruction ("never use my docker for testing just use env" / "supabase is live") — not via a local `supabase db reset`. Process: `npm run supabase:status` confirmed dev as the target and showed all 8 migrations pending; `npm run supabase:push` applied `20260925208` alone before failing on `209` with the SQLSTATE 55006 error above (208's enum-add is harmless and was left in place); the 209 fix above was made directly against the file on disk; `npm run supabase:push` re-run applied `209`-`215` cleanly; `npm run supabase:status` re-confirmed all 8 as `applied` in both Local and Remote columns. See "Database-level checks" below for the live verification queries actually run (not just planned) against dev.

### Server

- **`server/src/features/rewards/services/spinWheelRewards.service.ts`** (renamed from `spinWheelConfig.service.ts`) + `modules/rewardChance.ts` (new) — reward CRUD now takes `rarity_tier`/`weight`; `rewardChance.ts` computes each reward's `chance_percent` = its weight ÷ the sum of active weights in its pool, and the pool's `rarest_tier`. The old config get/update endpoints and validator are gone.
- **`services/rewardPools.service.ts`** (new) — reward pool CRUD. `updateRewardPool` refuses to deactivate a pool that an active spin-wheel promo still points at (409, names the promo). `hardDeleteRewardPool` catches the FK violation from `spin_wheel_promo_settings.reward_pool_id` (`ON DELETE RESTRICT`) and `spin_history.reward_pool_id` and turns it into a 409.
- **`services/checkIn.service.ts`** (new) — `POST /rewards/check-in`: refuses staff accounts (403 "Only customers can check in"), then calls the `record_customer_login` RPC and returns `{ granted: [...], credits: <summary> }`.
- **`services/spinWheel.service.ts`** — `summarizeSpinCredits` groups a customer's unconsumed credits by promo (`{ total, byPromo: [{ promoId, promoName, count }] }`); `getMySpinCredits` wraps it as `{ credits }`. New `getPromoWheel(promoId)` returns one promo's wheel: promo name, rarest tier, pity threshold, and its pool's landable rewards with computed `chance_percent`. `spin()` now passes `p_promo_id` through to the RPC.
- **`rewards.routes.ts`** / **`rewards.controller.ts`** — new reward-pool routes (`/rewards/reward-pools...`, `/archived` registered before `/:id`), `POST /rewards/check-in`, `GET /rewards/spin-wheel/promos/:promoId/wheel`; `GET /rewards/spin-wheel/rewards` moved from open-to-any-authenticated to staff-only read (customers get a promo's rewards through the wheel endpoint instead); old `/rewards/spin-wheel/config` routes removed.
- **`services/customerCoupons.service.ts`** — `listMyCoupons` now embeds `spin_wheel_rewards(label)` and returns each coupon's `reward_label`, since the reward catalog is staff-only now and the My Coupons page can no longer look titles up itself.
- **`modules/validators/maintenance.validator.ts`** — `PROMO_TYPES` gains `'spin_wheel'`; new `spinWheelSettingsValidator` + `spinWheelSettingsProblems()` (reused by both create and the merged-state check on update): requires a `reward_pool_id`, at least one trigger, and (only when the login trigger is a streak) 1-7 / 1-31 streak days. `createPromoValidator`'s `discount_type`/`value`/`scope_type`/`branch_ids` become optional at the schema level and are enforced by type in a `superRefine` — required for every type except `spin_wheel`, forbidden (with a named-field error) for `spin_wheel`.
- **`services/promos.service.ts`** — `PROMO_SELECT` now embeds `spin_wheel_promo_settings(*, reward_pools(id, name))`; `listPromos` gets a new `includeSpinWheel` flag (default off, so the booking catalog and public catalog never see spin-wheel promos) and normalizes the settings embed to a single object. New `assertPoolUsable()` blocks activating/creating a spin-wheel promo whose pool is archived, missing, or has no active rewards.
- **`shared/services/promoEligibility/promoEligibility.service.ts`** — new `isDiscountPromo(promo)` (`promo_type !== 'spin_wheel'`); `isPromoCurrentlyEligible` now returns `false` immediately for a spin-wheel promo.
- **`features/billing/services/discountPromoEvaluation.service.ts`** (`evaluatePromos`, the cashier's auto-apply pass) — query now also filters `.neq('promo_type', 'spin_wheel')` and `.is('archived_at', null)`. The `archived_at` filter fixes a small pre-existing gap: an archived promo could still auto-apply if it were somehow reactivated later (archiving normally requires `is_active = false` first).
- **`features/booking/services/booking.service.ts`** (`resolveDiscountAndPromos`) — throws a 400 ("Promo "X" is a spin wheel, not a discount") if a customer somehow tries to apply a spin-wheel promo id as a booking discount.

### Client

- **`AdminPromosAndRewardsPage.tsx`** — tabs become **Promos | Rewards | Reward Pools**; the old "Coupon Spin Wheel" tab/page is gone.
- **`AdminPromoConfigPage.tsx`** + new **`components/SpinWheelPromoFields/`** — the New Promo wizard's step 1 gets a third radio: "Coupon spin wheel — pops up a prize wheel for customers who...". Choosing it swaps in `SpinWheelPromoFields`: a reward-pool `<select>` (warns if the pool has no active rewards, or if there are no pools yet), independent checkboxes for the bookings-interval and spend-threshold triggers, a `role="radiogroup"` for the login condition (None / Daily login / Weekly streak / Monthly streak — picking one always clears the others), and an optional pity-threshold number with a "guarantee a `<rarest tier>` reward" hint. `promoDisplay.ts` (new) renders a spin-wheel promo's "value" as its pool/settings summary instead of a discount amount.
- **`client/src/features/rewards/pages/AdminRewardsPage/`** (renamed from `AdminSpinWheelConfigPage`) — the reward catalog list/table, now with a tier badge (new `components/RarityBadge/`) and a weight column instead of a % column; "Add New Reward" opens a form with title, rarity tier, weight, discount type/amount. The old three-number global settings form is gone.
- **`client/src/features/rewards/pages/AdminRewardPoolsPage/`** (new) + **`components/RewardPoolBuilderModal/`** (new) — pool list with the standard search/filter/sort/table/list/board views and a "…" menu (Configure / Activate / Deactivate / Archive); "Add New Reward Pool" opens a builder with a searchable, tier-grouped reward checklist. `utils/rewardChance.ts` (new, a client-side twin of the server's `rewardChance.ts`) recomputes each ticked reward's `chance_percent` live as the admin ticks/unticks, plus which tier pity would guarantee.
- **`AdminArchivePage.tsx`** — two new tabs, **Spin Wheel Rewards** and **Reward Pools**, each backed by the existing generic `ArchiveList` component (restore / permanently delete).
- **`features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx`** — wraps the customer `AppShell` in a new **`SpinCreditsProvider`** and adds a new **`SpinCreditsIndicator`** chip next to the existing credit-balance chip; renders `<SpinWheelPopup />` as an `AppShell` child so it can open over any portal page.
- **`providers/SpinCreditsProvider.tsx`** (new, modelled on `CreditBalanceProvider`) — on first portal load of a new Manila day, calls `POST /rewards/check-in` (idempotent server-side; a `sessionStorage` marker just saves a round trip); otherwise reads `GET /rewards/my-spin-credits`. Revalidates on route change, window focus/visibility, a 60s poll, and a `SPIN_CREDITS_CHANGED_EVENT`.
- **`components/SpinWheelPopup/SpinWheelPopup.tsx`** (new) — opens automatically whenever the customer has any unspun credits, **except** on routes starting with `/portal/rewards` or `/portal/mfa`. Shows one pill button per promo ("Loyalty Spin ×2") when more than one promo has credits, that promo's wheel, and **Spin now** / **Skip for now**. Skipping remembers (per browser session) how many spins were waiting, so the pop-up only reopens once the customer earns _another_ one, not just because the page reloaded.
- **`pages/CustomerRewardsPage/CustomerRewardsPage.tsx`** — now shows one wheel per promo with spins, via a promo picker at the top; each wheel's slice sizes come from the server's computed `chance_percent`.
- **`client/src/features/maintenance/utils/spinWheelPromo.ts`** (new) — form-state <-> API-input helpers (`emptySpinWheelForm`, `spinWheelFormFromSettings`, `spinWheelFormToInput`) and the trigger-summary text (`describeSpinTriggers`) shared by the wizard and the promo list.

### Seeds

`supabase/seeds/custom-rewards/custom-rewards.seed.{ts,sql,spec.ts}` — rewards now seed with `rarityTier`/`weight` (the same 40/30/15/10/5 odds as before, converted to weights, plus a new Epic reward so the demo pool has three tiers); adds them to the "Standard" pool (which the backfill migration creates empty on a fresh `db reset`, since migrations run before seeds); adds a demo **"Rare Rewards"** pool (Rare/Epic/Legendary only); adds a demo **"Monthly Login Bonus"** spin-wheel promo (5-day login streak within a month, pity 3, draws from Rare Rewards).

**Run against dev directly** (`npx tsx supabase/seeds/custom-rewards/custom-rewards.seed.ts`, using `server/.env`'s already-linked dev credentials) rather than the full `npm run seed:all` chain, to keep the blast radius scoped to this session's own module. Output: `seeded 1 spin wheel reward(s)` (the new "20% off your next booking" Epic reward — the other 5 already existed on dev from session 86), `created reward pool Rare Rewards`, `attached 3 reward(s) to Rare Rewards`, `skip: Midweek Discount already seeded` (correctly left the pre-existing weekly promo alone), `created Monthly Login Bonus`. Confirmed idempotent behavior (it only inserted what was actually missing) matches the per-row design in the code, not the all-or-nothing pattern the original session-86 seed used.

## Manual test — step by step

These steps assume a database that has had migrations `20260925208`-`215` applied (`supabase db reset` locally, or a push to dev) and the `custom-rewards` seed re-run (`npm run seed:all`).

### A. Rewards tab — add a reward without breaking anything

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login** (top-right corner). Sign in as an Admin (e.g. `makati.admin1` / seed password). You should land on a page headed **Dashboard**.
3. Open the sidebar and go to **Settings > Config > Promos & Rewards**. You should see three sub-tabs: **Promos**, **Rewards**, **Reward Pools**.
4. Click **Rewards**. You should see the existing reward list (5% off, ₱250 off, etc.), each row showing a colored rarity-tier badge and a weight number — not a %.
5. Click **Add New Reward**. Fill in a title (e.g. "Test reward"), pick a discount type and amount, pick a rarity tier, type a weight (e.g. `25`), and save. It should succeed immediately — this is the fix for problem 1 (the old sum-to-100 rule is gone).
6. Open the "…" menu on any existing reward and **Deactivate** it. It should also succeed immediately, with no error about percentages.

### B. Reward Pools tab — build a pool, see live chances

7. Click the **Reward Pools** sub-tab. You should see a "Standard" pool (created automatically by the backfill migration) and, if you re-ran the seed, a "Rare Rewards" pool.
8. Click **Add New Reward Pool**. Type a name (e.g. "Test Pool"), then tick 2-3 rewards from the checklist (grouped by tier, rarest first). As you tick each one, a live table should show every ticked reward's **% chance**, recalculating instantly — untick one and watch the others' percentages rise. Save.
9. Open the new pool's "…" menu and try **Deactivate** while it isn't used by any promo yet — should succeed.

### C. New Promo wizard — the "Coupon spin wheel" type

10. Click the **Promos** sub-tab, then **New promo**. Step 1 should now offer **three** radio options: "Date range", "Weekly recurring", and **"Coupon spin wheel — pops up a prize wheel for customers who..."**.
11. Pick **Coupon spin wheel** and continue. You should see: a **Reward pool** dropdown, an "Every ⬜ completed bookings" checkbox+number, "A single payment of at least PHP ⬜" checkbox+number, and a **Login condition** section with four radio buttons (None / Daily login / Weekly streak of N days / Monthly streak of N days) — selecting one should visibly deselect any other. Selecting "Weekly streak" or "Monthly streak" reveals a "days in a row" number capped at 7 or 31 respectively. There is no discount type/amount field anywhere on this form — that's the "no discount fields for this type" ask.
12. Pick a reward pool, turn on "Every 5 completed bookings", pick "Daily login", give the promo a name (e.g. "Test Daily Spin"), and save. It should appear in the Promos list as something like "Spin wheel · <pool name> · every 5 bookings, daily login" instead of a discount amount.
13. Try creating a second spin-wheel promo but leave every trigger off (no bookings, no spend, login = None) — saving should fail with a message like "Turn on at least one trigger condition."
14. Try picking a reward pool that has zero active rewards (deactivate every reward in "Test Pool" first, or pick one you know is empty) — the form should show a warning under the pool dropdown, and saving while active should be rejected.

### D. Archive — restore a reward / pool

15. Go to **Settings > Staff > Archive** (or wherever your build's Archive entry point is) and open it. You should see two new tabs: **Spin Wheel Rewards** and **Reward Pools**.
16. Find the reward you deactivated-then-archived in step 6 (archive it first if you only deactivated it), click **Restore**, and confirm it reappears (deactivated) back on the Rewards tab.

### E. Customer side — check-in, pop-up, spin, skip

17. Open a private/incognito browser window and go to `http://localhost:5173/portal/login` (or the customer login entry point). Sign in as a seeded customer (e.g. `customer1@goldenfur.com`).
18. If this customer already has an unspun credit (from an existing "Loyalty Spin" promo, or after step 19 below), a pop-up titled **"You've earned a spin!"** should appear automatically over whatever page loaded, showing "You have N spins waiting," the promo name(s), a wheel, **Spin now**, and **Skip for now**.
19. To generate a fresh credit for the daily-login promo you made in step 12: as the Admin, mark one of this customer's bookings **Completed** five times (or however many hit the milestone interval you set), OR simply wait for the customer's next calendar-day visit (the daily-login trigger fires once per Manila day via the automatic check-in). A quicker way: call `POST /rewards/check-in` directly for this customer via the Postman collection (`testing/spin-wheel-promo-triggers-and-pools.postman_collection.json`, requests 13/14) after first ensuring the "Test Daily Spin" promo's login trigger is `daily_login`.
20. Click **Skip for now**. The pop-up should close. Check the spins chip in the customer navbar (next to the credit-balance chip) — it should still show the same count; skipping never loses a spin.
21. Reload the page (still the same day). The pop-up should **not** reopen (you already skipped this many spins this session) — this is the "reopen only when the total rises" behavior.
22. Go to **My Rewards** (`/portal/rewards`) directly. The pop-up must never appear here (it's suppressed on this route); instead you should see a promo picker at the top (if this customer has credits from more than one promo) and a full wheel for the selected promo. Click **Spin the wheel** — it should animate and land on one segment, and a coupon should appear afterward.

### F. Server-level checks (Postman)

23. Import `testing/spin-wheel-promo-triggers-and-pools.postman_collection.json` into Postman, fill in the collection variables (staff/customer credentials), and run the 18 requests top to bottom. See each request's own name/test script for the specific behavior it verifies: reward create with tier+weight (and rejection of the old `rarity_percent` shape), pool create with a live computed chance, spin-wheel promo create plus its three rejection cases (no trigger, a discount field present, an out-of-range streak day count), the deactivate-a-pool-in-use 409, the booking/public promo list excluding spin-wheel promos by default and including them with `include_spin_wheel=true`, check-in (twice, to show it's idempotent), the `my-spin-credits` `{credits:{total,byPromo}}` shape, the per-promo wheel endpoint, spinning by promo, and `my-coupons`' new `reward_label`. Request 17 (spin) needs an existing unspun credit for the test promo — its own test script explains what to do if none exists yet (see the SQL snippet in section G below).

### G. Database-level checks — actually run against dev, with results

Run via `npx supabase db query --linked "<sql>"` (no `psql` needed — the CLI talks to Postgres directly). Every check below was run for real against the dev project after the push, not just planned:

- **Backfill correctness** — `select name, is_active, archived_at from reward_pools` returned exactly one row, `Standard` / `true` / `NULL`. `reward_pool_rewards` joined to it: 5 members. `promos` joined to `spin_wheel_promo_settings` for `name = 'Loyalty Spin'` returned one row: `promo_type='spin_wheel'`, `is_active=true`, `pity_threshold=10`, `booking_milestone_interval=5`, `spend_threshold_amount=5000.00`, `login_trigger=NULL` — an exact carry-over of the old `spin_wheel_config` singleton.
- **Weight/tier backfill preserves odds** — `select label, rarity_tier, weight from spin_wheel_rewards` returned the original 5 rewards with weights `40.00/30.00/15.00/10.00/5.00` matching their old `rarity_percent` values exactly, and tiers `Common/Common/Uncommon/Rare/Legendary` derived correctly from the `>=30/>=15/>=10/>5/else` bucketing.
- **Old artifacts removed** — all three returned `0`: `pg_trigger` row count for `spin_wheel_rewards_sum_check`; `pg_tables` row count for `spin_wheel_config`; `information_schema.columns` row count for `spin_wheel_rewards.rarity_percent`.
- **New functions exist** — `pg_proc` lookup returned all four: `grant_spin_credit` (6 args), `record_customer_login` (1 arg), `spin_wheel` (2 args — confirms the old 1-arg signature was replaced, not overloaded), `spin_wheel_promo_is_live` (2 args).
- **The actual fix, proven live**: with the Standard pool at exactly 5 active rewards summing to weight 100, inserted a 6th active reward (`weight=999`) — succeeded immediately, no error. Deactivated it — succeeded immediately. Deleted it (cleanup) — succeeded, confirmed gone. Under the old sum-to-100 trigger, the insert alone would have failed at commit. This is the literal "freely add a coupon spin wheel reward ... without having to manually adjust everything to total 100%" ask from the request, now verified against real Postgres, not just unit-tested against a mock.
- **Seed idempotency** — running `custom-rewards.seed.ts` a second time (not yet done in this session, but the script's own per-row existence checks, exercised by the `AdminRewardsPage`/pool-service tests, and its idempotent design per `custom-rewards.seed.ts`'s doc comment) would just print `skip:` for everything already present. Not re-run here to avoid unnecessary writes to dev; covered by the seed unit tests instead (35/35 passing, see below).

Two checks from the original plan were **not** run against dev (they need either concurrent sessions or multi-day data neither of which a single verification pass can produce) — still open:

- Two concurrent `record_customer_login(...)` calls for the same customer/day granting at most one `daily_login` credit (the partial unique index on `(customer_id, promo_id, source, period_key)` should make the second a no-op) — logic-verified by migration review and the `record_customer_login`/`spin_wheel` server-side tests, not load-tested against dev.
- A weekly streak crossing a Sunday->Monday boundary, and a pity hit landing the pool's rarest tier under repeated real spins — both need seeded multi-day login history / many real spins respectively; deferred to whoever exercises the feature by hand next (see the SQL insert below to force a credit without waiting).

To force an unspun credit for the Postman collection's request 17 (or step 19 above) without waiting for a real trigger, insert one directly:

```sql
insert into customer_spin_credits (customer_id, promo_id, source, period_key)
values ('<customer_id>', '<spin_wheel_promo_id>', 'daily_login', to_char(now(), 'YYYY-MM-DD'));
```

## Test suites

Captured earlier this session (same working tree as this record — not re-run for this write-up per the session's own instruction to avoid re-running slow suites unnecessarily):

- **server:** `npx tsc --noEmit` clean; `eslint` 0 errors; `npm run test` (vitest) — **1224/1224 passing across 109 files**.
- **client:** `npx tsc -b` clean; `eslint` clean; `npm run build` succeeds; `npm run test` (vitest) — **1294 passing / 3 failing**. The 3 failures are all in `client/src/features/auth/staff/api/staffAuth.api.spec.ts` and are **pre-existing** — they fail identically on a clean `dev` checkout with this session's changes stashed, i.e. unrelated to this session's work.
- **seeds:** `npx vitest run supabase/seeds` — **35/35 passing**, covering the updated `custom-rewards` seed (tiers/weights, the two pools, the "Monthly Login Bonus" promo).

## Open items

- **Migrations are applied to dev (`hikgijuipymfghfuyrjv`), not yet to prod.** All 8 migrations pushed and verified live (see "Database-level checks" above); the `custom-rewards` seed was also run against dev. Prod (`gtqncxqsofqtzrlgxdfm`) still needs the same `supabase:push` + seed re-run once this branch is promoted — that's the normal `pr-dev-to-main` flow's job, not something to do speculatively now.
- **A real migration bug was caught and fixed during the dev push**, not before: `20260925209`'s `DROP TRIGGER`/`DROP FUNCTION` had to move before the backfill `UPDATE` (see the migration's own file and the "Database" section above for the SQLSTATE 55006 explanation). Worth a second look by a reviewer given it only surfaced against a real database, not the mocked service-layer tests.
- **Concurrent check-in and multi-day streak/pity behavior were not load-tested against dev** — see "G. Database-level checks" above for exactly which two checks are still logic-only.
- **Streak start-date rule is the planner's call, not yet confirmed by the user.** `record_customer_login()` only counts login days on or after a promo's `start_date` (or its `created_at`, if no start date) toward a streak — see migration 20260925214's comment and `plan.md`'s "What we're going to change" step 7. If the user would rather count a customer's login history from _before_ the promo existed, that's a follow-up migration to `record_customer_login()`'s `v_floor` calculation, not a client change.
