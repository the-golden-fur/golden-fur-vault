-- Reference copies for session 81. Source of truth:
--   golden-fur/supabase/migrations/20260910183_m13_backfill_service_average_duration.sql (new)
--   golden-fur/supabase/migrations/20260715034_m13_seed_maintenance_data.sql (edited - duration_minutes values)
-- Do not run these from here; they are already committed in golden-fur.
-- Query 1 (manual test D-6): after confirming a 90-minute Bath booking -
--   select scheduled_start, scheduled_end,
--          extract(epoch from (scheduled_end - scheduled_start))/60 as minutes
--   from bookings order by created_at desc limit 1;
--   select duration_minutes_at_booking from booking_items
--     where booking_id = '<that booking id>';

-- ===== NEW: 20260910183_m13_backfill_service_average_duration.sql =====

-- Backfill the average service time (services.duration_minutes) for the
-- seeded Grooming and Veterinary catalog rows.
--
-- WHY THIS MIGRATION: duration_minutes was always NULL for Grooming and
-- Veterinary in the base catalog seed (20260715034) - only Hotel (1440) and
-- Daycare (60) carried a value. The "set average time of service"
-- change (Architectural-Change-History) exposes duration_minutes in Admin
-- Settings > Services for every category and lets it drive booking length +
-- package duration, so the seeded services need sensible starting values.
--
-- 20260715034 now seeds these values directly, but it is idempotent
-- (ON CONFLICT (id) DO NOTHING) and will NOT re-apply on a provisioned
-- database kept current with `supabase db push` - the rows are already
-- there with duration_minutes = NULL. This migration sets them.
--
-- Guarded on `duration_minutes IS NULL` so a value an admin has already
-- tuned by hand is never overwritten. Values match 20260715034; they are
-- first-draft estimates and stay admin-editable.
--
-- Harmless no-op on a fresh `supabase db reset`: the rows either don't
-- exist yet or already carry the seeded value, so the WHERE matches nothing.

update public.services as s
set duration_minutes = v.duration_minutes,
    updated_at = now()
from (
  values
    ('a1300000-0000-4000-a000-000000000001'::uuid, 45),  -- Bath
    ('a1300000-0000-4000-a000-000000000002'::uuid, 30),  -- Blow-dry
    ('a1300000-0000-4000-a000-000000000003'::uuid, 20),  -- Brushing
    ('a1300000-0000-4000-a000-000000000004'::uuid, 15),  -- Nail Trim
    ('a1300000-0000-4000-a000-000000000005'::uuid, 15),  -- Teeth Brushing
    ('a1300000-0000-4000-a000-000000000006'::uuid, 15),  -- Ear Cleaning
    ('a1300000-0000-4000-a000-000000000007'::uuid, 15),  -- Anal Drain
    ('a1300000-0000-4000-a000-000000000008'::uuid, 20),  -- Face Trim
    ('a1300000-0000-4000-a000-000000000009'::uuid, 60),  -- Dematting
    ('a1300000-0000-4000-a000-000000000010'::uuid, 20),  -- Poodle Feet
    ('a1300000-0000-4000-a000-000000000016'::uuid, 30),  -- Wellness Exam
    ('a1300000-0000-4000-a000-000000000017'::uuid, 15),  -- Vaccination
    ('a1300000-0000-4000-a000-000000000018'::uuid, 20),  -- Laboratory Test
    ('a1300000-0000-4000-a000-000000000019'::uuid, 60),  -- Dental Cleaning
    ('a1300000-0000-4000-a000-000000000020'::uuid, 120), -- Surgery
    ('a1300000-0000-4000-a000-000000000021'::uuid, 45)   -- Emergency Consultation
) as v(id, duration_minutes)
where s.id = v.id
  and s.duration_minutes is null;
