# Architectural-Change-History — the two "In Progress" items this session closes

Extracted verbatim (2026-09-08) from
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`,
section **Tasks → Development → In Progress**. Kept here so this session
record stays self-contained if the backlog doc is later edited.

---

## Item 1 — bundled booking lets the same staff member be double-booked (owner: Matthew)

> Currently, the new bundled booking feature allows selection of the same
> staff (from staff picker) on the same date/time
>
> - Determine if staff assignment is 1 = 1 (e.g. 1 groomer = 1 pet only) or
>   1 = many (e.g. 1 groomer = 2 pets)
> - Sample booking chose groomer 1 for both Luna and Cooper on same date 11 AM
>
> Perhaps add a config in admin settings that will allow admins to set how
> many times a staff can be chosen by a booking customer at the same time on
> the same date

## Item 2 — Hotel step 8 "Care Instructions" fails when per-night rows are incomplete (owner: Matthew)

> Fix booking > new booking > hotel type service > step 8 care instructions:
>
> - When unchecking same instructions every night, and instructions in other
>   nights are not configured, booking fails
> - Should set the first night instructions the default for other nights (so
>   no need to set)
>
> Changing instructions for a specific night will only overwrite the
> instructions for that night
>
> - Or perhaps add a new tab that says default instructions, which will be
>   applied to all nights
> - Then apply overwrite on nights that are edited

---

## Not in the backlog doc — the third change was found while verifying

While reproducing Item 2 on the dev database, the booking flow showed
**"No Hotel services available at this branch"** for every category. Root
cause: `service_branch_availability` / `service_type_branch_availability`
were completely empty on the dev DB because the `m13-maintenance` seed only
runs on `supabase db reset`, never on `supabase db push`. Migration
`20260908180` backfills those rows. This was a data-recovery side quest, not
a planned backlog item.
