---
id: M10-01-cancellation-to-credit-conversion
module: M10
title: Cancellation-to-Credit Conversion
actors: [Customer, Staff]
trigger: A customer or staff member cancels a booking in Pending or In Progress status
outcome_success: booking cancelled; a configurable percentage (cancellation_credit_conversion_rate, default 100) of the amount the customer actually paid is converted to a credit_balances increment + issuance credit_transactions row when it qualifies, otherwise forfeited/not applicable
outcome_failure: [not_cancellable_status, booking_update_failed]
related_modules: [M08, M09, M13, M14]
source:
  - server/src/features/booking/services/cancellation.service.ts
  - server/src/features/booking/services/cancellationLog.service.ts
  - server/src/features/booking/services/reschedule.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - server/src/features/credits/services/creditIssuance.service.ts
  - server/src/features/credits/services/creditIssuance.service.spec.ts
  - supabase/migrations/20260805096_m10_create_credit_balances_schema.sql
  - supabase/migrations/20260805097_m10_create_credit_transactions_schema.sql
  - supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql
  - supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql
  - supabase/migrations/20260731068_m08_create_transactions_schema.sql
steps:
  - id: start
    type: start
    label: Cancellation requested for a booking
    next: check_status
  - id: check_status
    type: decision
    label: Booking status is Pending or In Progress?
    branches:
      - condition: "no"
        next: end_blocked_status
      - condition: "yes"
        next: evaluate_notice
  - id: end_blocked_status
    type: end
    result: blocked
    label: Booking in this status cannot be cancelled (409)
  - id: evaluate_notice
    type: action
    label: Evaluate notice period against branch's effective policy_configurations
    next: update_booking
  - id: update_booking
    type: action
    label: "Update booking: status = Cancelled, cancelled_at, cancellation_reason"
    next: check_update
  - id: check_update
    type: decision
    label: Booking update succeeded?
    branches:
      - condition: "no"
        next: end_blocked_update
      - condition: "yes"
        next: write_log
  - id: end_blocked_update
    type: end
    result: blocked
    label: Failed to cancel booking (400)
  - id: write_log
    type: action
    label: Write cancellation_logs row (credit_issued=false, credit_amount=null by default; best-effort, returns null on failure)
    next: compute_paid
  - id: compute_paid
    type: action
    label: "confirmedAmountPaid = SUM(total_amount) of the booking's transactions where transaction_type = 'booking_payment' AND payment_status != 'Pending' (a settled downpayment is 'Partially Paid', a settled full/remaining payment is 'Fully Paid'). NOT bookings.payment_stage. Skipped (0) when notice was not met."
    next: compute_credit
  - id: compute_credit
    type: action
    label: "creditAmount = round2(amountPaid * policy.cancellation_credit_conversion_rate / 100)"
    next: check_qualifies
  - id: check_qualifies
    type: decision
    label: Qualifies for credit? (notice period met AND creditAmount > 0)
    branches:
      - condition: "no"
        next: skip_credit
      - condition: "yes"
        next: check_expiry_enabled
  - id: skip_credit
    type: action
    label: No credit attempted (notice missed and payment forfeited, nothing was paid, or rate is 0%)
    next: send_notification
  - id: check_expiry_enabled
    type: decision
    label: credit_expiry_enabled on the branch's policy?
    branches:
      - condition: "yes"
        next: set_expiry
      - condition: "no"
        next: set_no_expiry
  - id: set_expiry
    type: action
    label: expires_at = now() + credit_expiry_days
    next: call_issue_credit
  - id: set_no_expiry
    type: action
    label: expires_at = null (never expires)
    next: call_issue_credit
  - id: call_issue_credit
    type: action
    label: "Call issue_credit() DB function (atomic: upsert credit_balances + insert issuance credit_transactions row); cancellation_log_id is null when the log write failed (#117 - issuance is not gated on the log)"
    next: check_issue_result
  - id: check_issue_result
    type: decision
    label: issue_credit() returned a transaction row?
    branches:
      - condition: "no"
        next: issuance_failed
      - condition: "yes"
        next: patch_log
  - id: issuance_failed
    type: action
    label: Credit issuance failed (cancellation_logs.credit_issued stays false, best-effort, never re-thrown)
    next: send_notification
  - id: patch_log
    type: action
    label: "If a cancellation_logs row exists, patch it: credit_issued = true, credit_amount = creditAmount (best-effort)"
    next: send_notification
  - id: send_notification
    type: action
    label: Send booking-cancelled notification (reports the issued credit amount if any, else none)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Booking cancelled — credit issued, forfeited, or not applicable
---

# M10 · Cancellation-to-Credit Conversion

Machine-readable companion to
[[M10-01-cancellation-to-credit-conversion|the human-readable version]] in
`Library/golden-fur/workflows/`.
