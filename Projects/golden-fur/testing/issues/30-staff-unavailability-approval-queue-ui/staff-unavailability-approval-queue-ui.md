# Issue #30 Verification: Unavailability Block approval queue UI (Admin/Supervisor/Superadmin)

**Issue:** #30 — feat(staff): Unavailability Block approval queue UI (Admin/Supervisor/Superadmin)
**Owner:** James
**Originally planned branch:** `feat/staff-unavailability-approval-queue-ui`
**Actual branch (bundled Jul 12, 2026):** `feat/staff-unavailability-approval-bundle-28-30` — Issues #28, #29, and #30 were bundled into a single branch/PR going forward to save review overhead; this doc still covers #30 in isolation.
**Base:** `dev`
**Depends on:** #25, #26, #29 merged (same bundle for #29)
**Sprint:** Sprint 1 — M01 Staff Auth & Access Control

## Overview

Adds a page where Admin, Supervisor, or Superadmin can see every pending Unavailability Block request at their branch(es) and approve or deny each one, using Issue #29's `GET /staff/unavailability/pending` and `PATCH .../review` endpoints.

**Deviation from the original Affected Files list (reconciled during implementation):** the Guide's dev notes say to "parameterize [`AdminStaffListPage`'s guard] with the allowed-roles list or use a separate guard," implying a reusable guard component exists. It doesn't — Issue #26's own verification doc already flagged this: `AdminStaffListPage` has no separate guard component, it resolves the viewer's own role inline (via a `GET /staff/:id` call for their own id, since the Supabase session carries no app-level role claim) and redirects with `<Navigate>` directly in the page. `UnavailabilityApprovalQueuePage` follows that same established in-page pattern — `getStaffProfile(user.id, accessToken)` to learn the viewer's role, then gate against `{'Admin', 'Supervisor', 'Superadmin'}` — rather than introducing a new guard abstraction that doesn't match how the rest of this feature area works.

The Guide's Affected Files list also includes `client/src/routes.tsx` as **modified**; it isn't. `client/src/routes.tsx` only composes `staffRoutes` (`{staffRoutes}`), and the new route is registered inside `client/src/features/staff/staff.routes.ts` itself — no change to `routes.tsx` was needed.

## What Changed

