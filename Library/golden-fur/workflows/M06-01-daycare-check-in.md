---
title: "M06 · Daycare Check-In"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M06
---

# M06 · Daycare Check-In

**Actors:** Receptionist, Admin, Supervisor, Superadmin, Groomer, Pet Assistant
**Code:** `server/src/features/daycare/services/daycareCheckIn.service.ts`,
`server/src/features/daycare/daycare.controller.ts`,
`server/src/features/hotel/services/cageAssignment.service.ts`,
`server/src/features/hotel/services/careInstructions.service.ts`
**Part of:** [[M06-daycare-management|M06 · Daycare Management]]

A front-desk-capable staff member checks a pet into Daycare, either against
an existing advance booking or as a fresh walk-in. Since the `stays` table
was unified across Hotel and Daycare, this reuses Hotel's own cage-claim and
structured care-instruction machinery rather than any Daycare-specific
capacity model — the two categories differ only in billing and in Daycare
having no scheduled multi-night length.

```mermaid
flowchart TD
    A(["START: Staff initiates Daycare check-in"]) --> B{"booking_id provided?"}
    B -- "Yes" --> C["Fetch booking"]
    C --> D{"Booking exists,\nservice_category = Daycare,\nstatus = Pending?"}
    D -- "No" --> E(["END: Blocked — not found /\nwrong category / wrong status"])
    D -- "Yes" --> F["Resolve pet_id + branch_id\nfrom booking"]
    B -- "No (walk-in)" --> G["Take pet_id + branch_id\ndirectly from input"]
    F --> H["Fetch branch\n(timezone, daycare_checkin_cutoff)"]
    G --> H
    H --> I{"Branch found?"}
    I -- "No" --> J(["END: Blocked — branch not found"])
    I -- "Yes" --> K["Resolve today's cutoff instant\n(Makati fixed 4:00 PM,\nelse branch's own\ndaycare_checkin_cutoff)"]
    K --> L{"Current time\npast cutoff?"}
    L -- "Yes" --> M(["END: Blocked — check-in\nunavailable after cutoff\n(no stays row created)"])
    L -- "No" --> N["Suggest cage by pet's\nweight_class, or use\nstaff-overridden cage_id"]
    N --> O{"Cage available\nand claimed\n(Available → Occupied)?"}
    O -- "No" --> P(["END: Blocked — no cage\nof suggested size / cage\nalready occupied"])
    O -- "Yes" --> Q["Resolve Daycare service_id\n(booking's own service,\nexplicit walk-in choice,\nor branch's first active\nDaycare service)"]
    Q --> R["Insert stays row\n(stay_type = Daycare,\nstatus = Active,\ncage_id, service_id)"]
    R --> S{"Insert succeeded?"}
    S -- "No" --> T["Release the claimed cage\n(compensating rollback)"] --> U(["END: Blocked — failed\nto check in"])
    S -- "Yes" --> V{"booking_id present?"}
    V -- "Yes" --> W["Sync booking:\nPending → In Progress"]
    V -- "No" --> X["Insert feeding / walking /\nplaying / medication\ninstructions"]
    W --> X
    X --> Y["Generate today's\nCare Log entries\n(single day — Daycare has\nno multi-night stay length)"]
    Y --> Z["Record check_in activity"]
    Z --> AA(["END: Daycare session Active,\ncage occupied, care log seeded"])
```

## Notes

- A failure at **any** point after the cage is claimed — the `stays` insert,
  the care-instruction inserts, or Care Log generation — releases the cage
  back to `Available` via a single `try/catch` wrapping that whole block, so
  a failed check-in never strands an Occupied cage with no session behind
  it.
- The Makati cutoff (4:00 PM) is a hardcoded application constant, not read
  from `branches.daycare_checkin_cutoff` even though that column exists (and
  is seeded identically) on every branch — only Southwoods' branch-config
  value is ever actually read. This is a deliberate, documented asymmetry,
  not a bug.
- Booking-linked check-in is the "service started" event: there is no
  separate Confirmed gate, so a booking must still be `Pending` to be
  checked in, and check-in itself advances it to `In Progress`.
- `service_id` (which Daycare service's fee schedule bills this session)
  is resolved once at check-in and stored on the `stays` row — a
  booking-linked check-in always derives it from the booking's own selected
  service server-side, ignoring any `service_id` sent in the request; only
  a walk-in's explicit choice (or the branch fallback) is honored.
- Groomer and Pet Assistant can check pets in/out of Daycare because Daycare
  has no dedicated assigned-staff role of its own (unlike Grooming or
  Veterinary) — this mirrors Hotel's identical advance-role list.

## Relationship to other modules

Booking-linked check-ins come from [[M03-appointment-booking|M03]]; the
Boarding Checklist Care Log this seeds is shared with
[[M05-pet-hotel-boarding-management|M05]]'s Kanban board.
