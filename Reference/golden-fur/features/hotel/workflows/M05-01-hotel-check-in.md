---
id: M05-01-hotel-check-in
module: M05
title: Hotel Check-In
actors: [Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin]
trigger: Staff opens Check-In for a confirmed, Pending Hotel booking on its scheduled day
outcome_success: stays row created (Active), cage flipped to Occupied, booking advanced to In Progress, care instructions + Boarding Checklist entries generated
outcome_failure:
  [
    booking_not_found_or_not_hotel,
    booking_not_pending,
    wrong_branch,
    already_checked_in,
    no_available_cage,
    checkin_write_failed,
  ]
related_modules: [M03, M07]
source:
  - server/src/features/hotel/services/careInstructions.service.ts
  - server/src/features/hotel/services/cageAssignment.service.ts
  - server/src/features/hotel/hotel.controller.ts
  - server/src/features/hotel/hotel.routes.ts
  - server/src/features/hotel/hotel.types.ts
  - server/src/features/hotel/modules/validators/hotel.validator.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/services/cagePicker.service.ts
  - server/src/features/veterinary/services/currentPrescription.service.ts
  - supabase/migrations/20260727050_m05_create_cages_schema.sql
  - supabase/migrations/20260727051_m05_create_hotel_stays_schema.sql
  - supabase/migrations/20260807104_m05_m06_unify_stays.sql
  - supabase/migrations/20260803081_m05_m06_hotel_daycare_advance_roles.sql
  - supabase/migrations/20260803086_m05_add_playing_instructions.sql
steps:
  - id: start
    type: start
    label: Staff opens Check-In for a Hotel booking
    next: input_checkin
  - id: input_checkin
    type: input
    actor: [Receptionist, Groomer, Pet Assistant, Admin, Supervisor, Superadmin]
    label: Enter booking_id, optional cage_id override, feeding/walking/playing rows, medications, notify_opt_in
    next: check_booking_hotel
  - id: check_booking_hotel
    type: decision
    label: Booking exists and service_category = Hotel?
    branches:
      - condition: "no"
        next: end_blocked_not_hotel
      - condition: "yes"
        next: check_pending
  - id: end_blocked_not_hotel
    type: end
    result: blocked
    label: Booking not found or not a Hotel booking (404/400)
  - id: check_pending
    type: decision
    label: Booking status = Pending?
    branches:
      - condition: "no"
        next: end_blocked_status
      - condition: "yes"
        next: check_branch
  - id: end_blocked_status
    type: end
    result: blocked
    label: A booking that isn't Pending cannot be checked in (409)
  - id: check_branch
    type: decision
    label: Booking's branch = requester's branch?
    branches:
      - condition: "no"
        next: end_blocked_branch
      - condition: "yes"
        next: check_existing_stay
  - id: end_blocked_branch
    type: end
    result: blocked
    label: Booking does not belong to this branch (403)
  - id: check_existing_stay
    type: decision
    label: Does a stay already exist for this booking?
    branches:
      - condition: "yes"
        next: end_blocked_duplicate
      - condition: "no"
        next: resolve_cage
  - id: end_blocked_duplicate
    type: end
    result: blocked
    label: Already checked in (409)
  - id: resolve_cage
    type: action
    label: Resolve cage (cage_id given, else suggest by pet's weight_class - first Available match)
    next: claim_cage
  - id: claim_cage
    type: decision
    label: "Conditional claim: cage still Available? (flip to Occupied)"
    branches:
      - condition: "no"
        next: end_blocked_no_cage
      - condition: "yes"
        next: insert_stay
  - id: end_blocked_no_cage
    type: end
    result: blocked
    label: No available cage of the suggested/chosen size (409)
  - id: insert_stay
    type: action
    label: Insert stays row (Hotel, check_in_at=now, scheduled_check_out_date from booking, downpayment snapshot, created_by)
    next: advance_booking
  - id: advance_booking
    type: action
    label: Advance booking - Pending -> In Progress
    next: insert_feeding_walking_playing
  - id: insert_feeding_walking_playing
    type: action
    label: Insert feeding/walking/playing instruction rows as submitted
    next: check_medications_provided
  - id: check_medications_provided
    type: decision
    label: Medications field provided in the request?
    branches:
      - condition: "no (omitted)"
        next: autofill_medications
      - condition: "yes (incl. empty array)"
        next: use_submitted_medications
  - id: autofill_medications
    type: action
    label: Auto-fill from M07's current-prescription derivation (empty if no current prescription)
    next: insert_medications
  - id: use_submitted_medications
    type: action
    label: Use submitted list verbatim (receptionist's own list)
    next: insert_medications
  - id: insert_medications
    type: action
    label: Insert medication instruction rows
    next: generate_care_log
  - id: generate_care_log
    type: action
    label: Generate one care_log_entries row per scheduled action per calendar day (check-in date through scheduled checkout date; dated stay_date row overrides every-night default for that day)
    next: check_step_failure
  - id: check_step_failure
    type: decision
    label: Did any step from the stay insert through Care Log generation fail?
    branches:
      - condition: "yes"
        next: release_cage
      - condition: "no"
        next: record_activity
  - id: release_cage
    type: action
    label: Release the claimed cage back to Available (compensating rollback)
    next: end_blocked_checkin_failed
  - id: end_blocked_checkin_failed
    type: end
    result: blocked
    label: Check-in failed, no stray Occupied cage left behind
  - id: record_activity
    type: action
    label: Record check_in activity (best-effort)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Stay Active, cage Occupied, Boarding Checklist populated
---

# M05 · Hotel Check-In

Machine-readable companion to
[[M05-01-hotel-check-in|the human-readable version]] in
`Library/golden-fur/features/hotel/workflows/`.
