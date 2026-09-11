# Context — 83-slot-conflict-notifications

## Copied into ./context/

- `Architectural-Change-History.pdf` — the running backlog of architectural
  change requests, the source of this session's request (the "In Progress"
  list item, page 5, owner Matthew, quoted verbatim in `plan.md` and
  `testing/testing.md`). **Note the file used here is the `.pdf` export**,
  not `Architectural-Change-History.docx` — the two have diverged (the
  `.docx` in `shared/context/` does not yet contain this item; only the
  `.pdf`, which has a newer file timestamp, does). Canonical copy:
  `Projects/golden-fur/shared/context/Architectural-Change-History.pdf`
  (normally referenced, not copied — copied here anyway so this session
  record stays self-contained given the source has since drifted from the
  `.docx`).
- `Architectural-Change-History.txt` — a plain-text extraction of the PDF
  above (via `pypdf`, all 57 pages, ligatures/bullets normalized, repeated
  spaces collapsed), generated this session for quick diffing/grep — the
  PDF itself is 3.4 MB and not practically greppable. The page-5 item this
  session is built from starts at the `===== page 5 =====` marker and was
  used to double-check `plan.md`'s verbatim quote character-for-character
  (confirmed matching, modulo the ligature/whitespace normalization noted
  above).

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx` —
  the same backlog doc's older `.docx` export; referenced only to confirm
  it does *not* yet contain this session's item (see note above), not used
  as a source.
- `golden-fur/server/src/features/booking/booking.types.ts` —
  `SLOT_HOLD_PAID_OR_FILTER`, the pre-existing filter re-confirmed (not
  changed) as already solving the first half of the request.
  `golden-fur/server/src/features/booking/services/capacity.service.ts`,
  `staffPicker.service.ts`, and the `get_staff_availability` Postgres
  function are its other call sites.
- `golden-fur/client/src/shared/auth/guards/StaffAuthGuard/StaffAuthGuard.tsx`
  — the always-mounted `MfaSetupModal` pattern this session's
  `SlotConflictModal` on `CustomerPortalPage` was modeled on.
- `golden-fur/client/src/pages/NotificationsPage/NotificationsPage.tsx` —
  the existing `?open=<id>` deep-link convention this session's
  `CustomerBookingsPage.tsx` and `SlotConflictModal` reused.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` — staff
  login values (`<branch>.<roleslug>N@goldenfur.com`, e.g.
  `makati.cashier1@goldenfur.com`, password `password123`) used in
  `testing/testing.md`'s manual test.
- `golden-fur/supabase/seeds/m02-customers-pets/m02-customers-pets.seed.ts`
  — customer login values (`customerN@goldenfur.com`, password
  `password123`) used in `testing/testing.md`'s manual test.
- `golden-fur/supabase/.temp/project-ref` — confirms the linked Supabase
  project is the dev ref `hikgijuipymfghfuyrjv`, not prod
  `gtqncxqsofqtzrlgxdfm`, before the `supabase db push` done earlier this
  session and re-confirmed (via `supabase:status`) in this documentation
  pass.
- `golden-fur/server/.env`, `golden-fur/client/.env` — Supabase URL/keys the
  test suites and migration checks ran against this session; secrets, never
  copied.
