-- Session 115 (Stage A) - migration for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260927216_custom_remove_online_payment_columns.sql
--
-- Request, verbatim: "Also remove all traces of online payment - We're
-- switching to just having gcash and paymaya as payment methods, not
-- actual online payment processes."
--
-- This is Stage A's only schema change. It drops the three columns that
-- existed purely to support the PayMongo webhook-confirmation flow, now
-- that GCash/Maya settle immediately like every other manual payment
-- method (see server/src/features/billing/services/paymentMethod.service.ts's
-- resolvePaymentConfirmation). transactions.payment_choice is a separate,
-- unrelated column (used by every booking payment regardless of method)
-- and is deliberately left untouched.

alter table public.transactions
  drop column if exists webhook_confirmed_at,
  drop column if exists initiated_by;

alter table public.policy_configurations
  drop column if exists online_payments_enabled;

-- =============================================================================
-- Session 115 (Stage C) - migration for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260927217_custom_discounts_add_misc_sale_scope.sql
--
-- Follow-up request, verbatim: "...then the promo/discount step..." (as part
-- of "make it look like the booking step wizard, add steps to it: first is
-- customer ... then the product chooser ... then the promo/discount step,
-- then payment method step, then confirmation step").
--
-- Adds a fourth discounts.scope_type value, 'misc_sale', meaning "applies to
-- any miscellaneous sale at this discount's available branches, no further
-- sub-scoping" - mirrors how a promo's existing scope_type = 'all_services'
-- already needs no further scope row. scope_service_id/scope_package_id/
-- scope_category all stay NULL for a misc_sale-scoped discount.
--
-- Deliberately NOT reusing/extending the shared public.service_category enum
-- (scope_category's type) - that enum also drives real bookable services
-- (AdminServicesPage's category dropdown), and a "Miscellaneous Sale" value
-- there would let an admin nonsensically create a bookable service in that
-- category. This is a new scope_type value only, fully isolated from the
-- booking/services schema.
--
-- Promos need no schema change: evaluatePromos' existing
-- scope_type = 'all_services' branch already matches unconditionally
-- (server/src/features/billing/services/discountPromoEvaluation.service.ts),
-- so an "all_services" promo already applies to a misc sale once that
-- function is called with an empty `items` array - see
-- evaluateMiscSaleDiscounts/evaluateMiscSalePromos in the same file.

alter table public.discounts
  drop constraint discounts_scope_type_check,
  drop constraint discounts_scope_matches_type;

alter table public.discounts
  add constraint discounts_scope_type_check
    check (scope_type in ('service', 'package', 'category', 'misc_sale')),
  add constraint discounts_scope_matches_type check (
    (
      scope_type = 'service'
      and scope_service_id is not null
      and scope_package_id is null
      and scope_category is null
    )
    or (
      scope_type = 'package'
      and scope_package_id is not null
      and scope_service_id is null
      and scope_category is null
    )
    or (
      scope_type = 'category'
      and scope_category is not null
      and scope_service_id is null
      and scope_package_id is null
    )
    or (
      scope_type = 'misc_sale'
      and scope_service_id is null
      and scope_package_id is null
      and scope_category is null
    )
  );
