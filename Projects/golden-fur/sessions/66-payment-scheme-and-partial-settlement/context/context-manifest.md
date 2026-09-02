# Context — 66-payment-scheme-and-partial-settlement

## Copied into ./context/

- `Architectural-Change-History.docx` — the client's task tracker. The
  "In Progress" row assigned to Matthew (payment scheme choice + two-transaction
  downpayment + partial settlement) is the source request. Origin:
  `golden-fur-vault/Inbox/Architectural-Change-History.docx` /
  `Projects/golden-fur/shared/context/`.

## Referenced only (not copied)

- `golden-fur/server/.env` — staff/customer test-login values for the manual
  test steps come from here; a secrets file, never copied.
- `Projects/golden-fur/shared/decisions/2026-08-29-online-payment-gate-and-downpayment-holds.md`
  — the down-payment slot-gate / pencil-booking design this builds on.
- `Projects/golden-fur/shared/decisions/2026-08-30-transactions-page-and-confirmation-status.md`
  — the transactions-page / confirmation-status design.
- `Projects/golden-fur/shared/decisions/2026-08-28-walk-in-booking-flow.md`
  — confirms the Online/Walk-in step is receptionist-only (relevant to the
  follow-up question in `testing.md` step G).
- `Library/golden-fur/features/{booking,billing,credits}/workflows/` — M03-01,
  M08-02, M08-04, M10-04 workflow docs are stale after this change (see the
  golden-fur PR's "How" section for the exact drift) and need a
  `workflow-documenter` refresh — deferred, the agent hit the session rate
  limit this run.
