# 38 - Superadmin dashboard widgets

Adds an at-a-glance widget row to the Superadmin's own dashboard landing
page (`/staff/dashboard/admin`, `StaffDashboardPage.tsx`) - three separate
widgets, each reusing an existing report endpoint (no new API routes or DB
objects). Follow-up to #37 (branch revenue comparison chart), which is now
also embedded here as one of the three widgets.

## What changed

`StaffDashboardPage` is shared by every staff role (keyed by
`ROLE_TO_DASHBOARD_SLUG`), and Admin shares the same `'admin'` slug as
Superadmin. The widgets are gated on the **actual role being `Superadmin`**,
not on the slug - an Admin visiting `/staff/dashboard/admin` still sees only
the plain welcome message, exactly as before this change.

Three new widgets, shown only to a Superadmin viewer, in a responsive grid
below the welcome message:

1. **Cage Availability** (`CageAvailabilityWidget`) - available-cage counts
   for Makati and Southwoods, named separately. Calls the existing
   `GET /reports/cage-occupancy` once per branch (it has no
   both-branches-broken-down-by-branch mode) and sums each branch's
   `Available`-status rows across all cage sizes.
2. **Recent Transactions** (`RecentTransactionsWidget`) - the 5 most recent
   transactions across both branches (date, branch, description, amount),
   with a "View all" link to the existing full Transaction History page.
   Calls the existing `GET /reports/transaction-history` unfiltered (all
   branches, all time) and slices the newest 5 client-side - the endpoint
   has no `limit` param and is already sorted newest-first server-side.
3. **Makati vs Southwoods Revenue** (`BranchRevenueComparisonChart`, from
   #37) - reused as-is, defaulted to the **Today** time filter for this
   dashboard placement (the full Analytics Dashboard page still lets you
   pick any time period).

**Files:**
`client/src/features/reports/components/CageAvailabilityWidget/*` (new),
`client/src/features/reports/components/RecentTransactionsWidget/*` (new),
`client/src/features/staff/pages/StaffDashboardPage/StaffDashboardPage.tsx`
(role tracking + branch loading + widget grid),
`client/src/features/staff/pages/StaffDashboardPage/StaffDashboardPage.module.css`
(`.widgets` grid), `client/src/features/staff/pages/StaffDashboardPage/StaffDashboardPage.spec.ts`
(2 new tests: widgets show for Superadmin, stay hidden for Admin).

## Verify manually

1. Start the app and log in as a **Superadmin** staff account.
2. Land on (or navigate to) `/staff/dashboard/admin` - the page you get
   right after login/clicking the logo.
3. Below "Welcome back, ...!", confirm three cards in a row (or stacked on
   a narrow window):
   - **Cage Availability** - two rows, "Makati" and "Southwoods", each with
     an "N available" count.
   - **Recent Transactions** - up to 5 rows (date, branch, description,
     amount), newest first, plus a "View all" link.
   - **Makati vs Southwoods Revenue** - the same pie chart from #37, scoped
     to **today**.
4. Click **View all** on the Recent Transactions widget - confirm it
   navigates to `/staff/reports/transaction-history` (the existing full
   page).
5. Cross-check the Cage Availability numbers against **Staff → Reports →
   Cage Occupancy**, picking each branch one at a time and summing its
   "Available" badges per size - should match the widget's counts exactly.
6. Cross-check the Recent Transactions rows against **Staff → Reports →
   Transaction History** (no filters applied) - the widget's 5 rows should
   be the first 5 rows of that page's unfiltered, default-sorted list.
7. Log in as an **Admin** (not Superadmin) and revisit
   `/staff/dashboard/admin` - confirm you see the same page (still shares
   the `'admin'` slug) but **none** of the three widgets appear, same as
   before this change.
8. Log in as any other role (e.g. Receptionist, Groomer) - confirm their
   own dashboard is unaffected (still the plain welcome message, no
   widgets - this was never gated to them and still isn't).
9. (Optional) Toggle dark mode - confirm all three widgets stay readable,
   same check as #37.

## Test suites

- `client`: `npm test` (from `client/`) - **593 tests pass** across 128
  files. New: 2 tests in `StaffDashboardPage.spec.ts` (widgets render for
  Superadmin; stay hidden for Admin).
- `client`: `npx tsc -b --noEmit` clean.
- `client`: `npm run lint` clean.
- No server-side changes, no new migrations, no new API routes - nothing to
  run in `server/`.

## Suggested branch name

`38-superadmin-dashboard-widgets`
