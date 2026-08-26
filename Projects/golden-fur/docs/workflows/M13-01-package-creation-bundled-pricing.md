---
id: M13-01-package-creation-bundled-pricing
module: M13
title: Package Creation & Bundled-Price Derivation
actors: [Admin, Superadmin]
trigger: Admin or Superadmin creates a package bundling 2+ existing services across one or more branches
outcome_success: packages row + package_services links + package_branch_availability rows created; bundled_price/total_duration_minutes derived on every subsequent read
outcome_failure: [validation_error, unknown_or_inactive_service_id]
related_modules: [M03, M08]
source:
  - server/src/features/maintenance/services/packages.service.ts
  - server/src/features/maintenance/services/packagePricing.service.ts
  - server/src/features/maintenance/utils/deriveBundledPrice.ts
  - server/src/features/maintenance/utils/derivePackageDuration.ts
  - server/src/features/maintenance/modules/validators/maintenance.validator.ts
  - server/src/features/maintenance/maintenance.types.ts
  - supabase/migrations/20260715032_m13_create_maintenance_schema.sql
  - supabase/migrations/20260726048_m13_package_pricing_configuration.sql
  - supabase/migrations/20260807106_m13_optional_pricing_matrix.sql
  - supabase/migrations/20260818134_custom_package_branch_availability.sql
steps:
  - id: start
    type: start
    label: Admin/Superadmin creates a package
    next: input_details
  - id: input_details
    type: input
    actor: [Admin, Superadmin]
    label: Enter name, service_ids (2+), branch_ids (1+), optional use_pricing_matrix/downpayment fields
    next: check_payload
  - id: check_payload
    type: decision
    label: Payload valid? (>=2 service_ids, >=1 branch_id, downpayment amount+type present if requires_downpayment)
    branches:
      - condition: "no"
        next: error_validation
      - condition: "yes"
        next: check_services_active
  - id: error_validation
    type: action
    label: Show validation error (400)
    next: input_details
  - id: check_services_active
    type: decision
    label: Every service_id exists and is_active = true?
    branches:
      - condition: "no"
        next: error_unknown_service
      - condition: "yes"
        next: insert_package
  - id: error_unknown_service
    type: action
    label: "Show error: unknown or inactive service id(s) (400)"
    next: input_details
  - id: insert_package
    type: action
    label: Insert packages row (is_active defaults true)
    next: insert_links
  - id: insert_links
    type: action
    label: Insert package_services link rows (one per service_id)
    next: insert_availability
  - id: insert_availability
    type: action
    label: Insert package_branch_availability rows (is_available = true for each chosen branch_id)
    next: refetch_package
  - id: refetch_package
    type: action
    label: Re-fetch package with services(base_price, duration_minutes) joined
    next: derive_price
  - id: derive_price
    type: action
    label: "Derive bundled_price = round2(sum(member base_price) * (1 - bundle_discount_percentage))"
    next: derive_duration
  - id: derive_duration
    type: action
    label: Derive total_duration_minutes = sum(member duration_minutes), null member counts as 0
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Package active; bundled_price/total_duration_minutes shown as a read-only preview
---

# M13 · Package Creation & Bundled-Price Derivation

Machine-readable companion to
[[M13-01-package-creation-bundled-pricing|the human-readable version]] in
`Library/golden-fur/workflows/`.
