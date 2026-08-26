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
- **Downpayment** — no longer configured here; it's a per-item catalog
  flag ([[M13-maintenance-packages-services-promos|M13]]). The old branch-level `downpayment_percentage`
  column was dropped.
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

A cancelled Hotel booking's downpayment converts to a credit balance if
the notice period was met; otherwise it's forfeited without credit
issuance. A cancellation log is created regardless.

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

## Relationship to other modules

Triggered by cancellation/reschedule events in [[M03-appointment-booking|M03]]. Posts credit
records to [[M10-credit-balance-management|M10]]. Reschedule fee amounts are logged here but not yet
posted to [[M08-sales-billing|M08]]. Policy Configuration (including lunch break, online
payments) is read by [[M01-staff-authentication-access-control|M01]], M03, and M08. Downpayment rules now live in
[[M13-maintenance-packages-services-promos|M13]].
