---
title: "M04 · Grooming Queue Population & Visibility"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M04
---

# M04 · Grooming Queue Population & Visibility

**Actors:** Groomer, Admin, Supervisor, Superadmin
**Code:** `server/src/features/grooming/services/grooming.service.ts`,
`server/src/features/grooming/grooming.controller.ts`,
`server/src/features/grooming/grooming.routes.ts`
**Part of:** [[M04-grooming-management|M04 · Grooming Management]]

A staff member opens the Grooming Queue; the server resolves which
not-yet-finished Grooming bookings are visible to them, lazily creates a
`grooming_sessions` row for any that don't have one yet, and orders the
result. There is no database trigger that creates these rows — the queue
endpoint itself is the only thing that vivifies them.

```mermaid
flowchart TD
    A(["START: Staff opens the Grooming Queue\n(GET /grooming/queue)"]) --> B{"Role in\nGroomer/Admin/Supervisor/Superadmin,\nand branch resolved?"}
    B -- "No" --> C(["END: Blocked — forbidden / unauthorized"])
    B -- "Yes" --> D["Resolve date range\n(date_from/date_to query params,\ndefault: today, UTC)"]
    D --> E["Query bookings:\nservice_category = Grooming,\nstatus IN (Pending, In Progress),\nscheduled_start within range"]
    E --> F["Exclude bookings still needing\nan unpaid downpayment\n(downpayment_required = true\nAND payment_stage = Unpaid)"]
    F --> G{"Requester role?"}
    G -- "Groomer" --> H["Filter to bookings\nassigned_staff_id = requester"]
    G -- "Admin / Supervisor" --> I["Filter to bookings\nbranch_id = requester's branch"]
    G -- "Superadmin" --> J["No filter — all branches"]
    H --> K
    I --> K
    J --> K["Look up existing grooming_sessions\nfor these booking IDs"]
    K --> L{"Any matching booking\nwithout a session row yet?"}
    L -- "Yes" --> M["Insert a grooming_sessions row\nfor each missing booking\n(booking_id, assigned_groomer_id\n= bookings.assigned_staff_id)"]
    L -- "No" --> N
    M --> N["Fetch full session rows\n(joined booking + booking_items)"]
    N --> O{"queue_position set\non both rows being compared?"}
    O -- "Yes" --> P["Sort by queue_position"]
    O -- "No" --> Q["Fall back to\nbooking.scheduled_start\n(chronological)"]
    P --> R(["END: Ordered queue returned\n(possibly empty)"])
    Q --> R
```

## Notes

- The queue's date filter defaults to **today** when neither `date_from`
  nor `date_to` is supplied — every existing caller relies on this, so it
  isn't just a UI default, it's baked into the service function itself.
- `grooming_sessions` rows are created lazily, on read, not by a trigger
  or at booking-creation time — this keeps the queue working without
  touching `booking.service.ts` at all. A booking that never gets viewed
  through the queue simply never gets a session row (harmless, since the
  row exists only to support queue display/ordering, not billing).
- The downpayment gate (`downpayment_required = false OR payment_stage <>
'Unpaid'`) is evaluated in the same query that selects candidate
  bookings — a booking failing it is invisible to the queue and never
  gets a `grooming_sessions` row vivified, not merely hidden after the
  fact.
- Role scoping is three-tiered: Groomer sees only sessions assigned to
  them, Admin/Supervisor are branch-scoped, and Superadmin is
  unrestricted (all branches) — mirroring the pattern used by other
  execution queues in this app.
- Sorting is per-pair: `queue_position` wins only when **both** rows
  being compared have one set; a row with no `queue_position` falls back
  to its booking's `scheduled_start`, so an explicit manual reorder
  (`queue_position`) and the default chronological order can coexist in
  the same list.
- `grooming_sessions.assigned_groomer_id` is a denormalized copy of
  `bookings.assigned_staff_id` taken at vivification time — it exists so
  the Groomer's "my sessions" query doesn't need to join through
  `bookings`, not as a second source of truth for who's assigned.

## Relationship to other modules

Reads booking state owned by [[M03-appointment-booking|M03]] (status,
`assigned_staff_id`, downpayment fields) and staff role/branch from
[[M01-staff-authentication-access-control|M01]].
