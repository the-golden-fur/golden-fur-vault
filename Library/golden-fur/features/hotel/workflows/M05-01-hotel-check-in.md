---
title: "M05 · Hotel Check-In"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M05
---

# M05 · Hotel Check-In

**Actors:** Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin (`HOTEL_ADVANCE_ROLES`)
**Code:** `server/src/features/hotel/services/careInstructions.service.ts`,
`server/src/features/hotel/services/cageAssignment.service.ts`,
`server/src/features/hotel/hotel.controller.ts`
**Part of:** [[M05-pet-hotel-boarding-management|M05 · Pet Hotel (Boarding) Management]]

A front-desk or advance-role staff member checks a confirmed Hotel booking
in on its scheduled day: the system claims a cage, writes the stay's
structured feeding/walking/playing/medication instructions, and
auto-generates one Boarding Checklist entry per scheduled action per day of
the stay.

```mermaid
flowchart TD
    A(["START: Staff opens Check-In\nfor a Hotel booking"]) --> B["Enter booking_id, optional cage_id override,\nfeeding/walking/playing rows, medications,\nnotify_opt_in"]
    B --> C{"Booking exists and\nservice_category = Hotel?"}
    C -- "No" --> C1(["END: Blocked — booking not found\nor not a Hotel booking (404/400)"])
    C -- "Yes" --> D{"Booking status = Pending?"}
    D -- "No" --> D1(["END: Blocked — a booking that isn't\nPending cannot be checked in (409)"])
    D -- "Yes" --> E{"Booking's branch =\nrequester's branch?"}
    E -- "No" --> E1(["END: Blocked — booking does not\nbelong to this branch (403)"])
    E -- "Yes" --> F{"Does a stay already exist\nfor this booking?"}
    F -- "Yes" --> F1(["END: Blocked — already checked in (409)"])
    F -- "No" --> G["Resolve cage:\ncage_id given, else suggest by\npet's weight_class (first Available match)"]
    G --> H{"Conditional claim:\ncage still Available?\n(flip to Occupied)"}
    H -- "No" --> H1(["END: Blocked — no available cage\nof the suggested/chosen size (409)"])
    H -- "Yes" --> I["Insert stays row\n(Hotel, check_in_at = now,\nscheduled_check_out_date from booking,\ndownpayment snapshot, created_by)"]
    I --> J["Advance booking:\nPending -> In Progress"]
    J --> K["Insert feeding / walking / playing\ninstruction rows as submitted"]
    K --> L{"Medications field\nprovided in the request?"}
    L -- "No (omitted)" --> L1["Auto-fill from M07's\ncurrent-prescription derivation\n(empty if no current prescription)"]
    L -- "Yes (incl. empty array)" --> L2["Use submitted list verbatim\n(receptionist's own list)"]
    L1 --> M["Insert medication instruction rows"]
    L2 --> M
    M --> N["Generate one care_log_entries row per\nscheduled action per calendar day\n(check-in date through scheduled checkout date;\na dated stay_date row overrides the\nevery-night default for that one day)"]
    N --> O{"Did any step from the\nstay insert through Care Log\ngeneration fail?"}
    O -- "Yes" --> P["Release the claimed cage\nback to Available\n(compensating rollback)"] --> P1(["END: Blocked — check-in failed,\nno stray Occupied cage left behind"])
    O -- "No" --> Q["Record check_in activity\n(best-effort)"]
    Q --> R(["END: Stay Active, cage Occupied,\nBoarding Checklist populated"])
```

## Notes

- Cage capacity has no separate reservation table — a cage's `status`
  column _is_ the capacity signal. Claiming a cage is a conditionally-guarded
  `UPDATE ... WHERE status = 'Available'`, not a real DB transaction (the
  Supabase client here has no cross-table transaction); a race between two
  concurrent check-ins for the last cage of a size resolves to one winner,
  the other gets a 409.
- This whole flow (from the stay insert through Care Log generation) is
  wrapped in a single try/catch in application code, not a DB transaction —
  a failure at _any_ point in that range releases the cage rather than
  leaving it stranded Occupied with no `stays` row behind it.
- Medications is the only care-instruction field with omit-vs-empty-array
  semantics: omitting it entirely triggers auto-fill from the pet's current
  prescription ([[M07-health-veterinary-management|M07]]); submitting `[]`
  explicitly means "no medications," verbatim, with no prescription lookup.
- A medication's `scheduled_times` are bucketed into the same
  Morning/Noon/Afternoon/Evening `time_block` vocabulary feeding/walking/
  playing use (hour < 11 → Morning, < 13 → Noon, < 17 → Afternoon, else
  Evening), so the Boarding Checklist can group every care type consistently.
- Physical check-in — not booking confirmation — is what advances the
  booking from Pending to In Progress. A booking that's already In Progress
  or further along cannot be checked in again.

## Relationship to other modules

Depends on a Hotel booking already existing ([[M03-appointment-booking|M03]])
and, when medications are omitted, on [[M07-health-veterinary-management|M07]]'s
current-prescription lookup. Feeds the Boarding Checklist covered by
[[M05-02-boarding-checklist-task-lifecycle|M05 · Boarding Checklist Task Lifecycle]].
