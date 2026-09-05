---
title: Make the Settings page fill the screen and add icons to its Config tiles
date: 2026-09-05
tags: [session-plan, golden-fur]
project: golden-fur
session: 71-settings-fullscreen-and-config-icons
branch: feat/settings-fullscreen-config-icons
---

# 71 — Make the Settings page fill the screen and add icons to its Config tiles

## What you asked for

Two small UI polish items from the team's running task list, then it was requested directly:

> Make settings modal fullscreen
> Settings sidebar should be a second sidebar
> Auto collapses the dashboard sidebar when settings opened
>
> Add icons to admin settings > config navigation tiles

## What this part of the app does today

When a staff member or customer clicks the gear icon in the top navigation bar, they
land on the **Settings page** (`/staff/settings` or `/portal/settings`). Before this
session, Settings rendered as a **modal**: a dimmed overlay covered the whole screen,
and a smaller card floated in the middle of it, with its own "Settings" sidebar
(Profile / Preferences / Account / Security, plus Config for Admin/Superadmin) down the
left side of that card. There was already a button to make the card bigger
("fullscreen"), but the user had to click it every time, and even at its biggest it was
still a floating overlay sitting on top of the app's real left-hand navigation menu (the
**dashboard sidebar** — the permanent menu with things like Bookings Queue, Cage
Occupancy, etc.).

Inside Settings, an Admin or Superadmin sees a "Config" section that expands to list
every admin configuration page (Services and Packages, Pricing Configuration, Promos,
Breed Management, Product Catalog, Discounts, Miscellaneous Sales, Policies, Cages, and
— Superadmin only — System Configuration). These are called **tiles**, and they showed
up as plain text with no picture/icon next to them, either in that expanding sidebar
list or in the tile-grid view you see when you click "Config" itself.

## What's wrong / what's missing

- Settings always opened as a small floating card the user had to manually resize —
  it never used the full screen by default, and even when resized it still sat on top
  of (hid) the dashboard's own navigation menu instead of sitting neatly beside it.
- The Config tiles (and the matching entries in the Settings sidebar) had no icons, so
  the list read as a wall of plain text with nothing to help the eye pick out, say,
  "Cages" from "Discounts" at a glance.

## What we're going to change

1. **Settings always fills the content area, permanently — no more manual toggle.**
   _Which files:_ `client/src/pages/SettingsPage/SettingsPage.tsx`,
   `client/src/pages/SettingsPage/SettingsPage.module.css` — _Why:_ the floating
   card + dimmed backdrop is removed; Settings now renders as a normal page that fills
   the space next to the app's real navigation menu, the same way every other page in
   the app already does.

2. **The dashboard's navigation menu automatically shrinks to icons-only while Settings
   is open, and goes back to how it was once you leave.**
   _Which files:_ a new `client/src/shared/providers/SidebarCollapseProvider/` (a small
   shared "remote control" for the menu's collapsed/expanded state) and
   `client/src/shared/hooks/useSidebarCollapse/`, wired up in
   `client/src/shared/components/AppShell/AppShell.tsx` (the component that always
   renders the navbar + navigation menu + page content together) — _Why:_ before this
   change, only the `AppShell` component itself could collapse the menu; there was no
   way for the Settings page (which is just "page content" as far as `AppShell` is
   concerned) to reach out and say "collapse yourself for now."

3. **Every Config tile gets its own icon**, both in the tile-grid view and in the
   Settings sidebar's expanding Config list.
   _Which files:_ `client/src/pages/SettingsPage/configTiles.config.ts` (one icon
   picked per tile — e.g. a percent sign for Discounts, a little dog for Breed
   Management), `client/src/features/staff/components/dashboard/DashboardTile/
DashboardTile.tsx` (the shared "tile" component learned how to show an icon if it's
   given one), `client/src/pages/SettingsPage/tabs/ConfigTab.tsx` (passes the icon
   through), and `client/src/pages/SettingsPage/SettingsPage.tsx` (shows the icon next
   to each Config sub-item in the sidebar list too).

## Words you might not know

- **Modal** — a floating box that sits on top of the rest of the page and usually dims
  everything behind it, so you focus on just that box.
- **Context (React context)** — a way for a piece of state (like "is the menu
  collapsed?") to be read or changed by a component far away in the tree, without
  passing it down manually through every component in between.
- **Ref (`useRef`)** — a box that holds a value across re-renders without itself
  causing the component to re-render when it changes; used here to remember "what was
  the menu's collapsed state right before Settings opened?" so it can be restored later.
- **lucide-react** — the one icon library this app already uses everywhere else (the
  gear icon, the bell icon, etc.) — this session just added a few more icons from the
  same library.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
