# Hide navigation when printing branch reports

Branch: `fix/branch-report-print-chrome`

## The request, verbatim

> As a supervisor/admin/superadmin, I don't want the navbar and sidebar to be
> included when printing the navbar > supervisor > branch reports document.
>
> see Projects\golden-fur\shared\context\Architectural-Change-History.pdf for
> full context and image

## Root cause / Context

The Daily Sales Report page already had its own print stylesheet, but that
stylesheet only controlled elements inside the report page. The navbar and
sidebar are rendered by the shared `AppShell`, which is outside the report
component. Because the shell did not have print-specific rules, the browser
included the staff navigation chrome in print preview.

## What changed

### Client

`client/src/shared/components/AppShell/AppShell.tsx`

- Added wrapper elements around the `Navbar` and `Sidebar`.
- Added test ids to those wrappers so the print CSS anchors are covered by the
  existing AppShell test suite.

`client/src/shared/components/AppShell/AppShell.module.css`

- Added a `sidebarWrapper` that behaves like normal layout on screen.
- Added `@media print` rules that hide the navbar and sidebar wrappers.
- Changed the shell/body/main layout in print mode so report content can use
  natural document flow instead of the fixed-height scrolling layout used on
  screen.

`client/src/shared/components/AppShell/AppShell.spec.ts`

- Added assertions that the navbar and sidebar wrappers render.

## Manual test - step by step

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login**. Sign in as a Supervisor, Admin, or Superadmin test
   account.
3. After login, use the staff navigation to open **Supervisor** and then
   **Branch Reports**. You should land on a page headed **Daily Sales Report**.
4. Click **Print** on the report page.
5. In the browser print preview, check the preview page.
6. The preview should show the report content, such as **Daily Sales Report**,
   **Service Breakdown**, **Credit Usage**, and **Miscellaneous Sales**.
7. The preview should not show the top navbar, the left sidebar, the staff
   identity chip, the sign-out button, or sidebar navigation links.
8. Cancel the print dialog.
9. Return to the normal browser tab. The navbar and sidebar should still be
   visible on screen, because the change only applies while printing.

## Test suites

- `client`: `npm.cmd run test:run -- AppShell` - 1 test file passed, 5 tests
  passed.
- Repo diff whitespace check: `git diff --check` - passed.

## Open items

- Full client/server CI was not run for this small print-style fix.
