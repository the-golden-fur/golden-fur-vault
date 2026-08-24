-- Manual verification / cleanup helpers for
-- 26-reports-notifications-fixes-and-preferences. Run against the linked
-- Supabase project (migrations 20260806102-103 must already be applied).

-- 1. Inspect a staff/customer account's current notification preferences.
select id, registered_email, notification_preferences
from public.staff_profiles
where registered_email = 'makati.superadmin1@goldenfur.com';

select id, email, notification_preferences
from public.customer_profiles
where email = '<customer email here>';

-- 2. Mute one event type + one channel directly (bypasses the API, useful
-- for confirming createNotification() actually reads this column without
-- going through the PATCH endpoint first).
update public.staff_profiles
  set notification_preferences = jsonb_set(
    notification_preferences,
    '{password_reset,in_browser}',
    'false'
  )
  where registered_email = 'makati.superadmin1@goldenfur.com';

-- 3. Reset a test account's notification preferences back to all-on.
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

update public.customer_profiles
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
  where email = '<customer email here>';

-- 4. Remove any test notifications created while exercising the
-- forgot-password -> createNotification() gating path manually.
delete from public.notifications
  where event_type = 'password_reset'
  and recipient_staff_id = (
    select id from public.staff_profiles
    where registered_email = 'makati.superadmin1@goldenfur.com'
  );
