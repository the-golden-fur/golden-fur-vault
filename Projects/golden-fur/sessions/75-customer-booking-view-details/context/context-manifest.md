# Context — 75-customer-booking-view-details

## Copied into ./context/

- `backlog-items.md` — the two backlog rows this session implements, transcribed
  verbatim. Origin:
  `Projects/golden-fur/shared/context/Architectural-Change-History.docx`
  ("Production" section — "Add new option to … in customer account > bookings
  page"; and "Low Priority" table — "Fix unknown pet owner and unknown pet
  when viewing bookings as cashier").

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx`
  (and its `.pdf` export) — the full project change backlog. Project-wide
  reference material; stays canonical in `shared/context/`.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` — source of
  the staff login values in `testing/testing.md` (`<branch>.<role>N`, e.g.
  `makati.cashier1` / `makati.receptionist1`, password `password123`).
- `golden-fur/supabase/seeds/m02-customers-pets/m02-customers-pets.seed.ts` —
  source of the customer login values (`customerN@goldenfur.com`, password
  `password123`).
- `golden-fur/server/.env`, `golden-fur/client/.env` — Supabase URL / keys for
  the dev database the manual test and Postman collection run against. Secrets;
  never copied.
