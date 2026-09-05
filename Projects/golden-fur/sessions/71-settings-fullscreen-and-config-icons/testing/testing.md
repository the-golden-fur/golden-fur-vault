# Settings page fills the screen (second sidebar, auto-collapse) + Config tile icons

Branch: `feat/settings-fullscreen-config-icons`

## The request, verbatim

> Make settings modal fullscreen
> Settings sidebar should be a second sidebar
> Auto collapses the dashboard sidebar when settings opened
>
> Add icons to admin settings > config navigation tiles

Context: `Projects/golden-fur/shared/context/Architectural-Change-History.pdf` (p.5)
lists both as "In Progress" items, with a screenshot of the pre-change Settings modal
and its plain-text Config sidebar list.

## Root cause / Context

`SettingsPage` (`/staff/settings`, `/portal/settings`) rendered as a `position: fixed`
dimmed backdrop with a centered card (`.backdrop` / `.modalPanel` /
`.modalPanelFullscreen` in `SettingsPage.module.css`), even though it's a normal routed
page rendered through `AppShell`'s `<Outlet/>`. There was a manual, per-session
"fullscreen" toggle, but even at its biggest the panel was still `position: fixed;
inset: 0`, covering the real dashboard `Sidebar` underneath it rather than sitting
beside it. `AppShell.tsx` owned the dashboard sidebar's collapsed state as plain
`useState` with no way for a descendant routed page to read or drive it.

Separately, the Config tiles (`configTiles.config.ts` — Services and Packages, Pricing
Configuration, Promos, Breed Management, Product Catalog, Discounts, Miscellaneous
Sales, Policies, Cages, System Configuration) had no `icon` field, and neither the tile
grid (`ConfigTab.tsx` via the shared `DashboardTile` component) nor the Settings
sidebar's own nested Config list rendered one.

## What changed

### Server

No server changes.

### Client

- **`client/src/shared/providers/SidebarCollapseProvider/sidebarCollapseContext.ts`**
  (new) — a `createContext` holding `{ collapsed, setCollapsed }`.
