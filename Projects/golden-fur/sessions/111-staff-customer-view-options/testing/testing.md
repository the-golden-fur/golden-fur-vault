# Gallery/Table/List/Board views for Staff and Customer Management, plus three rounds of polish

Branch: `feat/staff-customer-view-options` (PR #196, squash-merged into
`dev` as commit `ca026d0`)

## The request, verbatim

> add the view options to staff management page
> table, list, gallery, board
> default gallery
> add ... button, move actions there
>
> extend group by options
> add group by [PROPERTY], sort options for it (e.g. alphabetical, manual, etc.)

> do the same for customer management page
> add the missing notion features, search, sort, filter, group by, view options

**Scope note:** two more rounds of polish arrived in the same session, once
the first version was actually visible on screen (see "What changed" below
for each):

> board view looks a bit broken when there's too many group by options
> fix its responsiveness
> also make it so that the ... button is not visible when in board or gallery view
> replace it with a right click on desktop, or tap in mobile, both opens the options menu (from ... button)

> staff management page > board view still broken
> cards should fit inside the group by option
> also the manual sort option in group by should make the group by columns draggable to the side
> also what does the resend account email button do?
> for now move it to the ... options

## Root cause / Context

A prior session (110) had already given Staff Management and Customer
Management a lighter "Tier 2" pass — search/filter/sort only, no view
switcher, no board, no group-by — and had already built four reusable
pieces for the pages that _did_ get the full treatment: `DataTable`,
`DataList`, `DataBoard`, and `useGroupBy`. This session's job was to wire
those same four pieces into the two pages that had been deliberately left
lighter, then fix what broke once a real Board view (8 Role columns) was
actually looked at.

## What changed

### Database / Server

None. Both pages already fetched everything they need; view switching,
grouping, and sorting all happen client-side over data already in memory,
same as every other page in this rollout.

### Client — Staff Management

- `client/src/features/staff/pages/StaffManagementPage/staffBrowserFields.ts`
  — new `buildStaffGroupByAxes(branches, isSuperadminViewer)`: a Role axis
  (always offered, covering all 8 roles even ones nobody currently holds)
  and a Branch axis (Superadmin viewers only, matching the same branch-
  scoping the page's filters already used).
- `client/src/features/staff/pages/StaffManagementPage/StaffManagementPage.tsx`
  — added the Gallery/Table/List/Board `ViewSwitcher` (default: Gallery), a
  "Group by" dropdown (Role/Branch) and a "Sort groups" dropdown (Manual/
  Alphabetical) shown only in Board view, and a `renderStaffCard` helper
  used by both Gallery and Board. The existing "Set day(s) off"/"Manage
  account" modals and their triggers are unchanged in Table/List (still a
  visible `MoreOptionsMenu` "..." button); Gallery/Board switched to the
  new `CardContextMenu` (see below).
- `StaffManagementPage.module.css` — new `.viewControls`/`.boardCard`/
  `.gridItem` etc., plus the two fit fixes below.

### Client — Customer Management

- `client/src/features/staff/pages/CustomerManagementPage/customerBrowserFields.ts`
  — new `CUSTOMER_GROUP_BY_AXES`: a Status axis (Active/Inactive) and a
  Sign-in method axis (Email/Google/Facebook).
- `client/src/features/staff/pages/CustomerManagementPage/CustomerManagementPage.tsx`
  — same Gallery/Table/List/Board + Group by + Sort groups additions as
  Staff Management. Table/List kept the existing `CustomerRowActionMenu`
  "..." button; Gallery/Board switched to `CardContextMenu`, via a new
  `buildCustomerActionItems(customer)` helper that mirrors
  `CustomerRowActionMenu`'s own conditional item logic (Check Profile/View
  Pets/Add Pet always; Deactivate/Reactivate and Archive gated the same
  way) as a plain item list `CardContextMenu` can render.

### Client — shared pieces (used by both pages, and by anything else that adopts them later)

- `client/src/shared/hooks/useGroupBy/useGroupBy.ts` —
  - `GroupSortMode`/`GROUP_SORT_MODE_OPTIONS`/`sortGroupByAxis(axis, mode, manualOrder?)`:
    "Alphabetical" sorts columns A–Z; "Manual" now accepts an optional
    saved column order (see below) instead of just meaning "leave it
    alone" — a saved order that references a column the axis no longer
    declares is dropped, and a column the axis declares that the saved
    order never saw is appended at the end.
  - `moveColumnBefore(order, column, before)`: a small pure function that
    moves one column to sit immediately before another in an order array —
    what powers drag-to-reorder (below). Dropping a column onto itself or
    an unknown target is a no-op.
