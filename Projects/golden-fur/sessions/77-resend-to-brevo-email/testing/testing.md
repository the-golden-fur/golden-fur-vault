# Resend → Brevo transactional-email migration, plus email-quota fixes

Branch: `feat/resend-to-brevo-email` (golden-fur) · `chore/brevo-session-and-inbox` (golden-fur-vault, for the session record + Inbox cleanup)

## The request, verbatim

> Audit repo to change Resend to Brevo. Optimize all email API features,
> perhaps there's some bugs that drain the 300 email daily limit for Brevo.
> Make sure to capture all email features and change it to Brevo. … update
> .env and .env.example files, remove resend variables. … at the end, empty
> out Inbox/, just keep a .gitkeep in it.

Setup context: `Inbox/Golden-Fur-Brevo-Setup-Guide.docx` (Brevo already
verified a sender `The Golden Fur <thegoldenfur.dev@gmail.com>` and issued a
**dev-only** API key; prod key later). Dev key copied into `server/.env`
(git-ignored) — `Inbox/brevo-api-keys.txt` then deleted.

## Root cause / Context

`server/src/shared/email/resend.client.ts` was the single delivery path for
all transactional email, talking to Resend. The migration adds
`brevo.client.ts` with the identical `sendEmail({ to, subject, html })`
export so the seven templates only swap an import line.

Two behaviours were established quota drains against Brevo's 300/day free cap:

- multi-booking checkout fired one `booking_confirmed` email **per sub-booking**;
- the hotel care log fired one email **per completed care-log task**.

The `@getbrevo/brevo` SDK is now at v6 (a full rewrite — `new BrevoClient({apiKey})`
→ `client.transactionalEmails.sendTransacEmail({sender,to,subject,htmlContent})`),
not the `TransactionalEmailsApi` shape the setup guide's snippet assumed; the
client wrapper is written against v6 and pins `maxRetries: 0` so a failed send
(including a `429` at the daily cap) never silently retries into the quota.

## What changed

### Database

- `supabase/migrations/20260908181_custom_policy_configurations_email_behavior.sql`
  — adds `booking_group_email_mode text NOT NULL DEFAULT 'combined'
CHECK (in ('combined','per_booking'))`, `care_log_task_email_enabled bool
NOT NULL DEFAULT false`, `care_log_daily_report_enabled bool NOT NULL
DEFAULT true` to `policy_configurations`. Column defaults seed every
  existing row (default + branch overrides).
- `supabase/migrations/20260908182_m05_create_care_log_daily_reports.sql`
  — new `care_log_daily_reports (stay_id, report_date, sent_at, PK
(stay_id, report_date))`, FK to `stays` `ON DELETE CASCADE`, RLS enabled
  with no policy (service-role only). The nightly job's dedupe ledger.

### Server

- **`shared/email/brevo.client.ts`** (new) — lazy cached `BrevoClient`
  singleton reading `BREVO_API_KEY` at call time; `maxRetries: 0`; parses
  `BREVO_FROM_EMAIL` (`"Name <addr>"`) into a Brevo `sender`; wraps SDK
  failures as `Failed to send email via Brevo: …`. `resend.client.ts`
  deleted; `resend` uninstalled, `@getbrevo/brevo` added.
- **7 email templates** (`accountCreatedEmail`, `appointmentReminderEmail`,
  `bookingCancelledEmail`, `bookingConfirmedEmail`, `bookingRescheduledEmail`,
  `careLogCompletedEmail`, `paymentConfirmedEmail`) — import swapped to
  `./brevo.client.ts`. No other change.
- **`shared/email/bookingGroupConfirmedEmail.ts`** (new) — one email listing
  every booking in a multi-booking checkout (pet, category, date/time, staff).
- **`shared/email/careLogDailyReportEmail.ts`** (new) — one nightly per-stay
  summary, tasks bucketed Completed / Missed / Still scheduled.
- **`features/notifications/services/notification.service.ts`** — new exported
  `isEmailNotificationEnabled({recipient…, eventType})` so the two senders
  that don't route through `createNotification`'s own email thunk still honour
  the recipient's Settings → Preferences opt-out.
