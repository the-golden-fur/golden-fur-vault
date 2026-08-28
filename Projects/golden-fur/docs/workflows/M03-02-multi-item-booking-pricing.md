---
id: M03-02-multi-item-booking-pricing
module: M03
title: Multi-Item Booking Selection & Pricing
actors: [Customer, Staff]
trigger: Within a single booking submission (see M03-01), one or more services and/or packages have been checkbox-selected for one pet in one service_category
outcome_success: one booking_items row per selected item with price_at_booking/duration_minutes_at_booking snapshotted; bookings.total_price/downpayment_required/downpayment_amount/discount_amount/promo_amount set
outcome_failure:
  [
    item_inactive,
    item_category_mismatch,
    package_wrong_branch,
    package_member_category_mismatch,
    pet_not_assessed,
    discount_role_forbidden,
    discount_cash_only,
    discount_branch_unavailable,
    discount_scope_mismatch,
    promo_inactive,
    promo_not_started,
    promo_ended,
    promo_branch_unavailable,
    promo_scope_mismatch,
  ]
related_modules: [M13, M09]
source:
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - supabase/migrations/20260803077_m03_multi_item_bookings.sql
  - supabase/migrations/20260803078_m03_m08_booking_discount_promo.sql
  - supabase/migrations/20260803082_m08_booking_payment_stage.sql
  - supabase/migrations/20260828143_m09_policy_configurations_downpayment.sql
  - supabase/migrations/20260828144_m13_services_packages_downpayment_removal.sql
steps:
  - id: start
    type: start
    label: One or more services/packages have been selected for one pet, one service_category
    next: decision_item_type
  - id: decision_item_type
    type: decision
    label: "Per selected item: is it a package or a standalone service?"
    branches:
      - condition: "package"
        next: decision_pet_assessed_package
      - condition: "service"
        next: action_check_service
  - id: action_check_service
    type: action
    label: Verify the service is active and its category matches the booking's service_category
    next: decision_service_valid
  - id: decision_service_valid
    type: decision
    label: Service inactive or category mismatch?
    branches:
      - condition: "yes"
        next: end_blocked_item_invalid
      - condition: "no"
        next: decision_assessment_required_service
  - id: end_blocked_item_invalid
    type: end
    result: blocked
    label: Inactive service/package, wrong branch, or member-category mismatch (400)
  - id: decision_assessment_required_service
    type: decision
    label: service.requires_assessed_pet AND the pet is not yet assessed (weight_class/coat_type still NULL)?
    branches:
      - condition: "yes"
        next: end_blocked_pet_not_assessed
      - condition: "no"
        next: action_price_service
  - id: end_blocked_pet_not_assessed
    type: end
    result: blocked
    label: This pet must be assessed by staff before booking this service/any package (403)
  - id: action_price_service
    type: action
    label: "Compute price: resolveServicePrice (Grooming matrix tier for a dog if use_pricing_matrix, else base_price) x quantity (Hotel nights via resolveQuantity, else 1)"
    next: collect_item
  - id: decision_pet_assessed_package
    type: decision
    label: Pet not yet assessed? (every package requires an assessed pet)
    branches:
      - condition: "yes"
        next: end_blocked_pet_not_assessed
      - condition: "no"
        next: action_verify_package
  - id: action_verify_package
    type: action
    label: Verify the package is active, available at this branch, and every member service belongs to the booking's service_category
    next: decision_package_valid
  - id: decision_package_valid
    type: decision
    label: Package inactive, wrong branch, or a member service outside the booking's category?
    branches:
      - condition: "yes"
        next: end_blocked_item_invalid
      - condition: "no"
        next: action_price_package
  - id: action_price_package
    type: action
    label: "Compute price: resolvePackagePrice (matrix cell of bundled_price if package.use_pricing_matrix and pet is not a Cat, else flat bundled_price) x quantity"
    next: collect_item
  - id: collect_item
    type: action
    label: Add the resolved item (price_at_booking, duration_minutes_at_booking) to the booking's item list
    next: decision_hotel_free_package
  - id: decision_hotel_free_package
    type: decision
    label: "Hotel only: does the selected Hotel service's own min_nights_for_free_package threshold get met by the computed nights?"
    branches:
      - condition: "yes"
        next: action_award_free_package
      - condition: "no"
        next: action_sum_total
  - id: action_award_free_package
    type: action
    label: Append a zero-priced booking_items row for the matching free package (resolved by name, filtered to one available at this branch) and notify the customer + branch Receptionists
    next: action_sum_total
  - id: action_sum_total
    type: action
    label: total_price = sum of every item's price_at_booking (pre-discount; the free-package award contributes 0)
    next: action_compute_downpayment
  - id: action_compute_downpayment
    type: action
    label: "Resolve the effective downpayment policy for this branch (M09, default-row-plus-per-branch-override); if downpayment_enabled, downpayment_amount = Flat amount, or Percentage x total_price; downpayment_required = downpayment_enabled"
    next: decision_discount
  - id: decision_discount
    type: decision
    label: A discount_id was supplied?
    branches:
      - condition: "yes"
        next: action_validate_discount
      - condition: "no"
        next: decision_promo
  - id: action_validate_discount
    type: action
    label: Verify requester is a money-handling staff role, payment_method = Cash, the discount is available at this branch, and its scope (service/package/category) matches a selected item
    next: decision_discount_valid
  - id: decision_discount_valid
    type: decision
    label: Any discount check failed?
    branches:
      - condition: "yes"
        next: end_blocked_discount
      - condition: "no"
        next: action_apply_discount
  - id: end_blocked_discount
    type: end
    result: blocked
    label: Discount forbidden — wrong role, non-Cash payment, branch-unavailable, or scope mismatch (400/403)
  - id: action_apply_discount
    type: action
    label: discount_amount = discount.value% of total_price, or flat value capped at total_price
    next: decision_promo
  - id: decision_promo
    type: decision
    label: A promo_id was supplied?
    branches:
      - condition: "yes"
        next: action_validate_promo
      - condition: "no"
        next: end_success
  - id: action_validate_promo
    type: action
    label: Verify the promo is active, within its start/end date window, available at this branch, and its scope (all_services, or a specific service/package) matches a selected item
    next: decision_promo_valid
  - id: decision_promo_valid
    type: decision
    label: Any promo check failed?
    branches:
      - condition: "yes"
        next: end_blocked_promo
      - condition: "no"
        next: action_apply_promo
  - id: end_blocked_promo
    type: end
    result: blocked
    label: Promo inactive, not started, ended, branch-unavailable, or scope mismatch (400)
  - id: action_apply_promo
    type: action
    label: promo_amount = min(promo.value% or flat value of total_price, the branch's or default promo_cap_configuration cap)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: booking_items inserted with their price/duration snapshots; total_price/discount_amount/promo_amount/downpayment_required/downpayment_amount stored on the booking row
---

# M03 · Multi-Item Booking Selection & Pricing

Machine-readable companion to
[[M03-02-multi-item-booking-pricing|the human-readable version]] in
`Library/golden-fur/workflows/`.
