# Reports/notifications proxy fixes + per-event notification preferences

Branch: `feat/sprint6-epicA-notifications-and-reports` (continuation of the already-merged M11 Notification + M14 Report Management work from `Sprint6-EpicA-Guide.docx`).

Type: Custom bug-fix + feature batch, found and requested during manual QA of the just-built Sprint 6 Epic A reports/notifications UI, not sourced from a numbered issue.

## Scope

1. **`GET /reports/{dsr,cage-occupancy,transaction-history}` returning "Request failed. Please try again."** — same root cause class as `16`/`17`'s `/branches`/`/catalog` vite-proxy gaps: `client/vite.config.ts`'s dev-server `proxy` block had no entry for `/reports` (or, separately, `/notifications`), so requests fell through to Vite's own SPA `index.html` instead of reaching Express on port 3000. The response looked like a 200/304 with `Content-Type: text/html` and a small fixed byte count instead of JSON — not a 404/403, which is what made it non-obvious from the Network tab alone.
2. **Notifications bell/portal tab, same bug.** `GET /notifications`, `PATCH /notifications/:id/read`, `PATCH /notifications/read-all` had the identical gap.
3. **Report filter styling.** `DailySalesReportPage`, `CageOccupancyReport`, and `TransactionHistoryTable`'s `<select>`/`<input>` filter controls had no themed class, so they rendered as bare browser-native controls instead of matching the app's `--color-surface`/`--color-border`/`--color-text-primary` look every other page uses (e.g. `QueueFilterBar`'s `.filterSelect`).
4. **Cage occupancy size abbreviations.** `S`/`M`/`L`/`XL` badges/headings now render as Small/Medium/Large/Extra Large (display-only remap — the underlying `size` values are unchanged, since they're also the Hotel module's cage-size enum).
5. **Per-event notification preferences (new, Settings > Preferences).** `Sprint6-EpicA-Guide.docx` explicitly scoped "Notification Preferences (per-channel opt-in/opt-out configuration)" out of the Epic A build ("desirable but scoped as a separate, future Module 11 feature" — see the Guide's Non-Goals). This batch builds that deferred feature: a per-`notification_event_type`, per-channel (email / in-browser) toggle grid, filtered to the event types each role can actually receive, replacing the old single always-on delivery path.
6. **Settings tab restructure.** The `Appearance` tab (theme + font size) is renamed `Preferences` and now also holds the new notification grid — no new tab was added.

## Root cause detail (items 1-2)

`server/src/features/reports/reports.routes.ts` and `server/src/features/notifications/notifications.routes.ts` are both mounted at the server root (`router.use(reportsRoutes)` / `router.use(notificationsRoutes)` in `shared/app.routes.ts`, no prefix) — same pattern as `/branches`, `/catalog`, `/staff`, etc. Every other root-mounted feature has a matching entry in `vite.config.ts`'s `proxy` object; `/reports` and `/notifications` were simply never added when those features were built. Fixed by adding both, following the exact `/catalog`/`/billing` pattern (no `bypass` needed — neither has a colliding bare-path client route; the client pages live under `/staff/reports/...` and the bell/portal tab, not `/reports` or `/notifications` themselves).

## Why the notification-preferences design changed mid-implementation

The first pass stored two flat booleans (`email_notifications_enabled`, `in_browser_notifications_enabled`) directly on `staff_profiles`/`customer_profiles` — migration `20260806102`. That can't express "mute appointment reminders but keep booking-cancellation emails," which is what was actually asked for once the UI mockup came back wanting a per-event-type grid ("booking made, booking reminder, cancellation, etc.") split by role. Migration `20260806103` drops both booleans and replaces them with one `notification_preferences jsonb` column per table, keyed by `notification_event_type`, each value `{ "email": boolean, "in_browser": boolean }`. `102` was pushed to the linked Supabase project and then superseded by `103` minutes later in the same session — both are kept as separate migration files (never squashed) so the history stays honest about what actually happened, matching this repo's established convention of never rewriting a pushed migration in place.

### Which event types are role-relevant (and why there's no Admin/Superadmin-specific set)

Tracing every `createNotification()` call site (`server/src/features/{staff/services/staffManagement,auth/staff/staffAuth.controller,booking/services/bookingNotifications,hotel/services/careLogNotifications,billing/services/checkoutAggregation,notifications/services/appointmentReminder.job}`) shows a clean, code-backed split of the 8 `notification_event_type` values:

- **Staff-facing** (`recipientStaffId`): `account_created`, `password_reset` — fired uniformly for every staff role, including Admin and Superadmin. There is no event type in the current 8-value enum that only fires for a subset of staff roles.
- **Customer-facing** (`recipientCustomerId`): `booking_confirmed`, `booking_rescheduled`, `booking_cancelled`, `payment_confirmed`, `appointment_reminder`, `care_log_completed`.

So `EVENT_TYPES_BY_ROLE` in `NotificationPreferencesGrid.tsx` has exactly two lists (staff, customer) — Admin/Superadmin staff see the same 2-row grid as every other staff role, since fabricating an admin-only row with no real trigger behind it would be dishonest UI. If a future event type is added that's genuinely admin-only, it belongs in a third list at that point, not invented now.

## Migration numbering

```
supabase/migrations/20260806102_shared_add_notification_preference_columns.sql                       (superseded by 103, see above)
supabase/migrations/20260806103_shared_replace_notification_booleans_with_preferences_jsonb.sql       (current schema)
```

Both apply after `20260805101` (the actual latest on this branch) with no gaps. Both have been pushed to the linked Supabase project (`supabase db push`, confirmed by the user before each push since both touch a shared remote database).

## New/changed API surface

- `PATCH /auth/staff/preferences` / `PATCH /auth/customers/preferences` — **unchanged from before this batch** (still just `theme_preference` / `font_size_preference`; the `email_notifications_enabled`/`in_browser_notifications_enabled` fields added then removed during the mid-implementation redesign never shipped on this endpoint).
- `PATCH /staff/notification-preferences` (new) / `PATCH /customers/notification-preferences` (new) — body `{ "event_type": NotificationEventType, "channel": "email" | "in_browser", "enabled": boolean }`. Merges into the caller's own `notification_preferences` jsonb (read-modify-write against the user-scoped Supabase client, RLS-enforced), so one call never clobbers other event types' stored values. Returns `{ "notification_preferences": {...full map...} }`. `400` for an invalid `event_type`, an invalid `channel`, or a non-boolean `enabled`.
- `notification.service.ts#createNotification()` — now reads the recipient's `notification_preferences[event_type]` before doing anything: the `notifications` row is only inserted if `in_browser` is true (so it's the only thing gating whether the row shows up in the bell/portal inbox at all), and the email thunk is only invoked if `email` is true — independently, per event type, per recipient. No call site changed; all gating lives in the one shared write path per the original Issue #97 design intent ("the ONE write path").

## Files changed (high level)

**Migrations**: the 2 listed above.

**Server**: `shared/app.routes.ts` unchanged (proxy fix is client-only); `features/notifications/notifications.types.ts` (`NOTIFICATION_EVENT_TYPES`/`NOTIFICATION_CHANNELS` runtime consts + `NotificationPreferences` type); `features/notifications/services/notification.service.ts` (`getRecipientPreferences` reads jsonb keyed by `event_type`); `features/auth/staff/staffAuth.routes.ts` + `features/auth/customers/customerAuth.routes.ts` (new `staff/customerNotificationPreferencesController` + route).

**Client**: `vite.config.ts` (`/reports`, `/notifications` proxy entries); `features/reports/components/{CageOccupancyReport,TransactionHistoryTable}/*`, `features/reports/pages/DailySalesReportPage/*` (themed `.control` class on filters; size-label map in `CageOccupancyReport.tsx`); `shared/api/preferences.api.ts` (`NotificationPreferences`/`NotificationChannel` types, `getNotificationPreferences`, `updateNotificationPreference`); `shared/providers/ThemeProvider/{themeContext,ThemeProvider}.tsx` (reverted to theme+font-size only — notification state doesn't live here); `shared/components/ToggleSwitch/{ToggleSwitch.tsx,ToggleSwitch.module.css}` (`hideLabel` prop for grid use); new `pages/SettingsPage/tabs/NotificationPreferencesGrid.tsx`; `pages/SettingsPage/tabs/AppearanceTab.tsx` deleted, replaced by new `pages/SettingsPage/tabs/PreferencesTab.tsx`; `pages/SettingsPage/{SettingsPage.tsx,SettingsPage.module.css}` (`appearance` tab renamed `preferences`, grid layout styles).

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **734/734 tests pass** (77 files, unchanged count — no new server spec files were added for this batch; verification was manual/API-level, see below).

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
```

Expected: typecheck clean, **538/538 tests pass** (117 files, unchanged count).

Both confirmed clean as of this revision.

## Manual Verification

You'll need: `server/`/`client/` dev servers running (`npm run dev` from the repo root), the linked Supabase project with migrations `102`-`103` applied, and Postman (or the collection alongside this doc).

### 1. Reports pages load

Visit `/staff/reports/dsr`, `/staff/reports/cage-occupancy`, `/staff/reports/transaction-history` as an Admin/Supervisor/Superadmin (DSR/occupancy) or Admin/Supervisor/Receptionist/Cashier (transaction history). Confirm each loads real data instead of "Request failed. Please try again." — open DevTools Network tab and confirm the request's `Content-Type` is `application/json`, not `text/html`.

### 2. Report filters are themed

On each of the three pages, confirm the filter `<select>`/`<input>` controls have a visible border, themed background, and themed text color matching the rest of the app (not bare browser-default chrome). Toggle Settings > Preferences > Theme between Light/Dark and confirm the filters restyle along with everything else.

### 3. Cage occupancy size labels

On `/staff/reports/cage-occupancy`, confirm the four size cards read "Small", "Medium", "Large", "Extra Large" — not "S"/"M"/"L"/"XL".

### 4. Notification bell/portal tab loads

Open the staff notification bell (navbar) or, as a customer, the Notifications tab on `/portal`. Confirm it loads (even if empty) instead of showing an error.

### 5. Notification preferences grid — staff

Open Settings > Preferences as any staff role. Confirm the tab is labeled "Preferences" (not "Appearance"), and below Theme/Font size there's a "Notifications" section with a 2-row grid: **Account created**, **Password reset requested**, each with an Email and an In-browser toggle switch side by side under column headers. Toggle a few switches and reload — confirm they persisted.

### 6. Notification preferences grid — customer

Open Settings > Preferences as a customer. Confirm a 6-row grid: Booking made, Booking reminder, Booking rescheduled, Booking cancellation, Payment confirmed, Pet care log completed.

### 7. Preferences actually gate delivery

As a staff member, turn off "In-browser" for "Password reset requested" in Settings > Preferences. Trigger `POST /auth/staff/forgot-password` for that account (Postman collection item, or the "Forgot password" link on the staff login page — note Supabase Auth's own 15-second rate limit between requests). Confirm no new row appears in `GET /notifications` for that account. Turn "In-browser" back on and repeat — confirm a row now appears.

### 8. Toggling one event type doesn't affect others

In the grid, toggle one switch (e.g. Email off for Booking cancellation). Reload the page and confirm every other row's toggles are unchanged — the merge-not-replace behavior on `PATCH .../notification-preferences` should never clobber sibling event types.

### Cleanup

```sql
-- Reset a test account's notification preferences back to all-on
update public.staff_profiles
  set notification_preferences = '{
    "account_created": {"email": true, "in_browser": true},
    "password_reset": {"email": true, "in_browser": true},
    "booking_confirmed": {"email": true, "in_browser": true},
    "booking_rescheduled": {"email": true, "in_browser": true},
    "booking_cancelled": {"email": true, "in_browser": true},
    "payment_confirmed": {"email": true, "in_browser": true},
    "appointment_reminder": {"email": true, "in_browser": true},
    "care_log_completed": {"email": true, "in_browser": true}
  }'::jsonb
  where registered_email = 'makati.superadmin1@goldenfur.com';

-- Remove any password_reset test notifications created during manual verification
delete from public.notifications
  where event_type = 'password_reset'
  and recipient_staff_id = (
    select id from public.staff_profiles where registered_email = 'makati.superadmin1@goldenfur.com'
  );
```

## Open Items

- **The notification-preferences UI has no "mute all" shortcut** — each of the (up to) 8 event types must be toggled individually per channel. Not requested; flagging in case a future pass wants a header-row "select all" control.
- **`account_created` and `password_reset` remain the only staff-facing event types.** If a future feature introduces an event that only fires for a specific staff role (e.g. an Admin-only low-stock alert), `EVENT_TYPES_BY_ROLE` in `NotificationPreferencesGrid.tsx` will need a third, role-scoped list rather than the current flat `staff`/`customer` split.
