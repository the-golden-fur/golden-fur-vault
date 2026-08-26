---
title: "M05 · Boarding Checklist Task Lifecycle"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M05
---

# M05 · Boarding Checklist Task Lifecycle

**Actors:** Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin
(`HOTEL_ADVANCE_ROLES`); the system itself for the lazy Missed transition
**Code:** `server/src/features/hotel/services/careLogCompletion.service.ts`,
`server/src/features/hotel/services/careLogNotifications.service.ts`
**Part of:** [[M05-pet-hotel-boarding-management|M05 · Pet Hotel (Boarding) Management]]

Each feeding/walking/playing/medication row [[M05-01-hotel-check-in|check-in
generates]] becomes a Kanban card any advance-role staff member can move
through Pending → In Progress → Completed, or reopen. There is no
scheduled job in this app — a card's Missed/Backlog labeling happens lazily,
computed the moment the board is read, not written by a background process.

```mermaid
flowchart TD
    A(["START: Care log entries exist\nfor an active stay\n(auto-generated at check-in)"]) --> B["Board is read (Boarding Checklist Kanban)"]
    B --> C{"Pending/In Progress entry whose\nscheduled_date is before today?"}
    C -- "Yes" --> C1["Bulk-flip to Missed"] --> C2["Record task_missed activity\n(system-driven, no actor)"] --> C3(["END: status = Missed —\ndoesn't block checkout,\ncan still be reopened"])
    C -- "No" --> D{"Pending entry whose\nscheduled_date is after today?"}
    D -- "Yes" --> D1(["Displayed as Backlog for this read only —\nnever written to the DB;\nself-resolves to Pending once its date arrives"])
    D -- "No" --> E{"Staff action on a card"}
    E -- "Start" --> F{"Entry status = Pending?"}
    F -- "No" --> F1(["END: Blocked — entry is\nnot Pending (409)"])
    F -- "Yes" --> F2["Set status = In Progress"] --> F3["Record task_started activity"] --> F4(["END: status = In Progress"])
    E -- "Complete" --> G{"completed_at\nalready set?"}
    G -- "Yes" --> G1(["END: Blocked — already\ncompleted (409)"])
    G -- "No" --> G2["Set completed_at, completed_by,\nstatus = Completed"]
    G2 --> G3["Send care_log_completed notification\n(best-effort; gated solely by the\ncustomer's own\nnotification_preferences.care_log_completed)\n+ email if account_email on file"]
    G3 --> G4["Record task_completed activity"] --> G5(["END: status = Completed"])
    E -- "Reopen" --> H{"Entry status = Pending?"}
    H -- "Yes" --> H1(["END: Blocked — already\nPending (409)"])
    H -- "No" --> H2["Clear completed_at/completed_by,\nset status = Pending"] --> H3["Record task_reopened activity"] --> H4(["END: status = Pending"])
```

## Notes

- `Missed` and `Backlog` are asymmetric: Missed is a real, persisted status
  transition (a bulk `UPDATE`) fired the moment a stale Pending/In Progress
  row is next read by _any_ caller (`getCareLogEntries` or the checkout
  gate's `assertChecklistComplete`); Backlog is a display-only relabeling of
  a still-`Pending` row scheduled for a future date — the stored column
  never changes, so it needs no reverse transition either.
- Missed is not terminal — `reopenCareLogEntry` accepts any status other
  than Pending, Missed included, so a mistakenly-flipped or genuinely-missed
  task can still be brought back to Pending.
- `completeCareLogEntry` does not require the entry to currently be In
  Progress — its only guard is `completed_at IS NULL` — so a card can be
  completed directly from Pending, matching a drag straight to the
  Completed column.
- The `care_log_completed` notification is gated purely by the customer's
  own notification preference now — there is no per-stay "owner opted in"
  staff checkbox anymore (see [[M11-notification|M11]]).
- Missed entries never block checkout; Backlog entries never block it
  either, since a future-dated task was never going to happen by today's
  checkout anyway — see
  [[M05-03-hotel-checkout|M05 · Hotel Checkout]]'s checklist gate, which
  only treats Pending/In Progress as outstanding.

## Relationship to other modules

Completion fires a customer notification/email via
[[M11-notification|M11]]. Outstanding (Pending/In Progress) entries gate
[[M05-03-hotel-checkout|M05 · Hotel Checkout]].
