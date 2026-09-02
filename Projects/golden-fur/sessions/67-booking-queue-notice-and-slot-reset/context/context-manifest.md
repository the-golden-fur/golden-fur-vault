# Context — 67-booking-queue-notice-and-slot-reset

## Copied into ./context/

- `architectural-change-history-excerpt.md` — the two "In Progress" backlog rows
  (assignee Alarie) this session addresses, plus the related "Merged" row
  ("Investigate and fix the 3-day-minimum booking filter"). Extracted from the
  source doc below.

## Referenced only (not copied)

- `golden-fur-vault/Inbox/Architectural-Change-History.docx` — the full backlog
  board. Only the two rows above are in scope this session.
- `golden-fur-vault/Projects/golden-fur/sessions/_legacy/custom/59-booking-notice-lead-time/`
  — the session that first coupled `notice_period_days` to new bookings; this
  session partially reverses it.
- `golden-fur/supabase/migrations/20260901156_m03_get_staff_availability_payment_status.sql`
  — current `get_staff_availability` definition, reviewed to confirm the staff
  picker is already correct.