- `client/src/shared/components/DataBoard/DataBoard.tsx` — new optional
  `onReorderColumn(dragged, target)` prop. When provided, each column's
  header (`<h3>`) becomes a drag handle (native HTML5 drag-and-drop, no new
  dependency); dropping one column's header onto another calls the
  callback, and the column currently being dragged over gets a dashed gold
  outline so the drop target is visible. A page only passes this prop while
  its own "Sort groups" is set to Manual — dragging an Alphabetical
  (derived) order wouldn't have anywhere to persist.
- `client/src/shared/components/DataBoard/DataBoard.module.css` — two
  fixes:
  1. `.board` gained `min-width: 0`. A CSS grid item's default `min-width:
auto` refuses to shrink below its own content's size — with 8 Role
     columns, that pushed the _whole page_ wider instead of the board
     scrolling sideways within its own box (the `overflow-x: auto` it
     already had).
  2. The column-track floor is now `minmax(var(--column-min-width, 15rem), 1fr)`
     instead of a hardcoded `15rem` — a page can raise that floor to match
     its own card's actual minimum width via a CSS custom property, so a
     card never ends up wider than the column it's sitting in (see
     Staff Management's `.content` below).
- `client/src/features/staff/pages/StaffManagementPage/StaffManagementPage.module.css`
  — `.content` sets `--column-min-width: var(--staff-card-min-width)`
  (both fix #2 above), and `.gridItem`/`.boardCard` dropped `justify-items:
start`, which had been keeping each `StaffCard` shrink-wrapped to its own
  260px floor instead of stretching to fill a column/cell that was often
  considerably wider — this is what was actually causing names to truncate
  ("Makati Su…") even with visible unused space next to the card.
- `client/src/shared/components/MoreOptionsMenu/CardContextMenu.tsx` (new)
  — same `MoreOptionsMenuItem[]` shape and menu markup as the existing
  button-triggered `MoreOptionsMenu`, but with **no visible trigger at
  all**: right-click opens it on desktop (and suppresses the browser's own
  right-click menu); on touch, a **long-press** (500ms hold, under 10px of
  drift) opens it instead — a plain, quick tap is deliberately left alone
  so it still reaches other interactive things already inside a card (e.g.
  a button), rather than a blanket single-tap handler swallowing every tap
  on the card. Clicking outside or pressing Escape closes it.
- `client/src/shared/components/MoreOptionsMenu/MoreOptionsMenu.module.css`
  — added `.contextWrapper` (stretches to fill its card's grid cell,
  unlike `.container`'s shrink-to-content sizing for the small kebab
  button) plus `.columnTitleDraggable`/`.columnDragOver` for the new drag
  affordance in `DataBoard.module.css`.

### Client — "Resend account email" relocation

- `client/src/features/staff/components/cards/StaffCard/StaffCard.tsx` —
  removed the always-visible `ResendEmailButton`.
- `client/src/features/staff/components/forms/ManageStaffAccountForm/ManageStaffAccountForm.tsx`
  — added `<ResendEmailButton staffId={staffId} accessToken={accessToken} />`
  at the top of the form. **What the button actually does** (answered
  in-session, from `server/src/features/staff/services/resendAccountEmail.service.ts`):
  it re-sends the _original_ account-creation email — the same username and
  the same temporary password issued when the account was created,
  decrypted server-side — for when that first email didn't arrive. It never
  issues a new password, and it only works before the staff member's first
  login; once they've logged in, the server clears the stored temporary
  credential and a resend request returns a 409 instead of emailing a
  stale, already-changed password.

## Manual test — step by step

Both dev servers need to already be running (client on port 5173, server
on port 3000) — use the `dev-servers` check first rather than starting a
second copy of either.

### A. Staff Management — views, group-by, sort groups

1. Log in as an Admin or Superadmin, go to
   `http://localhost:5173/staff/admin/staff`, or navigate: **Staff
   Management** (sidebar).
2. Confirm the page loads in **Gallery** view by default (a card grid).
3. Click **Table** — confirm a spreadsheet-style table appears with the
   same staff. Click **List** — confirm stacked rows instead. Click
   **Board** — confirm columns appear, one per Role (all 8, even roles no
   one currently holds), each staff card under its own Role column.
4. In Board view, confirm a **Group by** dropdown (Role/Branch — Branch
   only if you're a Superadmin) and a **Sort groups** dropdown (Manual/
   Alphabetical) appear. Switch Group by to Branch (Superadmin only) —
   confirm the board regroups by branch instead. Switch Sort groups to
   Alphabetical — confirm the columns reorder A–Z.
