---
id: M03-01-new-appointment-booking
module: M03
title: New Appointment Booking
actors: [Customer, Staff]
trigger: A customer (or a staff member on behalf of a walk-in/phone-in customer) submits a booking with pet, branch, service category, one or more items, a schedule, booking_source ('Online' default, or 'Walk-in' - staff-only), and optional staff/cage preference
outcome_success: "bookings row created - 'Walk-in' -> status=In Progress, started_at set, down payment skipped; 'Online' -> status=Pending. An Online booking that requires a down payment and hasn't paid any of it is a pencil booking: it holds NO slot (capacity queries + get_staff_availability exclude it) and carries downpayment_due_at (now + downpayment_hold_hours); paying it, or a staff-collected payment at creation, makes it a real slot-holding reservation. booking_confirmed notification sent"
outcome_failure:
  [
    staff_customer_id_required,
    forbidden_customer_mismatch,
    walk_in_requires_staff,
    pet_not_found,
    pet_ownership_mismatch,
    veterinary_branch_ineligible,
    item_invalid,
    pet_not_assessed,
    staff_preference_unavailable,
    no_eligible_staff,
    capacity_unavailable,
    capacity_lost_race,
  ]
related_modules: [M01, M05, M06, M09, M11, M13]
source:
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/booking.routes.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/services/availability.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/services/capacity.service.ts
  - server/src/features/booking/services/cagePicker.service.ts
  - server/src/features/booking/services/veterinaryEligibility.service.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - supabase/migrations/20260718035_m03_create_booking_schema.sql
  - supabase/migrations/20260718036_m03_get_staff_availability_rpc.sql
  - supabase/migrations/20260728062_m03_get_staff_availability_unified_status.sql
  - supabase/migrations/20260803083_m03_m08_remove_paid_booking_status.sql
  - supabase/migrations/20260804092_m03_get_staff_availability_lunch_break.sql
  - supabase/migrations/20260808109_m03_get_staff_availability_fix_paid_status.sql
  - supabase/migrations/20260803077_m03_multi_item_bookings.sql
  - supabase/migrations/20260828143_m09_policy_configurations_downpayment.sql
  - supabase/migrations/20260828144_m13_services_packages_downpayment_removal.sql
  - supabase/migrations/20260828145_custom_bookings_booking_source.sql
  - supabase/migrations/20260829146_m09_policy_configurations_downpayment_hold_hours.sql
  - supabase/migrations/20260829147_m03_bookings_downpayment_due_at.sql
  - supabase/migrations/20260829148_m03_get_staff_availability_downpayment_hold.sql
