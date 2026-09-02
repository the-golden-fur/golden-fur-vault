---
id: M10-05-credit-expiry-policy-retroactive-restamp
module: M10
title: Credit-Expiry Policy Change — Retroactive Re-stamp
actors: [Admin, Superadmin]
trigger: An Admin/Superadmin PATCH /bookings/policy in which the effective credit_expiry_mode, credit_expiry_days, or credit_expiry_fixed_date for the target policy row actually changes
outcome_success: policy row saved (200); expires_at re-stamped on every not-yet-swept issuance credit_transactions lot at the affected branch(es) via the reapply_branch_credit_expiry SECURITY-DEFINER RPC
outcome_failure: [forbidden, invalid_payload, policy_write_failed]
related_modules: [M09, M08]
source:
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/booking.routes.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - server/src/features/booking/services/cancellation.service.ts
  - server/src/features/credits/modules/creditExpiry.util.ts
  - server/src/features/credits/services/creditExpiry.job.ts
  - supabase/migrations/20260902159_m10_policy_credit_expiry_mode.sql
  - supabase/migrations/20260902160_m10_credit_expiry_manila_end_of_day.sql
  - supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql
  - supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql
steps:
  - id: start
    type: start
    label: Admin/Superadmin submits PATCH /bookings/policy (branch_id null/omitted = system-default row, a uuid = that branch's override row)
    next: check_role
  - id: check_role
    type: decision
    label: "adminWrite guard — jwtMiddleware + sessionTimeoutMiddleware + requireRole(BOOKING_POLICY_WRITE_ROLES = Admin, Superadmin)"
    branches:
      - condition: "not authorized"
        next: end_forbidden
      - condition: "authorized"
        next: validate_payload
  - id: end_forbidden
    type: end
    result: blocked
    label: Forbidden (401/403)
  - id: validate_payload
    type: decision
    label: "updatePolicyValidator.safeParse — strict object; superRefine requires >=1 setting, and credit_expiry_fixed_date present iff credit_expiry_mode = 'fixed_date' ('only one or the other'); credit_expiry_days is a positive int"
    branches:
      - condition: "invalid"
        next: end_invalid
      - condition: "valid"
        next: normalize_fixed_date
  - id: end_invalid
    type: end
    result: blocked
    label: Invalid payload (400)
  - id: normalize_fixed_date
    type: action
    label: "updatePolicyConfiguration — if credit_expiry_mode is present and != 'fixed_date', force settings.credit_expiry_fixed_date = null so a stale date can't linger on the row"
    next: lookup_existing_row
  - id: lookup_existing_row
    type: decision
    label: "Look up the policy_configurations row for the target (branch_id eq, or branch_id IS NULL for the default). Lookup error -> 400 (policy_write_failed)"
    branches:
      - condition: "row exists"
        next: update_row
      - condition: "no row (branch has no override yet)"
        next: build_baseline
  - id: update_row
    type: action
    label: "UPDATE the row with settings + updated_at; on error/no-row -> 400. before = the pre-update row"
    next: reapply_entry
  - id: build_baseline
    type: action
    label: "resolveEffectivePolicy(branchId) -> baseline (the values this branch's credit followed with no override). INSERT baseline + settings + branch_id; on error -> 400. before = that resolved effective policy"
    next: reapply_entry
  - id: reapply_entry
    type: action
    label: "reapplyCreditExpiryAfterPolicyChange(branchId, before, after) — best-effort, wrapped in try/catch"
    next: check_expiry_changed
  - id: check_expiry_changed
    type: decision
    label: "creditExpiryUnchanged(before, after)? — credit_expiry_mode AND credit_expiry_days AND credit_expiry_fixed_date all equal (the Policies page PATCHes every field on every save, so an unrelated edit must not fan out)"
    branches:
      - condition: "unchanged"
        next: end_success_noop
      - condition: "changed"
        next: resolve_branch_ids
  - id: end_success_noop
    type: end
    result: success
    label: "Policy row returned (200); no lots touched"
  - id: resolve_branch_ids
    type: decision
    label: Was a concrete branch row saved (branchId non-null)?
    branches:
      - condition: "yes (branch override row)"
        next: rpc_reapply
      - condition: "no (system-default row)"
        next: fan_out_branches
  - id: fan_out_branches
    type: action
    label: "Query branches + all policy_configurations rows with branch_id NOT NULL; branchIds = every branch that has NO override of its own (exactly the branches resolveEffectivePolicy hands the default row). A branches/overrides query error is thrown into the catch below"
    next: check_branch_ids_empty
  - id: check_branch_ids_empty
    type: decision
    label: branchIds non-empty?
    branches:
      - condition: "empty"
        next: end_success_saved
      - condition: "non-empty"
        next: rpc_reapply
  - id: rpc_reapply
    type: action
    label: "supabase.rpc('reapply_branch_credit_expiry', { p_branch_ids: branchIds, p_mode: after.credit_expiry_mode, p_days: after.credit_expiry_days, p_fixed_date: after.credit_expiry_fixed_date }) — SECURITY DEFINER, service_role-only. UPDATEs credit_transactions.expires_at for every transaction_type='issuance' AND expired_at IS NULL lot at those branches: 'none' -> NULL, 'rolling' -> end of the Manila day (created_at + p_days), 'fixed_date' -> end of the Manila day p_fixed_date"
    next: check_rpc_error
  - id: check_rpc_error
    type: decision
    label: Did the branch fan-out query or the RPC error?
    branches:
      - condition: "yes"
        next: swallow_error
      - condition: "no"
        next: end_success_saved
  - id: swallow_error
    type: action
    label: "catch — console.error('reapplyCreditExpiryAfterPolicyChange failed (policy still saved)'); the error is NOT re-thrown (mirrors the #117 credit-issuance non-gating precedent)"
    next: end_success_saved
  - id: end_success_saved
    type: end
    result: success
    label: "Policy row returned (200); outstanding lots at the affected branch(es) re-stamped, or the re-stamp was best-effort skipped/failed. expire_credits() then sweeps on its normal schedule"
---

# M10 · Credit-Expiry Policy Change — Retroactive Re-stamp

Machine-readable companion to
[[M10-05-credit-expiry-policy-retroactive-restamp|the human-readable version]] in
`Library/golden-fur/features/credits/workflows/`.
