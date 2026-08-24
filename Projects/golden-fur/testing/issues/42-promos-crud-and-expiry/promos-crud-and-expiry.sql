-- Issue #42 SQL verification - deactivate_expired_promos() (AC-2 / AC-3).
-- Run each block separately in Supabase Studio SQL Editor. Everything this
-- script inserts uses fixed 8888... ids and is deleted by the final block.

-- ============================================================
-- Block 1: seed three test promos -
--   (a) expired date-bounded  -> must be deactivated by the function
--   (b) future date-bounded   -> must be left alone
--   (c) condition-based (NULL end_date) -> must NEVER be deactivated (AC-3)
-- Expected: INSERT 0 3
-- ============================================================

insert into public.promos (id, name, start_date, end_date, condition_note, discount_type, value, scope_type, branch_scope, is_active)
values
  ('88888888-8888-4888-a888-888888888801', '__expiry_test_expired',
   '2026-01-01', '2026-01-31', null, 'Percentage', 10, 'all_services', 'both', true),
  ('88888888-8888-4888-a888-888888888802', '__expiry_test_future',
   '2027-01-01', '2027-01-31', null, 'Percentage', 10, 'all_services', 'both', true),
  ('88888888-8888-4888-a888-888888888803', '__expiry_test_condition',
   null, null, 'First booking of the month', 'Flat', 50, 'all_services', 'both', true);

-- ============================================================
-- Block 2 (AC-2): run the expiry function
-- Expected: returns 1 (only the expired promo deactivated). If other real
-- expired promos exist in the DB the count may be higher - check Block 3.
-- ============================================================

select public.deactivate_expired_promos() as deactivated_count;

-- ============================================================
-- Block 3 (AC-2 / AC-3): verify per-row outcomes
-- Expected:
--   __expiry_test_expired   -> is_active = false  (AC-2)
--   __expiry_test_future    -> is_active = true
--   __expiry_test_condition -> is_active = true   (AC-3: NULL end_date exempt)
-- ============================================================

select name, end_date, is_active
from public.promos
where name like '__expiry_test%'
order by name;

-- ============================================================
-- Block 4: idempotency - a second run deactivates nothing new
-- Expected: 0.
-- ============================================================

select public.deactivate_expired_promos() as deactivated_count_second_run;

-- ============================================================
-- Block 5 (pg_cron check, informational): is the daily schedule installed?
-- Expected: one row ('deactivate-expired-promos', '5 0 * * *') if pg_cron is
-- installed in this project; an error "relation cron.job does not exist" if
-- it is not - in that case the application-level scheduler in
-- server/src/features/maintenance/jobs/promoExpiry.job.ts is the active
-- mechanism (started by app.ts outside test env).
-- ============================================================

select jobname, schedule, command from cron.job
where jobname = 'deactivate-expired-promos';

-- ============================================================
-- Block 6: cleanup - remove the three test promos
-- Expected: DELETE 3.
-- ============================================================

delete from public.promos where name like '__expiry_test%';
