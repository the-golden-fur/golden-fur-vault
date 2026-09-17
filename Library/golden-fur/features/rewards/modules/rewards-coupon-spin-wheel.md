---
title: "Rewards · Coupon Spin Wheel"
date: 2026-09-17
tags: [architecture, golden-fur, module, rewards]
project: golden-fur
---

# Rewards · Coupon Spin Wheel

**Layer:** Operations
**Code:** `features/rewards` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

A gamified loyalty feature (session 86): customers earn spin credits
by crossing a repeating completed-bookings milestone or by paying a
single transaction over a configured spend threshold, then spend a
credit to spin a wheel and win a percentage/flat coupon. A pity rule
guarantees the lowest-rarity reward after too many spins without one.
Coupons are redeemable at the booking-time Promos & Coupons step
alongside discounts and promos (see
[[M03-appointment-booking|M03]]).

Added after the original 14-module spec — per
[[Architecture|the architecture doc]]'s Module map notes, `rewards`
(like `messaging`) isn't covered by an M01–M14 module code.

## Code Guide

- [[features/rewards/code/overview|Rewards — Code Guide]]

## Relationship to other modules

Coupons are selected and locked in during
[[M03-appointment-booking|M03]] booking creation, alongside
[[M12-discount-management|M12]] discounts, which share the same
`Percentage`/`Flat` value shape.
