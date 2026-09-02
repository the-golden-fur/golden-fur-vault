-- Issue #31 Verification SQL
-- Confirms the staff-facing RLS policies added to customer_profiles by
-- migration 20260712022_m02_customer_profiles_staff_rls.sql. The existing
-- customer-self SELECT/UPDATE policies (...009) are unaffected and not
-- re-verified here.
--
-- Note: the Supabase SQL Editor runs as the postgres role and bypasses RLS
-- entirely, so this script confirms policy definitions but does not
-- exercise them as a signed-in user - that's what the Postman collection in
-- this folder does through the actual API (the server itself uses the
-- service-role client and enforces the same role check at the application
-- layer in customer.controller.ts's isAuthorizedStaff, so RLS here is
-- defense-in-depth, not the primary enforcement layer).

-- ============================================================
-- 1. Confirm all customer_profiles policies (existing + new)
-- ============================================================

select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'customer_profiles'
order by cmd, policyname;
-- Expected: 5 rows total -
--   SELECT "Customers can view their own profile."   (auth.uid() = id)
--   SELECT "Staff can read customer profiles"          (current_staff_role() in (...))
--   INSERT "Staff can insert customer profiles"        (current_staff_role() in (...))
--   UPDATE "Customers can update their own profile."   (auth.uid() = id)
--   UPDATE "Staff can update customer profiles"        (current_staff_role() in (...))

-- ============================================================
-- 2. Policy count sanity check
-- ============================================================

select cmd, count(*) as policy_count
from pg_policies
where tablename = 'customer_profiles'
group by cmd
order by cmd;
-- Expected: INSERT 1, SELECT 2, UPDATE 2 - no DELETE policy exists on this
-- table at all; customer_profiles rows are never deleted by any Epic C
-- issue.

-- ============================================================
-- 3. Confirm the staff policies use the correct role list
-- ============================================================

select policyname, qual
from pg_policies
where tablename = 'customer_profiles'
  and policyname like 'Staff can%';
-- Expected: qual/with_check text contains
-- "current_staff_role() = ANY (ARRAY['Receptionist'::staff_role,
-- 'Admin'::staff_role, 'Supervisor'::staff_role, 'Superadmin'::staff_role])"
-- (Groomer/Veterinarian/Cashier/Pet Assistant are NOT in this list).
