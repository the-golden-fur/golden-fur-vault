# Context — 112-add-form-modals-and-pet-type-cleanup

## Copied into ./context/

- None — the only written context used was the shared
  Architectural-Change-History log, which stays canonical (see below). The
  Service-Types "generate key server-side" precedent this session copied
  is existing repo source (`server/src/features/maintenance/services/serviceTypes.service.ts`),
  not a vault context file.

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx` —
  "In Progress" section, owned by Alarie: the eight bullet points quoted
  verbatim in `testing/testing.md`'s "The request, verbatim" (Add pet type
  as a modal, simplify labels, remove the Key field, add Configure, Add
  Cage/Add Breed as modals, remove Notifications/Credits from the sidebar).
  Project-wide reference material, not session-specific — referenced in
  place rather than copied. The doc's own "Merged" section immediately
  below this one (owned by Matthew) is session 111's work, not this
  session's — see the scope note in `testing/testing.md`.
- `golden-fur/server/src/features/maintenance/services/serviceTypes.service.ts`
  and its `.spec.ts` — the existing "generate `key` via `randomUUID()`,
  never client-supplied" precedent this session's Pet Types change copies
  exactly; ordinary source code, not a vault context file, so referenced by
  path rather than copied here.
