# Issue #13 Verification: Role-tiered inactivity session timeouts

**Issue:** #13 — refactor(server): role-tiered inactivity session timeouts
**Branch:** `refactor/role-tiered-session-timeouts`
**Sprint:** Sprint 1 — Epic A-1

## Overview

This issue adds server-side session enforcement for staff users based on their role. The middleware reads the authenticated staff member's role from `staff_profiles` and applies the matching inactivity threshold:

- Superadmin/Admin: 30 minutes
- Supervisor: 60 minutes
- Receptionist/Cashier: 4 hours
- Groomer/Veterinarian/Pet Assistant: 8 hours

Customer sessions are skipped by design because customer JWTs are not enforced server-side for inactivity.

---

## Verification Steps

### Step 1: Run the server tests

From the repository root:

```bash
cd server
npm test
```

Expected result:

- All server Vitest suites pass
- The new session timeout middleware spec passes

### Step 2: Review the middleware behavior

The implementation lives at:

```text
server/src/shared/middleware/sessionTimeout/sessionTimeout.middleware.ts
```

It should:

- read the authenticated user's `sub` and `auth_time`
- look up the staff role in `staff_profiles`
- enforce the threshold for staff roles listed above
- skip customer-style requests when no matching staff profile is found

### Step 3: Validate the acceptance criteria manually

Use the following checks against the middleware logic or a test harness:

- Superadmin/Admin roles time out after 30 minutes of inactivity
- Supervisor roles time out after 60 minutes of inactivity
- Receptionist/Cashier roles time out after 4 hours of inactivity
- Groomer/Veterinarian/Pet Assistant roles time out after 8 hours of inactivity
- Customer-style sessions are not rejected by the middleware

### Step 4: Confirm the implementation details

Pass criteria:

- The middleware uses `staff_profiles.role` to determine the timeout
- The timeout values match the issue specification
- The middleware returns `401` with an inactivity-related message when expired
- The middleware calls `next()` for non-staff or still-active sessions

---

## Acceptance Criteria Checklist

- [x] **AC-1:** Superadmin and Admin roles are logged out after 30 minutes of inactivity
- [x] **AC-2:** Supervisor role is logged out after 60 minutes of inactivity
- [x] **AC-3:** Receptionist and Cashier roles are logged out after 4 hours of inactivity
- [x] **AC-4:** Groomer, Veterinarian, and Pet Assistant roles are logged out after 8 hours of inactivity
- [x] **AC-5:** Customer sessions have no server-side inactivity timeout
- [x] **AC-6:** Timeout middleware reads the authenticated staff member's role from `staff_profiles` to determine the applicable threshold
