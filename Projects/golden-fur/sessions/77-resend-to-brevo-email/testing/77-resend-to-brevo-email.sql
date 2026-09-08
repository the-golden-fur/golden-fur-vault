-- Reference copy — source of truth:
--   supabase/migrations/20260908181_custom_policy_configurations_email_behavior.sql
--   supabase/migrations/20260908182_m05_create_care_log_daily_reports.sql
-- Do not run this file directly; it is a session-record snapshot of the two
-- migrations committed on branch feat/resend-to-brevo-email.

-- ============================================================
-- 20260908181_custom_policy_configurations_email_behavior.sql
-- ============================================================
-- Admin-configurable transactional-email behaviour (Brevo quota controls).
--
-- WHY: the Brevo free plan caps sends at 300/day. Two flows were the biggest
-- avoidable drains:
--   1. Multi-booking checkout sent one "booking confirmed" email per pet in
--      the cart. Default is now ONE combined email per checkout; an admin can
--      switch back to one-per-booking.
--   2. The hotel care-log emailed the customer on every single completed task
--      (feeding / walk / meds - many per pet per day). Per-task email is now
--      OFF by default; instead a single nightly summary per stay is ON by
--      default (see care_log_daily_reports, next migration).
--
-- Follows the policy_configurations column pattern (20260908178
-- max_concurrent_bookings_per_staff, 20260902166 booking_notice_period): NOT
-- NULL columns with a documented default, seeded onto every existing row
-- (default + per-branch overrides) by the default itself. policy_configurations
-- is migration-seeded only - no supabase/seeds/** file.

alter table public.policy_configurations
  add column booking_group_email_mode text not null default 'combined'
    check (booking_group_email_mode in ('combined', 'per_booking')),
  add column care_log_task_email_enabled boolean not null default false,
  add column care_log_daily_report_enabled boolean not null default true;

comment on column public.policy_configurations.booking_group_email_mode is
  'Multi-booking checkout confirmation email: ''combined'' = one email listing every booking in the cart (default); ''per_booking'' = one email per booking. In-app notification rows are always one per booking regardless.';

comment on column public.policy_configurations.care_log_task_email_enabled is
  'When true, email the customer as each hotel care-log task is completed. Default false (in-app notification still fires) - the nightly summary covers the customer instead.';

comment on column public.policy_configurations.care_log_daily_report_enabled is
  'When true (default), send the customer one nightly summary email per active hotel stay listing that day''s completed / missed / still-open care tasks.';

-- ============================================================
-- 20260908182_m05_create_care_log_daily_reports.sql
-- ============================================================
-- M05: nightly care-summary send ledger.
--
-- WHY: care_log_daily_report_enabled (previous migration) turns on one
-- customer email per active hotel stay per night, summarising that day's care
-- tasks. careLogDailyReport.job.ts polls hourly from 21:00 onward; this table
-- is the once-per-(stay, date) claim so a stay is never emailed twice for the
-- same day, whether from a later poll tick that same evening or a server
-- restart. Same single-writer pattern as bookings.reminder_sent_at - the job
-- does `upsert ... ignoreDuplicates` and only sends if it wins the row.
--
-- Runtime-only table (no supabase/seeds/** entry) - rows are written solely by
-- the job's service-role client.

create table public.care_log_daily_reports (
  stay_id uuid not null references public.stays(id) on delete cascade,
  report_date date not null,
  sent_at timestamptz not null default now(),
  primary key (stay_id, report_date)
);

comment on table public.care_log_daily_reports is
  'One row per (hotel stay, calendar date) for which the nightly care-summary email was sent. Claim ledger for careLogDailyReport.job.ts - prevents duplicate sends against the Brevo daily quota.';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- No authenticated-role policy at all: this table is written and read only by
-- the job's service-role client (which bypasses RLS), never surfaced to staff
-- or customers. Enabling RLS with no policy = deny-all for authenticated
-- callers, matching the "service-role only" intent.

alter table public.care_log_daily_reports enable row level security;
