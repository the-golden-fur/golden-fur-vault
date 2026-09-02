-- Boarding Checklist Kanban redesign (#48) - bundled migration for manual review/reference.
-- Source of truth is supabase/migrations/; this file mirrors that one file.

-- =============================================================================
-- 20260819135_custom_care_log_entries_missed_status.sql
-- =============================================================================
-- Adds a 4th status, 'Missed', alongside the existing Pending/In Progress/
-- Completed (migration 20260809121). Missed is a lazy, read-time transition
-- (no cron infra exists in this app, same as bookings.status='No-show') -
-- applied server-side whenever a Pending/In Progress entry's scheduled_date
-- is found to be in the past, not written directly by any client request.

alter table public.care_log_entries
  drop constraint care_log_entries_status_check,
  add constraint care_log_entries_status_check
  check (status in ('Pending', 'In Progress', 'Completed', 'Missed'));

-- =============================================================================
-- 20260819136_custom_create_activity_log_schema.sql
-- =============================================================================
-- Round 3: Hotel/Daycare activity logbook. Note: 'Backlog' (the other round-3
-- status addition) is deliberately NOT a migration - it's never persisted,
-- see careLogCompletion.service.ts's applyBacklogLabel.

create table public.activity_log (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id),
  stay_id uuid references public.stays(id) on delete cascade,
  care_log_entry_id uuid references public.care_log_entries(id) on delete cascade,
  action text not null check (action in (
    'check_in',
    'check_out',
    'task_started',
    'task_completed',
    'task_reopened',
    'task_missed'
  )),
  actor_staff_id uuid references public.staff_profiles(id),
  description text not null,
  created_at timestamptz not null default now()
);

create index activity_log_branch_created_idx
  on public.activity_log (branch_id, created_at desc);
create index activity_log_stay_id_idx on public.activity_log (stay_id);

alter table public.activity_log enable row level security;

create policy "Staff can read the activity log at their branch"
  on public.activity_log
  for select
  to authenticated
  using (
    public.current_staff_role() in (
      'Receptionist', 'Admin', 'Supervisor', 'Groomer', 'Pet Assistant'
    )
    and branch_id = (
      select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
    )
  );

create policy "Superadmins can read the activity log for every branch"
  on public.activity_log
  for select
  to authenticated
  using (public.current_staff_role() = 'Superadmin');
