---
title: "M13 · Maintenance (Packages, Services & Promos)"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M13 · Maintenance (Packages, Services & Promos)

**Layer:** Back-office
**Code:** `features/maintenance` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The configuration layer: services, packages, derived pricing,
downpayment rules, Service Types, and time-limited promos.

## Services

The atomic offerings across all five `service_category` values —
Grooming, Hotel, Daycare, Veterinary, and Misc (pet-assessment
services). Each has a base price, a branch availability toggle, an
active/inactive status, and its own downpayment and pricing-matrix
flags.

## Optional pricing matrix

The size-and-coat pricing matrix is opt-in per service/package
(`use_pricing_matrix`, default `false`) rather than universal. Only
Bath, Blow-dry, Brushing, and the Golden Package opt in by default;
every add-on (nail trim, teeth brushing, ear cleaning, anal drain, face
trim, dematting, poodle feet) is flat-priced. A Cat always gets the
flat base price regardless of the flag, since cats have no weight class
or coat type.

## Packages

Named bundles of two or more services at a combined price, per branch,
enabled/disabled via the same status toggle as services. The bundled
price derives from the included services' prices via an
admin-configurable calculation on the Pricing Configuration page,
recalculating as services are added/removed and shown as a read-only
preview before saving. Packages carry the same `use_pricing_matrix` and
downpayment flags as services.

## Pricing Configuration

Each size (S/M/L/XL) and Long Coat independently configures its own
rule type — Multiplier, Flat, or Percentage — rather than one fixed
shape for the whole matrix; Percentage is always computed against the
item's own base price, never a running total.

## Downpayment (per item)

`requires_downpayment`, `downpayment_type` (Flat/Percentage), and
`downpayment_amount` are configurable on any individual service or
package. Seeded pre-flagged at 50%: Hotel's "Overnight Stay (Aircon
Room)" service, and three high-price Veterinary services (Dental
Cleaning, Surgery, Emergency Consultation). A downpayment-flagged item
can't combine with any other item on the same booking ([[M03-appointment-booking|M03]]).

## Hotel fixed pricing

Hotel's four cage-size-tiered services (S/M/L/XL Cage) are soft-disabled
rather than deleted. A single "Overnight Stay (Aircon Room)" service
(₱850 base) is the only bookable Hotel service — cage size is purely a
check-in/capacity concern ([[M05-pet-hotel-boarding-management|M05]]), never a price input. The service
also carries `min_nights_for_free_package`/`free_package_name`: booking
5+ nights auto-awards a zero-priced Golden Package line item.

## Daycare fee configuration

A Daycare service's `first_hour_fee`, `succeeding_hour_fee`, and
`daycare_overnight_fee` are configured per service (seeded defaults
₱100 / ₱50 / ₱850). `base_price` derives from `first_hour_fee` rather
than being entered separately.

## Promos

Time-limited or condition-limited discount events layered on a service
or package: name, start/end date or event condition, discount value,
scope, branch scope, active/inactive status.

An admin-configured **promo amount cap per transaction** (max total
discount value, pesos or percentage, all combined promos may
contribute) applies in customer-activation order until reached.
Customers see every promo they're currently eligible for, each with its
own activation toggle defaulting off. Expired promos auto-deactivate on
their end date, or can be manually deactivated anytime. Promo Cap
Configuration is inline on this same Promos page.

## Service Types

A `service_types` table gives each of the four booking-flow categories
(Grooming/Hotel/Daycare/Veterinary) a configurable display name, an
active/inactive toggle, and per-type `staff_picker_enabled`/
`cage_picker_enabled` flags. Misc is intentionally excluded — never a
customer-selectable booking category. **This is a display/toggle layer
over the existing four hardcoded categories, not a new booking
dimension** — a newly added fifth row has no real availability,
capacity, or pricing logic behind it. `cage_picker_enabled` is currently
only honored for Hotel regardless of its stored value elsewhere.

## Misc service category

A fifth `service_category`, Misc, carries Initial Assessment and
Reassessment — the pet weight/coat physical-assessment services
referenced from [[M02-customer-portal-pet-management|M02]]. Reassessment is gated by
`requires_assessed_pet`. Both book through the normal flow but have no
dedicated execution queue, so they're worked from the Payments Queue
([[M08-sales-billing|M08]]) instead.

## System Configuration

Branch identity and operating hours, driving Date & Time slot
generation and staff day-off shift-end resolution app-wide. Superadmin
can create new branches here, not only edit existing ones — see [[M01-staff-authentication-access-control|M01]].

## Policies

An admin-facing Policies page (Admin/Superadmin) sits alongside the
other Maintenance/Config pages, editing notice period, reschedule fee,
credit expiry, online payments, Staff Picker visibility, and lunch break
— see [[M09-policy-enforcement|M09]] for the policy content itself.

## Admin config consolidation

Promo Cap Configuration moved inline onto the Promos page. Services,
Service Types, and Packages share a single tabbed "Services and
Packages" page. A Cages tile ([[M05-pet-hotel-boarding-management|M05]]) sits alongside them under
Settings > Config.

## Relationship to other modules

Service/package definitions, downpayment rules, and Service Types are
consumed in [[M03-appointment-booking|M03]] (booking selection, Cage Picker), [[M04-grooming-management|M04]]
(execution), [[M05-pet-hotel-boarding-management|M05]] (cage CRUD, Hotel fixed pricing), [[M06-daycare-management|M06]] (fee schedules),
[[M08-sales-billing|M08]] (billing, downpayment netting), and [[M09-policy-enforcement|M09]] (policy fields).
Misc-category services feed [[M02-customer-portal-pet-management|M02]]'s pet-assessment flow.

## Open items

- A Service Type beyond the seeded four can be created but has no real
  logic behind it.
- `cage_picker_enabled` only works for Hotel regardless of stored value.
- Precedence between this page's Staff/Cage Picker toggle and Policy
  Configuration's per-branch toggle ([[M09-policy-enforcement|M09]]) is unconfirmed.
