-- Issue #12 Verification SQL Queries
-- Verifies public.get_staff_availability() uses operating hours and unavailability blocks.

-- Reuse an existing branch and auth user that is not already a staff profile.
with branch_row as (
  select id
  from public.branches
  order by created_at
  limit 1
),
staff_user as (
  select id
  from auth.users
  where id not in (select id from public.staff_profiles)
  order by created_at
  limit 1
),
new_staff_user as (
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  select
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    concat('issue12-staff+', split_part(gen_random_uuid()::text, '-', 1), '@example.com'),
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Issue 12 Staff"}'::jsonb,
    now(),
    now()
  where not exists (select 1 from staff_user)
  returning id
),
staff_user_final as (
  select id from staff_user
  union all
  select id from new_staff_user
),
inserted_staff as (
  insert into public.staff_profiles (
    id,
    branch_id,
    role,
    username,
    registered_email,
    display_name,
    phone_number,
    emergency_contact_name,
    emergency_contact_number,
    preferred_communication_channel,
    is_active,
    created_at,
    updated_at
  )
  select
    su.id,
    br.id,
    'Receptionist'::public.staff_role,
    concat('issue12-staff-', split_part(gen_random_uuid()::text, '-', 1)),
    concat('issue12-staff+', split_part(gen_random_uuid()::text, '-', 1), '@example.com'),
    'Issue 12 Staff',
    null,
    null,
    null,
    null,
    true,
    now(),
    now()
  from staff_user_final su
  cross join branch_row br
  on conflict (id) do nothing
  returning id
),
availability_tests as (
  insert into public.staff_unavailability_blocks (
    staff_id,
    start_time,
    end_time,
    reason,
    created_by,
    created_at
  )
  select
    ins.id,
    '2026-07-06 10:30:00+08'::timestamptz,
    '2026-07-06 11:30:00+08'::timestamptz,
    'Issue #12 smoke test',
    (select id from auth.users order by created_at limit 1),
    now()
  from inserted_staff ins
  returning staff_id
)
select
  public.get_staff_availability(test.staff_id, '2026-07-06 10:00:00+08'::timestamptz, '2026-07-06 11:00:00+08'::timestamptz) as in_hours_available,
  public.get_staff_availability(test.staff_id, '2026-07-06 07:00:00+08'::timestamptz, '2026-07-06 08:00:00+08'::timestamptz) as outside_hours_unavailable,
  public.get_staff_availability(test.staff_id, '2026-07-06 10:30:00+08'::timestamptz, '2026-07-06 11:00:00+08'::timestamptz) as unavailability_overlap_unavailable
from availability_tests test;

-- Cleanup so the script can be re-run safely.
-- Each statement above ends the scope of its CTEs, so cleanup here
-- matches on the literal markers this script used when inserting,
-- rather than referencing a CTE that no longer exists by this point.
delete from public.staff_unavailability_blocks
where reason = 'Issue #12 smoke test';

delete from public.staff_profiles
where username like 'issue12-staff-%';

-- Note: any auth.users row this script created (email like
-- 'issue12-staff+%@example.com') is intentionally left in place —
-- the hosted SQL Editor role cannot DELETE from auth.users directly
-- (only INSERT); remove it via Dashboard > Authentication > Users
-- if you want it gone, it is otherwise harmless test data.
