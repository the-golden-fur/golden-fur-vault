-- Reference copy — source of truth is
-- golden-fur/supabase/migrations/20260904171_custom_seed_assessment_service_type.sql
-- Applied to the linked Supabase project (confirmed via `npm run supabase:status`).

-- Seeds an 'Assessment' row into service_types, which never had one - the
-- original creation migration (20260809113) deliberately excluded it,
-- since it's not a top-level category a customer picks the way Grooming/
-- Hotel/Daycare/Veterinary are (it's auto-triggered for an unassessed pet,
-- see CustomerBookingFlowPage.tsx's availableCategories). Adding it now
-- makes it visible/configurable in Admin Settings > Service Types, at the
-- client's explicit request, matching the other 4 rows' shape.
--
-- staff_picker_enabled/cage_picker_enabled/eligible_staff_roles all stay at
-- their inactive defaults - Assessment bookings (Initial Assessment,
-- Reassessment - see 20260802074/20260802076) have never involved staff
-- assignment or a cage, and resolveStaffAssignment (booking.service.ts) now
-- resolves eligibility purely from this row's staff_picker_enabled flag for
-- every category (custom change, same session as 20260904168-170) - leaving
-- it false here preserves that existing "no staff resource" behavior
-- exactly, rather than accidentally turning on staff assignment for a
-- category that was never designed for it.
--
-- is_active stays true (the column's default) - CustomerBookingFlowPage.tsx
-- already treats a category absent from service_types as active
-- (`serviceTypeByKey.get(candidate)?.is_active ?? true`), so this row's
-- presence must keep matching that default, not accidentally hide the
-- Assessment tab an already-assessed pet needs to book a Reassessment
-- (Reassessment is intentionally NOT assessment-exempt - see 20260802076 -
-- so an assessed customer reaches it through this same 'Assessment' tab).
--
-- Branch availability mirrors 20260818133's cross-join seeding convention -
-- available at every existing branch, same "opt-out not opt-in" default.

insert into public.service_types (key, name) values ('Assessment', 'Assessment')
on conflict (key) do nothing;

insert into public.service_type_branch_availability (service_type_id, branch_id, is_available)
select st.id, b.id, true
from public.service_types st
cross join public.branches b
where st.key = 'Assessment'
on conflict (service_type_id, branch_id) do nothing;
