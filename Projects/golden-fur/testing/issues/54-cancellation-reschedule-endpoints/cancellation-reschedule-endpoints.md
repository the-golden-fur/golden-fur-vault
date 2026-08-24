# Issue #54 Verification: cancellation/reschedule endpoints + notice-period check stub

**Issue:** #54 — feat(booking): cancellation/reschedule endpoints + notice-period check stub
**Owner:** Matthew
**Branch:** `feat/cancellation-reschedule-endpoints`
**Base:** `dev`
**Depends on:** #51, #52 merged
**Sprint:** Sprint 2 — M03 Appointment & Booking

## Overview

`POST /bookings/:id/reschedule` and `POST /bookings/:id/cancel`, both reading the `policy_configurations` stub (#52) for a notice-period check: `notice_enforcement_enabled` off skips the check entirely; on, Strict blocks an unmet reschedule outright while Soft allows it but flags `policy_violation: true` in the response (no `cancellation_logs` table exists yet to persist it — Sprint 5). A cancellation is **never blocked** by notice — per the M03 Process 5 flow diagram, the booking always moves to Cancelled; what the notice outcome decides is the (Sprint 5) financial consequence, reported here as `notice_period_met`/`policy_violation` for the future credit-issuance hook to read.

Reschedule updates `scheduled_start`/`scheduled_end`/`assigned_staff_id` **in place** on the same `bookings` row and increments `reschedule_count`; it re-runs the relevant capacity check (via #51's `capacity.service.ts`) for the new slot, and both endpoints call #53's `veterinaryEligibility.service.ts` guard when a reschedule changes `branch_id`.

## What Changed

- **Added** `server/src/features/booking/services/reschedule.service.ts` (+spec):
  - `evaluateNoticePeriod(branchId, scheduledStart)` — shared by both services; measures notice against the booking's **current** `scheduled_start`.
  - `loadBookingForChange(...)` — ownership check (owning customer or any authenticated staff member, AC-6); the server runs on the service-role client, so this application-layer check is the actual enforcement (RLS additionally scopes direct customer table access).
  - `rescheduleBooking(...)` — Strict/Soft/disabled branching, #53 guard on branch change, capacity re-check excluding the booking's own row (via the #49 RPC's new `p_exclude_booking_id` param), staff re-resolution (keeps the current assignee if still eligible, else falls back like "No preference").
- **Added** `server/src/features/booking/services/cancellation.service.ts` (+spec) — sets `status = 'Cancelled'`, `cancelled_at`, `cancellation_reason`; explicitly writes **no** credit balance anywhere (`TODO(Sprint 5, M09/M10)` comment at the exact point credit issuance would trigger).
- **Modified** `booking.routes.ts` / `booking.controller.ts` — registers both endpoints (customer-or-staff, jwt only; ownership enforced in the service).
- **Modified** `tests/booking.integration.spec.ts` — HTTP-level coverage for both endpoints.

### Design note — no fee logic

Guide dev notes are explicit that reschedule-fee calculation is out of scope for this stub (the `policy_configurations` columns for it don't exist). A met-or-Soft reschedule simply proceeds; `reschedule_count` increments so Sprint 5's fee logic has data to read, but nothing here computes a fee amount.

## Acceptance Criteria Map

| AC                                                                 | Automated                                                                                      | Postman                             |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- | ----------------------------------- |
| AC-1 notice met → reschedule succeeds, schedule updated in place   | `reschedule.service.spec.ts`, integration spec                                                 | request 4                           |
| AC-2 Strict + notice unmet → rejected, names the requirement       | spec + integration spec                                                                        | request 3                           |
| AC-3 Soft + notice unmet → succeeds with `policy_violation: true`  | spec                                                                                           | request 5 (mode-switch via Postman) |
| AC-4 enforcement disabled → any timing allowed                     | spec (reschedule + cancellation)                                                               | request 6                           |
| AC-5 cancellation sets status/cancelled_at/reason; no credit write | `cancellation.service.spec.ts` (asserts `credit_balances`/`credit_transactions` never touched) | request 7                           |
| AC-6 only owner or staff can reschedule/cancel                     | spec + integration spec                                                                        | request 8                           |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Postman Verification

Needs one **customer** account with a pet, one **Admin** account (to flip the enforcement mode/toggle), and: `branch_makati_id`, `pet_id`, `daycare_service_id` from Supabase Studio.

1. Import `cancellation-reschedule-endpoints.postman_collection.json` → fill collection variables → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login customer** / **Login Admin** → 200 each.
   2. **Create a Daycare booking ~10 days out** → 201 Confirmed. Captures `booking_id`.
   3. **AC-2 Reschedule to tomorrow (Strict, default)** → **422**, error names "3 day(s) notice" (the seeded default).
   4. **AC-1 Reschedule to +12 days (meets notice)** → **200**; `policy_violation: false`; booking's `scheduled_start` updated; re-`GET /bookings/:id` shows `reschedule_count: 1`.
   5. **Admin: PATCH policy → Soft mode** → 200.
   6. **AC-3 Reschedule to tomorrow again (Soft)** → **200** this time, with `"policy_violation": true`.
   7. **Admin: PATCH policy → disable enforcement** → 200.
   8. **AC-4 Reschedule to tomorrow (enforcement disabled)** → **200**, `policy_violation: false` regardless of timing.
   9. **Admin: PATCH policy → restore Strict + enforcement on** → 200 (cleanup of the shared system-wide row).
   10. **AC-5 Cancel the booking** → **200**; `booking.status = "Cancelled"`, `cancelled_at` set, `notice_period_met` reported. Response contains no credit fields at all.
   11. **AC-6 A second customer attempts to cancel the same booking** → **403** (needs a second customer's token — fill `other_customer_account_email`/`password`).
4. Cleanup: Studio → `bookings` → delete the row from step 2 (it's already Cancelled from step 10, safe to delete or leave as historical data).

## Notes for the reviewer

- `evaluateNoticePeriod` reads the branch's **effective** policy (override-or-default), same resolution `staffPicker.service.ts` uses — a single shared `resolveEffectivePolicy()`.
- Cancelling a `Pending` booking is allowed (treated the same as `Confirmed` for cancel/reschedule eligibility) — only `Cancelled`/`Completed`/`No-show` rows refuse further changes.
