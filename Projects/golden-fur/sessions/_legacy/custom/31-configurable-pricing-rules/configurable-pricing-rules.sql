-- Custom change (#31) - migration for manual review/reference.
-- Source of truth is supabase/migrations/20260807108_m13_configurable_pricing_rules.sql.

-- Custom change (configurable pricing rules, live follow-up feedback on
-- #28's optional-matrix change): "I don't like that long coat is just a
-- flat price add on, shouldn't it be a multiplier as well - actually
-- separate each size and coat, make it so that I can individually set for
-- each size/coat if I want it to be a multiplier type, flat price add on,
-- or something like percentage."
--
-- Generalizes pricing_configuration's fixed "size = multiplier, coat = flat
-- add-on" shape into five independent rules (one per size, one for Long
-- coat), each with its own type (multiplier/flat/percentage) and value.
-- Percentage rules are always a percentage of the service's own base_price,
-- not the running (already size-adjusted) total, per the deliberate design
-- choice made when this was scoped out with the client - keeps the
-- calculation predictable regardless of which rules are combined or in
-- what order.
--
-- Column rename (not a new table) so every existing row's configured value
-- carries forward unchanged; the CHECK constraints loosen from "> 0" to
-- ">= 0" since a flat/percentage rule can legitimately be zero - a
-- multiplier of exactly 0 is instead rejected at the application layer
-- (updatePricingConfigurationValidator), where the paired rule_type is
-- actually known.

create type public.pricing_rule_type as enum ('multiplier', 'flat', 'percentage');

alter table public.pricing_configuration
  rename column size_s_multiplier to size_s_rule_value;
alter table public.pricing_configuration
  rename column size_m_multiplier to size_m_rule_value;
alter table public.pricing_configuration
  rename column size_l_multiplier to size_l_rule_value;
alter table public.pricing_configuration
  rename column size_xl_multiplier to size_xl_rule_value;
alter table public.pricing_configuration
  rename column long_coat_addon to coat_long_rule_value;

alter table public.pricing_configuration
  drop constraint pricing_configuration_size_s_multiplier_check,
  drop constraint pricing_configuration_size_m_multiplier_check,
  drop constraint pricing_configuration_size_l_multiplier_check,
  drop constraint pricing_configuration_size_xl_multiplier_check,
  drop constraint pricing_configuration_long_coat_addon_check,
  add constraint pricing_configuration_size_s_rule_value_check check (size_s_rule_value >= 0),
  add constraint pricing_configuration_size_m_rule_value_check check (size_m_rule_value >= 0),
  add constraint pricing_configuration_size_l_rule_value_check check (size_l_rule_value >= 0),
  add constraint pricing_configuration_size_xl_rule_value_check check (size_xl_rule_value >= 0),
  add constraint pricing_configuration_coat_long_rule_value_check check (coat_long_rule_value >= 0);

alter table public.pricing_configuration
  add column size_s_rule_type public.pricing_rule_type not null default 'multiplier',
  add column size_m_rule_type public.pricing_rule_type not null default 'multiplier',
  add column size_l_rule_type public.pricing_rule_type not null default 'multiplier',
  add column size_xl_rule_type public.pricing_rule_type not null default 'multiplier',
  add column coat_long_rule_type public.pricing_rule_type not null default 'flat';

comment on table public.pricing_configuration is
  'Singleton (Admin/Superadmin editable): the shared grooming size/coat '
  'calculation - five independent rules (size_s/m/l/xl, coat_long), each a '
  'type (multiplier/flat/percentage) + value. Percentage rules are always a '
  'percentage of the service''s own base_price. Default values are a '
  'starting point, not a confirmed business rule - flag for client review.';
