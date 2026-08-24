-- Issue #33 Verification SQL
-- Confirms the first-ever schema/RLS for pet_vaccination_records and
-- pet_medical_notes (migrations 20260712026-030), plus the new
-- medical_note_category enum.
--
-- Note: the Supabase SQL Editor runs as the postgres role and bypasses RLS
-- entirely - this script confirms schema/policy definitions only. The
-- Postman collection in this folder exercises actual RLS-gated behavior
-- through the API (server uses the service-role client; the application-
-- layer role checks in vaccinationRecord.service.ts / medicalNote.service.ts
-- are the primary enforcement layer, these policies are defense-in-depth).

-- ============================================================
-- 1. pet_vaccination_records shape and policies
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'pet_vaccination_records'
order by ordinal_position;
-- Expected: id, pet_id, vaccine_name, date_administered NOT NULL;
-- next_due_date, administered_by, notes NULLABLE; created_at defaulted.

select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'pet_vaccination_records'
order by cmd, policyname;
-- Expected: 2 rows -
--   ALL    "Staff can manage vaccination records" (current_staff_role() in
--          ('Receptionist','Veterinarian','Admin','Supervisor','Superadmin'))
--   SELECT "Customers can view their own pets vaccination records"
--          (exists (... pets.customer_id = auth.uid()))

-- ============================================================
-- 2. medical_note_category enum
-- ============================================================

select typname, enumlabel
from pg_enum
join pg_type on pg_type.oid = pg_enum.enumtypid
where typname = 'medical_note_category'
order by enumsortorder;
-- Expected: Medical Note, Allergy, Behavioral Flag

-- ============================================================
-- 3. pet_medical_notes shape and policies
-- ============================================================

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'pet_medical_notes'
order by ordinal_position;
-- Expected: id, pet_id, note_text, category, staff_id NOT NULL; created_at
-- NOT NULL default now().

select cmd, count(*) as policy_count
from pg_policies
where tablename = 'pet_medical_notes'
group by cmd
order by cmd;
-- Expected: INSERT 1, SELECT 2. No UPDATE or DELETE policy exists at all -
-- AC-6's append-only design is enforced here AND at the router level
-- (pet.routes.ts defines no PATCH/DELETE route for
-- /pets/:id/medical-notes/:noteId).

select policyname, cmd
from pg_policies
where tablename = 'pet_medical_notes'
  and cmd in ('UPDATE', 'DELETE');
-- Expected: 0 rows.
