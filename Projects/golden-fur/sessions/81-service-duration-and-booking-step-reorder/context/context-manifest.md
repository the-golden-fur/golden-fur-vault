# Context — 81-service-duration-and-booking-step-reorder

## Copied into ./context/

- `Architectural-Change-History.docx` — the running backlog of architectural
  change requests. This session implements the row owned by Matthew, status
  "In Progress" (the three-part "average time of service / date-time picker /
  rearrange booking steps" item). Origin:
  `Projects/golden-fur/shared/context/Architectural-Change-History.docx`.
  Note: the user removed the sibling `Architectural-Change-History.pdf` in the
  same change — docx is the only kept variant now.
- `Architectural-Change-History.txt` — plain-text extraction of the same
  document (the `.docx` is binary), for quick diffing / grep. Generated this
  session from the `.docx` above.

## Referenced only (not copied)

- `golden-fur/server/.env` — the staff and customer test-login values used in
  the manual test steps come from here; a secrets file, never copied.
- `golden-fur/supabase/.temp/project-ref` — confirms the linked Supabase
  project is `hikgijuipymfghfuyrjv` (dev), not prod
  `gtqncxqsofqtzrlgxdfm`, before any `supabase db push`.
