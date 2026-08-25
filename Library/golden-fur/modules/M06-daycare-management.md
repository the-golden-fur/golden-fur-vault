---
title: "M06 · Daycare Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M06 · Daycare Management

**Layer:** Operations
**Code:** `features/daycare` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Daycare shares [[M05-pet-hotel-boarding-management|M05]]'s `stays` table with Hotel (`stay_type =
'Daycare'` vs `'Hotel'`) rather than its own `daycare_sessions` table,
which was dropped. This closed the earlier structural gap between the
two: Daycare bookings and walk-ins get the same cage assignment and
structured care instructions Hotel already had, and Daycare check-in
reuses Hotel's own backend services.

## Billing

Billed by time — first-hour and succeeding-hour fees, plus a flat
no-pickup overnight fee — configured **per Daycare service**
(`services.first_hour_fee`, `succeeding_hour_fee`,
`daycare_overnight_fee`) rather than one shared admin setting (seeded
defaults ₱100 / ₱50 / ₱850). A daily check-in cutoff is enforced per
branch.

## Status

`stays.status` (Active/Completed) is shared by Hotel and Daycare alike —
not a Daycare-specific exemption from the unified booking status. It
exists because a walk-in stay row has no parent booking to unify
against; a stay created from an advance booking keeps that booking's own
unified status in sync separately.

The Boarding Checklist ([[M05-pet-hotel-boarding-management|M05]]) covers Daycare on the same Kanban board
as Hotel.

## Relationship to other modules

Bookings come from [[M03-appointment-booking|M03]] (advance) or are created directly by a
receptionist for walk-ins, sharing M05's cage-assignment and
care-instruction machinery. Billing flows to [[M08-sales-billing|M08]]; fee schedules
are configured in [[M13-maintenance-packages-services-promos|M13]].
