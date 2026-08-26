---
id: M01-01-staff-account-creation
module: M01
title: Staff Account Creation
actors: [Admin, Superadmin]
trigger: Admin or Superadmin submits new staff details (username, registered_email, role, branch_id)
outcome_success: staff_profiles row + Supabase Auth identity created; temp password delivered via best-effort email + in-app notification
outcome_failure:
  [
    insufficient_permissions,
    username_taken,
    email_taken,
    auth_creation_failed,
    profile_insert_failed,
  ]
related_modules: [M11]
source:
  - server/src/features/staff/services/staffManagement.service.ts
  - server/src/features/staff/staff.controller.ts
  - supabase/migrations/20260625004_m01_create_staff_role_enum.sql
steps:
  - id: start
    type: start
    label: Admin/Superadmin initiates account creation
    next: input_details
  - id: input_details
    type: input
    actor: [Admin, Superadmin]
    label: Enter staff details (username, registered_email, role, branch_id)
    next: check_role
  - id: check_role
    type: decision
    label: Is the actor a Superadmin or Admin?
    branches:
      - condition: "no"
        next: end_blocked_permissions
      - condition: "yes"
        next: check_username
  - id: end_blocked_permissions
    type: end
    result: blocked
    label: Insufficient permissions
  - id: check_username
    type: decision
    label: Is username already taken?
    branches:
      - condition: "yes"
        next: error_username
      - condition: "no"
        next: check_email
  - id: error_username
    type: action
    label: "Show error: username already exists (409)"
    next: input_details
  - id: check_email
    type: decision
    label: Is registered_email already taken?
    branches:
      - condition: "yes"
        next: error_email
      - condition: "no"
        next: assign_role_branch
  - id: error_email
    type: action
    label: "Show error: registered email already exists (409)"
    next: input_details
  - id: assign_role_branch
    type: action
    label: Assign role (staff_role enum) and branch_id
    next: create_auth_user
  - id: create_auth_user
    type: decision
    label: Supabase Auth identity created successfully?
    branches:
      - condition: "no"
        next: end_blocked_auth
      - condition: "yes"
        next: create_profile
  - id: end_blocked_auth
    type: end
    result: blocked
    label: Failed to create staff login (400)
  - id: create_profile
    type: decision
    label: staff_profiles insert succeeded?
    branches:
      - condition: "no"
        next: rollback_auth_user
      - condition: "yes"
        next: encrypt_credential
  - id: rollback_auth_user
    type: action
    label: Delete orphaned Auth user (compensating rollback)
    next: end_blocked_profile
  - id: end_blocked_profile
    type: end
    result: blocked
    label: Failed to create staff profile (400)
  - id: encrypt_credential
    type: action
    label: Encrypt + store temp credential (best-effort, enables later resend)
    next: send_email
  - id: send_email
    type: action
    label: Send account_created email with username + temp password (best-effort)
    next: write_notification
  - id: write_notification
    type: action
    label: Write in-app account_created notification (best-effort)
    next: end_success
  - id: end_success
    type: end
    result: success
    label: Staff account active and ready for first login
---

# M01 · Staff Account Creation

Machine-readable companion to
[[M01-01-staff-account-creation|the human-readable version]] in
`Library/golden-fur/workflows/`.
