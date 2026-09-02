-- Issue #44 SQL verification - run each block separately in Supabase Studio
-- SQL Editor after migrations AND seeds have been applied (on a linked
-- remote: `npm run supabase:push` was enough for the migration, but the
-- branch-dependent rows also need branches to exist - see the .md).

-- ============================================================
-- Block 1 (AC-1): service counts per category
-- Expected: Grooming 10, Daycare 1, Hotel 4, Veterinary 6 (21 total).
-- ============================================================

select category, count(*) as services
from public.services
where id::text like 'a1300000-%'
group by category
order by category;

-- ============================================================
-- Block 2 (AC-1): every Grooming service carries the full 4x2 tier matrix
-- Expected: 10 rows, each with tier_count = 8.
-- ============================================================

select s.name, count(t.id) as tier_count
from public.services s
left join public.service_pricing_tiers t on t.service_id = s.id
where s.category = 'Grooming' and s.id::text like 'a1300000-%'
group by s.name
order by s.name;

-- ============================================================
-- Block 3 (AC-1): every seeded service is available at both branches
-- Expected: 21 rows, each with branch_count = 2 and all_available = true.
-- (Zero rows here means the branch-dependent seed hasn't run - see the .md,
-- section "Fresh reset vs. linked database".)
-- ============================================================

select s.name,
       count(a.branch_id) as branch_count,
       bool_and(a.is_available) as all_available
from public.services s
left join public.service_branch_availability a on a.service_id = s.id
where s.id::text like 'a1300000-%'
group by s.name
order by s.name;

-- ============================================================
-- Block 4 (AC-2): Golden Package - one row per branch, three services each
-- Expected: 2 rows (one per branch), each service_count = 3 and the
-- included list = Bath, Blow-dry, Brushing; bundled_price 600.
-- ============================================================

select b.name as branch,
       p.bundled_price,
       count(ps.service_id) as service_count,
       array_agg(s.name order by s.name) as included_services
from public.packages p
join public.branches b on b.id = p.branch_id
left join public.package_services ps on ps.package_id = p.id
left join public.services s on s.id = ps.service_id
where p.name = 'Golden Package'
group by b.name, p.bundled_price
order by b.name;

-- ============================================================
-- Block 5 (AC-3): mandated discounts - 2 types x 2 branches x 4 categories
-- Expected: 4 rows (one per name x branch), each category_count = 4,
-- all_inactive = true, every value = 20, is_mandated = true.
-- ============================================================

select d.name,
       b.name as branch,
       count(*) as category_count,
       bool_and(not d.is_active) as all_inactive,
       bool_and(d.is_mandated) as all_mandated,
       min(d.value) as value
from public.discounts d
join public.branches b on b.id = d.branch_id
where d.is_mandated = true
group by d.name, b.name
order by d.name, b.name;

-- ============================================================
-- Block 6: promos deliberately NOT seeded
-- Expected: 0 (ignoring anything you created via Postman - filter is on
-- the seed's naming; a fresh DB shows plain 0).
-- ============================================================

select count(*) as seeded_promos from public.promos
where name like '__seed%';

-- ============================================================
-- Block 7 (AC-4): idempotency - re-paste and re-run the full contents of
-- supabase/seeds/module-3-maintenance/module-3-maintenance.seed.sql here
-- (or run `npm run seed:module-3` in a terminal instead), then run the
-- count query below. Expected: no error, and the same totals as before
-- (42 availability rows, 16 mandated discount rows) - nothing duplicated.
-- ============================================================

select
  (select count(*) from public.service_branch_availability
    where service_id::text like 'a1300000-%') as availability_rows,
  (select count(*) from public.discounts where is_mandated) as mandated_discount_rows;
