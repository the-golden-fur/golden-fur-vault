---
id: M07-02-follow-up-visit-scheduling
module: M07
title: Follow-Up Visit Scheduling
actors: [Veterinarian]
trigger: A Veterinarian selects "Schedule Follow-up" on a Completed consultation that has no existing follow-up booking
outcome_success: A new Veterinary booking is created through the normal booking pipeline and linked onto the originating consultation (follow_up_booking_id, follow_up_date)
outcome_failure:
  [
    booking_creation_failed,
    consultation_not_finished,
    follow_up_already_scheduled,
    pet_mismatch,
  ]
related_modules: [M03, M11]
source:
  - client/src/features/veterinary/components/ScheduleFollowUpModal/ScheduleFollowUpModal.tsx
  - client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx
  - server/src/features/veterinary/services/followUp.service.ts
  - server/src/features/veterinary/services/consultation.service.ts
  - server/src/features/veterinary/veterinary.controller.ts
  - server/src/features/veterinary/veterinary.routes.ts
  - server/src/features/veterinary/modules/validators/veterinary.validator.ts
  - server/src/features/booking/services/booking.service.ts
  - server/src/features/booking/booking.types.ts
steps:
  - id: start
    type: start
    label: Veterinarian selects 'Schedule Follow-up' on a Completed consultation with no existing follow-up booking
    next: choose_service_slot
  - id: choose_service_slot
    type: input
    actor: [Veterinarian]
    label: Choose Veterinary service, slot, optional staff preference and special instructions (pet/owner/branch/category locked)
    next: submit_create_booking
  - id: submit_create_booking
    type: action
    label: Submit createBooking (POST /bookings - same pipeline a receptionist walk-in uses)
    next: check_booking_created
  - id: check_booking_created
    type: decision
    label: Booking created? (capacity/eligibility/pricing checks inside createBooking)
    branches:
      - condition: "no"
        next: error_booking_creation
      - condition: "yes"
        next: send_notifications
  - id: error_booking_creation
    type: action
    label: Show error
    next: choose_service_slot
  - id: send_notifications
    type: action
    label: sendBookingConfirmedNotification to customer + sendStaffAssignedNotification if staff assigned (best-effort)
    next: call_link_follow_up
  - id: call_link_follow_up
    type: action
    label: Call linkFollowUpBooking (consultationId, newBookingId)
    next: check_consultation_finished
  - id: check_consultation_finished
    type: decision
    label: Originating consultation's booking status = Completed?
    branches:
      - condition: "no"
        next: end_blocked_not_finished
      - condition: "yes"
        next: check_already_linked
  - id: end_blocked_not_finished
    type: end
    result: blocked
    label: Can only schedule a follow-up once finished (409)
  - id: check_already_linked
    type: decision
    label: Consultation already has a follow_up_booking_id?
    branches:
      - condition: "yes"
        next: end_blocked_already_scheduled
      - condition: "no"
        next: check_pet_match
  - id: end_blocked_already_scheduled
    type: end
    result: blocked
    label: A follow-up is already scheduled (409)
  - id: check_pet_match
    type: decision
    label: New booking's pet_id = consultation's pet_id?
    branches:
      - condition: "no"
        next: end_blocked_pet_mismatch
      - condition: "yes"
        next: update_consultation_link
  - id: end_blocked_pet_mismatch
    type: end
    result: blocked
    label: Follow-up must be for the same pet (400)
  - id: update_consultation_link
    type: action
    label: Update consultations - follow_up_date, follow_up_booking_id
    next: check_link_succeeded
  - id: check_link_succeeded
    type: decision
    label: Link update succeeded?
    branches:
      - condition: "no"
        next: end_success_unlinked
      - condition: "yes"
        next: end_success_linked
  - id: end_success_unlinked
    type: end
    result: success
    label: Booking scheduled, link failed - best-effort, no rollback of the booking
  - id: end_success_linked
    type: end
    result: success
    label: Booking scheduled and linked as this consultation's follow-up
---

# M07 · Follow-Up Visit Scheduling

Machine-readable companion to
[[M07-02-follow-up-visit-scheduling|the human-readable version]] in
`Library/golden-fur/workflows/`.
