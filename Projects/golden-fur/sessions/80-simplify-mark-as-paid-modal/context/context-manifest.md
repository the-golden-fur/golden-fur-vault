# Context — 80-simplify-mark-as-paid-modal

## Copied into ./context/

- `request.md` — the session request, transcribed from the chat message
  that started this session, plus the two planning decisions and the
  arch-history task source.

## Copied into ../reviews/

- `2026-09-09-1900-pre-pr.md` — the `Skill(code-review, "high")` pre-PR
  review for `feat/simplify-mark-as-paid-modal` (`pr-to-dev` step 4).
  Verdict APPROVE, no Blocking findings; the method-narrowing was reverted
  as scope creep and the amount bounds check extracted into a shared helper;
  two items recorded as intentional no-ops.
  Origin: `Projects/golden-fur/testing/reviews/feat/simplify-mark-as-paid-modal/2026-09-09-1900-pre-pr.md`.
- `2026-09-09-1812-pre-pr.md` — the earlier `/code-review` (medium) pass on
  the same branch, superseded by the high pass above. Kept for the trail.
  Also committed on vault branch `docs/arch-change-simplify-mark-as-paid`
  (`c054f4e`).

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx` —
  the advisor backlog; this change is the "Simplify cashier ... mark
  transaction as paid modal" item, moved to Merged by the user on vault
  branch `docs/arch-change-simplify-mark-as-paid` (`c054f4e`). Canonical,
  project-wide — referenced, not copied.
- `golden-fur/server/src/features/billing/services/transactionPayment.service.ts`
  — `recordTransactionPayment` / `payTransactionWithCredit`; the services
  changed this session.
- `golden-fur/server/src/features/billing/modules/validators/billing.validator.ts`
  — `recordTransactionPaymentValidator` and the new
  `payTransactionWithCreditValidator`.
- `golden-fur/server/supabase/migrations/*settle_transaction*` /
  `*pay_transaction_with_credit*` — the unchanged DB functions the services
  hand off to (`p_cash_tendered` was already ignored;
  `pay_transaction_with_credit` has clamped to available credit and spawned
  a leftover since migration `20260902164`). No migration added this
  session.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` — staff
  login values (`<branch>.<role>N`, e.g. `makati.cashier1`, password
  `password123`).
- `golden-fur/supabase/seeds/m02-customers-pets/m02-customers-pets.seed.ts`
  — customer login values (`customerN@goldenfur.com`, password
  `password123`).
- `golden-fur/server/.env`, `golden-fur/client/.env` — Supabase URL / keys
  for the dev database the manual test and verification ran against.
  Secrets; never copied.
