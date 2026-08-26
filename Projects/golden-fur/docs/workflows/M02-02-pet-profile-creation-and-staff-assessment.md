---
id: M02-02-pet-profile-creation-and-staff-assessment
module: M02
title: Pet Profile Creation & Staff Physical Assessment
actors: [Customer, Receptionist, Admin, Supervisor, Superadmin]
trigger: A customer registers a pet on their own account, or staff creates/edits a pet on a customer's behalf (walk-in intake, booking, daycare check-in)
outcome_success: pets row created/updated; weight_class and coat_type (and the resulting "assessed" state) are only ever set by staff
outcome_failure: [forbidden, validation_error, staff_only_fields_rejected]
related_modules: [M03, M13]
source:
  - server/src/features/customers/pets/pet.controller.ts
  - server/src/features/customers/pets/pet.routes.ts
  - server/src/features/customers/pets/pet.types.ts
  - server/src/features/customers/pets/modules/validators/pet.validator.ts
  - server/src/features/customers/pets/tests/pet.integration.spec.ts
  - client/src/features/customers/components/forms/PetForm/PetForm.tsx
  - supabase/migrations/20260712024_m02_create_pets.sql
  - supabase/migrations/20260712025_m02_pets_rls.sql
  - supabase/migrations/20260725041_m02_create_breeds_and_pet_fields.sql
  - supabase/migrations/20260731070_m02_add_customer_pet_is_active.sql
  - supabase/migrations/20260802073_m02_pets_assessment_lock.sql
  - supabase/migrations/20260802075_m02_pets_assessment_trigger_fix.sql
steps:
  - id: start
    type: start
    label: Customer or staff submits a pet create/update
    next: check_who
  - id: check_who
    type: decision
    label: Is the caller the pet's own customer (self-service)?
    branches:
      - condition: "yes"
        next: input_self
      - condition: "no"
        next: check_staff_authorized
  - id: check_staff_authorized
    type: decision
    label: Is the caller staff with a Receptionist/Admin/Supervisor/Superadmin role (CUSTOMER_MANAGER_ROLES)?
    branches:
      - condition: "no"
        next: end_forbidden
      - condition: "yes"
        next: input_staff
  - id: end_forbidden
    type: end
    result: blocked
    label: "Forbidden (403)"
  - id: input_self
    type: input
    actor: [Customer]
    label: Enter name, pet_type, breed_id, gender?, date_of_birth?, photo? — createPetValidator/.strict() rejects weight_class or coat_type outright as unknown keys
    next: validate_self
  - id: input_staff
    type: input
    actor: [Receptionist, Admin, Supervisor, Superadmin]
    label: Enter the same fields, optionally including weight_class/coat_type from a physical weigh-in and coat check (createPetValidatorStaff)
    next: validate_staff
  - id: validate_self
    type: decision
    label: Payload passes createPetValidator (name/pet_type required, no unknown keys)?
    branches:
      - condition: "no"
        next: error_validation_self
      - condition: "yes"
        next: insert_pet
  - id: error_validation_self
    type: action
    label: "Show validation error (400) - includes the case where a customer payload contains weight_class/coat_type at all"
    next: input_self
  - id: validate_staff
    type: decision
    label: Payload passes createPetValidatorStaff?
    branches:
      - condition: "no"
        next: error_validation_staff
      - condition: "yes"
        next: insert_pet
  - id: error_validation_staff
    type: action
    label: "Show validation error (400)"
    next: input_staff
  - id: insert_pet
    type: action
    label: Insert pets row (customer_id = target customer)
    next: check_both_assessment_fields
  - id: check_both_assessment_fields
    type: decision
    label: Was the caller staff, AND did the submitted row end up with both weight_class and coat_type non-null?
    branches:
      - condition: "yes"
        next: stamp_assessment
      - condition: "no"
        next: end_created_unassessed
  - id: stamp_assessment
    type: action
    label: "Stamp assessed_by = requester id, assessed_at = now() (done in pet.controller.ts, not the DB trigger - see Notes)"
    next: end_created_assessed
  - id: end_created_assessed
    type: end
    result: success
    label: Pet profile created — fully assessed (weight_class + coat_type recorded)
  - id: end_created_unassessed
    type: end
    result: success
    label: "Pet profile created — Unassessed (weight_class/coat_type NULL until staff records a physical assessment)"
  - id: later_update
    type: start
    label: "Later: staff opens an existing pet to record/update the physical assessment"
    next: check_update_who
  - id: check_update_who
    type: decision
    label: Is the caller the pet's owner, or authorized staff?
    branches:
      - condition: "owner"
        next: update_owner_fields
      - condition: "staff"
        next: update_staff_fields
      - condition: "neither"
        next: end_forbidden
  - id: update_owner_fields
    type: action
    label: Owner PATCHes non-assessment fields only (updatePetValidator rejects weight_class/coat_type as unknown keys)
    next: end_updated_owner
  - id: end_updated_owner
    type: end
    result: success
    label: Pet profile updated by owner (assessment fields untouched)
  - id: update_staff_fields
    type: action
    label: Staff PATCHes fields, optionally resubmitting weight_class/coat_type (updatePetValidatorStaff)
    next: check_fields_actually_changed
  - id: check_fields_actually_changed
    type: decision
    label: Did weight_class or coat_type actually change value from the stored row (not just resent)?
    branches:
      - condition: "yes"
        next: restamp_assessment
      - condition: "no"
        next: carry_forward_stamp
  - id: restamp_assessment
    type: action
    label: Re-stamp assessed_by/assessed_at to this staff member/now
    next: end_updated_assessed
  - id: end_updated_assessed
    type: end
    result: success
    label: Pet re-assessed — assessed_by/assessed_at refreshed
  - id: carry_forward_stamp
    type: action
    label: Leave assessed_by/assessed_at unchanged (an unrelated edit, e.g. name/photo, doesn't count as a fresh assessment)
    next: end_updated_no_restamp
  - id: end_updated_no_restamp
    type: end
    result: success
    label: Pet profile updated — no re-assessment occurred
---

# M02 · Pet Profile Creation & Staff Physical Assessment

Machine-readable companion to
[[M02-02-pet-profile-creation-and-staff-assessment|the human-readable version]] in
`Library/golden-fur/workflows/`.
