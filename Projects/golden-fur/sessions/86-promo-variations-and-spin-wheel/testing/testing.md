# Weekly-recurring promos, promo builder wizard, coupon spin wheel, and a multiselect Promos & Coupons booking step

Branch: `feat/promo-variations-spin-wheel` (golden-fur), branched off `dev`.
Vault docs branch: `docs/golden-fur-session-86-promo-spin-wheel`.

## The request, verbatim

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

> As a developer, I want rewards for wheel spin, the thresholds, everything
> in this request, etc. to be seeded to supabase.
> — follow-up clarification given mid-session

## Root cause / Context

Not a bug fix — a from-scratch feature spanning four connected asks (see
`plan.md`). The existing promo system only ever supported one shape (a
date-range window); booking-time promo selection was a single-select
dropdown even though the cashier's checkout-time fallback already knew how
to stack multiple promos against the existing `promo_cap_configuration`.

## What changed

### Database

7 new migrations, `20260913195` through `20260913201`:

- `..._195_custom_promos_add_weekly_recurring_type.sql` — `promo_type`
  (`date_range`/`weekly_recurring`) + `days_of_week` on `promos`.
- `..._196_custom_rewards_create_spin_wheel_config_and_rewards.sql` —
  singleton `spin_wheel_config` (real column defaults: 5 bookings, ₱5000
  spend, pity 10 — not left null/disabled) + `spin_wheel_rewards` with a
  deferred constraint trigger enforcing active rewards' rarity sums to 100.
- `..._197_custom_rewards_create_coupons_milestones_pity.sql` —
  `customer_booking_milestone_progress`, `customer_pity_progress`,
  `customer_spin_credits`, `customer_coupons`.
- `..._198_custom_rewards_create_spin_history_and_spin_wheel_rpc.sql` —
  `spin_history` + the atomic `spin_wheel()` RPC (row-locked, mirrors
  `issue_credit()`/`redeem_credit()`'s style).
- `..._199_custom_rewards_create_completion_triggers.sql` — grants a spin
  credit on a booking-count milestone or a large single transaction.
  **Fixed mid-session**: the original single `after insert or update`
  trigger on `transactions` referenced `OLD` in its `WHEN` clause, which
  Postgres rejects outright for any trigger that fires on `INSERT`
  (SQLSTATE 42P17) — caught by `supabase db push` itself against the dev
  project; split into `..._insert`/`..._update` trigger variants on the
  same function.
- `..._200_custom_booking_create_booking_promo_selections.sql` — the
  one-row-per-selection table replacing the old singular
  `selected_promo_id`, plus widening `transaction_promo_selections` to
  also record a redeemed coupon.
- `..._201_custom_notification_event_type_add_spin_wheel_earned.sql` — new
  notification event value (own migration - enum values can't be added and
  used in the same transaction).

New seed: `supabase/seeds/custom-rewards/` (`.ts` + `.sql` + `.spec.ts`) —
a 5-tier reward catalog (rarities sum to 100) and a demo weekly-recurring
promo ("Midweek Discount"), added to `seed:all` and
`supabase/config.toml`'s `[db.seed] sql_paths`. The config thresholds
themselves are NOT seeded here — they're real column defaults in migration
196, so they reach every environment on `db push` alone.

### Server

- New shared pure helpers: `shared/services/promoEligibility/` (date-range
  - weekly-recurring "is this promo live right now," replacing three
    separate copies of the old date-only check) and `shared/services/promoCap/`
    (the cap-application math extracted from the checkout-time fallback, now
    used by both it and the new booking-time resolution).
- `booking.service.ts`: `resolveDiscountAndPromo` → `resolveDiscountAndPromos`,
  now accepting `promo_ids`/`coupon_ids` arrays instead of a single
  `promo_id`, validating/capping all of them together, and writing one
  `booking_promo_selections` row per selection plus redeeming any spent
  coupons. Same treatment in `bookingGroup.service.ts`.
- `billing/services/checkoutAggregation.service.ts` /
  `lineItemSources.service.ts`: read back `booking_promo_selections` as the
  primary source for a booking's promo lines, falling back to the old
  singular field (pre-migration bookings) and then to the checkout-time
  auto-evaluate fallback, in that order.
- New feature folder `server/src/features/rewards/` — config/reward CRUD,
  the `spin_wheel()` RPC wrapper, coupon listing/redemption, mounted at
  `/rewards/*` (mixed RBAC: admin-only config/reward-catalog writes,
  `jwtMiddleware`-only for the customer-or-staff spin/coupon/history
  routes, same shape as `credits.routes.ts`).
- `catalog.service.ts`'s `getBookingCatalog` (the customer-accessible
  read-through for staff-gated `/maintenance/*` data) now also returns the
  effective `promoCap`, so the new booking step can show a correctly
  capped preview to a customer session too.
