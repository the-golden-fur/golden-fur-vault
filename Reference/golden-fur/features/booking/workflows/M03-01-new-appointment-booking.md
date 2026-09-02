---
id: M03-01-new-appointment-booking
module: M03
title: New Appointment Booking
actors: [Customer, Staff]
trigger: A customer (or a staff member on behalf of a walk-in/phone-in customer) submits a booking with pet, branch, service category, one or more items, a schedule, booking_source ('Online' default, or 'Walk-in' - staff-only), an optional payment_scheme ('full' | 'downpayment'), and optional staff/cage/discount/promo selections. No payment method is collected.
outcome_success: "bookings row created with payment_status='Pending'. 'Walk-in' -> status=In Progress, started_at set, down payment skipped; 'Online' -> status=Pending. netTotal = total_price - discount_amount - promo_amount. Unless the category is Veterinary (priced during the visit), the server then emits exactly one Pending booking_payment transaction (createInitialBookingCharge) for netTotal, or just the down payment when payment_scheme='downpayment' and the branch down-payment policy is on - a cashier settles it later (M08-04). An Online booking that requires a down payment and hasn't paid any of it is a pencil booking: it holds NO slot (SLOT_HOLD_PAID_OR_FILTER now keys on payment_status != 'Pending') and carries downpayment_due_at (now + downpayment_hold_hours). Confirmation notifications fire at creation only for Walk-in / Veterinary; for an unpaid Online booking they are held back and sent by recomputeBookingPaymentStatus on the first settled payment."
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
    notice_lead_time_not_met,
    staff_preference_unavailable,
    no_eligible_staff,
    capacity_unavailable,
    capacity_lost_race,
  ]
related_modules: [M01, M05, M06, M08, M09, M10, M11, M13]
source:
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/booking.routes.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/services/capacity.service.ts
  - server/src/features/booking/services/cagePicker.service.ts
  - server/src/features/booking/services/veterinaryEligibility.service.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - supabase/migrations/20260718035_m03_create_booking_schema.sql
  - supabase/migrations/20260803077_m03_multi_item_bookings.sql
  - supabase/migrations/20260828143_m09_policy_configurations_downpayment.sql
  - supabase/migrations/20260828145_custom_bookings_booking_source.sql
  - supabase/migrations/20260829146_m09_policy_configurations_downpayment_hold_hours.sql
  - supabase/migrations/20260829147_m03_bookings_downpayment_due_at.sql
  - supabase/migrations/20260901150_m08_bookings_replace_payment_stage_with_payment_status.sql
  - supabase/migrations/20260901151_m08_transactions_payment_choice_free_label.sql
  - supabase/migrations/20260901153_m08_settle_transaction_rpc.sql
  - supabase/migrations/20260901156_m03_get_staff_availability_payment_status.sql
