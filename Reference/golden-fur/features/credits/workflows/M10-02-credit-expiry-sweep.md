---
id: M10-02-credit-expiry-sweep
module: M10
title: Credit Expiry Sweep
actors: [System, Admin, Superadmin]
trigger: Daily pg_cron schedule (if pg_cron installed) OR an Admin/Superadmin manually calls POST /credits/expire
outcome_success: every not-yet-swept issuance row past its expires_at gets an offsetting expiry credit_transactions row (capped at the balance re-read FOR UPDATE that iteration) and its expired_at marked; returns count swept
outcome_failure: [forbidden_role, expire_credits_rpc_error]
related_modules: [M08, M14]
source:
  - server/src/features/credits/services/creditExpiry.job.ts
  - server/src/features/credits/services/creditExpiry.job.spec.ts
  - server/src/features/credits/credits.controller.ts
  - server/src/features/credits/credits.routes.ts
  - server/src/features/credits/credits.types.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - supabase/migrations/20260805098_m10_create_credit_expiry_function.sql
  - supabase/migrations/20260902159_m10_policy_credit_expiry_mode.sql
  - supabase/migrations/20260902160_m10_credit_expiry_manila_end_of_day.sql
  - server/src/features/billing/services/creditStub.service.ts
steps:
  - id: start
    type: start
    label: Credit expiry sweep triggered
    next: check_trigger_source
  - id: check_trigger_source
    type: decision
    label: Trigger source
    branches:
      - condition: pg_cron (daily 00:10, if installed)
        next: call_expire_credits
      - condition: Admin/Superadmin manual trigger
        next: manual_route
  - id: manual_route
    type: action
    actor: [Admin, Superadmin]
    label: "POST /credits/expire (jwtMiddleware + sessionTimeoutMiddleware)"
    next: check_role
  - id: check_role
    type: decision
    label: Caller role is Admin or Superadmin?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: call_expire_credits
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: call_expire_credits
    type: action
    label: Call expire_credits() DB function
    next: check_rpc_error
  - id: check_rpc_error
    type: decision
    label: expire_credits() RPC errored?
    branches:
      - condition: "yes"
        next: end_error
      - condition: "no"
        next: select_expired_rows
  - id: end_error
    type: end
    result: error
    label: Credit expiry job failed (500)
  - id: select_expired_rows
    type: action
    label: "Open a cursor over every not-yet-swept issuance row (transaction_type='issuance', expired_at IS NULL, expires_at IS NOT NULL AND < now()), ordered oldest expires_at first. Since migration 20260902159 the cursor selects only ct.id/credit_balance_id/amount — NOT a one-time cb.balance join"
    next: check_rows_remaining
  - id: check_rows_remaining
    type: decision
    label: Any rows left to process?
    branches:
      - condition: "no"
        next: end_success
      - condition: "yes"
        next: reread_balance
  - id: reread_balance
    type: action
    label: "Re-select this row's credit_balances.balance FOR UPDATE (per-iteration, new in migration 20260902159 — the old version read balance once via the cursor join, so several same-dated lots each capped against the ORIGINAL balance and could drive it below 0, tripping the balance >= 0 CHECK and aborting the whole sweep)"
    next: compute_expire_amount
  - id: compute_expire_amount
    type: action
    label: "expire_amount = LEAST(issuance amount, GREATEST(this-iteration balance, 0))"
    next: check_expire_amount_positive
  - id: check_expire_amount_positive
    type: decision
    label: expire_amount > 0?
    branches:
      - condition: "yes"
        next: write_expiry_row
      - condition: "no"
        next: skip_ledger_write
  - id: write_expiry_row
    type: action
    label: "Insert 'expiry' credit_transactions row (amount = -expire_amount) and decrement credit_balances.balance"
    next: mark_expired_at
  - id: skip_ledger_write
    type: action
    label: Skip ledger write (balance already fully consumed)
    next: mark_expired_at
  - id: mark_expired_at
    type: action
    label: Mark this issuance row's expired_at = now() (never reprocessed)
    next: check_rows_remaining
  - id: end_success
    type: end
    result: success
    label: Sweep complete — returns count of rows swept
---

# M10 · Credit Expiry Sweep

Machine-readable companion to
[[M10-02-credit-expiry-sweep|the human-readable version]] in
`Library/golden-fur/features/credits/workflows/`.
