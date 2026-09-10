# Context — 82-pet-weight-derived-class

## Copied into ./context/

- `Architectural-Change-History.docx` — the running backlog of architectural
  change requests. This session implements the "Matthew / Low Priority" row:
  the two-part "derive weight class from actual weight / per-user kg-lb view"
  item. **Double-homed on purpose:** the canonical copy stays at
  `Projects/golden-fur/shared/context/Architectural-Change-History.docx` (that
  is the project-wide shared doc, normally referenced not copied), but the
  requester explicitly asked to "include it in commits in the end", so it is
  also copied here so the session record is self-contained. Origin:
  `Projects/golden-fur/shared/context/Architectural-Change-History.docx`.
- `Architectural-Change-History.txt` — plain-text extraction of the same
  document (the `.docx` is binary, ~2.8 MB with images), for quick
  diffing / grep. Generated this session from the `.docx` above (paragraphs +
  table cells). The weight-class task text is around the "Low Priority" table
  near the end.

## Referenced only (not copied)

- `golden-fur/server/.env` — the staff and customer test-login values behind
  the manual test are the m01 seed accounts; the file itself is a secrets
  file, never copied.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` — the
  exact seeded staff credential format
  (`<branch>.<roleslug>N@goldenfur.com` / `password123`, e.g.
  `makati.receptionist1@goldenfur.com`, `makati.admin1@goldenfur.com`).
- `golden-fur/supabase/.temp/project-ref` — confirms the linked Supabase
  project is the dev ref `hikgijuipymfghfuyrjv`, not prod
  `gtqncxqsofqtzrlgxdfm`, before any `supabase db push`.
