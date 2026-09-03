-- Custom change (#64) - migration for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260903167_custom_rename_misc_service_category_to_assessment.sql
--
-- Request, verbatim (part 2 of the bundled change - see the .md for part 1,
-- the new Assessment Queue page):
-- - Rename the "Misc" service category to "Assessment" everywhere - the
--   category was always specifically the pre-booking pet assessment step
--   (Initial Assessment/Reassessment), never truly miscellaneous, and the
--   name was confusing staff.
--
-- Context: public.service_category is a single Postgres enum shared by both
-- services.category and discounts.scope_category (see
-- 20260715033_m12_create_discounts_schema.sql), so one RENAME VALUE covers
-- both columns. Unlike ADD VALUE, RENAME VALUE has no same-transaction
-- restriction and preserves every existing row's underlying value identity
-- (existing 'Misc' rows read back as 'Assessment' with no data migration
-- needed).

alter type public.service_category rename value 'Misc' to 'Assessment';
