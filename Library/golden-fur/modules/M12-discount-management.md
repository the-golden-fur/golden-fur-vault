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
PWD discounts are built in. Discounts are **inactive by default** and
must be explicitly enabled.

Discounts can be applied by staff at booking creation ([[M03-appointment-booking|M03]]) —
cash-only, staff-verified ID for Senior/PWD/custom — in addition to the
existing checkout-time application in [[M08-sales-billing|M08]]; both paths write to the
same discounts data and are reflected consistently in reporting.

## Relationship to other modules

Consumed by [[M08-sales-billing|M08]] (checkout) and [[M03-appointment-booking|M03]] (booking-time application);
configured under [[M13-maintenance-packages-services-promos|M13]]'s catalog patterns.
