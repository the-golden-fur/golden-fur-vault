-- Fix MFA verification helper.
-- Confirms the enroll-cleanup fix (no orphaned unverified TOTP factors), the
-- unenroll action actually removes rows, and inspects the staff_role enum
-- used by the mandatory-MFA popup gate.
-- Run as the project owner in the Supabase SQL Editor - it queries the
-- built-in `auth` schema, which requires elevated (service-role/owner)
-- access and is not reachable through the anon/authenticated API roles.

-- 1. All TOTP factors for a given test user, oldest first.
-- Replace '<user-id>' with the auth.users.id of the account you tested
-- enroll/verify against (Table Editor > staff_profiles or customer_profiles,
-- the row's `id` column is the same as auth.users.id).
select
  id,
  friendly_name,
  factor_type,
  status,
  created_at,
  updated_at
from auth.mfa_factors
where user_id = '<user-id>'
order by created_at asc;

-- Expected after the enroll-cleanup fix:
-- At most ONE row with status = 'unverified' at any time (repeated Enroll
-- calls unenroll the previous unverified factor before creating a new one,
-- and the enroll retry-on-conflict path cleans up again if two enroll calls
-- ever race each other, e.g. React StrictMode's double-invoked mount effect).

-- 2. Count factors per status for that same user - a quick way to confirm
-- there is no pile-up of stale unverified factors after several Postman or
-- browser Enroll re-runs against the same account.
select
  status,
  count(*) as factor_count
from auth.mfa_factors
where user_id = '<user-id>'
group by status;

-- Expected: unverified count is 0 or 1, never more.

-- 3. After running the Unenroll (Disable MFA) request/button for this user,
-- re-run query 1. Expected: zero rows at all - unenroll removes every TOTP
-- factor for the caller, not just unverified ones (Supabase itself will have
-- rejected removing a verified factor here if the caller's session wasn't
-- aal2 - check the Postman/browser response body for a "failed" entry if a
-- row unexpectedly still shows status = 'verified').

-- 4. staff_role enum values, for reference when picking a test account for
-- the mandatory-popup roles (Admin, Superadmin) vs. the optional-settings
-- roles (everyone else).
select
  enumlabel as role
from pg_enum
where enumtypid = 'public.staff_role'::regtype
order by enumsortorder;

-- Expected: Superadmin, Admin, Supervisor, Receptionist, Groomer,
-- Veterinarian, Cashier, Pet Assistant.