- **`features/booking/services/bookingNotifications.service.ts`** —
  `sendBookingConfirmedNotification(booking, { skipEmail })`; new
  `sendCombinedBookingGroupConfirmedEmail(customerId, branchId, bookings)`
  (single email, gated on the customer's `booking_confirmed` email pref).
- **`features/booking/services/bookingGroup.service.ts`** — step 11 resolves
  `booking_group_email_mode`; `combined` → per-member in-app rows with
  `skipEmail`, then one combined email; `per_booking` → unchanged.
- **`features/booking/services/booking.service.ts`** —
  `applyFirstBookingPaymentSideEffects` gains `suppressConfirmationEmail`;
  `recomputeBookingGroupPaymentStatus` collects the newly-confirmed members
  and sends one combined email in `combined` mode.
- **`features/hotel/services/careLogNotifications.service.ts`** — the
  per-task email thunk is only attached when
  `resolveEffectivePolicy(branchId).care_log_task_email_enabled` is true
  (default false). In-app row unchanged.
- **`features/notifications/services/careLogDailyReport.job.ts`** (new) —
  hourly poll; `shouldRunAt(now)` gates the batch to `getHours() >= 21` (server
  time). For each Active Hotel stay whose branch has
  `care_log_daily_report_enabled`: claim `(stay_id, today)` in
  `care_log_daily_reports` (`upsert … ignoreDuplicates`), then send one summary
  gated on the customer's `care_log_completed` email pref (event type reused —
  no new `notification_event_type` enum value). Later ticks the same evening
  (or after a restart) are cheap no-ops for already-claimed stays. Wired into
  `app.ts` alongside the two existing schedulers.
- **`features/notifications/services/appointmentReminder.job.ts`** — reminder
  query is now `.eq('status', 'Pending')` (was `.in(['Pending','In Progress'])`).
- **`features/booking/booking.types.ts`**, **`services/staffPicker.service.ts`**
  (`DOCUMENTED_DEFAULTS` + `updatePolicyConfiguration` baseline),
  **`modules/validators/booking.validator.ts`** — the 3 new policy fields
  threaded through `EffectivePolicy` / `PolicyConfiguration` / the PATCH
  schema.
- Comments naming "Resend" updated to "Brevo" across
  `notification.service.ts`, `notifications.types.ts`,
  `staffManagement.service.ts`, `resendAccountEmail.service.ts`,
  `staffAuth.controller.ts` (server) and `staff.api.ts` +
  `CreateStaffAccountForm.tsx` (client). The `resendAccountEmail` /
  `ResendEmailButton` _feature_ keeps its "re-send" name — unrelated to the
  provider.

### Client

- **`features/booking/booking.types.ts`** — 3 new fields on
  `PolicyConfiguration` / `EffectivePolicy` / `UpdatePolicyPayload`.
