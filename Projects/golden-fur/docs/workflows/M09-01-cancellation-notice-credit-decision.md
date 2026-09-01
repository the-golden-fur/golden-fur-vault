---
id: M09-01-cancellation-notice-credit-decision
module: M09
title: Cancellation Notice-Period Check & Credit Conversion
actors: [Customer, Staff]
trigger: Customer or staff member cancels a Pending or In Progress booking (POST /bookings/:id/cancel)
outcome_success: booking.status = Cancelled; a cancellation_logs row is always written (best-effort); when it qualifies, a configurable share (cancellation_credit_conversion_rate, default 100%) of the amount the customer actually paid converts to a credit_balances increment, otherwise it is forfeited
outcome_failure: [forbidden, booking_not_cancellable]
related_modules: [M03, M08, M10, M11]
source:
  - server/src/features/booking/services/cancellation.service.ts
  - server/src/features/booking/services/cancellationLog.service.ts
  - server/src/features/booking/services/reschedule.service.ts
  - server/src/features/booking/services/staffPicker.service.ts
  - server/src/features/booking/services/bookingNotifications.service.ts
  - server/src/features/booking/booking.controller.ts
  - server/src/features/booking/booking.routes.ts
  - server/src/features/booking/booking.types.ts
  - server/src/features/booking/modules/validators/booking.validator.ts
  - server/src/features/credits/services/creditIssuance.service.ts
  - supabase/migrations/20260805095_m09_create_cancellation_logs_schema.sql
  - supabase/migrations/20260718037_m03_policy_configurations_stub.sql
  - supabase/migrations/20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql
  - supabase/migrations/20260808111_m03_m08_bookings_downpayment_generalize.sql
  - supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql
  - supabase/migrations/20260731068_m08_create_transactions_schema.sql
steps:
  - id: start
    type: start
    label: Customer or staff member requests cancellation of a booking
    next: input_reason
  - id: input_reason
    type: input
    actor: [Customer, Staff]
    label: Submit cancellation_reason (optional, trimmed non-empty if provided)
    next: check_ownership
  - id: check_ownership
    type: decision
    label: Is requester the owning customer, or an authenticated staff member? (loadBookingForChange)
    branches:
      - condition: "no"
        next: end_forbidden
      - condition: "yes"
        next: check_status
  - id: end_forbidden
    type: end
    result: blocked
    label: Forbidden (403)
  - id: check_status
    type: decision
    label: Is booking.status Pending or In Progress? (CANCELLABLE_BOOKING_STATUSES)
    branches:
      - condition: "no"
        next: end_not_cancellable
      - condition: "yes"
        next: check_enforcement_enabled
  - id: end_not_cancellable
    type: end
    result: blocked
    label: "A <status> booking cannot be cancelled (409)"
  - id: check_enforcement_enabled
    type: decision
    label: Is the branch's effective policy.notice_enforcement_enabled true? (resolveEffectivePolicy, evaluateNoticePeriod)
    branches:
      - condition: "no"
        next: update_status
      - condition: "yes"
        next: check_notice_period
  - id: check_notice_period
    type: decision
    label: "scheduled_start minus now >= notice_period_days?"
    branches:
      - condition: "yes (met)"
        next: update_status
      - condition: "no (not met)"
        next: update_status
  - id: update_status
    type: action
    label: Set status=Cancelled, cancelled_at=now, cancellation_reason (cancellation proceeds regardless of notice outcome or enforcement mode — unlike reschedule, notice never blocks a cancellation)
    next: write_log
  - id: write_log
    type: action
    label: Write cancellation_logs row (event_type=cancellation, notice_period_met, enforcement_mode_applied, policy_violation=enforced AND NOT met; credit_issued starts false) — best-effort, swallows its own failure and returns null
    next: compute_credit_amount
  - id: compute_credit_amount
    type: action
    label: "confirmedAmountPaid = SUM(total_amount) of the booking's transactions where transaction_type='booking_payment' AND payment_status != 'Pending' (NOT bookings.payment_stage); creditAmount = round2(confirmedAmountPaid * policy.cancellation_credit_conversion_rate / 100)"
    next: check_credit_qualifies
  - id: check_credit_qualifies
    type: decision
    label: notice_period_met = true AND creditAmount > 0? (NOT gated on the log write succeeding — #117)
    branches:
      - condition: "no"
        next: send_notification
      - condition: "yes"
        next: issue_credit
  - id: issue_credit
    type: action
    label: Call issue_credit() Postgres RPC (atomic credit_balances increment + credit_transactions row); p_amount = creditAmount; p_cancellation_log_id may be null; expires_at computed from credit_expiry_enabled/credit_expiry_days
    next: check_credit_issued
  - id: check_credit_issued
    type: decision
    label: Did issue_credit() return a transaction row?
    branches:
      - condition: "no"
        next: send_notification
      - condition: "yes"
        next: mark_log_credit_issued
  - id: mark_log_credit_issued
    type: action
    label: If a cancellation_logs row exists, patch it (credit_issued=true, credit_amount=creditAmount)
    next: send_notification
  - id: send_notification
    type: action
    label: Send booking_cancelled notification (in-app + email, best-effort) reporting notice_period_met, policy_violation, and credit amount if issued
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Booking Cancelled; notice_period_met, policy_violation, and credit_issued returned to caller
---

# M09 · Cancellation Notice-Period Check & Credit Conversion

Machine-readable companion to
[[M09-01-cancellation-notice-credit-decision|the human-readable version]] in
`Library/golden-fur/workflows/`.
