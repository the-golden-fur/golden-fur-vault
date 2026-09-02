# Issue #70 Verification: Veterinary console UI — consultation queue, consultation form, pet history tab, follow-up scheduling

**Issue:** #70 — feat(veterinary): Veterinary console UI — consultation queue, consultation form, pet history tab, follow-up scheduling
**Owner:** Alarie
**Branch:** `feat/veterinary-console-ui`
**Base:** `dev`
**Depends on:** #66, #67 merged
**Sprint:** Sprint 3 Epic A — M07 Health & Veterinary Management

## Overview

`VeterinaryConsolePage` at `/staff/veterinary/console` — a single screen with today's consultations grouped by Pending/Ongoing/Completed, a detail panel (consultation form + Pet History tab + follow-up scheduling) for whichever one is selected.

## What Changed

- **Added** `client/src/features/veterinary/veterinary.types.ts`, `client/src/features/veterinary/api/veterinary.api.ts` (+spec) — client mirror of #66/#67's `Consultation`, `listConsultationQueue()`/`updateConsultation()`/`scheduleFollowUp()`/`getPetConsultationHistory()`.
- **Added** `client/src/features/veterinary/components/ConsultationStatusBadge/ConsultationStatusBadge.tsx` (+spec) — Pending/Ongoing/Completed pill using the 3 new `--color-consult-status-*` tokens.
- **Added** `client/src/features/veterinary/components/PetHistoryTab/PetHistoryTab.tsx` (+spec) — read-only list of a pet's prior consultations (diagnosis + medications), reachable from within any consultation.
- **Added** `client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx` (+spec) and its `ConsultationDetailPanel.tsx` (form + tabs + follow-up, kept local to the page rather than a separate top-level component — the Guide's Affected Files name only `PetHistoryTab.tsx` as a standalone component for this issue) — role gate (`Veterinarian`/`Admin`/`Supervisor`/`Superadmin`), queue fetch + 15s poll (same pattern and same reviewer note as #68's Groomer Dashboard), client-side pet/owner name resolution.
- **Added** `client/src/features/veterinary/veterinary.routes.tsx`; **modified** `client/src/routes.tsx` (registers it) and `staffDashboard.config.ts` (Veterinarian dashboard's "Consultation Queue" tile now links to `/staff/veterinary/console`).
- **Added** 9 new `--color-consult-status-*`/`--color-daycare-status-*`/`--color-grooming-status-*`/`--color-followup-indicator-*` tokens to `client/src/styles/tokens.css` (shared across #68/#69/#70 — see `Sprint3-EpicA-Design.xlsx` → Styles).

### Decision flagged for the reviewer: line-item amounts are entered in the same form as billing (mirrors #66's own flag)

The consultation form collects a `professional_fee` and a per-medication/procedure `amount` only when completing (fields are hidden once a consultation is `Completed`, since #66's backend rejects further edits). This mirrors #66's own decision note that no fee schedule exists yet in this system. **Raise with Alarie if a fixed/read-only fee display was actually intended** instead of vet-entered amounts.

### Decision flagged for the reviewer: "the whole visit fits in a single screen"

The Guide's user story frames this as one screen; the implementation is a two-pane layout (grouped queue list + detail panel for the selected consultation) rather than one continuous scroll, so a vet can see the rest of the queue while working a consultation. This still satisfies every AC (queue grouping, form, pet history, follow-up all reachable without navigating to a different route) — **raise with Alarie if a literally single, non-split layout was intended.**

## Acceptance Criteria Map

| AC                                                                                                                                                      | Automated                                                                                                                                              | Manual UI                       |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------- |
| AC-1 console lists today's consultations grouped by Pending/Ongoing/Completed                                                                           | `VeterinaryConsolePage.spec.ts`                                                                                                                        | step D3                         |
| AC-2 consultation form saves vitals/diagnosis/medications/procedures; marking Completed reflects immediately in the queue                               | `VeterinaryConsolePage.spec.ts`                                                                                                                        | step D4                         |
| AC-3 pet history tab shows all previous consultations for the selected pet                                                                              | `PetHistoryTab.spec.ts`, `VeterinaryConsolePage.spec.ts`                                                                                               | step D5                         |
| AC-4 setting a follow-up date creates a pending booking visible to the receptionist and shows the "follow-up scheduled" indicator without a page reload | `VeterinaryConsolePage.spec.ts`                                                                                                                        | step D6                         |
| AC-5 updating vaccination records saves immediately and is visible from the pet profile without navigating away                                         | covered by #66's own `consultation.service.spec.ts` (write-through reuses #33's service); pet-profile visibility not re-verified here — see note below | step D4 (Supabase Studio check) |

**Note on AC-5:** the pet profile's own Vaccination Records section (`PetProfilePage` / `VaccinationRecordList`, M02 #33) is unmodified by this issue — it already reads `pet_vaccination_records` directly, so a row written here appears there the next time that page is viewed. This issue doesn't add a live cross-page refresh; "without navigating away" is verified within the console itself (the vaccination write happens as part of the same Complete Consultation action, with no separate save step or page transition).

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/veterinary
npm --prefix client run lint
npm --prefix client run build
```

Expected: 4 test files / 15 tests pass; lint 0 errors/warnings; `tsc -b && vite build` succeeds with no type errors.

## Manual UI Verification

### Prerequisites

- Server running (`npm --prefix server run dev`) with migrations through `040` pushed.
- Client running (`npm --prefix client run dev`).
- One **Veterinarian** account at Makati (Sprint 1 seed data, `makati.vet1@goldenfur.com` / `password123`).
- A **Confirmed Veterinary booking** at Makati for **today**, assigned to that Veterinarian (create via `/staff/bookings/new`, or reuse #51's booking collection).
- Optional: a second, already-`Completed` consultation for the same pet from an earlier run of #66's Postman collection, to see Pet History populated with more than one entry.

### D. Steps

1. Log in to the staff portal as the Veterinarian. From the dashboard, click **Consultation Queue** (or navigate to `/staff/veterinary/console`).
2. Confirm the pet/owner name for today's booking appears under the **Pending** column (AC-1).
3. Click the row to select it. In the detail panel, click **Start Consultation** → status badge changes to **Ongoing**, and the row moves from Pending to Ongoing in the queue list.
4. Fill in temperature/weight/heart rate/respiratory rate, a diagnosis, add a medication (name/dose/amount) and a procedure (type/description/amount), optionally fill in the vaccination sub-section (vaccine name + date), enter a Professional Fee, then click **Complete Consultation** → status badge changes to **Completed**, the row moves to the Completed column, and the form's editable fields become read-only. In Supabase Studio → Table Editor, confirm `consultation_line_items` has one row per medication/procedure plus the professional fee, and (if a vaccination was entered) `pet_vaccination_records` has a new row for the pet (AC-2, AC-5).
5. Click the **Pet History** tab → the just-completed consultation appears with its diagnosis and medications (and any earlier consultation for the same pet, if seeded) (AC-3).
6. Back on the **Consultation** tab, pick a follow-up date and click **Schedule follow-up** → a **"Follow-up scheduled"** indicator replaces the date picker without a page reload (AC-4). Confirm the new booking is visible to a Receptionist at `/staff/bookings/queue` filtered to `Pending` status.

### E. Cleanup

Supabase Studio → Table Editor → delete the `consultation_line_items` rows, then the `consultations` row, then the follow-up `bookings` row created in step 6, then any `pet_vaccination_records` row created in step 4.