- **Found and fixed by this session's own pre-PR `/code-review` pass**
  (see `reviews/2026-09-13-1347-pre-pr.md` for the full list of findings,
  fixed and deferred):
  - `promo_ids`/`coupon_ids` had no duplicate-id guard — the old single
    `promo_id` scalar made a repeat structurally impossible; the array
    form didn't carry over an equivalent check, so the same promo id sent
    twice could apply twice. Added a dedup `superRefine` (mirroring the
    existing `items` dedup check) to both booking validators, plus a
    `.max(20)` ceiling.
  - `markCouponsRedeemed` had no `is_redeemed = false` guard at write
    time (a TOCTOU race) — added the guard, an affected-row-count check
    that throws 409 on a concurrent redemption, and wired that failure
    into the same booking/booking-group rollback path every other
    post-insert failure already uses.

### Client

- `AdminPromoConfigPage.tsx` — a two-step wizard for **create** (pick
  Date range vs. Weekly recurring, then the matching fields via a new
  `DayOfWeekPicker`); edit stays a flat form (type is immutable after
  creation).
- New `client/src/features/rewards/` — `AdminSpinWheelConfigPage`
  (thresholds + reward CRUD with a live rarity-sum indicator),
  `CustomerRewardsPage` ("My Rewards": spin button, coupon list), and a
  hand-rolled SVG `SpinWheel` component (lands on a server-precomputed
  result — never picks its own outcome). New sidebar entry ("My Rewards")
  and a Settings > Config tile ("Coupon Spin Wheel").
- `CustomerBookingFlowPage.tsx` — new `'promos'` step (both customer and
  receptionist flows) rendering the new `PromoCouponMultiSelect` component;
  replaces the old single-select dropdown. State/payload moved from
  singular `selectedPromoId` to `selectedPromoIds`/`selectedCouponIds`
  arrays.
- `staffAuth.api.ts` / `MfaChallengeForm.tsx` — **unrelated pre-existing
  bug fixed mid-session** (found while investigating an MFA report that
  turned out to be unconnected to this branch): the staff MFA form always
  showed "Invalid verification code." on any failure, masking a 423
  lockout response behind the same generic message. Now shows the
  server's actual message.

## Manual test — step by step

1. Run the new migrations locally (`supabase db reset`, or apply
   `20260913195`–`201` to a dev project) and `npm run seed:all` so the
   spin wheel reward catalog and demo weekly-recurring promo exist.
2. **Weekly-recurring promo + wizard**: log in as Admin/Superadmin, go to
   **Settings → Config → Promos → New promo**. Confirm step 1 asks for a
   type (Date range / Weekly recurring) before showing any other field.
   Pick **Weekly recurring**, click Next, pick a day (e.g. today's
   weekday), save. Confirm the promo appears in the list.
3. Start a booking (customer or receptionist) for a service scoped by that
   promo, on today's weekday — confirm it shows up as selectable in the
   new **Promos & Coupons** step. Change the promo's day to a
   non-matching one and confirm it disappears from that step.
4. **Multiselect + cap**: as Admin, set **Promo Cap Configuration** to a
   small percentage (e.g. 10%) for a branch. In a booking for that branch,
   select two or more applicable promos in the new step and confirm the
   running "you'll save ₱X" total stops growing once the 10% cap is hit,
   not the naive sum of both promos.
