---
title: "M02 · Customer Portal & Pet Management"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M02 · Customer Portal & Pet Management

**Layer:** Foundation
**Code:** `features/customers` (client + server)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The data backbone for all booking, service, billing, and veterinary
actions.

## Customer profiles

Full name, contact number, emergency contact, preferred communication
channel (Call, Text, Viber, Messenger), account email. Customers
self-register with email + password, Google OAuth 2.0, or Facebook
Login — a matching email on a social login auto-merges with an existing
account. Staff can also create/update customer records for walk-ins.

## Pet profiles

Linked to a customer profile: name, Pet Type (dog/cat — relabeled from
"Species" in the UI, enum unchanged), breed (searchable dropdown with a
free-text "Other" fallback), gender, date of birth, weight class
(S/M/L/XL), coat type (Short/Long Coat), an optional photo, and
vaccination records.

- **Weight class and coat type can only be set by staff** performing a
  physical assessment (Receptionist/Admin/Supervisor/Superadmin) — a
  customer can create a pet record but can't self-declare these.
- **Health conditions** are recorded by a veterinarian in [[M07-health-veterinary-management|M07]];
  the pet profile surfaces them read-only.

## Breed Management (Admin/Superadmin)

Breeds are grouped by Pet Type, created under a chosen type (unique name
within that type), renamed in place, deleted only when no pet still
references them. Read access (the dropdown) is open to everyone; writes
are Admin/Superadmin only.

## Customer account settings

Profile, Security (password, opt-in TOTP), and Preferences (theme,
per-event-type notification toggles including appointment-reminder lead
time). "My Pets" is its own Pet Manager page, separate from Profile.

Customer sessions have **no inactivity timeout** — a customer stays
logged in until they manually log out (unlike staff, see [[M01-staff-authentication-access-control|M01]]).

## Relationship to other modules

Pet weight class/coat type drive the pricing matrix in [[M03-appointment-booking|M03]] and
[[M13-maintenance-packages-services-promos|M13]]. Breed and health-condition data feed [[M07-health-veterinary-management|M07]]. Credit
balances ([[M10-credit-balance-management|M10]]) and notifications ([[M11-notification|M11]]) are tied to the
customer record here. A pet with any unresolved booking (Pending or In
Progress, any category) can't be booked again until that one resolves
(M03). Pet-assessment services (Initial Assessment/Reassessment, Misc
category — [[M13-maintenance-packages-services-promos|M13]]) are booked normally and feed the weight/coat
assessment above.
