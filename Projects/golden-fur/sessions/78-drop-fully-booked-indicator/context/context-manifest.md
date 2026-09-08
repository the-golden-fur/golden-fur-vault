# Context — 78-drop-fully-booked-indicator

## Copied into ./context/

- `request.md` — the session request, transcribed verbatim from the chat
  message that started this session.

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/MsMayuga-URO-Aug27.pdf` — the Aug-27
  advisor demo transcript. Background only: the advisor's live walk-through
  of the receptionist New Booking flow is what surfaced the confusing
  "fully booked" behaviour that this request formalises. Project-wide
  reference material; stays canonical in `shared/context/`.
- `golden-fur/supabase/migrations/20260908179_m03_get_staff_availability_staff_capacity.sql`
  — the current definition of `get_staff_availability`; its Check 2
  (`bk.scheduled_start < p_requested_end AND bk.scheduled_end >
p_requested_start`) is the time-scoped overlap test referenced in
  `testing/testing.md`'s "Root cause".
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` —
  source of the staff login values in `testing/testing.md`
  (`<branch>.<role>N`, e.g. `makati.receptionist1`, password
  `password123`).
- `golden-fur/supabase/seeds/m02-customers-pets/m02-customers-pets.seed.ts`
  — source of the customer login values (`customerN@goldenfur.com`,
  password `password123`).
- `golden-fur/server/.env`, `golden-fur/client/.env` — Supabase URL / keys
  for the dev database the manual test runs against. Secrets; never copied.
