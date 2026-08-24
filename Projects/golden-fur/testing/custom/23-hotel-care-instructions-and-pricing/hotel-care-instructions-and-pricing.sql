-- Hotel care instructions & pricing follow-up (#23) - bundled migration for manual review/reference.
-- Source of truth is supabase/migrations/; this file mirrors that one file.

-- =============================================================================
-- 20260804089_m05_add_noon_meal_time.sql
-- =============================================================================
-- Care Instructions revision: feeding becomes a free add/remove list (like
-- walking/playing/medication already are) instead of three fixed
-- Morning/Afternoon/Evening checkboxes, and gains a "Noon" time-of-day
-- option on that list. Scoped to care_feeding_instructions.meal_time only -
-- care_walking_instructions/care_playing_instructions.time_block stay
-- Morning/Afternoon/Evening (walk/play scheduling wasn't asked to change).

alter table public.care_feeding_instructions
  drop constraint care_feeding_instructions_meal_time_check,
  add constraint care_feeding_instructions_meal_time_check
  check (meal_time in ('Morning', 'Noon', 'Afternoon', 'Evening'));
