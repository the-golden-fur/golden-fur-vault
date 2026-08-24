-- Custom Request Verification SQL: Reset Supabase Seed Data
-- Run in Supabase Studio (local: http://127.0.0.1:54323) -> SQL Editor,
-- after `npx supabase db reset`.

-- ============================================================
-- 1. Confirm branches seeded correctly (no break_window column)
-- ============================================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'branches'
  AND column_name = 'break_window';
-- Expected: 0 rows (column no longer exists)

SELECT name, is_vet_branch, timezone
FROM public.branches
ORDER BY name;
-- Expected: 2 rows — Makati (is_vet_branch = true), Southwoods (false)

-- ============================================================
-- 2. Confirm staff seeded: 32 rows (2 branches x 8 roles x 2 each)
-- ============================================================

SELECT COUNT(*) AS total_staff FROM public.staff_profiles;
-- Expected: 32

SELECT role, COUNT(*) AS per_role
FROM public.staff_profiles
GROUP BY role
ORDER BY role;
-- Expected: 4 rows per role (2 per branch x 2 branches), 8 roles total

SELECT b.name AS branch, COUNT(*) AS per_branch
FROM public.staff_profiles sp
JOIN public.branches b ON b.id = sp.branch_id
GROUP BY b.name
ORDER BY b.name;
-- Expected: Makati = 16, Southwoods = 16

-- Spot-check the naming convention on one known account
SELECT username, registered_email, role, display_name
FROM public.staff_profiles
WHERE registered_email = 'makati.admin2@goldenfur.com';
-- Expected: 1 row — username 'makati.admin2', role 'Admin',
-- display_name 'Makati Admin 2'

-- ============================================================
-- 3. Confirm customers seeded: 5 rows
-- ============================================================

SELECT COUNT(*) AS total_customers FROM public.customer_profiles;
-- Expected: 5

SELECT account_email, full_name
FROM public.customer_profiles
ORDER BY account_email;
-- Expected: customer1@goldenfur.com .. customer5@goldenfur.com

-- ============================================================
-- 4. Confirm every seeded auth.users row has a usable password
-- ============================================================

SELECT email, (encrypted_password IS NOT NULL) AS has_password
FROM auth.users
WHERE email LIKE '%@goldenfur.com'
  AND encrypted_password IS NULL;
-- Expected: 0 rows (every seeded account has a hashed password)

SELECT COUNT(*) AS goldenfur_auth_users
FROM auth.users
WHERE email LIKE '%@goldenfur.com';
-- Expected: 37 (32 staff + 5 customers)

-- ============================================================
-- 5. Confirm no leftover dropped columns on staff_profiles
-- ============================================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'staff_profiles'
  AND column_name IN ('is_busy', 'busy_until');
-- Expected: 0 rows

-- ============================================================
-- 6. Confirm the GoTrue token columns aren't NULL (this was the
-- bug that made every seeded login 500 with "Database error
-- querying schema" even though the rows looked fine otherwise —
-- GoTrue's Go driver can't scan NULL into these string fields)
-- ============================================================

SELECT email
FROM auth.users
WHERE email LIKE '%@goldenfur.com'
  AND (
    confirmation_token IS NULL
    OR recovery_token IS NULL
    OR email_change_token_new IS NULL
    OR email_change IS NULL
  );
-- Expected: 0 rows

-- ============================================================
-- 7. Confirm every seeded auth.users row has a matching identity
-- with provider_id set (also required by GoTrue, NOT NULL)
-- ============================================================

SELECT u.email
FROM auth.users u
LEFT JOIN auth.identities i ON i.user_id = u.id
WHERE u.email LIKE '%@goldenfur.com'
  AND (i.id IS NULL OR i.provider_id IS NULL);
-- Expected: 0 rows