- **`features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`**
  — new "Customer email notifications" section: a "Bundled checkout
  confirmation email" select (Combined / One per booking) and two checkboxes
  ("Email … as each hotel care task is completed" — off by default; "Send a
  nightly care summary for each hotel stay" — on by default).

### Config / docs

- `server/.env.example` — Resend block replaced with a Brevo block
  (`BREVO_API_KEY`, `BREVO_FROM_EMAIL`).
- `server/.env` (git-ignored) — real dev `BREVO_API_KEY` +
  `BREVO_FROM_EMAIL=The Golden Fur <thegoldenfur.dev@gmail.com>`; `RESEND_*`
  removed.
- `render.yaml`, `docs/deployment.md` — `RESEND_*` rows → `BREVO_*`.

## Manual test — step by step

### Pre-flight

1. Push the two new migrations to the **dev** Supabase project:
   in a terminal, from the `golden-fur` folder, first confirm you are NOT
   pointed at production — open `supabase/.temp/project-ref` and check it
   reads `hikgijuipymfghfuyrjv` (dev), not `gtqncxqsofqtzrlgxdfm` (prod).
   Then run `npx supabase db push`. It should report the two
   `20260908181` / `20260908182` files applied.
2. Confirm `server/.env` has `BREVO_API_KEY=xkeysib-…` and
   `BREVO_FROM_EMAIL=The Golden Fur <thegoldenfur.dev@gmail.com>`.
3. Start the servers (check ports first): from `server/` run `npm run dev`
   (Express on `:3000`); from `client/` run `npm run dev` (Vite on `:5173`).

### Scenario A — a real email actually sends via Brevo

1. Open `http://localhost:5173`. Click **Staff Login** (top-right). Sign in as
   a Superadmin or Admin from the seed data. You land on **Dashboard**.
2. Go to **Staff** (sidebar) → **Add staff account**. Fill the form with a
   **real inbox you can check** as the email, pick any role/branch, submit.
   You should see a success message with a temporary password.
3. Check that inbox within a minute — a "Welcome to Golden Fur" email arrives
   (check spam the first time; the sender is a Gmail address, not a verified
   domain).
4. In the Brevo dashboard → **Transactional** → **Email Activity / Logs**, the
   send shows as delivered.
   _Failure looks like:_ a `Failed to send email via Brevo: …` line in the
   `server/` terminal → the API key, sender, or payload is wrong.

### Scenario B — combined vs per-booking confirmation email

1. As an Admin, open **Settings** (gear/top-right) → **Config** → **Policies**.
   Scroll to **Customer email notifications**. Confirm **Bundled checkout
   confirmation email** shows **One combined email for the whole checkout**.
2. As a customer (or receptionist "New booking"), book **two pets** in one
   checkout for the same branch and pay. Only **one** email arrives ("2
   bookings confirmed"), but the bell (top bar) shows **two** "Booking
   confirmed" notifications.
3. Back on **Policies**, switch the select to **One email per booking**,
   **Save policy configuration**. Repeat the 2-pet checkout → now **two**
   emails arrive.

### Scenario C — hotel care emails

1. On **Policies → Customer email notifications**, leave **Email the customer
   as each hotel care task is completed** _unchecked_. Save.
2. Check in a hotel stay, open its **Boarding Checklist**, mark a feeding task
   **Completed**. The customer gets an in-app "Care update" notification but
   **no email**.
3. Check the box, Save, complete another task → an email now arrives per task.
4. Nightly summary: with **Send a nightly care summary …** checked (default),
   the `careLogDailyReport` job polls hourly and runs the batch once the
   server clock passes 21:00. To test without waiting, temporarily lower
   `RUN_HOUR` in
   `server/src/features/notifications/services/careLogDailyReport.job.ts` and
   restart the server, or call `runCareLogDailyReportJob(new Date())` from a
   scratch script. The customer gets one email per active hotel stay listing
   that day's Completed / Missed / Still-scheduled tasks. Running it a second
   time the same day sends nothing (the `care_log_daily_reports` claim row
   already exists).

### Scenario D — appointment reminder skips In-Progress bookings

Covered by unit tests (`appointmentReminder.job.spec.ts` — "only considers
Pending bookings"); no manual step needed.

### Vault

`Inbox/` now contains only `.gitkeep`.

## Test suites

Run this session (machine under load — client suite was run with
`--maxWorkers=2` to avoid flaky timeouts):

- `server`: `npm run test` — **1023/1023 passing (93 files)**; `npx tsc
--noEmit` clean; `npm run build` (esbuild) clean; `npm run lint` — 0 errors
  (33 pre-existing `no-console` warnings, unchanged).
- `client`: `npm run test:run` — **787/787 passing (153 files)**; `npx tsc
--noEmit` clean; `npm run build` (tsc + vite) clean; `npm run lint` clean.
- `npm run format:check` (root) — clean.

New test files: `brevo.client.spec.ts` (4), `careLogDailyReport.job.spec.ts`
(6), `careLogNotifications.service.spec.ts` (2), plus 3 added cases in
`bookingGroup.service.spec.ts` and `appointmentReminder.job.spec.ts`.

## Open items

- **No isolated regression test** for the pre-PR review Finding 1 fix (the
  `updated.payment_status !== 'Pending'` guard in
  `recomputeBookingGroupPaymentStatus`) — that function has no unit-test
  scaffold and is mocked wholesale by every consumer; the guard mirrors the
  already-tested `applyFirstBookingPaymentSideEffects` send condition. See
  `reviews/2026-09-08-1132-pre-pr.md`.
- **Production Brevo API key** not issued yet — `BREVO_API_KEY` stays unset on
  Render until then; email-triggering flows error there, which is expected
  (documented in `render.yaml` / `docs/deployment.md`), same posture Resend
  had.
- **`supabase db push`** to the dev project is a manual closing step (see
  Pre-flight #1) — not yet run at the time this record was written.
- The setup guide's `brevo.client.ts` snippet targets the old
  `@getbrevo/brevo` API; the guide could be refreshed if kept, but it has
  been removed from `Inbox/` per the request.
