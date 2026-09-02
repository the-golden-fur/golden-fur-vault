# Issue #80 Verification: Care log checklist UI + supervisor/admin flagging dashboard

**Issue:** #80 — feat(hotel): Care log checklist UI + supervisor/admin flagging dashboard
**Owner:** James
**Branch:** `feat/hotel-care-log-ui`
**Base:** `dev`
**Depends on:** #76, #77 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

`CareLogChecklist` — pet-assistant-facing daily checklist, one row per scheduled care action for today with a **Mark complete** button; read-only otherwise (no edit affordance for the underlying instructions at all). `UncompletedCareFlagPanel` — supervisor/admin view of end-of-day uncompleted entries, reusing Sprint 3's `--color-followup-indicator-*` tokens.

### Decision flagged for the reviewer: a new `HotelCareLogPage` route host was added

The Guide's Directory Structure lists both components but **no page file** to host them. `StaffDashboardPage`'s tiles are pure navigation links (confirmed by reading `StaffDashboardPage.tsx` — tiles render nothing inline), so a routed page is required for either component to be reachable at all. `client/src/features/hotel/pages/HotelCareLogPage/HotelCareLogPage.tsx` was added at `/staff/hotel/care-log` to fill this gap: Pet Assistant sees `CareLogChecklist`; Admin/Supervisor/Superadmin see `UncompletedCareFlagPanel` (the two audiences never need both views at once, so one route serves both rather than splitting into two near-empty pages). **Raise with Alarie/James if the intended design instead embeds these directly into an existing page** (e.g. inline on `StaffDashboardPage` itself, which would be a larger change to that shared page's rendering model).

### Decision flagged for the reviewer: completed_by display name via a new server-side join

Neither #76 nor #74 originally surfaced who completed an entry by name (`care_log_entries.completed_by` is a bare UUID). #76's `getTodayCareLogEntries()` (added for this endpoint, see #76's verification doc) was extended to join `staff_profiles(display_name)` as `completed_by_staff`, rather than doing N client-side lookups — a smaller, more contained change than adding a bulk staff-lookup endpoint. `CareLogEntry.completed_by_staff` is only populated by this one query.

## What Changed

- **Added** `client/src/features/hotel/components/CareLogChecklist/CareLogChecklist.tsx` (+CSS module) — fetches `GET /hotel/care-log/today`, one `Mark complete` button per uncompleted row, shows `completed_by_staff.display_name` + timestamp once done, updates in place (no reload) via local state merge on a successful PATCH.
- **Added** `client/src/features/hotel/components/UncompletedCareFlagPanel/UncompletedCareFlagPanel.tsx` (+CSS module) — fetches `GET /hotel/care-log/flagged`, renders using the reused `--color-followup-indicator-*` tokens.
- **Added** `client/src/features/hotel/pages/HotelCareLogPage/HotelCareLogPage.tsx` (+CSS module) — role-gated host page (see decision above).
- **Modified** `client/src/features/staff/config/staffDashboard.config.ts` — Pet Assistant's "Care Log" tile and a new "Hotel Care Log" tile for Admin/Supervisor now link to `/staff/hotel/care-log`.

## Acceptance Criteria Map

| AC                                                                                                                         | Automated                                                                 | Manual UI |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------- |
| AC-1 checklist shows each scheduled action for today with a mark-complete button; no instruction-edit affordance           | manual — no edit UI exists in `CareLogChecklist.tsx` at all               | step D3   |
| AC-2 marking complete updates immediately without reload; shows completing staff name + timestamp                          | `hotel.api.spec.ts` (`completeCareLogEntry`)                              | step D4   |
| AC-3 uncompleted end-of-day entries highlighted on supervisor/admin dashboard, scoped to own branch (Superadmin sees both) | backend `careLogFlagging.service.spec.ts`                                 | step D5   |
| AC-4 flag panel uses the reused `--color-followup-indicator-*` tokens, not a new color                                     | manual — `UncompletedCareFlagPanel.module.css` reads only that token pair | step D5   |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/hotel
npm --prefix client run lint
npx tsc -b --noEmit
```

## Manual UI Verification

### Prerequisites

- Server + client running, migrations through `053` pushed.
- A checked-in Hotel stay with at least one `care_log_entries` row scheduled for today (#75), plus one back-dated (yesterday) uncompleted row for the flag panel (Supabase Studio, same setup as #77's verification doc).
- One **Pet Assistant** account and one **Admin** account, same branch.

### D. Steps

1. Log in as the Pet Assistant.
2. From the staff dashboard, click **Care Log** (or navigate to `/staff/hotel/care-log`).
3. Confirm each scheduled entry appears with its description and a **Mark complete** button, and that there is no way to edit the underlying feeding/walking/medication details from this screen (AC-1).
4. Click **Mark complete** on one entry — confirm it immediately shows "Done by \<your name\> at \<time\>" without a page reload (AC-2).
5. Log out, log in as the Admin, navigate to `/staff/hotel/care-log` — confirm the back-dated uncompleted entry appears in the flag panel, styled with the amber follow-up-indicator colors (not a new color) (AC-3, AC-4).

### E. Cleanup

Supabase Studio → delete the test `care_log_entries` / `hotel_stays` rows created above.
