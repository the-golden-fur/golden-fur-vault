# Context — 65-credit-expiry-visibility-and-config

## Copied into ./context/

- `Architectural-Change-History.docx` — the running "Architectural Change
  Suggestions" backlog / advisory log. The row driving this session is under
  Tasks → "Allow customers to see when will their credits expire … Improve
  credits expiry config in admin settings" (assignee Matthew, status In
  Progress). Also contains the MsMayuga-Aug27 advisory session review whose
  "D. Cancellations & Credits" items (#10 configurable conversion rate, #11
  credit-not-generated bug) are the prior credit work this builds on.
  Origin: `Inbox/Architectural-Change-History.docx` (moved here during planning).

## Referenced only (not copied)

- `golden-fur/.agent/skills/credit-balance-ledger.md` — canonical credit rules
  (branch-locked, non-transferable, FIFO expiry sweep runs independently of
  user action).
- `golden-fur/supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql`
  and `20260805098_m10_create_credit_expiry_function.sql` — the current
  `credit_expiry_enabled` / `credit_expiry_days` columns and the
  `expire_credits()` sweep.
- `golden-fur/supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql`
  — the end-to-end "add one `policy_configurations` column" recipe this plan
  follows.
- Claude Code plan-mode plan file (machine-local, not in the repo):
  `C:\Users\Matthew\.claude\plans\plan-for-now-no-sparkling-hummingbird.md` —
  the detailed implementation plan; `plan.md` here is its near-beginner
  retelling.
