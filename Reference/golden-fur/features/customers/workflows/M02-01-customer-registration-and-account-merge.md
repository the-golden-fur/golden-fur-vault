---
id: M02-01-customer-registration-and-account-merge
module: M02
title: Customer Registration, Login & OAuth Account Merge
actors: [Customer]
trigger: A prospective or returning customer signs up with email/password, logs in, or completes a Google/Facebook OAuth flow
outcome_success: customer_profiles row exists (created or merged) and a Supabase Auth session is issued
outcome_failure:
  [
    signup_auth_failed,
    signup_profile_insert_failed,
    login_invalid_credentials,
    login_no_customer_profile,
    oauth_invalid_token,
    oauth_missing_provider_email,
  ]
related_modules: [M01]
source:
  - server/src/features/auth/customers/customerAuth.controller.ts
  - server/src/features/auth/customers/customerAuth.routes.ts
  - server/src/features/auth/customers/customerAuth.types.ts
  - server/src/features/auth/customers/modules/validators/customerAuth.validator.ts
  - server/src/features/auth/customers/services/accountMerge.service.ts
  - server/src/features/auth/customers/services/accountMerge.service.spec.ts
  - server/src/shared/auth/api/supabaseAuth.api.ts
  - supabase/migrations/20260625008_m02_create_customer_profiles.sql
  - supabase/migrations/20260625009_m02_customer_profiles_rls.sql
steps:
  - id: start
    type: start
    label: Customer signs up, logs in, or completes an OAuth redirect
    next: choose_path
  - id: choose_path
    type: decision
    actor: [Customer]
    label: Which entry path?
    branches:
      - condition: signup
        next: input_signup
      - condition: login
        next: input_login
      - condition: oauth
        next: oauth_receive_token
  - id: input_signup
    type: input
    actor: [Customer]
    label: Enter full_name, account_email, password
    next: create_auth_user
  - id: create_auth_user
    type: action
    label: Create Supabase Auth user via admin API (email_confirm true, no confirmation email sent - avoids hosted project's 2/hour email rate limit)
    next: check_auth_created
  - id: check_auth_created
    type: decision
    label: Auth user created successfully?
    branches:
      - condition: "no"
        next: end_signup_auth_failed
      - condition: "yes"
        next: insert_profile
  - id: end_signup_auth_failed
    type: end
    result: error
    label: "Signup failed to create Auth user (400)"
  - id: insert_profile
    type: action
    label: Insert customer_profiles row (id = auth user id, primary_auth_provider = 'email')
    next: check_profile_inserted
  - id: check_profile_inserted
    type: decision
    label: customer_profiles insert succeeded?
    branches:
      - condition: "no"
        next: end_signup_profile_failed
      - condition: "yes"
        next: signin_to_establish_session
  - id: end_signup_profile_failed
    type: end
    result: error
    label: "Signed up but failed to create profile (500) - no compensating rollback of the Auth user, unlike staff account creation"
  - id: signin_to_establish_session
    type: action
    label: admin.createUser returns no session - sign in with the just-set password on a throwaway client to establish one
    next: check_signin_succeeded
  - id: check_signin_succeeded
    type: decision
    label: Sign-in succeeded?
    branches:
      - condition: "no"
        next: end_signup_success_no_session
      - condition: "yes"
        next: end_signup_success_with_session
  - id: end_signup_success_no_session
    type: end
    result: success
    label: "Signup succeeded (201) - user record returned, but no access/refresh tokens; customer must log in separately"
  - id: end_signup_success_with_session
    type: end
    result: success
    label: "Signup succeeded (201) - access_token/refresh_token/expires_in returned immediately"
  - id: input_login
    type: input
    actor: [Customer]
    label: Enter account_email, password
    next: signin_with_password
  - id: signin_with_password
    type: action
    label: signInWithPassword on a throwaway service-role client (never the shared singleton, to avoid downgrading it to a customer session)
    next: check_credentials_valid
  - id: check_credentials_valid
    type: decision
    label: Credentials valid (Supabase Auth session issued)?
    branches:
      - condition: "no"
        next: end_login_invalid_credentials
      - condition: "yes"
        next: check_customer_profile_exists
  - id: end_login_invalid_credentials
    type: end
    result: blocked
    label: "Unauthorized (401)"
  - id: check_customer_profile_exists
    type: decision
    label: Does a customer_profiles row exist for this account_email?
    branches:
      - condition: "no"
        next: end_login_no_profile
      - condition: "yes"
        next: end_login_success
  - id: end_login_no_profile
    type: end
    result: blocked
    label: "Unauthorized (401) - valid Supabase Auth credentials alone aren't enough; staff and customers share the same Auth pool, so a staff member's credentials must not open the customer portal"
  - id: end_login_success
    type: end
    result: success
    label: "Login succeeded (200) - access_token/refresh_token/expires_in returned"
  - id: oauth_receive_token
    type: action
    label: Client completes Google/Facebook redirect and sends the provider access_token in the Authorization header
    next: validate_token
  - id: validate_token
    type: decision
    label: supabase.auth.getUser(token) resolves a valid user?
    branches:
      - condition: "no"
        next: end_oauth_invalid_token
      - condition: "yes"
        next: check_provider_email
  - id: end_oauth_invalid_token
    type: end
    result: blocked
    label: "Invalid token (401)"
  - id: check_provider_email
    type: decision
    label: Does the OAuth identity carry a confirmed email?
    branches:
      - condition: "no"
        next: end_oauth_missing_email
      - condition: "yes"
        next: check_existing_profile
  - id: end_oauth_missing_email
    type: end
    result: blocked
    label: "MissingProviderEmailError (422) - typically an unconfirmed provider-side email, not an app bug"
  - id: check_existing_profile
    type: decision
    label: Does a customer_profiles row already exist matching this account_email?
    branches:
      - condition: "yes (MERGE)"
        next: merge_identity
      - condition: "no (CREATE)"
        next: create_profile_from_oauth
  - id: merge_identity
    type: action
    label: "Update existing profile: set primary_auth_provider to google/facebook; if provider=facebook and a provider_id is present, also set facebook_id (supports a second linked provider on the same account)"
    next: end_oauth_merged
  - id: end_oauth_merged
    type: end
    result: success
    label: "Merged (200) - existing account now also has this OAuth identity linked"
  - id: create_profile_from_oauth
    type: action
    label: Insert new customer_profiles row (id = new auth user id, account_email, full_name from provider metadata or 'Anonymous User' fallback, primary_auth_provider = google/facebook)
    next: end_oauth_created
  - id: end_oauth_created
    type: end
    result: success
    label: "Created (200) - new customer account provisioned from the OAuth identity"
---

# M02 · Customer Registration, Login & OAuth Account Merge

Machine-readable companion to
[[M02-01-customer-registration-and-account-merge|the human-readable version]] in
`Library/golden-fur/features/customers/workflows/`.
