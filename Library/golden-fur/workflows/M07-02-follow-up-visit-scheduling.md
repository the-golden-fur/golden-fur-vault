---
title: "M07 · Follow-Up Visit Scheduling"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M07
---

# M07 · Follow-Up Visit Scheduling

**Actors:** Veterinarian
**Code:** `client/src/features/veterinary/components/ScheduleFollowUpModal/ScheduleFollowUpModal.tsx`,
`server/src/features/veterinary/services/followUp.service.ts`,
`server/src/features/booking/services/booking.service.ts` (`createBooking`)
**Part of:** [[M07-health-veterinary-management|M07 · Health & Veterinary Management]]

From a finished consultation, a Veterinarian schedules a follow-up visit
through the normal booking pipeline, then the new booking is linked back
onto the originating consultation as a two-step action.

```mermaid
flowchart TD
    A(["START: Veterinarian selects\n'Schedule Follow-up' on a\nCompleted consultation with\nno existing follow-up booking"]) --> B["Choose Veterinary service, slot,\noptional staff preference and\nspecial instructions\n(pet/owner/branch/category locked)"]
    B --> C["Submit createBooking\n(POST /bookings — same pipeline\na receptionist walk-in uses)"]
    C --> D{"Booking created?\n(capacity/eligibility/pricing\nchecks inside createBooking)"}
    D -- "No" --> D1["Show error"] --> B
    D -- "Yes" --> E["sendBookingConfirmedNotification\nto customer + sendStaffAssignedNotification\nif staff assigned\n(best-effort → M11)"]
    E --> F["Call linkFollowUpBooking\n(consultationId, newBookingId)"]
    F --> G{"Originating consultation's\nbooking status = Completed?"}
    G -- "No" --> G1(["END: Blocked — can only schedule\na follow-up once finished (409)"])
    G -- "Yes" --> H{"Consultation already has\na follow_up_booking_id?"}
    H -- "Yes" --> H1(["END: Blocked — a follow-up is\nalready scheduled (409)"])
    H -- "No" --> I{"New booking's pet_id\n= consultation's pet_id?"}
    I -- "No" --> I1(["END: Blocked — follow-up must be\nfor the same pet (400)"])
    I -- "Yes" --> J["Update consultations:\nfollow_up_date, follow_up_booking_id"]
    J --> K{"Link update\nsucceeded?"}
    K -- "No" --> K1(["END: Booking scheduled,\nlink failed — best-effort,\nno rollback of the booking"])
    K -- "Yes" --> L(["END: Booking scheduled\nand linked as this consultation's\nfollow-up"])
```

## Notes

- This is a **two-step** flow by design: the follow-up booking is created
  through the real booking-creation pipeline (`createBooking`), not a
  Veterinary-specific shortcut — it gets the same capacity/pricing/staff
  checks and fires the customer's `booking_confirmed` notification "for
  free," exactly as a receptionist walk-in would.
- `linkFollowUpBooking`'s three guard checks (finished, not already linked,
  same pet) are **defense-in-depth** — the UI already only offers "Schedule
  Follow-up" on a Completed row with no existing `follow_up_booking_id`,
  and the pet is locked in the modal before the booking is even created, so
  none of these should normally trigger from the UI path.
- If the link step fails after the booking was already created, the client
  does **not** roll back or delete the booking — the follow-up was still
  successfully scheduled from the customer's perspective, so the vet is
  routed straight to the new booking's receipt page rather than stranded
  with an orphaned retry.
- `consultations.follow_up_booking_id` is a **second** foreign key to
  `bookings` (alongside `booking_id`) — every query that embeds the joined
  booking must disambiguate with `!booking_id`, or PostgREST 400s on the
  ambiguous relationship.

## Relationship to other modules

The booking itself is created through
[[M03-appointment-booking|M03]]'s shared `createBooking` pipeline, which
fires the `booking_confirmed` and staff-assigned notifications via
[[M11-notification|M11]].
