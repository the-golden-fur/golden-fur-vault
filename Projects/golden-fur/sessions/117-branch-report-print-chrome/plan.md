---
title: Hide navigation when printing branch reports
date: 2026-10-06
tags: [session-plan, golden-fur]
project: golden-fur
session: 117-branch-report-print-chrome
branch: fix/branch-report-print-chrome
---

# 117 - Hide navigation when printing branch reports

## What you asked for

Make the Branch Reports printout exclude the app navigation:

> As a supervisor/admin/superadmin, I don't want the navbar and sidebar to be
> included when printing the navbar > supervisor > branch reports document.
> See Projects\golden-fur\shared\context\Architectural-Change-History.pdf for
> full context and image.

## What this part of the app does today

Golden Fur has a staff console for employees such as Supervisors, Admins, and
Superadmins. Those roles use the same app shell, which means every staff page
is wrapped by a top navbar and a left sidebar.

The Branch Reports tile opens the Daily Sales Report page at
`/staff/reports/dsr`. That page has a **Print** button, which asks the browser
to print the current page.

## What's wrong / what's missing

The report page already hides its own print button and filters when printing,
but the navbar and sidebar live outside the report page. Because they are part
of the shared `AppShell`, the browser was still including them in the printed
document.

For a real report handout, that is noisy: the person receiving the paper should
see the report content, not the controls used to navigate the web app.

## What we're going to change

1. **Mark the app chrome clearly** - _Which files:_
   `client/src/shared/components/AppShell/AppShell.tsx` - _Why:_ the navbar
   and sidebar need wrapper elements that print CSS can target cleanly.
2. **Hide the shell during printing** - _Which files:_
   `client/src/shared/components/AppShell/AppShell.module.css` - _Why:_ print
   mode should show the routed report content and hide the navigation chrome.
3. **Keep the behavior covered by tests** - _Which files:_
   `client/src/shared/components/AppShell/AppShell.spec.ts` - _Why:_ a small
   test confirms the wrappers exist, which protects the print CSS anchor from
   being removed accidentally.

## Words you might not know

- **App shell** - the shared outer frame of the app. In Golden Fur, it contains
  the navbar, sidebar, and the main area where each page appears.
- **Navbar** - the horizontal navigation bar at the top of the staff console.
- **Sidebar** - the vertical navigation menu at the left side of the staff
  console.
- **Print stylesheet** - CSS rules inside `@media print` that the browser uses
  only when printing or showing print preview.
- **Routed content** - the page that React Router places inside the app shell,
  such as the Daily Sales Report page.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
