# 37 - Branch revenue comparison chart (Makati vs Southwoods)

Added a pie chart to the Superadmin **Analytics Dashboard**
(`/staff/reports/analytics`, under **Staff → Reports**) that always compares
Makati's and Southwoods' total revenue side by side, using
[recharts](https://recharts.org) (newly added dependency).

## What changed

- **New dependency:** `recharts@3.10.1` added to `client/package.json` (no
  server/DB changes).
- **New component:** `BranchRevenueComparisonChart`, rendered below the
  existing Total Revenue / Bookings / Cancellation Rate cards on the
  Analytics Dashboard.
  - Always fetches **both** Makati's and Southwoods' revenue for whatever
    **Time period** is currently selected at the top of the page (Today /
    This week / This month / This year / All time) - independent of the
    page's own **Branch** dropdown, since that dropdown only shows one
    branch (or all) at a time and can't itself produce a two-branch
    comparison.
  - Reuses the existing `GET /reports/analytics` endpoint (already
    Superadmin-gated server-side) - called once per branch, no new API
    route or DB object was needed.
  - Shows a donut-style pie (two slices), a small legend below it with each
    branch's peso amount, and a hover tooltip. If both branches have zero
    revenue for the selected period, it shows "No revenue recorded for this
    period." instead of an empty chart.

**Files:**
`client/package.json`, `client/package-lock.json` (recharts added),
`client/src/features/reports/components/BranchRevenueComparisonChart/BranchRevenueComparisonChart.tsx`
(new), `client/src/features/reports/components/BranchRevenueComparisonChart/BranchRevenueComparisonChart.module.css`
(new), `client/src/features/reports/pages/AnalyticsDashboardPage/AnalyticsDashboardPage.tsx`
(renders the new component).

## Verify manually

1. From the repo root, install the new dependency if you haven't already
   (skip this if `client/node_modules/recharts` already exists):
   ```powershell
   cd client
   npm install
   ```
2. Start the app (`npm run dev` from `client/`, and make sure the `server/`
   dev server is running too) and log in as a **Superadmin** staff account.
3. Go to **Staff → Reports → Analytics Dashboard**
   (`/staff/reports/analytics`).
4. Below the three existing summary cards, confirm a new card titled
   **"Makati vs Southwoods Revenue"** appears, showing a pie chart (two
   colored slices) with a small legend underneath listing "Makati" and
   "Southwoods", each with a ₱ amount.
5. Hover over each slice - a tooltip should pop up showing the branch name
   and its peso amount, formatted like `₱12,345.00`.
6. Change the **Time period** dropdown at the top (e.g. from "Today" to
   "This month") - confirm the pie chart's two slices and legend amounts
   update to match the new period.
7. Change the page's own **Branch** dropdown to "Makati" only - confirm the
   three cards above filter to Makati-only numbers as before, but the new
   pie chart still shows **both** Makati and Southwoods (it's intentionally
   unaffected by that dropdown - see "What changed" above).
8. To check the empty-state: pick a time period you know has no bookings/
   payments for either branch (e.g. if you have a fresh/empty database, use
   "Today"). Confirm the card instead reads "No revenue recorded for this
   period." with no broken/empty chart.
9. To sanity-check the numbers: open **Staff → Reports → Daily Sales
   Report**, pick today's date and each branch one at a time, and compare
   its "Gross amount" total against what the new chart's tooltip/legend
   shows for **Today** (they're pulled from different queries -
   `get_analytics_summary` vs the DSR RPC - but should be in the same
   ballpark for the current day; large mismatches would indicate a bug
   worth flagging).
10. Log in as a non-Superadmin staff role (e.g. Admin or Receptionist) and
    confirm you're redirected away from `/staff/reports/analytics`
    entirely, same as before this change (the whole page, including the new
    chart, stays Superadmin-only).
11. (Optional) Toggle **Settings → Appearance → dark mode** while on this
    page - confirm the chart's slice colors, legend, and tooltip all remain
    readable and match the app's existing dark palette (no white/unstyled
    boxes).

## Test suites

- `client`: `npm test` (from `client/`) - **591 tests pass** across 128
  files (no new spec file was added for this chart - it's a small, purely
  presentational addition wired into the existing Analytics Dashboard).
- `client`: `npx tsc -b --noEmit` clean.
- `client`: `npm run lint` clean.
- No server-side changes, no new migrations, no new API routes - nothing to
  run in `server/`.

## Suggested branch name

`37-branch-revenue-comparison-chart`
