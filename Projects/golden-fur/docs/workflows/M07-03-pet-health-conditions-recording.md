---
id: M07-03-pet-health-conditions-recording
module: M07
title: Pet Health Conditions Recording
actors: [Veterinarian]
trigger: A Veterinarian edits the Health Conditions field on a pet's consultation form
outcome_success: pet_health_conditions row upserted (one per pet_id) with the new conditions_text, updated_by_staff_id, and updated_at
outcome_failure: [forbidden_not_veterinarian, pet_not_found]
related_modules: [M02]
source:
  - server/src/features/veterinary/services/petHealthConditions.service.ts
  - server/src/features/veterinary/veterinary.controller.ts
  - server/src/features/veterinary/veterinary.routes.ts
  - server/src/features/veterinary/modules/validators/veterinary.validator.ts
  - supabase/migrations/20260725042_m02_m07_create_pet_health_conditions.sql
steps:
  - id: start
    type: start
    label: Veterinarian edits the Health Conditions field on a pet's consultation form
    next: input_conditions
  - id: input_conditions
    type: input
    actor: [Veterinarian]
    label: Enter or clear conditions_text (null/empty clears the flag)
    next: check_role
  - id: check_role
    type: decision
    label: Requester role = Veterinarian?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_pet_exists
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_pet_exists
    type: decision
    label: Pet exists?
    branches:
      - condition: "no"
        next: end_blocked_not_found
      - condition: "yes"
        next: upsert_conditions
  - id: end_blocked_not_found
    type: end
    result: blocked
    label: Pet not found (404)
  - id: upsert_conditions
    type: action
    label: Upsert pet_health_conditions (one row per pet_id) with updated_by_staff_id, updated_at
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Health conditions saved - surfaced read-only on the customer-portal pet profile
---

# M07 · Pet Health Conditions Recording

Machine-readable companion to
[[M07-03-pet-health-conditions-recording|the human-readable version]] in
`Library/golden-fur/workflows/`.
