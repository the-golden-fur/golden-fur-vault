---
title: "M12 · Discount Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M12 · Discount Management

**Layer:** Back-office
**Code:** `features/discounts` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Standing, per-branch discounts (percentage or flat) scoped to a
service, a package, or an entire service category; Senior Citizen and
PWD discounts are built in. Live end-to-end, not scaffolding: routes
are mounted, the booking wizard has a live discount picker, and
checkout has live Senior/PWD attestation checkboxes feeding real
transactions. `is_active` is derived from per-branch availability and
is always true from the moment a discount is created (`branch_ids` is
required non-empty) — an earlier "inactive by default" design/schema
comment no longer reflects `createDiscount`'s actual behavior. What
_isn't_ confirmed yet: ID-verification logging, protecting the
statutory rate from misconfiguration, and Senior/PWD-specific test
coverage (see [[M12-02-discount-eligibility-calculation-and-application|M12-02]]'s Notes).

Discounts can be applied by staff at booking creation ([[M03-appointment-booking|M03]]) —
cash-only, staff-verified ID for Senior/PWD/custom — in addition to the
existing checkout-time application in [[M08-sales-billing|M08]]; both paths write to the
same discounts data and are reflected consistently in reporting.

## Workflows

- [[M12-01-discount-creation-and-lifecycle|Discount Creation, Branch Availability & Archive Lifecycle]]
- [[M12-02-discount-eligibility-calculation-and-application|Discount Eligibility Calculation & Application]]

## Relationship to other modules

Consumed by [[M08-sales-billing|M08]] (checkout) and [[M03-appointment-booking|M03]] (booking-time application);
configured under [[M13-maintenance-packages-services-promos|M13]]'s catalog patterns.
