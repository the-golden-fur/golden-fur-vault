---
id: M02-03-customer-pet-deactivation-archive-lifecycle
module: M02
title: Customer & Pet Deactivate → Archive → Hard-Delete Lifecycle
actors: [Admin, Superadmin, Customer, Receptionist, Supervisor]
trigger: An Admin/Superadmin acts on a customer profile, or a pet's owner/staff acts on a pet, to deactivate, archive, restore, or permanently delete it
outcome_success: entity's is_active/archived_at state transitions correctly; a hard delete removes the row (and, for a customer, the Supabase Auth user)
outcome_failure:
  [forbidden, must_deactivate_first, must_archive_first, not_found]
related_modules: []
source:
  - server/src/features/customers/customer.controller.ts
  - server/src/features/customers/customer.routes.ts
  - server/src/features/customers/customer.types.ts
  - server/src/features/customers/services/customerArchive.service.ts
  - server/src/features/customers/pets/pet.controller.ts
  - server/src/features/customers/pets/pet.routes.ts
  - server/src/features/customers/pets/services/petArchive.service.ts
  - server/src/shared/archive/archiveGuard.ts
  - supabase/migrations/20260731070_m02_add_customer_pet_is_active.sql
steps:
  - id: start
    type: start
    label: An actor initiates a lifecycle action on a customer profile or a pet
    next: check_entity
  - id: check_entity
    type: decision
    label: Target entity?
    branches:
      - condition: customer
        next: check_customer_role
      - condition: pet
        next: check_pet_action
  - id: check_customer_role
    type: decision
    label: Is the requester Admin or Superadmin? (CUSTOMER_ARCHIVE_ROLES — no self-service, no broader staff tier)
    branches:
      - condition: "no"
        next: end_customer_forbidden
      - condition: "yes"
        next: choose_customer_action
  - id: end_customer_forbidden
    type: end
    result: blocked
    label: "Forbidden (403)"
  - id: choose_customer_action
    type: decision
    label: Which action?
    branches:
      - condition: deactivate
        next: customer_deactivate
      - condition: activate
        next: customer_activate
      - condition: archive
        next: customer_check_inactive
      - condition: restore
        next: customer_restore
      - condition: hard_delete
        next: customer_check_archived
  - id: customer_deactivate
    type: action
    label: "Set customer_profiles.is_active = false, AND cascade: set is_active = false on every pet owned by this customer"
    next: end_customer_deactivated
  - id: end_customer_deactivated
    type: end
    result: success
    label: Customer deactivated (all their pets deactivated too)
  - id: customer_activate
    type: action
    label: "Set customer_profiles.is_active = true (no precondition guard - callable any time)"
    next: end_customer_activated
  - id: end_customer_activated
    type: end
    result: success
    label: Customer re-activated (pets are NOT auto re-activated)
  - id: customer_check_inactive
    type: decision
    label: "Is the customer already deactivated (is_active = false)?"
    branches:
      - condition: "no"
        next: end_customer_must_deactivate_first
      - condition: "yes"
        next: customer_archive
  - id: end_customer_must_deactivate_first
    type: end
    result: blocked
    label: "Forbidden (403) - must be deactivated before it can be archived"
  - id: customer_archive
    type: action
    label: "Set customer_profiles.archived_at = now(), AND cascade: archive every not-yet-archived pet owned by this customer"
    next: end_customer_archived
  - id: end_customer_archived
    type: end
    result: success
    label: Customer archived (their not-yet-archived pets archived too)
  - id: customer_restore
    type: action
    label: "Clear customer_profiles.archived_at (pets are NOT restored with the customer - an individually archived pet may have its own separate reason)"
    next: end_customer_restored
  - id: end_customer_restored
    type: end
    result: success
    label: Customer restored from archive (still is_active = false until separately activated)
  - id: customer_check_archived
    type: decision
    label: "Is the customer already archived (archived_at set)?"
    branches:
      - condition: "no"
        next: end_customer_must_archive_first
      - condition: "yes"
        next: customer_hard_delete
  - id: end_customer_must_archive_first
    type: end
    result: blocked
    label: "Forbidden (403) - must be archived before it can be permanently deleted"
  - id: customer_hard_delete
    type: action
    label: "Delete the customer_profiles row, then delete the underlying Supabase Auth user (id is shared between the two)"
    next: end_customer_hard_deleted
  - id: end_customer_hard_deleted
    type: end
    result: success
    label: Customer permanently deleted (profile row + Auth identity both gone)
  - id: check_pet_action
    type: decision
    label: Which action, and who is asking?
    branches:
      - condition: "deactivate or archive - owner or authorized staff (CUSTOMER_MANAGER_ROLES)"
        next: check_pet_deactivate_archive_authorized
      - condition: "restore or hard_delete - Admin/Superadmin only, no owner exception"
        next: check_pet_admin_tier_authorized
  - id: check_pet_deactivate_archive_authorized
    type: decision
    label: Is the requester the pet's owner, or authorized staff?
    branches:
      - condition: "no"
        next: end_pet_forbidden
      - condition: "yes"
        next: choose_pet_deactivate_or_archive
  - id: end_pet_forbidden
    type: end
    result: blocked
    label: "Forbidden (403)"
  - id: choose_pet_deactivate_or_archive
    type: decision
    label: Deactivate or archive?
    branches:
      - condition: deactivate
        next: pet_deactivate
      - condition: archive
        next: pet_check_inactive
  - id: pet_deactivate
    type: action
    label: "Set pets.is_active = false (no precondition guard; independent of the owning customer's own state)"
    next: end_pet_deactivated
  - id: end_pet_deactivated
    type: end
    result: success
    label: "Pet deactivated (no API exists to re-activate a deactivated pet directly - see Notes)"
  - id: pet_check_inactive
    type: decision
    label: "Is the pet already deactivated (is_active = false)?"
    branches:
      - condition: "no"
        next: end_pet_must_deactivate_first
      - condition: "yes"
        next: pet_archive
  - id: end_pet_must_deactivate_first
    type: end
    result: blocked
    label: "Forbidden (403) - must be deactivated before it can be archived"
  - id: pet_archive
    type: action
    label: "Set pets.archived_at = now()"
    next: end_pet_archived
  - id: end_pet_archived
    type: end
    result: success
    label: Pet archived
  - id: check_pet_admin_tier_authorized
    type: decision
    label: Is the requester Admin or Superadmin?
    branches:
      - condition: "no"
        next: end_pet_forbidden
      - condition: "yes"
        next: choose_pet_restore_or_delete
  - id: choose_pet_restore_or_delete
    type: decision
    label: Restore or hard delete?
    branches:
      - condition: restore
        next: pet_restore
      - condition: hard_delete
        next: pet_check_archived
  - id: pet_restore
    type: action
    label: "Clear pets.archived_at (is_active is NOT reset to true - see Notes)"
    next: end_pet_restored
  - id: end_pet_restored
    type: end
    result: success
    label: "Pet restored from archive (still is_active = false, with no endpoint to flip it back)"
  - id: pet_check_archived
    type: decision
    label: "Is the pet already archived (archived_at set)?"
    branches:
      - condition: "no"
        next: end_pet_must_archive_first
      - condition: "yes"
        next: pet_hard_delete
  - id: end_pet_must_archive_first
    type: end
    result: blocked
    label: "Forbidden (403) - must be archived before it can be permanently deleted"
  - id: pet_hard_delete
    type: action
    label: "Delete the pets row"
    next: end_pet_hard_deleted
  - id: end_pet_hard_deleted
    type: end
    result: success
    label: Pet permanently deleted
---

# M02 · Customer & Pet Deactivate → Archive → Hard-Delete Lifecycle

Machine-readable companion to
[[M02-03-customer-pet-deactivation-archive-lifecycle|the human-readable version]] in
`Library/golden-fur/workflows/`.