steps:
  - id: start
    type: start
    label: Customer (or staff) begins a booking
    next: input_selection
  - id: input_selection
    type: input
    actor: [Customer, Staff]
    label: Select branch, service category, pet, and items; browse read-only Slot Picker / Staff Picker / Cage Picker (getDaySlots, getStaffPickerOptions, getCagePickerOptions)
    next: input_submit
  - id: input_submit
    type: input
    actor: [Customer, Staff]
    label: Submit booking payload (pet_id, branch_id, service_category, items[], scheduled_start/end, booking_source?, staff_preference?, cage_preference?, payment_method?, discount_id?, promo_id?)
    next: decision_actor
  - id: decision_actor
    type: decision
    label: Is the requester a staff member (has a staff_profiles role)?
    branches:
      - condition: "staff"
        next: decision_staff_customer_id
      - condition: "customer"
        next: decision_customer_match
  - id: decision_staff_customer_id
    type: decision
    label: "Staff caller: is customer_id present in the payload?"
    branches:
      - condition: "no"
        next: end_blocked_staff_customer_id
      - condition: "yes"
        next: decision_walk_in_role
  - id: end_blocked_staff_customer_id
    type: end
    result: blocked
    label: customer_id is required when staff create a booking on behalf of a customer (400)
  - id: decision_customer_match
    type: decision
    label: "Customer caller: customer_id omitted, or equal to the requester's own id?"
    branches:
      - condition: "no (mismatch)"
        next: end_blocked_forbidden
      - condition: "yes"
        next: decision_walk_in_role
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Customers can only create their own bookings (403)
  - id: decision_walk_in_role
    type: decision
    label: "booking_source resolves to 'Walk-in' (customer/pet physically at the branch now) requested by a non-staff caller? (default when omitted is 'Online')"
    branches:
      - condition: "yes (Walk-in + no staff role)"
        next: end_blocked_walk_in_role
      - condition: "no ('Online', or 'Walk-in' by staff)"
        next: action_lookup_pet
  - id: end_blocked_walk_in_role
    type: end
    result: blocked
    label: Only staff may create a walk-in booking (403)
  - id: action_lookup_pet
    type: action
    label: Look up the pet by pet_id
    next: decision_pet_found
  - id: decision_pet_found
    type: decision
    label: Pet exists?
    branches:
      - condition: "no"
        next: end_blocked_pet_not_found
      - condition: "yes"
        next: decision_pet_owner
  - id: end_blocked_pet_not_found
    type: end
    result: blocked
    label: Pet not found (404)
  - id: decision_pet_owner
    type: decision
    label: pet.customer_id matches the resolved customer_id?
    branches:
      - condition: "no"
        next: end_blocked_pet_ownership
      - condition: "yes"
        next: decision_vet_eligibility
  - id: end_blocked_pet_ownership
    type: end
    result: blocked
    label: Pet does not belong to this customer (403)
  - id: decision_vet_eligibility
    type: decision
    label: service_category = Veterinary AND branch.is_vet_branch = false?
    branches:
      - condition: "yes"
        next: end_blocked_vet_ineligible
      - condition: "no"
        next: action_resolve_items
  - id: end_blocked_vet_ineligible
    type: end
    result: blocked
    label: Veterinary bookings are exclusive to the Makati branch (422)
  - id: action_resolve_items
    type: action
    label: Resolve every selected item's price/duration snapshot and validate active/category/assessment; sum total_price (see M03-02 for the item-level detail)
    next: decision_items_valid
  - id: decision_items_valid
    type: decision
    label: Every item active, category-matched, and (if required) the pet assessed?
    branches:
      - condition: "no"
        next: end_blocked_item_invalid
      - condition: "yes"
        next: decision_downpayment_source
  - id: end_blocked_item_invalid
    type: end
    result: blocked
    label: Inactive service/package, category mismatch, or unassessed pet blocked from a package/assessed-only service (400/403)
  - id: decision_downpayment_source
    type: decision
    label: "booking_source = 'Online'?"
    branches:
      - condition: "yes (Online)"
        next: action_resolve_downpayment
      - condition: "no (Walk-in)"
        next: action_resolve_staff
  - id: action_resolve_downpayment
    type: action
    label: "Online only: resolve the branch's effective per-transaction downpayment policy (resolveDownpaymentPolicy - system default + per-branch override, see M09) and snapshot downpayment_required / downpayment_amount against the whole booking's total_price. A 'Walk-in' skips this step entirely - resolveDownpaymentPolicy is not even called and downpayment_required stays false, because a walk-in holds no slot at zero payment risk (the customer/pet is already present)."
    next: action_resolve_staff
  - id: action_resolve_staff
    type: action
    label: "Grooming/Veterinary only: resolve staff assignment via get_staff_availability() - re-verify a specific preference, or auto-assign a random eligible staff member for 'no preference' (Hotel/Daycare/Misc skip this step - no staff assignment)"
    next: decision_staff_ok
  - id: decision_staff_ok
    type: decision
    label: Staff assignment required and none eligible (or the specific preference no longer passes)?
    branches:
      - condition: "yes"
        next: end_blocked_no_staff
      - condition: "no"
        next: action_resolve_cage
  - id: end_blocked_no_staff
    type: end
    result: blocked
    label: No eligible staff available for the requested time (409)
  - id: action_resolve_cage
    type: action
    label: "Hotel only: verify a specific cage preference is still Available and (for a customer caller) matches the pet's own weight_class - degrades silently to null (no preference) rather than rejecting the booking"
    next: decision_capacity
  - id: decision_capacity
    type: decision
    label: "Hotel/Daycare only: authoritative checkCapacity() - is a cage/session slot available?"
    branches:
      - condition: "full"
        next: end_blocked_capacity
      - condition: "available or not applicable"
        next: action_insert
  - id: end_blocked_capacity
    type: end
    result: blocked
    label: No capacity available for the requested dates/time (409)
  - id: action_insert
    type: action
    label: "Insert the bookings row - booking_source='Online' -> status=Pending; booking_source='Walk-in' -> status=In Progress with started_at set to now (no separate Start/Check In step will fire) - plus its booking_items rows and a staff_picker_preferences row when staff resolution applied"
    next: decision_race
  - id: decision_race
    type: decision
    label: Post-insert re-verification (confirmCapacityAfterInsert) - did this booking win the slot?
    branches:
      - condition: "no (lost the race)"
        next: action_rollback
      - condition: "yes"
        next: action_notify
  - id: action_rollback
    type: action
    label: Delete the losing booking row
    next: end_blocked_race
  - id: end_blocked_race
    type: end
    result: blocked
    label: Capacity was taken between slot selection and submission - select another slot (409)
  - id: action_notify
    type: action
    label: Send booking_confirmed notification (+ staff_assigned if a specific staff preference was honored; + a free-package-award notification for a qualifying Hotel stay)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: "Booking created holding its slot immediately - Online at status=Pending (awaiting arrival/Check In), Walk-in at status=In Progress"
---

# M03 · New Appointment Booking

Machine-readable companion to
[[M03-01-new-appointment-booking|the human-readable version]] in
`Library/golden-fur/workflows/`.
