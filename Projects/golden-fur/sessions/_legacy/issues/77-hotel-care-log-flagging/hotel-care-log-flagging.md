# Issue #77 Verification: end-of-day uncompleted care log flagging

**Issue:** #77 — feat(hotel): end-of-day uncompleted care log flagging
**Owner:** Matthew
**Branch:** `feat/hotel-care-log-flagging`
**Base:** `dev`
**Depends on:** #75 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

`GET /hotel/care-log/flagged` — surfaces every `care_log_entries` row for an **active** stay whose `scheduled_date <= today` and `completed_at IS NULL`. Per the Guide's own dev notes, "flagged" is a **read/query concern, not a persisted column** — computed at query time, not stored, so a late completion after this endpoint was called simply stops matching on the next call; nothing needs to be kept in sync. That also means **no background scheduler exists for this issue** — despite the Guide framing it as "scheduled per branch operating hours," nothing here is ever written, so there is nothing to schedule. The per-branch-operating-hours framing is satisfied by the caller passing the branch-local "today" (client computes/display; server currently uses server-local date — see Notes), not by a cron job. This is a deliberate scope simplification, flagged here rather than silently built as a real job.

## What Changed

- **Added** `server/src/features/hotel/services/careLogFlagging.service.ts` (+spec) — `getFlaggedCareLogEntries({ branchId, today })`.
- **Modified** `server/src/features/hotel/hotel.routes.ts`, `hotel.controller.ts` — added `GET /hotel/care-log/flagged`, scoped to the caller's own branch (Admin/Supervisor) or unscoped (Superadmin, `branchId: null`).

## Acceptance Criteria Map

| AC                                                                                                     | Automated                                                                      | Postman       |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ | ------------- |
| AC-1 correctly identifies active-stay entries whose scheduled_date has passed and completed_at is NULL | `careLogFlagging.service.spec.ts`                                              | request 3     |
| AC-2 scoped to the caller's own branch for Admin/Supervisor; Superadmin sees across branches           | `careLogFlagging.service.spec.ts`                                              | requests 3, 4 |
| AC-3 a late completion is reflected correctly - no longer flagged once completed                       | manual test below                                                              | request 5     |
| AC-4 no notification/escalation fires as a result of flagging                                          | code inspection — `careLogFlagging.service.ts` has no event-firing call at all | —             |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Postman Verification

### Prerequisites

- A checked-in Hotel stay (#75) with at least one uncompleted `care_log_entries` row whose `scheduled_date` is **today or earlier** — the seeded row from #75's Postman flow already qualifies once today has "passed" its own scheduled_date; to test immediately without waiting, manually back-date one row's `scheduled_date` to yesterday via Supabase Studio.
- One **Admin** or **Supervisor** account, and one **Superadmin** account (optional, for AC-2's cross-branch check).

### A. Import and configure

1. Postman → **Import** → `testing/docs/issues/77-hotel-care-log-flagging/hotel-care-log-flagging.postman_collection.json`.
2. Fill `base_url`, `admin_email`/`admin_password`, `care_log_entry_id` (the back-dated row).

### B. Run requests 1→5

1. **Login Admin** → 200, token captured.
2. **Back-date reminder** — manually confirm in Supabase Studio that `care_log_entry_id`'s `scheduled_date` is in the past and `completed_at` is `NULL`.
3. **AC-1/AC-2 GET flagged** → 200; `care_log_entry_id` appears in `entries`, scoped to the Admin's own branch.
4. **AC-2 cross-branch check (optional)** — repeat with a Superadmin token; entries from both branches may appear.
5. **AC-3 complete the entry, then re-check** — `PATCH /hotel/care-log-entry/:id/complete` (#76), then re-run request 3: the entry must no longer appear.

## Notes

- **Deviation from the Guide flagged above:** no real per-branch-operating-hours scheduled job exists for this issue — the query is a pure, on-demand read (see Overview). If a genuine "auto-refresh the supervisor dashboard at end of day" requirement is confirmed later, it can be layered on top of this same query without a schema change, since nothing is persisted.
- `today` is currently computed server-side as `new Date().toISOString().slice(0, 10)` (server-local/UTC date), not per-branch timezone — matching the simplification above. A future revision could accept `today` as a query param if per-branch-timezone precision at the exact midnight boundary becomes a real requirement.