- **`client/src/shared/providers/SidebarCollapseProvider/SidebarCollapseProvider.tsx`**
  (new) — a thin wrapper component (`{collapsed, setCollapsed, children}` →
  `<SidebarCollapseContext.Provider>`, value `useMemo`'d), matching the sibling
  `ThemeProvider`/`ToastProvider` folder convention (a real `<Name>Provider.tsx` next to
  its context file) — added during code review (see below); the first pass had only the
  raw context file with `AppShell` constructing an unmemoized value inline.
- **`client/src/shared/hooks/useSidebarCollapse/useSidebarCollapse.ts`** (new) — thin
  `useContext` wrapper, same shape as the existing `useResizableWidth` hook folder.
- **`client/src/shared/components/AppShell/AppShell.tsx`** — the dashboard sidebar's
  `collapsed` state and its `localStorage` persistence are now wrapped in a memoized
  `setCollapsedPersist`, and the whole shell is wrapped in the new
  `<SidebarCollapseProvider>` so anything rendered under `<Outlet/>` (like
  `SettingsPage`) can read/drive it.
- **`client/src/pages/SettingsPage/SettingsPage.tsx`**:
  - Consumes `useSidebarCollapse()`. On mount, snapshots the current collapsed value in
    a `useRef` and force-collapses the dashboard sidebar; on unmount, restores the
    snapshot.
  - Removed the `isFullscreen` state, the `Maximize2`/`Minimize2` toggle-everything
    button, and the `.backdrop`/`.modalPanel`/`.modalPanelFullscreen` render branches.
    Settings now always renders as a single `<div className={styles.page}>` that fills
    `AppShell`'s content area (`height: 100%`, no `position: fixed`), with no
    `role="dialog"`/`aria-modal` (it no longer blocks the rest of the page — the
    dashboard sidebar stays visible and interactive beside it, collapsed).
  - Kept a narrower, unrelated button — "Open as a full page" — that still navigates to
    an embedded Config tile's real standalone route; it now only renders while a tile
    is actually embedded (there's nothing to toggle when Settings is showing a normal
    tab).
  - The existing internal `.sidebar` (Profile/Preferences/Account/Security/Config, with
    the expandable Config sub-item list) is unchanged in behavior — removing the
    backdrop wrapper is what makes it read as sitting directly beside the (now
    collapsed) dashboard sidebar instead of floating above everything.
  - The Config sidebar sub-items now render each tile's icon (14px) before its label.
- **`client/src/pages/SettingsPage/SettingsPage.module.css`** — replaced
  `.page`/`.backdrop`/`.modalPanel`/`.modalPanelFullscreen` with a single `.page` rule
  (`display:flex; flex-direction:column; height:100%; background: var(--color-bg-
secondary)`).
- **`client/src/pages/SettingsPage/configTiles.config.ts`** — added a required
  `icon: LucideIcon` field to `ConfigTileConfig`; assigned one icon per tile (Services
  and Packages → `Package`, Pricing Configuration → `Calculator`, Promos →
  `BadgePercent`, Breed Management → `Dog`, Product Catalog → `ShoppingBag`, Discounts →
  `Percent`, Miscellaneous Sales → `Receipt`, Policies → `ScrollText`, Cages →
  `DoorOpen`, System Configuration → `Settings2`), all from `lucide-react` (the app's
  one existing icon library).
- **`client/src/features/staff/components/dashboard/DashboardTile/DashboardTile.tsx`**
  (+ `.module.css`) — added an optional `icon?: LucideIcon` prop (not part of the
  shared `DashboardTileConfig` type, since the operational-dashboard's own tiles don't
  carry one — they simply won't pass it), rendered in a small `titleRow` reused across
  all three existing tile variants (link / inline-select button / "Coming soon"
  placeholder).
- **`client/src/pages/SettingsPage/tabs/ConfigTab.tsx`** — passes `icon={tile.icon}`
  through to `<DashboardTile>`.
- **`client/src/pages/SettingsPage/SettingsPage.spec.ts`** — updated: removed two tests
  that only exercised the now-deleted manual fullscreen toggle/backdrop
  (`the fullscreen toggle flips into an exit-full-screen state`,
  `Fullscreen still just resizes the panel for a plain section`, `Fullscreen for a
plain section drops the dimmed backdrop entirely`); rewrote the "renders as a modal
  dialog..." test to assert the new no-backdrop/no-dialog-role rendering instead; added
  `icon` to the mocked `CONFIG_TILES`/`SYSTEM_CONFIG_TILE` fixtures (required now that
  `SettingsPage` renders `tile.icon` unconditionally in the sidebar list).
- **`client/src/shared/components/AppShell/AppShell.spec.ts`** — added during code
  review, to close the gap it flagged (see below): a `SidebarCollapseProbe` component
  standing in for what `SettingsPage` actually does (force-collapse on mount via
  `useSidebarCollapse()`, restore the prior value on unmount), rendered on a second
  route reachable via an in-page link, plus two new tests proving the round-trip
  actually drives `AppShell`'s real `Sidebar` (not just the context's inert default) and
  correctly restores a pre-existing _collapsed_ state rather than always forcing it back
  open.

## Code review

`code-reviewer` subagent, manual trigger, reviewed the full staged diff before the
first commit — verdict **APPROVE WITH NITS** (0 blocking). All 4 non-blocking findings
were addressed before committing:

- Unmemoized context value in `AppShell` → extracted the real `SidebarCollapseProvider`
  component (above), value `useMemo`'d.
- `SidebarCollapseProvider/` folder held only a context file, no actual Provider
  component (inconsistent with `ThemeProvider`/`ToastProvider`) → same fix as above.
- A `.map()` callback's JSX body wasn't indented under its `return (` (Prettier would
  have flagged this in CI) → ran `prettier --write` on the touched files.
- A stale doc comment in `configTiles.config.ts` still described the removed
  "Fullscreen toggle" — reworded to reference the current "Open as a full page" button.
- Flagged test gap: the sidebar-collapse round-trip (force-collapse on mount, restore
  on unmount) had zero coverage, since `SettingsPage.spec.ts` renders the page with no
  `AppShell`/`SidebarCollapseProvider` ancestor at all → added the two `AppShell.spec.ts`
  tests described above instead.

Full report: `Projects/golden-fur/sessions/71-settings-fullscreen-and-config-icons/reviews/2026-09-05-2006-manual.md`

## Manual test — step by step

1. Make sure the dev servers are running: `npm run dev` from the repo root (starts the
   client on `http://localhost:5173` and the server on `http://localhost:3000`).
2. Open your web browser and go to `http://localhost:5173`.
3. Click **Staff Login**. Log in as an Admin or Superadmin seed account — username
   `makati.admin1` (or `makati.superadmin1` to also see the System Configuration tile),
   password `password123` (all seeded staff accounts share this password — see
   `supabase/seeds/module-1-staff-auth/module-1-staff-auth.seed.ts`). You should land on
   the **Dashboard** page with the dashboard navigation menu on the left.
4. Click the gear icon in the top navigation bar to open **Settings**.
   - **Expect:** Settings fills the whole area to the right of the navigation menu (no
     dimmed overlay, no floating card with rounded corners/shadow) — it looks like a
     normal page, not a popup.
   - **Expect:** the dashboard's own navigation menu (on the far left) has shrunk down
     to icons-only automatically, without you clicking its own collapse button.
5. Click the navigation menu's own collapse/expand button (the icon in its top-right
   corner) while Settings is still open.
   - **Expect:** it still expands/collapses normally — the auto-collapse only sets the
     starting state, it doesn't lock the toggle.
