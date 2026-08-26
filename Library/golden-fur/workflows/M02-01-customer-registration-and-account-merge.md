---
title: "M02 · Customer Registration, Login & OAuth Account Merge"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M02
---

# M02 · Customer Registration, Login & OAuth Account Merge

**Actors:** Customer
**Code:** `server/src/features/auth/customers/customerAuth.controller.ts`,
`server/src/features/auth/customers/services/accountMerge.service.ts`
**Part of:** [[M02-customer-portal-pet-management|M02 · Customer Portal & Pet Management]]

A customer reaches the portal one of three ways — self-registering with
email + password, logging back in with existing credentials, or completing
a Google/Facebook OAuth redirect. All three end with a `customer_profiles`
row in place and a Supabase Auth session issued; the OAuth path additionally
has to decide whether it's looking at a brand-new customer or an existing
one signing in with a second identity provider.

```mermaid
flowchart TD
    A(["START: Customer signs up, logs in,\nor completes an OAuth redirect"]) --> B{"Which entry path?"}

    B -- "Signup" --> C["Enter full_name, account_email, password"]
    C --> D["Create Supabase Auth user via admin API\n(email_confirm=true, no confirmation\nemail - avoids hosted rate limit)"]
    D --> E{"Auth user created\nsuccessfully?"}
    E -- "No" --> F(["END: Blocked — failed to create Auth user"])
    E -- "Yes" --> G["Insert customer_profiles row\n(id = auth user id,\nprimary_auth_provider = 'email')"]
    G --> H{"Profile insert\nsucceeded?"}
    H -- "No" --> I(["END: Signed up, but profile\ncreation failed (no rollback)"])
    H -- "Yes" --> J["Sign in with the just-set password\non a throwaway client to establish\na session (admin.createUser returns none)"]
    J --> K{"Sign-in\nsucceeded?"}
    K -- "No" --> L(["END: Signup succeeded —\nno session, must log in separately"])
    K -- "Yes" --> M(["END: Signup succeeded —\naccess/refresh tokens returned"])

    B -- "Login" --> N["Enter account_email, password"]
    N --> O["signInWithPassword on a throwaway\nservice-role client (never the shared\nsingleton)"]
    O --> P{"Credentials valid?"}
    P -- "No" --> Q(["END: Blocked — Unauthorized"])
    P -- "Yes" --> R{"customer_profiles row\nexists for this email?"}
    R -- "No" --> S(["END: Blocked — Unauthorized\n(valid Auth creds alone aren't enough;\nstaff share the same Auth pool)"])
    R -- "Yes" --> T(["END: Login succeeded —\naccess/refresh tokens returned"])

    B -- "OAuth" --> U["Client sends the provider access_token\nin the Authorization header"]
    U --> V{"supabase.auth.getUser(token)\nresolves a valid user?"}
    V -- "No" --> W(["END: Blocked — invalid token"])
    V -- "Yes" --> X{"Does the identity carry\na confirmed email?"}
    X -- "No" --> Y(["END: Blocked — missing provider email"])
    X -- "Yes" --> Z{"Existing customer_profiles row\nmatches this email?"}
    Z -- "Yes (MERGE)" --> AA["Update primary_auth_provider;\nif Facebook + provider_id present,\nalso set facebook_id"]
    AA --> AB(["END: Merged — existing account\nnow linked to this identity too"])
    Z -- "No (CREATE)" --> AC["Insert new customer_profiles row\n(id = new auth user id, full_name\nfrom provider metadata or fallback)"]
    AC --> AD(["END: Created — new customer\naccount provisioned from OAuth"])
```

## Notes

- Signup uses the Supabase **admin** `createUser` API rather than
  `auth.signUp`, deliberately, so no confirmation email is sent — the
  hosted project's email rate limit (2/hour) would otherwise fail most
  signups with a 400.
- If the `customer_profiles` insert fails after the Auth user was already
  created, there is **no compensating rollback** here — unlike staff
  account creation ([[M01-01-staff-account-creation|M01]]), which deletes
  the orphaned Auth user on a failed profile insert. A failed customer
  signup can leave a login-capable Auth user with no profile row.
- Login intentionally checks for a matching `customer_profiles` row _in
  addition to_ a valid Supabase Auth session — staff and customers are
  issued from the same Auth pool, so without this check a staff member's
  email/password would also open the customer portal.
- `sign in with password` never runs on the shared service-role `supabase`
  singleton — a dedicated throwaway client is created per call, because
  `signInWithPassword` mutates the calling client's internal session state
  and would otherwise silently downgrade every later request on the
  process to that one customer's RLS-restricted session.
- The OAuth merge/create decision is keyed purely on **email match** —
  `mergeOrCreate` looks up `customer_profiles.account_email`, not any
  provider-specific id. A Facebook login updates `facebook_id` on top of
  whatever provider created the account originally, so one customer can
  end up with both a Google-created profile and a linked Facebook
  identity.
- `MissingProviderEmailError` (422) is a distinct, actionable error class —
  it means the OAuth provider itself never handed Supabase a confirmed
  email for that identity, not an application bug.

## Relationship to other modules

Customer sessions have no inactivity timeout, unlike staff sessions in
[[M01-staff-authentication-access-control|M01]].
