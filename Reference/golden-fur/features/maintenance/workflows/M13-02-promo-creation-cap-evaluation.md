---
id: M13-02-promo-creation-cap-evaluation
module: M13
title: Promo Creation, Branch Availability & Per-Transaction Cap Evaluation
actors: [Admin, Superadmin, System]
trigger: Admin or Superadmin creates a promo; separately, a booking reaches checkout and the system evaluates which active promos apply
outcome_success: promo created and branch-scoped; at checkout, active/eligible promos are auto-applied largest-amount-first up to the effective per-branch or default cap, and recorded in transaction_promo_selections
outcome_failure:
  [
    validation_error_date_and_condition,
    validation_error_window_or_condition,
    validation_error_percentage_over_100,
    validation_error_scope_mismatch,
  ]
related_modules: [M08]
source:
  - server/src/features/maintenance/services/promos.service.ts
  - server/src/features/maintenance/services/promoCap.service.ts
  - server/src/features/maintenance/modules/validators/maintenance.validator.ts
  - server/src/features/maintenance/maintenance.types.ts
  - server/src/features/billing/services/discountPromoEvaluation.service.ts
  - server/src/features/billing/services/checkoutAggregation.service.ts
  - server/src/features/maintenance/jobs/promoExpiry.job.ts
  - supabase/migrations/20260715032_m13_create_maintenance_schema.sql
  - supabase/migrations/20260726049_m13_promo_cap_and_transaction_promo_selections.sql
  - supabase/migrations/20260818132_custom_promo_cap_count_type.sql
  - supabase/migrations/20260820141_custom_promo_branch_availability.sql
steps:
  - id: start
    type: start
    label: Admin/Superadmin creates a promo
    next: input_details
  - id: input_details
    type: input
    actor: [Admin, Superadmin]
    label: "Enter name, discount_type + value, scope_type + scope, start_date/end_date OR condition_note, branch_ids (1+)"
    next: check_date_and_condition
  - id: check_date_and_condition
    type: decision
    label: Date-bounded AND condition-based at once?
    branches:
      - condition: "yes"
        next: error_date_and_condition
      - condition: "no"
        next: check_window
  - id: error_date_and_condition
    type: action
    label: "Show error: pick one, dates OR condition_note (400)"
    next: input_details
  - id: check_window
    type: decision
    label: "Date-bounded: both dates present and end_date >= start_date? Condition-based: condition_note present?"
    branches:
      - condition: "no"
        next: error_window
      - condition: "yes"
        next: check_percentage
  - id: error_window
    type: action
    label: Show validation error (400)
    next: input_details
  - id: check_percentage
    type: decision
    label: discount_type = Percentage AND value > 100?
    branches:
      - condition: "yes"
        next: error_percentage
      - condition: "no"
        next: check_scope
  - id: error_percentage
    type: action
    label: "Show error: percentage cannot exceed 100 (400)"
    next: input_details
  - id: check_scope
    type: decision
    label: scope_type/scope mismatch (all_services with non-empty scope, or specific with empty scope)?
    branches:
      - condition: "yes"
        next: error_scope
      - condition: "no"
        next: insert_promo
  - id: error_scope
    type: action
    label: Show scope/scope_type mismatch error (400)
    next: input_details
  - id: insert_promo
    type: action
    label: Insert promos row (is_active defaults true)
    next: insert_scope
  - id: insert_scope
    type: action
    label: Insert promo_scope rows (if scope_type = specific)
    next: insert_availability
  - id: insert_availability
    type: action
    label: Insert promo_branch_availability rows (is_available = true per chosen branch)
    next: end_created
  - id: end_created
    type: end
    result: success
    label: Promo active and scoped; visible to booking/checkout evaluation at its available branches
  - id: expiry_job
    type: action
    label: "Daily 00:05 job (or app-layer fallback): deactivate_expired_promos() sets is_active = false on date-bounded promos past end_date"
    next: end_expired
  - id: end_expired
    type: end
    result: success
    label: Promo auto-deactivated (condition-based promos exempt)
  - id: checkout_evaluate
    type: action
    label: "At checkout: evaluatePromos() filters to promos that are is_active, branch-available, in date window, and scope-matches a booking item"
    next: check_any_matched
  - id: check_any_matched
    type: decision
    label: Any promo matched?
    branches:
      - condition: "no"
        next: end_no_promo
      - condition: "yes"
        next: compute_amounts
  - id: end_no_promo
    type: end
    result: success
    label: No promo lines applied
  - id: compute_amounts
    type: action
    label: Compute each matched promo's discount amount against subtotal; sort largest amount first
    next: lookup_cap
  - id: lookup_cap
    type: action
    label: Look up effective cap - branch-specific promo_cap_configuration row, else the system-wide default row
    next: check_cap_type
  - id: check_cap_type
    type: decision
    label: cap_type?
    branches:
      - condition: count
        next: apply_count_cap
      - condition: percentage_or_flat
        next: apply_amount_cap
  - id: apply_count_cap
    type: action
    label: Apply the N largest-value promos in full (N = cap_value); drop the rest entirely
    next: record_selections
  - id: apply_amount_cap
    type: action
    label: Apply promos largest-first; trim the one crossing the cap to exactly fill remaining headroom; apply nothing beyond it
    next: record_selections
  - id: record_selections
    type: action
    label: Record each applied promo as a transaction_promo_selections row (is_activated = true) after checkout completes
    next: end_capped
  - id: end_capped
    type: end
    result: success
    label: Capped promo total netted into the transaction
---

# M13 · Promo Creation, Branch Availability & Per-Transaction Cap Evaluation

Machine-readable companion to
[[M13-02-promo-creation-cap-evaluation|the human-readable version]] in
`Library/golden-fur/features/maintenance/workflows/`.