steps:
  - id: start
    type: start
    label: Customer (or staff) begins a booking
    next: input_selection
  - id: input_selection
    type: input
    actor: [Customer, Staff]
    label: Select branch, service category, pet, and items; browse read-only Slot Picker / Staff Picker / Cage Picker
    next: input_submit
  - id: input_submit
    type: input
    actor: [Customer, Staff]
    label: "Submit booking payload (pet_id, branch_id, service_category, items[], scheduled_start/end, booking_source?, payment_scheme?, staff_preference?, cage_preference?, discount_id?, promo_id?). No payment_method / card details."
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
    label: "booking_source resolves to 'Walk-in' requested by a non-staff caller? (default when omitted is 'Online')"
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
    next: decision_pet_ok
  - id: decision_pet_ok
    type: decision
    label: Pet exists and pet.customer_id matches the resolved customer_id?
    branches:
      - condition: "no"
        next: end_blocked_pet
      - condition: "yes"
        next: decision_vet_eligibility
  - id: end_blocked_pet
    type: end
    result: blocked
    label: Pet not found (404) or does not belong to this customer (403)
  - id: decision_vet_eligibility
    type: decision
    label: service_category = Veterinary AND branch is not a vet branch?
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
    label: Resolve every item's price/duration snapshot, validate active/category/assessment; sum total_price (see M03-02)
    next: decision_items_valid
  - id: decision_items_valid
    type: decision
    label: Every item active, category-matched, and (if required) the pet assessed?
    branches:
      - condition: "no"
        next: end_blocked_item_invalid
      - condition: "yes"
        next: action_resolve_discount_promo
  - id: end_blocked_item_invalid
    type: end
    result: blocked
    label: Inactive service/package, category mismatch, or unassessed pet blocked from a package/assessed-only service (400/403)
  - id: action_resolve_discount_promo
    type: action
    label: "Resolve and lock in any discount (money-handling staff only, ID verified onsite) and promo (self-service); compute netTotal = total_price - discount_amount - promo_amount"
    next: decision_downpayment_source
  - id: decision_downpayment_source
    type: decision
    label: "booking_source = 'Online'?"
    branches:
      - condition: "yes (Online)"
        next: action_resolve_downpayment
      - condition: "no (Walk-in)"
        next: action_resolve_scheme
  - id: action_resolve_downpayment
    type: action
    label: "Online only: assert the branch minimum-notice lead time (422 if the slot is inside the window), then resolve the effective per-transaction downpayment policy (system default + per-branch override, see M09) and snapshot downpayment_required / downpayment_amount against netTotal. A 'Walk-in' skips this step entirely (downpayment_required stays false)."
    next: action_resolve_scheme
  - id: action_resolve_scheme
    type: action
    label: "Resolve paymentScheme = 'downpayment' only when downpayment_required AND payment_scheme = 'downpayment', else 'full'. initialChargeAmount = downpayment_amount (fallback netTotal) for 'downpayment', else netTotal. requiresUpfrontCharge = service_category != 'Veterinary'. holdsSlot = NOT downpayment_required; a pencil booking (Online, down payment required, unpaid) also gets downpayment_due_at = now + downpayment_hold_hours."
    next: action_resolve_staff
  - id: action_resolve_staff
    type: action
    label: "Grooming/Veterinary only: resolve staff assignment via get_staff_availability() - re-verify a specific preference, or auto-assign a random eligible staff member for 'no preference'"
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
    label: "Hotel only: verify a specific cage preference is still Available and (for a customer caller) matches the pet's weight_class - degrades silently to null rather than rejecting the booking"
    next: decision_capacity
  - id: decision_capacity
    type: decision
    label: "holdsSlot AND Hotel/Daycare: authoritative checkCapacity() - is a cage/session slot available? (skipped for a pencil booking, which reserves nothing)"
    branches:
      - condition: "full"
        next: end_blocked_capacity
      - condition: "available / not applicable / pencil booking"
        next: action_insert
  - id: end_blocked_capacity
    type: end
    result: blocked
    label: No capacity available for the requested dates/time (409)
  - id: action_insert
    type: action
    label: "Insert the bookings row (payment_status='Pending', legacy payment_method=null / payment_confirmed=false) - 'Online' -> status=Pending; 'Walk-in' -> status=In Progress with started_at=now - plus booking_items rows and a staff_picker_preferences row when staff resolution applied"
    next: decision_race
  - id: decision_race
    type: decision
    label: "holdsSlot: post-insert re-verification (confirmCapacityAfterInsert) - did this booking win the slot? (skipped for a pencil booking)"
    branches:
      - condition: "no (lost the race)"
        next: action_rollback
      - condition: "yes / skipped"
        next: decision_confirmed_at_creation
  - id: action_rollback
    type: action
    label: Delete the losing booking row
    next: end_blocked_race
  - id: end_blocked_race
    type: end
    result: blocked
    label: Capacity was taken between slot selection and submission - select another slot (409)
  - id: decision_confirmed_at_creation
    type: decision
    label: Confirmed at creation? (booking_source = 'Walk-in' OR service_category = 'Veterinary')
    branches:
      - condition: "yes"
        next: action_notify_now
      - condition: "no (unpaid Online)"
        next: decision_upfront_charge
  - id: action_notify_now
    type: action
    label: Send booking_confirmed notification (+ staff_assigned if a specific staff preference was honored)
    next: decision_upfront_charge
  - id: decision_upfront_charge
    type: decision
    label: "requiresUpfrontCharge (service_category != 'Veterinary') AND initialChargeAmount > 0?"
    branches:
      - condition: "yes"
        next: action_initial_charge
      - condition: "no (Veterinary, or zero net total)"
        next: action_free_package
  - id: action_initial_charge
    type: action
    label: "Best-effort createInitialBookingCharge: insert one Pending booking_payment transaction (payment_choice = 'downpayment' or 'full', payment_method 'Cash' placeholder) + one matching transaction_line_items row so SUM(line_total) = total_amount. A thrown error is caught and logged and never undoes the booking."
    next: action_free_package
  - id: action_free_package
    type: action
    label: "If a qualifying Hotel stay unlocked a free package, notify the customer and the branch Receptionist"
    next: end_success
  - id: end_success
    type: end
    result: success
    label: "Booking created. Online non-Veterinary: one Pending booking_payment transaction awaiting counter settlement (M08-04); slot held immediately unless a down payment is required and unpaid (pencil booking). Walk-in / Veterinary: confirmed at creation. Confirmation notifications for an unpaid Online booking are sent later by recomputeBookingPaymentStatus on the first settled payment."
---

# M03 · New Appointment Booking

Machine-readable companion to
[[M03-01-new-appointment-booking|the human-readable version]] in
`Library/golden-fur/features/booking/workflows/`.
