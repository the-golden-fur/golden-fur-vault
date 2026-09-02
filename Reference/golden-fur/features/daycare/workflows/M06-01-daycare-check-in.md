---
id: M06-01-daycare-check-in
module: M06
title: Daycare Check-In
actors: [Receptionist, Admin, Supervisor, Superadmin, Groomer, Pet Assistant]
trigger: A front-desk-capable staff member checks a pet into Daycare, from an existing Pending Daycare booking or as a fresh walk-in
outcome_success: stays row created (stay_type Daycare, status Active) with a claimed cage, resolved fee-schedule service_id, and today's Care Log entries seeded
outcome_failure:
  [
    booking_not_found_or_wrong_state,
    branch_not_found,
    past_checkin_cutoff,
    no_cage_available,
    insert_failed,
  ]
related_modules: [M03, M05]
source:
  - server/src/features/daycare/daycare.controller.ts
  - server/src/features/daycare/daycare.routes.ts
  - server/src/features/daycare/daycare.types.ts
  - server/src/features/daycare/services/daycareCheckIn.service.ts
  - server/src/features/daycare/services/daycareCheckIn.service.spec.ts
  - server/src/features/daycare/modules/validators/daycare.validator.ts
  - server/src/features/hotel/services/cageAssignment.service.ts
  - server/src/features/hotel/services/careInstructions.service.ts
  - server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts
  - server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts
  - server/src/features/booking/services/booking.service.ts
  - supabase/migrations/20260719039_m06_create_daycare_schema.sql
  - supabase/migrations/20260807104_m05_m06_unify_stays.sql
  - supabase/migrations/20260803081_m05_m06_hotel_daycare_advance_roles.sql
  - supabase/migrations/20260807107_m06_m09_daycare_fee_config.sql
steps:
  - id: start
    type: start
    label: Staff initiates Daycare check-in
    next: check_booking_provided
  - id: check_booking_provided
    type: decision
    label: booking_id provided?
    branches:
      - condition: "yes"
        next: fetch_booking
      - condition: "no"
        next: take_walkin_inputs
  - id: fetch_booking
    type: action
    label: Fetch booking by id
    next: check_booking_valid
  - id: check_booking_valid
    type: decision
    label: Booking exists, service_category = Daycare, status = Pending?
    branches:
      - condition: "no"
        next: end_blocked_booking
      - condition: "yes"
        next: resolve_from_booking
  - id: end_blocked_booking
    type: end
    result: blocked
    label: Not found (404) / wrong category (400) / wrong status (409)
  - id: resolve_from_booking
    type: action
    label: Resolve pet_id + branch_id from booking
    next: fetch_branch
  - id: take_walkin_inputs
    type: input
    actor: [Receptionist, Admin, Supervisor, Superadmin, Groomer, Pet Assistant]
    label: Take pet_id + branch_id directly from input (walk-in)
    next: fetch_branch
  - id: fetch_branch
    type: action
    label: Fetch branch (timezone, daycare_checkin_cutoff)
    next: check_branch_found
  - id: check_branch_found
    type: decision
    label: Branch found?
    branches:
      - condition: "no"
        next: end_blocked_branch
      - condition: "yes"
        next: resolve_cutoff
  - id: end_blocked_branch
    type: end
    result: blocked
    label: Branch not found (404)
  - id: resolve_cutoff
    type: action
    label: Resolve today's cutoff instant (Makati fixed 16:00:00, else branch's own daycare_checkin_cutoff)
    next: check_cutoff
  - id: check_cutoff
    type: decision
    label: Current time past cutoff?
    branches:
      - condition: "yes"
        next: end_blocked_cutoff
      - condition: "no"
        next: claim_cage
  - id: end_blocked_cutoff
    type: end
    result: blocked
    label: Check-in unavailable after cutoff (400) - no stays row created
  - id: claim_cage
    type: action
    label: Suggest cage by weight_class (or use staff-overridden cage_id), claim it Available -> Occupied
    next: check_cage_claimed
  - id: check_cage_claimed
    type: decision
    label: Cage available and claimed?
    branches:
      - condition: "no"
        next: end_blocked_no_cage
      - condition: "yes"
        next: resolve_service
  - id: end_blocked_no_cage
    type: end
    result: blocked
    label: No cage of suggested size, or cage already occupied (409)
  - id: resolve_service
    type: action
    label: Resolve Daycare service_id (booking's own service, explicit walk-in choice, or branch's first active Daycare service)
    next: insert_stay
  - id: insert_stay
    type: action
    label: Insert stays row (stay_type Daycare, status Active, cage_id, service_id)
    next: check_insert
  - id: check_insert
    type: decision
    label: Insert succeeded?
    branches:
      - condition: "no"
        next: release_cage_fail
      - condition: "yes"
        next: check_booking_linked
  - id: release_cage_fail
    type: action
    label: Release the claimed cage (compensating rollback)
    next: end_blocked_insert
  - id: end_blocked_insert
    type: end
    result: blocked
    label: Failed to check in (400)
  - id: check_booking_linked
    type: decision
    label: booking_id present?
    branches:
      - condition: "yes"
        next: sync_booking
      - condition: "no"
        next: insert_care_instructions
  - id: sync_booking
    type: action
    label: "Sync booking: Pending -> In Progress"
    next: insert_care_instructions
  - id: insert_care_instructions
    type: action
    label: Insert feeding/walking/playing/medication instructions
    next: generate_care_log
  - id: generate_care_log
    type: action
    label: Generate today's Care Log entries (single day only)
    next: record_activity
  - id: record_activity
    type: action
    label: Record check_in activity
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Daycare session Active, cage occupied, care log seeded
---

# M06 · Daycare Check-In

Machine-readable companion to
[[M06-01-daycare-check-in|the human-readable version]] in
`Library/golden-fur/features/daycare/workflows/`.