6. Click **Config** in the Settings sidebar (Admin/Superadmin only).
   - **Expect:** the Config tile grid shows one icon per tile (e.g. Discounts shows a
     percent-sign icon, Breed Management shows a small dog icon).
   - **Expect:** the Config entry in the Settings sidebar has expanded to list every
     tile underneath it, each with the same icon before its label.
7. Click one of the tiles (e.g. **Discounts**).
   - **Expect:** the real Discounts page loads inline, inside the Settings content
     area (no page navigation).
   - **Expect:** a new button appears in the Settings header, labeled (via its
     accessible name) "Open as a full page." Click it.
   - **Expect:** the browser navigates away from Settings entirely, to
     `/staff/admin/discounts`.
8. Go back to Settings (gear icon), click the **X** (Close settings) button in the
   Settings header.
   - **Expect:** you land back on the Dashboard, and the navigation menu is back to
     whatever state it was in before you opened Settings in step 4 (if it started
     expanded, it's expanded again now; if you had it collapsed before, it stays
     collapsed).
9. Repeat steps 2-4 logged in as a customer (`/portal`) to confirm the same
   fullscreen/second-sidebar/auto-collapse behavior on the customer side (Config won't
   be present there — customers don't get that tab).

## Test suites

- `client`: `npx vitest run` — **773/773 passing** (151 test files), including the
  updated `SettingsPage.spec.ts` (16 tests) and `DashboardTile.spec.ts` (5 tests), and
  `AppShell.spec.ts` (now 5 tests, +2 added during code review).
- `client`: `npx tsc --noEmit -p tsconfig.json` — clean.
- `client`: `npx eslint .` (whole `src/`) — clean, no errors or warnings.
- `server`: no changes made; suite not re-run for this session.

## Open items

- I could not visually verify the new layout in an actual browser myself (no
  browser-automation tool available in this session) — the dev servers were left
  running (`npm run dev`) for a human to do the manual test above.
