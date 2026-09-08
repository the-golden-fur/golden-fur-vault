---
title: Switching the app's email sending from Resend to Brevo (and stopping it from wasting emails)
date: 2026-09-08
tags: [session-plan, golden-fur]
project: golden-fur
session: 77-resend-to-brevo-email
branch: feat/resend-to-brevo-email
---

# 77 — Switching email sending from Resend to Brevo (and stopping it wasting emails)

## What you asked for

Move every automated email the app sends off one email provider (Resend) and
onto another (Brevo), and while doing that, look for bugs that burn through
Brevo's small daily sending allowance.

> Audit repo to change Resend to Brevo. Optimize all email API features,
> perhaps there's some bugs that drain the 300 email daily limit for Brevo.
> Make sure to capture all email features and change it to Brevo. Update .env
> and .env.example files, remove resend variables. At the end, empty out
> Inbox/, just keep a .gitkeep in it.

## What this part of the app does today

The **server** (the back-end program that the website talks to) sends
automated emails for things like:

- a new staff member's login details ("account created")
- a booking being confirmed, rescheduled, or cancelled
- a payment being confirmed
- an appointment reminder the day before
- a hotel "care update" when a pet's feeding/walk/medication task is done

Every one of those emails is built by a small template file in
`server/src/shared/email/` and then handed to **one** function, `sendEmail`,
which actually delivers it. Until now `sendEmail` lived in `resend.client.ts`
and talked to **Resend** (resend.com), a transactional-email service.

**Brevo** (brevo.com, formerly Sendinblue) is the replacement. Its free plan
sends **300 emails per day** and needs no custom domain — good enough for
development and a small pilot, but easy to exhaust if the app emails too
eagerly.

Admins configure app-wide rules on **Settings → Config → Policies** (the
"Policies" page). Behind the scenes those rules live in one database table,
`policy_configurations`.

## What's wrong / what's missing

1. Nothing in the code talked to Brevo yet — the Brevo SDK (software
   development kit: a ready-made library for calling their API) wasn't even
   installed.
2. Two email flows could burn the 300/day allowance fast:
   - **Multi-booking checkout** (booking several pets/services in one go) sent
     a _separate_ "booking confirmed" email for _each_ booking in the cart.
   - The **hotel care log** emailed the customer on _every single_ completed
     care task. A pet boarding for several days can rack up dozens of tasks.
3. The appointment-reminder job also reminded bookings that were already
   "In Progress" (the pet is already here) — a pointless email.

## What we're going to change

1. **Add a Brevo client and retire Resend.** — _Which files:_ new
   `server/src/shared/email/brevo.client.ts`; the 7 templates in
   `server/src/shared/email/` switch their `import`; `resend.client.ts`, the
   `resend` npm package, and every `RESEND_*` setting in `.env.example` /
   `render.yaml` / `docs/deployment.md` are removed. — _Why:_ `brevo.client.ts`
   exposes the exact same `sendEmail({ to, subject, html })` shape, so the
   templates barely change. Automatic retries are turned off so a failed send
   (including hitting the 300/day cap) never silently retries and wastes more.
2. **One combined email for a multi-booking checkout.** — _Which files:_ new
   `bookingGroupConfirmedEmail.ts`; `bookingNotifications.service.ts`,
   `bookingGroup.service.ts`, `booking.service.ts`. — _Why:_ one "your N
   bookings are confirmed" email instead of N near-identical ones. An admin
   can switch back to one-per-booking with the new
   `booking_group_email_mode` policy setting. The in-app bell notification is
   still one per booking.
3. **Per-task care emails become opt-in; add a nightly summary.** — _Which
   files:_ new `careLogDailyReportEmail.ts` + `careLogDailyReport.job.ts`;
   `careLogNotifications.service.ts`; new database table
   `care_log_daily_reports`. — _Why:_ per-task email is off by default (the
   in-app notification still fires); instead one summary email per hotel stay
   goes out each evening listing that day's completed / missed / still-open
   tasks. Both are admin-toggleable.
4. **Appointment reminders only for `Pending` bookings.** — _Which files:_
   `appointmentReminder.job.ts`. — _Why:_ an already-checked-in booking
   doesn't need a "see you soon" email.
5. **Surface the 3 new settings on the Policies page.** — _Which files:_
   `client/src/features/booking/pages/PolicyConfigurationPage/`.
6. **Empty `Inbox/` in the vault** — done on the vault branch
   `chore/brevo-session-and-inbox`.

## Words you might not know

- **transactional email** — an automated email triggered by one user's action
  (a receipt, a confirmation), as opposed to a marketing blast.
- **SDK** — "software development kit"; a library the vendor ships so you call
  their service with function calls instead of raw HTTP.
- **migration** — a numbered SQL script that changes the database's shape
  (adds a table or column). They run in order and are never edited once
  merged.
- **RLS (row-level security)** — Postgres rules deciding which rows a given
  logged-in user may read or write. A table with RLS on and no policy = only
  the server's service-role key can touch it.
- **policy_configurations** — the single table holding app-wide admin rules
  (notice periods, lunch break, downpayment, and now the 3 email settings).
- **job / scheduler** — a function the server runs on a timer (e.g. every 15
  minutes, or nightly at 21:00) with no user request involved.
- **claim row / single-writer** — writing a marker row _before_ doing work so
  that if the same job runs twice it can tell "already handled, skip".

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