- **Added** `client/src/features/staff/pages/UnavailabilityApprovalQueuePage/UnavailabilityApprovalQueuePage.tsx` (+ `.module.css`, `.spec.ts`) — the queue page. Resolves the viewer's role, redirects non-Admin/Supervisor/Superadmin to `/staff/profile`, loads pending requests, renders one `UnavailabilityReviewCard` per request, and does optimistic removal on approve/deny with rollback (reload) on failure.
- **Added** `client/src/features/staff/components/review/UnavailabilityReviewCard/UnavailabilityReviewCard.tsx` (+ `.module.css`, `.spec.ts`) — one card per pending request: requester photo/name/role, requested window, optional reason, and Approve/Deny actions. Deny opens an inline optional-reason field before confirming. When `reviewable: false` (the viewer's own pending request), renders read-only with an explanatory note instead of Approve/Deny.
- **Modified** `client/src/features/staff/staff.routes.ts` — registers `/staff/admin/unavailability` inside the existing `StaffAuthGuard`-wrapped route group (alongside `/staff/profile` and `/staff/admin/staff`).
- **Modified** `client/src/features/staff/pages/AdminStaffListPage/AdminStaffListPage.tsx` (+ `.module.css`, `.spec.ts`) — adds a link to the new page with a pending-count badge (fetched via `listPendingUnavailabilityRequests`, includes the viewer's own non-reviewable request in the count per the Guide's Jul 11 note, since it's still useful to know it exists).

Client-side `staff.types.ts`, `api/staff.api.ts` (+ spec), and `modules/validators/staff.validator.ts` were already updated as part of Issue #29 in this bundle (they mirror the server types/endpoints); this issue only adds the UI that consumes them.

### Why Supervisor can reach this page but not `AdminStaffListPage`

`AdminStaffListPage`'s guard is `{'Admin', 'Superadmin'}` (Issue #26, unchanged). `UnavailabilityApprovalQueuePage`'s guard is `{'Admin', 'Supervisor', 'Superadmin'}` — deliberately wider, since Issue #28/#29 grant Supervisor the same on-behalf-of and review powers as Admin. A Supervisor has no entry point via `AdminStaffListPage` (they're redirected away from it) and must navigate to `/staff/admin/unavailability` directly.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix client test -- --run
npx tsc -b --project client
npm --prefix client run lint
```

Expected: all client test files pass (new specs for `UnavailabilityApprovalQueuePage` and `UnavailabilityReviewCard`, plus the extended `AdminStaffListPage.spec.ts`), `tsc -b` produces no output, `eslint .` reports 0 errors.

## Structural Verification

1. Confirm the new files exist:

   ```powershell
   Get-ChildItem client/src/features/staff/pages/UnavailabilityApprovalQueuePage
   Get-ChildItem client/src/features/staff/components/review/UnavailabilityReviewCard
   ```

2. Confirm the route is registered:

   ```powershell
   Select-String -Path client/src/features/staff/staff.routes.ts -Pattern "unavailability"
   ```

## Manual Browser Verification

This is the primary way to verify a UI issue — the automated tests above cover the component logic in isolation, but not the real page rendering against a live server. You'll need three staff accounts already seeded in your Supabase project: a **Superadmin**, an **Admin** (or Supervisor), and a **Groomer** (or any non-manager role) — reuse accounts from earlier issues' verification if you still have them noted down. You'll also need at least one **pending** unavailability request to review; if you don't have one, create it first (step 0 below).

### 0. Start both servers

Open two PowerShell terminals from the repo root:

```powershell
# Terminal 1
npm --prefix server run dev
```

```powershell
# Terminal 2
npm --prefix client run dev
```

The client will print a local URL (typically `http://localhost:5173`). Open it in your browser.

### 1. Create a pending request to review

1. Log in at `/staff/login` as the **Groomer** (or any non-Admin/Supervisor/Superadmin) account.
2. Go to your staff profile page and use whatever custom-range unavailability form is available there (the self-service form from Issue #24/#25), submitting a **custom start/end range** (not the "quick action" button — quick-action auto-approves and won't appear in the queue).
3. Log out.

### 2. AC-1: role gating

1. Log in as the **Groomer** again and navigate directly to `/staff/admin/unavailability` in the address bar.
   **Expected:** immediately redirected to `/staff/profile` — the page never flashes visible content.
2. Log out, log in as the **Admin** (or Supervisor), and navigate to `/staff/admin/unavailability`.
   **Expected:** the "Unavailability Approval Queue" page loads.

### 3. AC-2: the pending list renders

**Expected:** the Groomer's request from step 1 appears as a card, showing their name, role badge, the requested time window, and (if provided) the reason. Approve and Deny buttons are visible since this isn't the viewer's own request.

### 4. AC-3: Approve

1. Click **Approve** on the card.
   **Expected:** the card disappears from the list immediately (optimistic removal); no error banner appears.
2. Refresh the page.
   **Expected:** the card stays gone (it's no longer `pending`, so it no longer appears in the queue).

### 5. AC-4: Deny with a reason

1. Repeat step 1 above to create a second pending request from the Groomer account.
2. As the Admin/Supervisor, click **Deny** on the new card.
   **Expected:** an inline reason field appears with **Confirm deny** / **Cancel** buttons.
3. Type a reason (e.g. "Short staffed that day") and click **Confirm deny**.
   **Expected:** the card disappears from the list; no error banner appears.

### 6. AC-5: stale-request error handling

This simulates someone else reviewing the same request first (#29 AC-6's `404`).

1. Create a third pending request from the Groomer account (repeat step 1).
2. Open the approval queue page in **two browser tabs**, both logged in as the Admin/Supervisor.
3. In Tab 1, click Approve on the card — it disappears.
4. In Tab 2 (which still shows the now-already-reviewed card because it hasn't refreshed), click Approve on the same card.
   **Expected:** an error banner appears (e.g. "Unavailability block not found or not pending") and the list reloads — the stale card is gone after the reload, not stuck in a broken state.

### 7. AC-7 & AC-8: self-request is read-only, never triggers the self-review error

1. While still logged in as the Admin/Supervisor, use their own staff profile page to submit a **custom-range** self-request (same as step 1, but from the Admin/Supervisor's own account).
2. Reload `/staff/admin/unavailability`.
   **Expected:** a card for this request appears, showing the pending status and a note like "Awaiting review from another Admin, Supervisor, or Superadmin" — **no Approve/Deny buttons are rendered on it.**
3. Confirm there is no way to click an action on this specific card (visually distinct from the other cards, which do have buttons). This is what AC-8 means by "never rendered in a state where clicking them would hit `cannot_review_own_request`" — the button simply isn't there to click, by construction, not disabled-and-visible.
4. Cleanup: cancel this self-request from the profile page (or leave it — it's harmless test data, just remember it's there if you re-run this check later).

### 8. AC-6: branch scoping

Needs a **Superadmin** account and at least one pending request at a _different_ branch than the Admin/Supervisor used above (create one via a Groomer account at that other branch, same as step 1).

1. Log in as the Admin/Supervisor from steps 2–7. Confirm the queue shows only their own branch's pending requests (no branch filter dropdown is visible for them).
2. Log out, log in as the **Superadmin**, and navigate to `/staff/admin/unavailability`.
   **Expected:** a **Branch** filter dropdown appears (only shown when there's more than one branch among the pending requests); with "All branches" selected, pending requests from both branches are visible. Selecting a specific branch filters the list to just that branch.

### 9. Entry point from AdminStaffListPage (Admin/Superadmin only)

1. Log in as the Admin (or Superadmin) and go to `/staff/admin/staff`.
   **Expected:** an "Unavailability approval queue" link appears near the top of the page, with a small badge showing the current pending count (if any requests are pending — the badge is omitted at zero).
2. Click the link.
   **Expected:** navigates to `/staff/admin/unavailability`.
3. Log in as a Supervisor and go to `/staff/admin/staff` directly.
   **Expected:** redirected away (Issue #26's existing Admin/Superadmin-only guard, unchanged) — confirming Supervisor's only entry point to the queue is the direct URL, as the dev notes describe.

## Acceptance Criteria Checklist

- [x] **AC-1:** Reachable by Admin, Supervisor, Superadmin; all other roles redirected — unit test `AC-1: redirects a non-Admin/Supervisor/Superadmin viewer...`, `AC-1 & AC-2: a Supervisor viewer sees the pending queue`; manual step 2.
- [x] **AC-2:** Lists every pending request at the caller's branch(es) via `GET /staff/unavailability/pending`, one `UnavailabilityReviewCard` per request — manual step 3.
- [x] **AC-3:** Approve calls `PATCH .../review` with `{ decision: 'approved' }` and removes the card on success — unit test `AC-3: clicking Approve calls the review API and removes the card`; manual step 4.
- [x] **AC-4:** Deny opens a reason field; confirming calls `PATCH .../review` with `{ decision: 'denied', denial_reason }` and removes the card on success — component unit tests in `UnavailabilityReviewCard.spec.ts`; manual step 5.
- [x] **AC-5:** A request already reviewed by someone else shows a clear error and refreshes the list rather than failing silently — manual step 6 (two-tab race).
- [x] **AC-6:** Superadmin can view across both branches or filter to one; Admin/Supervisor see only their own branch with no switch — manual step 8.
- [x] **AC-7:** A card for the viewer's own pending request renders without Approve/Deny, showing pending status and a note — unit test `#30 AC-7: renders read-only with no Approve/Deny for a non-reviewable block`, `#30 AC-7: a non-reviewable card...`; manual step 7.
- [x] **AC-8:** Approve/Deny are never rendered where clicking them would hit `cannot_review_own_request` — same tests/step as AC-7 (the buttons are structurally absent for non-reviewable cards, not disabled).
