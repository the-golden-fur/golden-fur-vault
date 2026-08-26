---
title: "M05 · Pet Hotel (Boarding) Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M05 · Pet Hotel (Boarding) Management

**Layer:** Operations
**Code:** `features/hotel` (client + server); food/medication catalog lives in `features/catalog`
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Cage assignment, structured care instructions, a shared Boarding
Checklist, pet-status notifications, and checkout/extension fees. Stay
progress follows the unified booking status ([[M03-appointment-booking|M03]]) for
booking-backed stays, and its own status field on the shared stays table
for walk-ins with no parent booking (see [[M06-daycare-management|M06]]).

## Food & Medication Catalog (Admin/Superadmin)

Customers maintain their own catalog of food/medication items for
future Hotel and Daycare bookings — moved off staff, since staff
purchasing on a customer's behalf created a liability question. Every
row is customer-owned; there's no "provided by the hotel" distinction
anymore.

In the booking flow, selecting a meal time or medication offers a
searchable dropdown sourced from that catalog (typing still supports
free text with no catalog match). Picking a real catalog item offers
"Owner will bring it" (default) or "Staff will purchase it" — the
latter, with a quantity, shows a live price estimate.

## Boarding Checklist (formerly Care Log)

Renamed and now shared with Daycare ([[M06-daycare-management|M06]]) rather than Hotel-only.
A Pet Assistant _or_ Groomer (both now have access) works a Kanban board
of the day's feeding/walking/playtime/medication entries across
Pending/In Progress/Completed columns, grouped/filtered by `time_block`
(Morning/Noon/Afternoon/Evening). Starting/completing shows who acted
and when live; a Reopen action corrects mistaken completions.
Uncompleted end-of-day entries flag on the Admin/Supervisor dashboard,
scoped to branch (Superadmin sees all).

Owner opt-in for pet-status notifications is a single reusable
preference — `notification_preferences.care_log_completed` (see
[[M11-notification|M11]]) — not a separate check-in checkbox.

## Cage management

Check-in cage assignment is suggest-then-override by weight class.
`checkInHotelStay` never reads `bookings.preferred_cage_id` — the
customer's Cage Picker preference from [[M03-appointment-booking|M03]] does not
automatically carry into check-in; front-desk staff must look it up and
re-enter it manually as the override if they want to honor it.
Admin/Superadmin can fully create/edit/delete cages from a dedicated
Cages admin page — previously seed-data-only. Admin write access is
branch-scoped; Superadmin unrestricted. A cage that's Occupied or
Reserved can't be deleted.

## Pricing

Hotel's four cage-size-tiered services are soft-disabled in favor of a
single "Overnight Stay (Aircon Room)" service at a flat base price —
cage size is purely a check-in/capacity concern, never a price input
(see [[M13-maintenance-packages-services-promos|M13]]). A stay of 5+ nights auto-awards a free Golden
Package line item.

## Check-in & checkout

Check-in opens as its own routed page (not an inline popup), fields
disabled until Edit is pressed. At checkout: no extension fee if within
the originally booked period; a late checkout triggers a calculated
extension fee. The system reconciles total stay cost against the
downpayment already collected (plus any extension fee); the remainder
passes to [[M08-sales-billing|M08]]. The cage releases back to Available.

## Workflows

- [[M05-01-hotel-check-in|Hotel Check-In]]
- [[M05-02-boarding-checklist-task-lifecycle|Boarding Checklist Task Lifecycle]]
- [[M05-03-hotel-checkout|Hotel Checkout]]

## Relationship to other modules

Depends on [[M01-staff-authentication-access-control|M01]], [[M02-customer-portal-pet-management|M02]], [[M03-appointment-booking|M03]], and [[M07-health-veterinary-management|M07]] (current
prescription can pre-fill medication fields). Feeds [[M08-sales-billing|M08]],
[[M09-policy-enforcement|M09]], [[M11-notification|M11]], [[M13-maintenance-packages-services-promos|M13]] (pricing), and [[M14-report-management|M14]].

## Open items

- Whether a Pet Assistant/Groomer can check off individual
  feeding/walking/playtime/medication items per pet, rather than the
  whole scheduled entry, is unconfirmed even after the Kanban rework.
