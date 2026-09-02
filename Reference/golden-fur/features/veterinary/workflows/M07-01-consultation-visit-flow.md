---
id: M07-01-consultation-visit-flow
module: M07
title: Consultation Visit Flow (Check-in to Completion)
actors: [Veterinarian, Admin, Supervisor, Superadmin, Receptionist]
trigger: A Veterinary booking (Pending or In Progress) appears in the day's Veterinary Console queue, and a Veterinarian works it from Start through Complete
outcome_success: Booking reaches Completed; consultation_line_items recorded (professional fee + medications/procedures); vaccination written through to pet_vaccination_records if administered
outcome_failure:
  [
    forbidden_not_veterinarian,
    already_finalized,
    invalid_start_status,
    validation_error_missing_amounts,
    invalid_complete_status,
  ]
related_modules: [M03, M02, M08, M13]
source:
  - server/src/features/veterinary/services/consultation.service.ts
  - server/src/features/veterinary/veterinary.controller.ts
  - server/src/features/veterinary/veterinary.routes.ts
  - server/src/features/veterinary/veterinary.types.ts
  - server/src/features/veterinary/modules/validators/veterinary.validator.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/services/veterinaryEligibility.service.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/customers/pets/services/vaccinationRecord.service.ts
  - client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx
  - supabase/migrations/20260719040_m07_create_veterinary_schema.sql
  - supabase/migrations/20260728060_m07_drop_consultation_status.sql
steps:
  - id: start
    type: start
    label: Veterinarian opens the Veterinary Console queue
    next: fetch_queue
  - id: fetch_queue
    type: action
    label: Fetch Veterinary bookings for the date range (status Pending/In Progress/Completed; downpayment-unpaid rows excluded)
    next: check_missing_consultation
  - id: check_missing_consultation
    type: decision
    label: Any Pending/In Progress booking missing a consultations row?
    branches:
      - condition: "yes"
        next: recheck_eligibility
      - condition: "no"
        next: render_queue
  - id: recheck_eligibility
    type: action
    label: Re-check Makati-branch eligibility (defense-in-depth)
    next: auto_vivify
  - id: auto_vivify
    type: action
    label: Auto-vivify a consultations row (reason_for_visit = special_instructions or 'General consultation')
    next: render_queue
  - id: render_queue
    type: action
    label: Render queue (Completed rows included, read-only)
    next: select_start
  - id: select_start
    type: input
    actor: [Veterinarian]
    label: Veterinarian selects a Pending row and clicks Start Consultation
    next: check_role
  - id: check_role
    type: decision
    label: Requester role = Veterinarian?
    branches:
      - condition: "no"
        next: end_blocked_forbidden
      - condition: "yes"
        next: check_already_finalized
  - id: end_blocked_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_already_finalized
    type: decision
    label: Booking already Completed?
    branches:
      - condition: "yes"
        next: end_blocked_finalized
      - condition: "no"
        next: check_start_status
  - id: end_blocked_finalized
    type: end
    result: blocked
    label: Consultation already finalized (409)
  - id: check_start_status
    type: decision
    label: Booking status = Pending?
    branches:
      - condition: "no"
        next: end_blocked_invalid_start
      - condition: "yes"
        next: start_booking
  - id: end_blocked_invalid_start
    type: end
    result: blocked
    label: Cannot start a non-Pending booking (409)
  - id: start_booking
    type: action
    label: "startBooking: bookings.status -> In Progress, started_at set"
    next: record_ongoing
  - id: record_ongoing
    type: action
    actor: [Veterinarian]
    label: Veterinarian records vitals, diagnosis, medications, procedures while Ongoing (no status change required)
    next: input_complete
  - id: input_complete
    type: input
    actor: [Veterinarian]
    label: Veterinarian clicks Complete - enters professional_fee, medication amounts, procedures, optional vaccination
    next: check_complete_payload
  - id: check_complete_payload
    type: decision
    label: professional_fee present, and every medication has an amount?
    branches:
      - condition: "no"
        next: error_validation
      - condition: "yes"
        next: check_complete_status
  - id: error_validation
    type: action
    label: Show validation error (400)
    next: input_complete
  - id: check_complete_status
    type: decision
    label: Booking status = In Progress?
    branches:
      - condition: "no"
        next: end_blocked_invalid_complete
      - condition: "yes"
        next: complete_booking
  - id: end_blocked_invalid_complete
    type: end
    result: blocked
    label: Cannot complete a non-In-Progress booking (409)
  - id: complete_booking
    type: action
    label: "completeBooking: bookings.status -> Completed, completed_at set"
    next: check_online_prepaid
  - id: check_online_prepaid
    type: decision
    label: Already paid online (GCash/Maya, payment_confirmed, not already Paid in Advance)?
    branches:
      - condition: "yes"
        next: advance_payment_stage
      - condition: "no"
        next: insert_line_items
  - id: advance_payment_stage
    type: action
    label: Auto-advance payment_stage -> Paid
    next: insert_line_items
  - id: insert_line_items
    type: action
    label: Insert consultation_line_items (professional fee + one row per medication/procedure)
    next: check_vaccination
  - id: check_vaccination
    type: decision
    label: Vaccination administered?
    branches:
      - condition: "yes"
        next: write_vaccination_record
      - condition: "no"
        next: update_consultation
  - id: write_vaccination_record
    type: action
    label: Write through to pet_vaccination_records (reuses M02 vaccination service)
    next: update_consultation
  - id: update_consultation
    type: action
    label: Update consultations row (vitals, diagnosis, medications JSON)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Consultation Completed - billing line items recorded, vaccination synced if given
---

# M07 · Consultation Visit Flow (Check-in to Completion)

Machine-readable companion to
[[M07-01-consultation-visit-flow|the human-readable version]] in
`Library/golden-fur/features/veterinary/workflows/`.
