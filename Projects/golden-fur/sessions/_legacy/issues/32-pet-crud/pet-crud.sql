-- Issue #32 Verification SQL
-- Confirms pets is greenfield schema created by this issue (migrations
-- 20260712023-025): the four pet_* enums, the pets table itself, and its
-- RLS policies (customer-self manage-all + staff manage-all).
--
-- Note: the Supabase SQL Editor runs as the postgres role and bypasses RLS
-- entirely - this script confirms schema/policy definitions only. Actual
-- RLS-gated behavior is exercised through the API via the Postman
-- collection in this folder (server uses the service-role client, so the
-- application-layer role check in pet.controller.ts is the primary
-- enforcement layer; these policies are defense-in-depth).

-- ============================================================
-- 1. Confirm the four pet enums and their values
-- ============================================================

select typname, enumlabel
from pg_enum
join pg_type on pg_type.oid = pg_enum.enumtypid
where typname in ('pet_species', 'pet_gender', 'pet_weight_class', 'pet_coat_type')
order by typname, enumsortorder;
-- Expected: pet_species (Dog, Cat), pet_gender (Male, Female),
-- pet_weight_class (S, M, L, XL), pet_coat_type (SC, LC)

-- ============================================================
-- 2. Confirm the pets table shape
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'pets'
order by ordinal_position;
-- Expected columns: id, customer_id, name, species, breed, gender,
-- date_of_birth, weight_class, coat_type, health_conditions, created_at,
-- updated_at.
-- NOT NULL: customer_id, name, species, weight_class, coat_type.
-- NULLABLE: breed, gender, date_of_birth, health_conditions.

-- ============================================================
-- 3. Confirm pets RLS policies
-- ============================================================

select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'pets'
order by cmd, policyname;
-- Expected: 5 rows - one customer-self policy per SELECT/INSERT/UPDATE/
-- DELETE (auth.uid() = customer_id), plus one staff "manage all" policy
-- (FOR ALL, current_staff_role() in ('Receptionist','Admin','Supervisor',
-- 'Superadmin')).

select cmd, count(*) as policy_count
from pg_policies
where tablename = 'pets'
group by cmd
order by cmd;
-- Expected: DELETE 2, INSERT 2, SELECT 2, UPDATE 2 (customer-self policy +
-- staff "manage all" FOR ALL policy applies to every command).
