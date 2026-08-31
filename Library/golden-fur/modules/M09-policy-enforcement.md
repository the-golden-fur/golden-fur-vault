---
title: "M09 · Policy Enforcement"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M09 · Policy Enforcement

**Layer:** Back-office
**Code:** lives inside `features/booking` (client + server) — `GET`/`PATCH /bookings/policy`, `cancellation_logs`
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The system's rules engine: evaluates whether business policies are
followed at a booking-change event (cancellation, reschedule) and
determines the consequence. Exposes a Policy Configuration panel to
Admin/Superadmin.

## Policy Configuration

Configurable per branch (or system-wide as a default row):

- **Notice period enforcement** — minimum notice before a
  cancellation/reschedule qualifies for credit (default 3 days).
  Strict (blocks the action) or Soft (allows it, flags the violation,
  withholds credit); can be disabled entirely.
- **Downpayment** — `downpayment_enabled`/`downpayment_type`
  (`'Flat'`/`'Percentage'`)/`downpayment_amount`, resolved the same
  default-row-plus-per-branch-override way as every other policy field.
  Applies once to the whole booking transaction (every selected
  service/package together, any category) at creation time — not a
  per-catalog-item flag. This replaced an earlier per-service/package
  `requires_downpayment` mechanism ([[M13-maintenance-packages-services-promos|M13]]
  used to own this), which itself had replaced the original branch-level
  `downpayment_percentage` column (dropped for being unwired dead code).
  A downpayment-flagged booking is no longer restricted to a single
  service/package — that restriction only ever existed because the old
  mechanism computed the amount per item.
- **Reschedule fee** — flat or percentage, with a configurable
  free-reschedule allowance (unlimited by default). Calculated and
  stored on the booking at reschedule time, logged on
  `cancellation_logs` — not yet posted as a billable line item at
  checkout (see [[M08-sales-billing|M08]]).
- **Credit expiry** — default 30 days from issuance, toggleable; backed
  by `credit_expiry_days`/`credit_expiry_enabled` and an
  `expire_credits()` sweep ([[M10-credit-balance-management|M10]]).
- **Staff Picker visibility** — show/hide the customer-facing Staff
  Picker per branch, per service type.
- **Online payments** — `online_payments_enabled` toggle (default on),
  gates the customer self-service payment path ([[M08-sales-billing|M08]]).
- **Lunch break** — enabled/disabled plus start/end time (default
  12:00–13:00). Enforced by `get_staff_availability()` and the Slot
  Picker ([[M03-appointment-booking|M03]]).

A dedicated Policies admin page (Settings > Config > Policies,
Admin/Superadmin) covers all of the above via `GET`/`PATCH
/bookings/policy`. Staff Picker (and Cage Picker) visibility has a
second, global per-service-type layer on the Service Types page
([[M13-maintenance-packages-services-promos|M13]]) — precedence between the two is unconfirmed.

## Cancellation policy

A cancelled booking's downpayment converts to a credit balance if the
notice period was met; otherwise it's forfeited without credit issuance.
This reads the booking's own snapshotted `downpayment_amount` (set at
creation time from the effective per-transaction downpayment policy
above), not just Hotel — the check is a generalized "positive
downpayment_amount" test, with no category-specific logic. A cancellation
log is created regardless, and if that log write itself fails, credit
issuance is skipped even for an otherwise-qualifying cancellation — see
[[M09-01-cancellation-notice-credit-decision|M09-01]]'s Notes for detail.

Client-side, both cancel entry points (the customer's My Bookings list
and the Receptionist Bookings Queue) route the action through an explicit
`ConfirmDialog` modal — a full-screen backdrop with an "Are you sure you
want to cancel this booking?" prompt and the optional reason field. The
`DELETE`/cancel call fires only from that dialog's confirm button, so a
stray or double click on a row's "Cancel" button just opens the dialog.

## Rescheduling policy

The configured notice period is validated on reschedule and, depending
on enforcement mode, blocks or flags the request; a reschedule fee is
calculated/stored if enabled and the free allowance is exhausted. The
Bookings Queue's Reschedule button mirrors this evaluation
(`evaluateNoticePeriod`) rather than always rendering ([[M03-appointment-booking|M03]]).

## No-show handling

If a booking's scheduled time passes while still Pending, it's marked
No-show via the lazy, read-time transition ([[M03-appointment-booking|M03]]). No credit is
issued for a no-show, downpayment or otherwise.

## Cancellation & reschedule logging

Every event writes to `cancellation_logs` (`event_type`,
`notice_period_met`, `enforcement_mode_applied`, `policy_violation`,
`credit_issued`, `credit_amount`, `reschedule_fee_charged`, `notes`),
visible on Admin/Supervisor dashboards regardless of outcome. This
table, [[M10-credit-balance-management|M10]], and [[M11-notification|M11]] did not actually exist in the database
before 2026-08-05 — earlier design docs described them as already
"Merged" ahead of the schema actually shipping.

## Workflows

- [[M09-01-cancellation-notice-credit-decision|Cancellation Notice-Period Check & Credit Conversion]]
- [[M09-02-reschedule-notice-fee-decision|Reschedule Notice-Period Enforcement & Fee Calculation]]

## Relationship to other modules

Triggered by cancellation/reschedule events in [[M03-appointment-booking|M03]]. Posts credit
records to [[M10-credit-balance-management|M10]]. Reschedule fee amounts are logged here but not yet
posted to [[M08-sales-billing|M08]]. Policy Configuration (including lunch break, online
payments, and downpayment) is read by [[M01-staff-authentication-access-control|M01]], M03, and M08 — downpayment specifically by
`createBooking` ([[M03-appointment-booking|M03]]) and the customer booking flow's amount preview.
