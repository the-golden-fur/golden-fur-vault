---
title: Rewards — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, rewards]
project: golden-fur
---

A plain-English tour of the `rewards` feature's code: a gamified
coupon spin wheel. Customers earn spin credits by hitting a booking
milestone or a spend threshold, spend a credit to spin, and land a
percentage/flat coupon they can later apply at booking time.

**Part of:** [[rewards-coupon-spin-wheel]]

## Client-side (`client/src/features/rewards/`)

### pages/

- **`AdminSpinWheelConfigPage/AdminSpinWheelConfigPage.tsx`** — the
  Admin/Superadmin-only config screen: the milestone/spend/pity
  thresholds form, and CRUD on the reward pool (label,
  percentage/flat value, rarity %). Shows a live running sum of active
  rewards' rarity percentages as a client-side guard — the real 100%
  rule is enforced by a database trigger.
- **`CustomerRewardsPage/CustomerRewardsPage.tsx`** — the customer-
  facing "My Rewards" page (`/portal/rewards`): available spin count,
  the spin wheel itself, and the customer's coupon list split into
  unused and used.

### components/

- **`SpinWheel/SpinWheel.tsx`** — a hand-rolled SVG pie-slice wheel,
  sized per segment by each reward's `rarity_percent` (no animation
  library in the dependency tree, deliberately). Spinning is a pure
  CSS transform; the wheel never picks its own outcome — it always
  animates to land on the `resultRewardId` the server already decided.

### api/

- **`rewards.api.ts`** — calls to the admin config/reward-pool
  endpoints, plus the customer-or-staff endpoints:
  `getMySpinCredits`, `spinTheWheel`, `getMyCoupons`,
  `getMySpinHistory`. Each of the latter accepts an optional
  `customerId` so a receptionist can act on behalf of a walk-in
  customer instead of themselves.

### Other files

- **`rewards.routes.tsx`** — mounts
  `/staff/admin/spin-wheel-config` behind `StaffAuthGuard` and
  `/portal/rewards` behind `CustomerAuthGuard`.
- **`rewards.types.ts`** — client-side mirror of the server types
  (`SpinWheelConfig`, `SpinWheelReward`, `CustomerCoupon`,
  `SpinHistoryEntry`, `SpinResult`).

## Server-side (`server/src/features/rewards/`)

### Controller & routes

- **`rewards.controller.ts`** — request handlers split into two
  groups: admin config/reward-catalog management, and
  customer-or-staff spin/coupon/history endpoints.
- **`rewards.routes.ts`** — mounts everything under `/rewards/*`.
  Config write and reward-catalog write are Admin/Superadmin only
  (`REWARDS_WRITE_ROLES`); reading the reward list is open to *any*
  authenticated principal (`jwtMiddleware` alone), since the
  customer-facing wheel needs every active reward to render its
  segments. The spin/coupon/history routes are likewise gated by
  `jwtMiddleware` only — ownership is resolved inside the service
  layer, not by role.

### Service

- **`services/spinWheel.service.ts`** — `spin()` calls the
  `spin_wheel()` Postgres RPC, which atomically consumes a spin
  credit, rolls (or applies pity), records history, and issues the
  resulting coupon in one database transaction. `getMySpinCreditCount`
  counts unconsumed `customer_spin_credits` rows.
- **`services/spinWheelConfig.service.ts`** — admin CRUD for the
  singleton `spin_wheel_config` row (thresholds/pity) and the
  `spin_wheel_rewards` pool (create/update/archive/restore/hard-
  delete). The active-rewards-sum-to-100 rule is authoritatively
  enforced by a deferred database trigger; a create/update/archive
  that would break it fails at commit and surfaces as a normal error.
- **`services/customerCoupons.service.ts`** — `listMyCoupons` (a
  customer's own coupon history), `getCouponsByIds` (batch ownership/
  eligibility check used when a coupon is selected at the booking-time
  Promos & Coupons step), and `markCouponsRedeemed` (locks coupons to
  the booking/booking group that used them, with an `is_redeemed =
  false` guard against a race between two concurrent requests
  redeeming the same coupon twice).
- **`services/rewardsAccess.service.ts`** — `resolveTargetCustomerId`,
  shared by the two services above: a customer can only ever act on
  themselves; a staff member must explicitly pass the `customerId`
  they're acting on behalf of (e.g. a receptionist triggering a
  walk-in's earned spin).

### Types & validators

- **`rewards.types.ts`** — `SpinWheelConfig`, `SpinWheelReward`,
  `CustomerCoupon` (snapshots `discount_type`/`value` at issuance so a
  later reward-catalog edit never changes an already-issued coupon),
  `SpinHistoryEntry`, `SpinResult`, plus
  `REWARDS_READ_ROLES`/`REWARDS_WRITE_ROLES`.
- **`modules/validators/rewards.validator.ts`** — Zod schemas for the
  config upsert, reward create/update (rejects a percentage value over
  100), and the spin request (`customer_id` optional, same
  staff-acting-on-behalf-of pattern as booking creation).

## How it connects

Rewards is one of a small number of features added after the original
14-module spec (alongside `messaging`) and isn't covered by an M0X
module code. A customer's coupon is selected and locked in at the
booking-time Promos & Coupons step alongside discounts and promos —
see [[M03-appointment-booking|M03]]'s "Booking-time discounts and
promos" section and `booking.service.ts`'s `resolveDiscountAndPromos`
— and shares its `Percentage`/`Flat` value shape with
[[M12-discount-management|M12]] discounts.