5. **Spin wheel — earning a spin**: as Admin, go to **Settings → Config →
   Coupon Spin Wheel**, set "grant a spin every" to a small number (e.g. 2) bookings. Complete that many bookings for one customer (mark them
   Completed) and confirm **My Rewards** (customer portal sidebar) shows
   an available spin.
6. **Spinning**: click **Spin the wheel** on My Rewards. Confirm the wheel
   animates and lands on a reward, and that reward appears under "My
   Coupons" immediately after.
7. **Pity system**: set the pity threshold low (e.g. 2) and the rarest
   reward's rarity very low. Force enough spins without landing the rare
   reward (grant more spin credits via more completed bookings) and
   confirm the next spin after the threshold guarantees a reward from the
   lowest-rarity pool.
8. **Coupon spend**: back in a booking's Promos & Coupons step, confirm an
   unredeemed coupon from step 6 is selectable alongside promos, and that
   selecting it and completing the booking marks it used (no longer shown
   as available in My Rewards afterward).
9. **Duplicate-id guard (this session's own review fix)**: not manually
   testable through the UI (the multiselect component can't select the
   same promo twice) — covered by the new validator tests instead (see
   Test suites below).

## Test suites

- `server`: `npx vitest run` — 1139/1139 passing (102 files, up from
  1125/101 before this session's own pre-PR review pass added
  `customerCoupons.service.spec.ts` and the duplicate-id validator tests);
  `npx tsc --noEmit` clean.
- `client`: `npx vitest run` — 884/884 passing across the feature's own
  suites when run in isolation (`CustomerBookingFlowPage.spec.ts` 38/38,
  `AdminPromoConfigPage.spec.ts` 13/13, the full `booking`+`maintenance`
  areas 181/181, `auth/staff` 37/37, `vite.proxy.config.spec.ts` 3/3);
  `npx tsc --noEmit` clean. One full-suite run (all 169 files together)
  showed a single timeout in `CustomerBookingFlowPage.spec.ts` under
  parallel load, re-confirmed passing (38/38) immediately after in
  isolation — a resource-contention flake, not a regression.
- Prettier: clean on every touched file (checked from repo root).
- A pre-PR `/code-review` (high effort) was run against the branch diff
  before opening the PR — see `reviews/2026-09-13-1347-pre-pr.md` for the
  full findings list (2 real bugs found and fixed with tests; the rest
  logged as deferred follow-ups).

All counts above were run directly in this session, not carried over from
a prior review.

## Open items

- **Migration push order matters**: this session's migrations were pushed
  to the dev Supabase project mid-session and `..._199` failed on first
  attempt (the OLD-in-INSERT-WHEN issue above) — migrations `195`–`198`
  from that same push had already applied successfully before it failed,
  and the fix to `199` was made in place (safe, since a failed migration's
  transaction rolls back and Supabase's CLI never recorded it as applied).
  `199`–`201` still need to be (re-)pushed, and the `custom-rewards` seed
  script still needs to be run against dev, then the whole batch repeated
  against prod, before this is live anywhere but a developer's own local
  reset.
- **Deferred follow-ups from the pre-PR review** (not fixed this session,
  see the review doc for the full list): no test coverage yet for
  `spinWheel.service.ts`/`spinWheelConfig.service.ts`/`rewardsAccess.service.ts`/
  `rewards.controller.ts` or any of the new client rewards/multiselect
  components; three independent "effective promo cap" implementations
  with inconsistent missing-default-row behavior; coupon redemption is
  still a two-step app-level write rather than one atomic DB function
  (unlike `spin_wheel()`); several `round2`/`DISCOUNT_TYPES`/
  `resolveTargetCustomerId` duplications typical of a first pass at a
  large feature.
- **No push-notification wiring** for the new `spin_wheel_earned` event —
  the spin credit is still granted correctly via the DB trigger; a
  customer just won't get a bell alert until they open My Rewards.
- The MFA fix (unrelated pre-existing bug, see above) was found and fixed
  while investigating a report that turned out to be a coincidental
  account lockout (5 failed attempts from expired TOTP codes) plus this
  UI bug hiding the real reason — not caused by anything in this branch.
