---
title: "M07 · Health & Veterinary Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M07 · Health & Veterinary Management

**Layer:** Operations
**Code:** `features/veterinary` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Exclusive to the **Makati branch**. Manages clinical consultations,
health records, prescriptions, and follow-ups. The Veterinarian
dashboard's Pending/Ongoing/Completed columns reflect the unified
booking status ([[M03-appointment-booking|M03]]) rather than a status tracked separately
on the consultation record.

## Consultations

For each consultation, the vet records vitals, diagnosis, medications
administered/prescribed, procedures performed, and follow-up
instructions. A vaccination sub-section writes to the pet's vaccination
record as part of the same Complete Consultation action.

## Health conditions

Chronic conditions, allergies, and other clinically relevant flags are
recorded here by a veterinarian, surfaced read-only on the pet profile
([[M02-customer-portal-pet-management|M02]]).

A Pending/In Progress booking that still needs an unpaid downpayment —
Dental Cleaning, Surgery, and Emergency Consultation ship pre-flagged at
50% ([[M13-maintenance-packages-services-promos|M13]]) — is excluded from the console until paid ([[M03-appointment-booking|M03]]).

## Relationship to other modules

Depends on [[M02-customer-portal-pet-management|M02]] and [[M03-appointment-booking|M03]]. Feeds M02 (read-only health flags),
M03 (eligibility), [[M05-pet-hotel-boarding-management|M05]] (prescription pre-fill), and [[M08-sales-billing|M08]] (billing).

## Recent activity (not yet reflected in the reconciled Aug 2026 spec)

PRs #112–#115 (merged after the doc's 2026-08-09 cutoff) added: a vet
catalog, a "My Patients" view, a Completed column on the queue, a
schedule-follow-up flow, and RBAC gating restricting console writes to
the Veterinarian role.

## Open items (from the Aug 2026 spec, "Hard" tracker)

- Vet staff specialization (e.g. respiratory, cardio) is not modeled —
  it would need to surface in the Staff Picker and influence which
  services a given vet can offer.