5. Switch Sort groups back to Manual. Click and hold a column's header,
   drag it onto a different column, and release — confirm the dragged
   column moves to sit where you dropped it, and a dashed gold outline
   appeared on the column you were hovering over while dragging. Switch to
   Alphabetical and back to Manual — confirm your custom order is still
   there (kept for this browser tab only, not saved to the server).
6. With many Role columns visible (Board, Group by: Role), confirm the
   board **scrolls sideways** if it doesn't all fit, rather than the whole
   page stretching — and confirm each card's name is fully readable (not
   cut off as "Makati Su…") given the column's actual width.
7. In Gallery and Board view, confirm there's **no visible "..." button**
   on any card. Right-click a card — confirm the same actions menu
   ("Set day(s) off", "Manage account") opens where you clicked. Click
   outside the menu — confirm it closes. On a touch device (or your
   browser's device toolbar set to a touch profile), press and hold a card
   for about half a second without moving your finger — confirm the same
   menu opens; a quick tap should **not** open it.
8. Switch to Table or List — confirm the visible "..." button is back,
   working exactly as before.
9. Click any card's "..." (or right-click it in Gallery/Board) > **Manage
   account** — confirm the modal now has a **Resend account email** button
   near the top, above the role/branch/deactivate controls. Confirm the
   card itself no longer shows this button directly.

### B. Customer Management — same view/group-by additions

1. Go to `http://localhost:5173/staff/admin/customers`, or navigate:
   **Customer Management**.
2. Confirm **Gallery** is the default view, and **Table**/**List**/**Board**
   all work the same way as Staff Management.
3. In Board view, confirm **Group by** offers Status (Active/Inactive) and
   Sign-in method (Email/Google/Facebook), and **Sort groups** offers
   Manual/Alphabetical with the same drag-to-reorder behavior as Staff
   Management (drag one column's header onto another while in Manual mode).
4. In Gallery/Board, confirm there's no visible "..." button on any card,
   and right-click (or long-press on touch) opens the same **Check
   Profile / View Pets / Add Pet / Deactivate-Reactivate / Archive** menu
   that Table/List's visible "..." button already offered — with the same
   Deactivate/Archive gating (Admin/Superadmin only, Archive only once
   already inactive).

## Test suites

Run from `golden-fur/client`:

- `npx tsc -b` — clean, no errors. (Note: this repo's root `tsconfig.json`
  is solution-style — `npx tsc --noEmit -p .` silently checks **zero**
  files; `tsc -b` is the real check.)
- `npx eslint <touched dirs>` — clean, no errors or warnings.
- `npx vitest run` — **1228/1231 passing** (212 test files). The 3 failures
  are all in `src/features/auth/staff/api/staffAuth.api.spec.ts`
  (`forgotPassword`/MFA-enroll base-URL assertions), a file this session
  never touched — pre-existing and unrelated.
- New/updated spec files, all passing: `StaffManagementPage.spec.ts` (27
  tests — includes the Gallery-default/view-switching test, Board
  group-by-Role-default + Sort-groups test, Board Branch-axis-Superadmin-
  only test, a right-click/long-press-opens-the-menu test, and the
  Resend-email-now-lives-in-Manage-account test), `staffBrowserFields.spec.ts`
  (new — `buildStaffGroupByAxes` coverage), `CustomerManagementPage.spec.ts`
  (equivalent set for Customer Management), `customerBrowserFields.spec.ts`
  (new), `CardContextMenu.spec.tsx` (new — 7 tests: no visible trigger,
  right-click opens + suppresses the native menu, item click closes it,
  outside-click closes it, long-press opens it, a quick tap does not, a
  long hold that drags does not), `DataBoard.spec.tsx` (4 new tests for
  `onReorderColumn`: headers aren't draggable without it, are draggable
  with it, dragging one header onto another calls it with the right
  arguments, dropping a column onto itself does not call it),
  `useGroupBy.spec.ts` (6 new tests: manual sort applying/dropping/
  appending a saved order, alphabetical ignoring a saved order, and
  `moveColumnBefore`'s three cases), `ManageStaffAccountForm.spec.ts`
  (existing tests kept, mock updated to include `resendAccountEmail`).

## Open items

None outstanding from this session's own requests. Two things worth
flagging for later, both explicitly called out as "for now" in the
request itself rather than a final decision:

- **Resend account email's placement** — moved into "Manage account" as
  the quickest correct home (it's already the page's destination for
  account-level actions), not necessarily where it belongs long-term.
- **Manual column order is session-only** (kept in React state, not
  persisted anywhere) — if a durable "remember my column order" is wanted
  later, it would need a small server-side or browser-storage addition
  that this session deliberately didn't scope in.
