-- Issue #27 Verification SQL
-- Sanity-checks the prerequisite schema this issue added
-- (migration 20260711019_m01_staff_unavailability_blocks_add_status.sql —
-- the status/is_quick_action/reviewed_by/reviewed_at/denial_reason columns
-- and the enforce_unavailability_block_status() trigger) since
-- staffAvailability.service.ts's core behavior (AC-1, AC-3, AC-5) depends on
-- that trigger correctly labeling rows and on `status = 'approved'`
-- correctly excluding pending/denied rows. This script does not call the
-- TypeScript service itself (there is no HTTP route for it — see the .md
-- in this folder for the unit-test-based verification path); it only
-- verifies the DB layer the service reads from.

-- Reuse an existing branch and two auth users that are not already staff
-- profiles: one becomes the target staff member, the other plays the
-- "Admin creating on-behalf-of" role for the approved-by-on-behalf-of case.
with branch_row as (
  select id
  from public.branches
  order by created_at
  limit 1
),
candidate_users as (
  select id
  from auth.users
  where id not in (select id from public.staff_profiles)
  order by created_at
  limit 2
),
new_users as (
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
    concat('issue27-user+', split_part(gen_random_uuid()::text, '-', 1), '@example.com'),
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Issue 27 Test User"}'::jsonb,
    now(),
    now()
  from generate_series(1, greatest(0, 2 - (select count(*) from candidate_users)))
  returning id
),
users_final as (
  select id, row_number() over () as rn
  from (
    select id from candidate_users
    union all
    select id from new_users
  ) u
),
inserted_staff as (
  insert into public.staff_profiles (
    id, branch_id, role, username, registered_email, display_name,
    phone_number, emergency_contact_name, emergency_contact_number,
    preferred_communication_channel, is_active, created_at, updated_at
  )
  select
    uf.id,
    br.id,
    'Receptionist'::public.staff_role,
    concat('issue27-staff-', split_part(gen_random_uuid()::text, '-', 1)),
    concat('issue27-staff+', split_part(gen_random_uuid()::text, '-', 1), '@example.com'),
    'Issue 27 Staff',
    null, null, null, null, true, now(), now()
  from users_final uf
  cross join branch_row br
  where uf.rn = 1
  on conflict (id) do nothing
  returning id
),
inserted_admin as (
  insert into public.staff_profiles (
    id, branch_id, role, username, registered_email, display_name,
    phone_number, emergency_contact_name, emergency_contact_number,
    preferred_communication_channel, is_active, created_at, updated_at
  )
  select
    uf.id,
    br.id,
    'Admin'::public.staff_role,
    concat('issue27-admin-', split_part(gen_random_uuid()::text, '-', 1)),
    concat('issue27-admin+', split_part(gen_random_uuid()::text, '-', 1), '@example.com'),
    'Issue 27 Admin',
    null, null, null, null, true, now(), now()
  from users_final uf
  cross join branch_row br
  where uf.rn = 2
  on conflict (id) do nothing
  returning id
),
-- Admin-on-behalf-of block: created_by <> staff_id -> trigger forces 'approved'.
approved_block as (
  insert into public.staff_unavailability_blocks (
    staff_id, start_time, end_time, reason, created_by
  )
  select
    s.id,
    '2026-07-13 10:00:00+08'::timestamptz,
    '2026-07-13 11:00:00+08'::timestamptz,
    'Issue #27 smoke test — approved (on-behalf-of)',
    a.id
  from inserted_staff s cross join inserted_admin a
  returning id, staff_id, status
),
-- Self, custom-range request: created_by = staff_id -> trigger forces 'pending'.
pending_block as (
  insert into public.staff_unavailability_blocks (
    staff_id, start_time, end_time, reason, created_by
  )
  select
    s.id,
    '2026-07-14 09:00:00+08'::timestamptz,
    '2026-07-14 10:00:00+08'::timestamptz,
    'Issue #27 smoke test — pending',
    s.id
  from inserted_staff s
  returning id, staff_id, status
),
-- Self request later reviewed and denied (status flipped by direct UPDATE
-- here since the review endpoint itself is Issue #29 scope, not this one).
denied_block_insert as (
  insert into public.staff_unavailability_blocks (
    staff_id, start_time, end_time, reason, created_by
  )
  select
    s.id,
    '2026-07-15 09:00:00+08'::timestamptz,
    '2026-07-15 10:00:00+08'::timestamptz,
    'Issue #27 smoke test — denied',
    s.id
  from inserted_staff s
  returning id
),
denied_block as (
  update public.staff_unavailability_blocks
  set status = 'denied', denial_reason = 'Issue #27 smoke test denial reason'
  where id = (select id from denied_block_insert)
  returning id, staff_id, status
)
select
  (select status from approved_block) as approved_block_status,
  (select status from pending_block) as pending_block_status,
  (select status from denied_block) as denied_block_status,
  -- Mirrors staffAvailability.service.ts's blocks query: only status =
  -- 'approved' rows for the day range should come back (AC-1/AC-3/AC-5).
  (
    select count(*)
    from public.staff_unavailability_blocks b
    join inserted_staff s on s.id = b.staff_id
    where b.status = 'approved'
      and b.start_time < '2026-07-16 00:00:00+08'::timestamptz
      and b.end_time > '2026-07-13 00:00:00+08'::timestamptz
  ) as approved_rows_in_range,
  (
    select count(*)
    from public.staff_unavailability_blocks b
    join inserted_staff s on s.id = b.staff_id
    where b.status in ('pending', 'denied')
      and b.start_time < '2026-07-16 00:00:00+08'::timestamptz
      and b.end_time > '2026-07-13 00:00:00+08'::timestamptz
  ) as pending_or_denied_rows_in_range;

-- Expected results:
--   approved_block_status         = 'approved'
--   pending_block_status          = 'pending'
--   denied_block_status           = 'denied'
--   approved_rows_in_range        = 1  (only the on-behalf-of block)
--   pending_or_denied_rows_in_range = 2 (the self-requested blocks)

-- Cleanup so the script can be re-run safely.
delete from public.staff_unavailability_blocks
where reason like 'Issue #27 smoke test%';

delete from public.staff_profiles
where username like 'issue27-staff-%' or username like 'issue27-admin-%';

-- Note: any auth.users row this script created (email like
-- 'issue27-user+%@example.com') is intentionally left in place —
-- the hosted SQL Editor role cannot DELETE from auth.users directly
-- (only INSERT); remove it via Dashboard > Authentication > Users
-- if you want it gone, it is otherwise harmless test data.
