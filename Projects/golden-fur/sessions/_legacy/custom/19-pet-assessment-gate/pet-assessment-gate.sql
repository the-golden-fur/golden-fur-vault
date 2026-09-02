-- Pet Assessment Gate - Verification SQL
-- Confirms the schema changes from ...073_m02_pets_assessment_lock.sql,
-- ...074_m13_services_requires_assessed_pet.sql,
-- ...075_m02_pets_assessment_trigger_fix.sql, and
-- ...076_m13_seed_reassessment_service.sql landed correctly: pets.
-- weight_class/coat_type are nullable, the assessed_by/assessed_at columns
-- and role-gating trigger exist (in its FIXED form), services.
-- requires_assessed_pet is in place with the seeded Initial Assessment and
-- Reassessment rows, and the pet seed data has the expected 13-row,
-- assessed/unassessed mix.
--
-- Note on section 7: the SQL Editor runs as the postgres role, which has no
-- auth.uid() (same as the app's real service-role write path) - so a plain
-- UPDATE there is now trusted, NOT rejected (that's the ...075 fix - before
-- it, this would have incorrectly failed too, blocking every legitimate
-- staff write). Section 7 also shows the case that's still correctly
-- rejected: a real authenticated non-staff (customer) session, simulated by
-- setting request.jwt.claims.

-- ============================================================
-- 1. Confirm pets.weight_class/coat_type are nullable, and the new
-- assessed_by/assessed_at columns exist
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'pets'
  and column_name in ('weight_class', 'coat_type', 'assessed_by', 'assessed_at')
order by column_name;
-- Expected: weight_class/coat_type both is_nullable = YES;
-- assessed_by (uuid, YES), assessed_at (timestamptz, YES).

-- ============================================================
-- 2. Confirm the enforce_pet_assessment_writes trigger exists and is wired
-- to BEFORE INSERT OR UPDATE on pets
-- ============================================================

select tgname, tgtype, tgenabled
from pg_trigger
where tgrelid = 'public.pets'::regclass
  and tgname = 'trg_enforce_pet_assessment_writes';
-- Expected: one row, tgenabled = 'O' (enabled).

select routine_name, security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'enforce_pet_assessment_writes';
-- Expected: one row, security_type = DEFINER.

-- ============================================================
-- 3. Confirm services.requires_assessed_pet exists, defaults true
-- ============================================================

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'services'
  and column_name = 'requires_assessed_pet';
-- Expected: boolean, is_nullable = NO, column_default = true.

-- ============================================================
-- 4. Confirm the seeded "Initial Assessment" service
-- ============================================================

select id, category, name, base_price, requires_assessed_pet, is_active
from public.services
where id = 'a1300000-0000-4000-a000-000000000022';
-- Expected: one row, category = 'Grooming', name = 'Initial Assessment',
-- requires_assessed_pet = false, is_active = true.
-- (base_price is a placeholder 0.00 - confirm with the client/Admin what
-- the real fee should be, then update it via the Services admin page.)

-- ============================================================
-- 5. Confirm the seeded "Reassessment" service
-- ============================================================

select id, category, name, base_price, requires_assessed_pet, is_active
from public.services
where id = 'a1300000-0000-4000-a000-000000000023';
-- Expected: one row, category = 'Grooming', name = 'Reassessment',
-- requires_assessed_pet = TRUE (opposite of Initial Assessment - this is
-- for an already-assessed pet, not a substitute entry point for a new one),
-- is_active = true.

-- ============================================================
-- 6. Confirm the pet seed data: 13 pets, each customer has both an
-- assessed and an unassessed pet
-- ============================================================

select count(*) as total_pets from public.pets;
-- Expected: 13 (only meaningful right after a fresh `supabase db reset` -
-- skip if your local data has since diverged).

select
  cp.account_email,
  count(*) filter (where p.weight_class is not null) as assessed_count,
  count(*) filter (where p.weight_class is null) as unassessed_count
from public.pets p
join public.customer_profiles cp on cp.id = p.customer_id
where cp.account_email like 'customer%@goldenfur.com'
group by cp.account_email
order by cp.account_email;
-- Expected: 5 rows (customer1..customer5), each with assessed_count >= 1
-- AND unassessed_count >= 1.

select id, name, weight_class, assessed_by, assessed_at
from public.pets
where weight_class is not null
limit 5;
-- Expected: every row here has assessed_by/assessed_at both populated (not
-- null) - confirms the seed script's own explicit stamping (not the
-- trigger - see the header above) worked.

-- ============================================================
-- 7. Demonstrate the FIXED trigger: still rejects a real non-staff
-- session, no longer rejects the service-role/postgres session (the app's
-- actual write path)
-- ============================================================

-- Pick any existing pet id from your local data first:
-- select id from public.pets limit 1;

-- (a) Service-role / postgres session (no auth.uid()) - this is what was
-- previously broken. Replace <pet-id>:
-- update public.pets set weight_class = 'M', coat_type = 'SC' where id = '<pet-id>';
-- Expected: SUCCESS (0 or more rows updated, no error) - this is the fix.

-- (b) A real authenticated non-staff (customer) session - still correctly
-- rejected. Replace <pet-id> and <a-real-customer-id> (any row from
-- `select id from public.customer_profiles limit 1;`):
--
-- select set_config(
--   'request.jwt.claims',
--   json_build_object('sub', '<a-real-customer-id>', 'role', 'authenticated')::text,
--   true
-- );
-- set local role authenticated;
-- update public.pets set weight_class = 'M' where id = '<pet-id>';
-- reset role;
--
-- Expected: ERROR - "weight_class and coat_type may only be changed by
-- staff (Receptionist/Admin/Supervisor/Superadmin)"
