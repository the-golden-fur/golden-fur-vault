---
title: "M04 · Grooming Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M04 · Grooming Management

**Layer:** Operations
**Code:** `features/grooming` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Groomer queue execution, driven directly by the unified booking status
(Start/Complete — see [[M03-appointment-booking|M03]]) rather than a separate status field on
the grooming session. A `grooming_sessions` row is lazily created for
any matching booking that doesn't have one yet, so the queue works
without a database trigger or a change to booking creation.

## Behavior

- A Grooming booking's billed lines come from its `booking_items`
  (services and/or packages from the merged selection step), not a
  single service plus a separate add-ons list — there's no longer a
  Grooming-only "Add-ons" step.
- A Pending/In Progress booking that still needs an unpaid downpayment
  is excluded from the queue until paid ([[M03-appointment-booking|M03]]).
- "No preference" staff auto-assignment picks **randomly** among
  eligible available staff (previously deterministic, first
  alphabetically) — spreads bookings more evenly.

## Relationship to other modules

Depends on [[M01-staff-authentication-access-control|M01]], [[M03-appointment-booking|M03]], and [[M13-maintenance-packages-services-promos|M13]] (packages, size/coat
pricing). Feeds [[M08-sales-billing|M08]] on completion.
