---
title: "M02 · Customer & Pet Deactivate → Archive → Hard-Delete Lifecycle"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M02
---

# M02 · Customer & Pet Deactivate → Archive → Hard-Delete Lifecycle

**Actors:** Admin, Superadmin, Customer, Receptionist, Supervisor
**Code:** `server/src/features/customers/customer.controller.ts`,
`server/src/features/customers/services/customerArchive.service.ts`,
`server/src/features/customers/pets/pet.controller.ts`,
`server/src/features/customers/pets/services/petArchive.service.ts`,
`server/src/shared/archive/archiveGuard.ts`
**Part of:** [[M02-customer-portal-pet-management|M02 · Customer Portal & Pet Management]]

Customers and pets each follow the same three-step lifecycle used
elsewhere in the app for Products and Staff: deactivate, then archive,
then permanently delete — each step gated behind the previous one having
actually happened. Customer profiles and pets are gated differently,
though: a customer-level action is Admin/Superadmin only end-to-end, while
a pet's owner (or any front-desk-tier staff) can deactivate or archive it
themselves, and only Admin/Superadmin can restore it from archive or hard
delete it.

```mermaid
flowchart TD
    A(["START: Actor initiates a lifecycle\naction on a customer or a pet"]) --> B{"Target entity?"}

    B -- "Customer" --> C{"Requester is\nAdmin or Superadmin?\n(no self-service, no\nbroader staff tier)"}
    C -- "No" --> C1(["END: Blocked — Forbidden"])
    C -- "Yes" --> D{"Which action?"}

    D -- "Deactivate" --> E["Set customer.is_active = false\nAND cascade: deactivate every\npet owned by this customer"]
    E --> E1(["END: Customer deactivated\n(all their pets deactivated too)"])

    D -- "Activate" --> F["Set customer.is_active = true\n(no precondition guard —\ncallable any time)"]
    F --> F1(["END: Customer re-activated\n(pets NOT auto re-activated)"])

    D -- "Archive" --> G{"Customer already\ndeactivated?"}
    G -- "No" --> G1(["END: Blocked — must be\ndeactivated before archiving"])
    G -- "Yes" --> H["Set customer.archived_at = now()\nAND cascade: archive every\nnot-yet-archived pet"]
    H --> H1(["END: Customer archived\n(their unarchived pets archived too)"])

    D -- "Restore" --> I["Clear customer.archived_at\n(pets NOT restored — an individually\narchived pet may have its own reason)"]
    I --> I1(["END: Customer restored from archive\n(still is_active = false)"])

    D -- "Hard delete" --> J{"Customer already\narchived?"}
    J -- "No" --> J1(["END: Blocked — must be\narchived before deleting"])
    J -- "Yes" --> K["Delete customer_profiles row,\nthen delete the Supabase Auth\nuser (shared id)"]
    K --> K1(["END: Customer permanently deleted\n(profile row + Auth identity gone)"])

    B -- "Pet" --> L{"Which action?"}

    L -- "Deactivate or archive" --> M{"Requester is the pet's\nowner, or authorized staff\n(Receptionist/Admin/\nSupervisor/Superadmin)?"}
    M -- "No" --> M1(["END: Blocked — Forbidden"])
    M -- "Yes" --> N{"Deactivate\nor archive?"}

    N -- "Deactivate" --> O["Set pet.is_active = false\n(no precondition guard; independent\nof the owning customer's own state)"]
    O --> O1(["END: Pet deactivated\n(no API to re-activate directly)"])

    N -- "Archive" --> P{"Pet already\ndeactivated?"}
    P -- "No" --> P1(["END: Blocked — must be\ndeactivated before archiving"])
    P -- "Yes" --> Q["Set pet.archived_at = now()"]
    Q --> Q1(["END: Pet archived"])

    L -- "Restore or\nhard delete" --> R{"Requester is\nAdmin or Superadmin?\n(no owner exception)"}
    R -- "No" --> M1
    R -- "Yes" --> S{"Restore or\nhard delete?"}

    S -- "Restore" --> T["Clear pet.archived_at\n(is_active NOT reset to true)"]
    T --> T1(["END: Pet restored from archive\n(still is_active = false)"])

    S -- "Hard delete" --> U{"Pet already\narchived?"}
    U -- "No" --> U1(["END: Blocked — must be\narchived before deleting"])
    U -- "Yes" --> V["Delete the pets row"]
    V --> V1(["END: Pet permanently deleted"])
```

## Notes

- Customer-level actions are gated entirely to `CUSTOMER_ARCHIVE_ROLES`
  (Admin/Superadmin) — there is no self-service path and no broader
  `CUSTOMER_MANAGER_ROLES` (Receptionist/Supervisor) exception, unlike most
  other customer/pet endpoints.
- Pet deactivate/archive is gated more loosely: the pet's own owner **or**
  any `CUSTOMER_MANAGER_ROLES` staff (Receptionist, Admin, Supervisor,
  Superadmin) can do it — matching the idea that an owner should be able to
  flag their own pet as deceased/rehomed without needing an admin. Restore
  and hard-delete narrow back down to `CUSTOMER_ARCHIVE_ROLES` only, with
  no owner exception at all.
- `deactivate → archive → hard-delete` is a strict, one-directional
  precondition chain, enforced by the shared `archiveGuard.ts` helpers
  (`assertInactiveBeforeArchive`, `assertArchivedBeforeHardDelete`) used
  identically for Products and Staff elsewhere in the app — you can't skip
  a step, e.g. hard-deleting a still-active customer or pet.
- Deactivating or archiving a **customer** cascades onto their pets (every
  pet gets deactivated, or every not-yet-archived pet gets archived), but
  **restoring** a customer does not cascade back — a pet may have been
  archived independently (e.g. deceased) for a reason unrelated to the
  customer's own account state, so undoing the customer's archive
  shouldn't silently undo the pet's too.
- Deactivating a pet has no corresponding "re-activate" endpoint, and
  restoring an archived pet does **not** flip `is_active` back to `true`
  — a restored pet stays inactive with no API path to re-activate it
  directly (unlike a customer, which does have a dedicated `activate`
  endpoint). This asymmetry is real in the code as read; it isn't
  addressed here further since the module note makes no claim either way.
- Hard-deleting a **customer** also deletes the underlying Supabase Auth
  user, since `customer_profiles.id` and `auth.users.id` are the same
  value — a hard delete removes both the profile row and the login
  identity. A pet hard-delete only removes the `pets` row (pets have no
  Auth identity).
- Customers and pets never had a deactivate/archive concept before this
  feature — unlike Products and Staff, there was no pre-existing
  `is_active` toggle to extend, so this introduces "deactivate" as a new
  first step ahead of the pre-existing archive/delete machinery those
  other entities already used.

## Relationship to other modules

None beyond M02 itself — `related_modules` is empty in the machine file.
