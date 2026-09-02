-- Bundled for reference only - source of truth is supabase/migrations/.
-- Adds services.captures_pet_assessment (per-service toggle: does Starting
-- a booking on this service open the pet-assessment modal?) and enables it
-- on the two seeded services this was built for.
--
-- Second statement must run in its own migration/transaction from the
-- first only in the sense that it depends on the column existing - unlike
-- an enum ADD VALUE, a plain ALTER TABLE ADD COLUMN has no same-transaction
-- restriction, so both are safe to paste together here.

alter table public.services
  add column captures_pet_assessment boolean not null default false;

update public.services
set captures_pet_assessment = true
where id in (
  'a1300000-0000-4000-a000-000000000022', -- Initial Assessment
  'a1300000-0000-4000-a000-000000000023'  -- Reassessment
);
