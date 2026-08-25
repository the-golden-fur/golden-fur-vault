---
title: "M11 · Notification"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M11 · Notification

**Layer:** Back-office
**Code:** `features/notifications` (dispatch, preferences), `features/messaging` (provider integration) — client + server
**Part of:** [[Architecture|Golden Fur — System Architecture]]

Purely reactive: 8 event types — `account_created`, `password_reset`,
`booking_confirmed`, `booking_rescheduled`, `payment_confirmed`,
`appointment_reminder`, `booking_cancelled`, `care_log_completed` —
across email and in-app, delivered non-blockingly via an external
provider. `booking_confirmed` fires at booking creation (Pending).
`payment_confirmed` fires specifically from the cashier checkout flow —
a customer's own self-service online payment ([[M08-sales-billing|M08]]) doesn't
currently trigger it the same way a cashier-recorded payment does. This
schema didn't exist in the database before 2026-08-05.

## Notification preferences

`staff_profiles` and `customer_profiles` each carry a
`notification_preferences` `jsonb` column keyed by event type, storing
an `{email, in_browser}` pair per type (all `true` by default). Every
dispatch checks the recipient's own preference for that event before
writing the in-app row or sending mail, so muting one event type
doesn't affect the rest. Managed from Settings > Preferences ([[M01-staff-authentication-access-control|M01]]/
[[M02-customer-portal-pet-management|M02]]) via a grid, one row per event type the viewer's role can receive.

## Appointment reminders

Moved from a single fixed daily 8 AM batch job to a 15-minute polling
sweep over a 3-day lookahead, firing each booking's reminder at
`scheduled_start` minus the customer's own configurable lead time
(15 min / 1 hr / 3 hr / 1 day / 2 days — default 1 day, matching the old
fixed behavior). `bookings.reminder_sent_at` is a dedupe marker, claimed
with a single-writer conditional update so a reminder is never sent
twice.

## Relationship to other modules

Depends on [[M01-staff-authentication-access-control|M01]], [[M02-customer-portal-pet-management|M02]], [[M03-appointment-booking|M03]], [[M05-pet-hotel-boarding-management|M05]], [[M08-sales-billing|M08]], and
[[M09-policy-enforcement|M09]] as event sources.
