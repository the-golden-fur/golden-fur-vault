---
id: M12-01-discount-creation-and-lifecycle
module: M12
title: Discount Creation, Branch Availability & Archive Lifecycle
actors: [Admin, Superadmin]
trigger: Admin or Superadmin creates a custom discount, then later manages its branch availability, archive, restore, or permanent-delete lifecycle
outcome_success: discounts row (+ per-branch discount_branch_availability rows) created/updated/archived/restored/deleted as requested
outcome_failure:
  [
    validation_error,
    mandated_rename_blocked,
    archive_blocked_still_active,
    hard_delete_blocked_referenced,
  ]
related_modules: [M13]
source:
  - server/src/features/discounts/discounts.controller.ts
  - server/src/features/discounts/discounts.routes.ts
  - server/src/features/discounts/discounts.types.ts
  - server/src/features/discounts/services/discounts.service.ts
  - server/src/features/discounts/modules/validators/discounts.validator.ts
  - server/src/shared/archive/archiveGuard.ts
  - supabase/migrations/20260715033_m12_create_discounts_schema.sql
  - supabase/migrations/20260731072_shared_add_archived_at_discounts_promos_packages.sql
  - supabase/migrations/20260820140_custom_discount_branch_availability.sql
  - supabase/seeds/module-3-maintenance/module-3-maintenance.seed.ts
steps:
  - id: start
    type: start
    label: Admin/Superadmin begins creating a custom discount
    next: input_details
  - id: input_details
    type: input
    actor: [Admin, Superadmin]
    label: Enter name, discount_type (Percentage/Flat), value, scope_type + matching scope target (scope_service_id/scope_package_id/scope_category), branch_ids
    next: validate_create
  - id: validate_create
    type: decision
    label: "Payload valid? (exactly one scope field set matching scope_type; Percentage value <= 100; branch_ids non-empty; is_mandated not present in payload - rejected by .strict())"
    branches:
      - condition: "no"
        next: error_create
      - condition: "yes"
        next: insert_discount
  - id: error_create
    type: action
    label: Show validation error (400)
    next: input_details
  - id: insert_discount
    type: action
    label: Insert discounts row (is_mandated = false, is_active = true, created_by/updated_by = requester)
    next: insert_availability
  - id: insert_availability
    type: action
    label: Insert one discount_branch_availability row per selected branch_id (is_available = true)
    next: manage_decision
  - id: manage_decision
    type: decision
    actor: [Admin, Superadmin]
    label: What does Admin/Superadmin do with this now-active discount?
    branches:
      - condition: edit
        next: edit_discount
      - condition: toggle_branch_availability
        next: toggle_availability
      - condition: archive
        next: check_archive_guard
      - condition: stop
        next: end_success_created
  - id: end_success_created
    type: end
    result: success
    label: Discount created and left active at its selected branches
  - id: edit_discount
    type: decision
    actor: [Admin, Superadmin]
    label: Attempting to rename a mandated (Senior Citizen/PWD) discount?
    branches:
      - condition: "yes"
        next: error_mandated_rename
      - condition: "no"
        next: apply_update
  - id: error_mandated_rename
    type: action
    label: "Show error: a mandated discount's name cannot be changed (400)"
    next: manage_decision
  - id: apply_update
    type: action
    label: Update discounts row (discount_type/value/scope_type+target); null out other scope columns if scope_type changed; set updated_by/updated_at
    next: manage_decision
  - id: toggle_availability
    type: action
    actor: [Admin, Superadmin]
    label: Upsert discount_branch_availability row for the chosen branch (is_available = new value)
    next: recompute_active
  - id: recompute_active
    type: action
    label: Recompute discounts.is_active = true if ANY branch row has is_available = true, else false
    next: manage_decision
  - id: check_archive_guard
    type: decision
    label: "discounts.is_active = false? (no branch currently available - is_active is fully derived, not independently settable)"
    branches:
      - condition: "no"
        next: end_blocked_archive
      - condition: "yes"
        next: archive_discount
  - id: end_blocked_archive
    type: end
    result: blocked
    label: Archive blocked (403) - this discount must be deactivated (all branch availability turned off) before it can be archived
  - id: archive_discount
    type: action
    label: Set archived_at = now() (soft archive, reversible)
    next: post_archive_decision
  - id: post_archive_decision
    type: decision
    actor: [Admin, Superadmin]
    label: Admin/Superadmin's next action on the archived discount
    branches:
      - condition: restore
        next: restore_discount
      - condition: permanently_delete
        next: check_hard_delete_guard
      - condition: leave_archived
        next: end_success_archived
  - id: end_success_archived
    type: end
    result: success
    label: Discount archived - hidden from the active list, still reversible
  - id: restore_discount
    type: action
    label: Set archived_at = null
    next: end_success_restored
  - id: end_success_restored
    type: end
    result: success
    label: Discount restored (visible again; is_active reflects whatever branch availability rows currently say, still false until a branch is re-enabled)
  - id: check_hard_delete_guard
    type: decision
    label: "Delete blocked by a foreign_key_violation (23503) - discount still referenced by an existing booking or transaction?"
    branches:
      - condition: "yes"
        next: end_blocked_referenced
      - condition: "no"
        next: end_success_deleted
  - id: end_blocked_referenced
    type: end
    result: blocked
    label: Permanent delete blocked (409) - still referenced by a booking or a sale
  - id: end_success_deleted
    type: end
    result: success
    label: Discount permanently deleted (irreversible)
---

# M12 · Discount Creation, Branch Availability & Archive Lifecycle

Machine-readable companion to
[[M12-01-discount-creation-and-lifecycle|the human-readable version]] in
`Library/golden-fur/workflows/`.
