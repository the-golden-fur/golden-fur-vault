# Context — 117-vet-prescription-and-consultation-form-builder

## Copied into ./context/

- (none — the source material is a project-wide canonical doc, referenced below rather than copied)

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.pdf` (pages ~158-177 of the plain-text extraction) — the three "As a vet staff / As a customer / As a developer" bullets this plan implements, plus the surrounding "As a developer, I want misc sales moved..." and "As a vet staff, I don't want access to the bookings queue..." entries used for stylistic/architectural context. Project-wide, stays canonical there per the session-documentation skill.
- User's mid-planning corrections (chat only, not a file): Hotel check-in's medication auto-fill should conceptually source from a customer's own registered food/medicine items, not vet data — deferred, not part of this plan; and a separate future roadmap item (receptionist/groomer play-and-walk-time-only config, staff-booking notifications, read-only feeding/medical instructions at hotel/daycare check-in) — also deferred, recorded in `plan.md`'s "What we're deliberately not touching" section.
- User's post-implementation review corrections (chat only, not a file, after seeing the running app): "break down my catalog > medications, have medications AND prescriptions..."; "turn this [the consultation detail panel] into a default form in my catalog > forms...", answered "move them into form_responses" when asked how vitals/diagnosis should be represented; "add a ... button for list/table view, rmb/hold tap for board/gallery view in consultation queue"; "remove consultation results, should just be an option in consultation queue > row options > results". Recorded in `plan.md`'s "Note: the design evolved after you reviewed the running app" section and `testing/testing.md`'s "Scope note 2".
