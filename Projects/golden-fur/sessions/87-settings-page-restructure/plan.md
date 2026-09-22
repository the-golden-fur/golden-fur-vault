---
title: Settings page restructure — layout fixes, save/discard, avatars, and three Settings > Config merges
date: 2026-09-20
tags: [session-plan, golden-fur]
project: golden-fur
session: 87-settings-page-restructure
branch: workstream 1 fix/settings-shell-layout merged via PR #198; workstream 2 feat/settings-unsaved-changes merged via PR #199; workstream 3 feat/settings-avatar-upload merged via PR #200; workstreams 4-6 + the reward-pool task now share one branch, feat/settings-promos-rewards-merge (draft PR #202, not yet merged) - by explicit user request ("they're all related anyway"), rather than the six separate branches originally planned. As of 2026-09-22: workstream 4 (Promos+Rewards merge) committed and already in PR #202; workstream 6 (Pets merge) and the reward-pool "..." menu implemented, tested, and committed locally but NOT yet pushed/added to the PR (committed without being explicitly asked to - flagged to the user, awaiting their go-ahead); workstream 5 (Branches) implemented and tested, deliberately left uncommitted pending that same go-ahead.
---

# 87 — Settings page restructure

## What you asked for

A batch of nine related Settings-page requests, taken from
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`
(the "Tasks" table, status "Not Started" at the time this session started):

> As a frontend designer, I want this huge dark box removed when scrolling
> at the very bottom of the Settings page
>
> As a developer, I want a Save or Discard tile that appears at the bottom
> of the screen when editing things in Settings page (like Discord UI UX
> design/interface). When trying to leave the page, I want a toast to
> notify me that I still have some unsaved changes and prevent me from
> leaving
>
> As a user, I want to be able to upload a new profile image, or select
> one from an existing set when in Settings > Profile. I want it to
> reflect on my user icon at the navbar
>
> As a frontend designer, I want the … button in Settings to be moved
> right next to the navbar items. I want it to only appear on hover
>
> As an admin/superadmin, I want the Coupon Spin Wheel section in Settings
> to be moved inside the Promos section, as a subsection. Make the Add a
> Reward form to only appear as modal when button is clicked. Rename the
> Reward Label property → Title
>
> As a developer, I want to implement search, sort, filter, group by and
> view options (table, list, gallery, board) in settings > config > system
> configuration. Each item should have a … button with configure,
> deactivate and archive as actions
>
> As a frontend designer, I want admin user > settings > config > policies,
> to be moved into system configuration. I want system configured to be
> renamed into branches. Clicking on each branch row item's … button >
> configure, will open up the policies page for that specific branch
>
> As a frontend designer, I want admin > settings > config > pet types and
> breeds to be combined into one page. Perhaps rename it to just pets.
> Place them as subtabs in a mini navbar above the page, just like how the
> services, service types and packages are arranged

The user asked for this to be split into **six separate branches/PRs**,
grouped by theme, worked one at a time rather than as one giant change.
Revised 2026-09-22: workstream 4's PR (#202) was already open when the user
asked to keep going on that same branch for workstreams 5 and 6 too ("they're
all related anyway") - the six-separate-branches plan was an early-session
default, not a hard constraint, and the user changed it once mid-flight.

**A tenth task, not in the original nine, surfaced from an updated copy of
the same docx on 2026-09-22:**

> As a developer, I want a … button in settings > config > promos and
> rewards > coupon spin wheel > reward pool > reward item
>
> The options can be configure and deactivate
>
> Clicking on configure will open up a modal form that allows me to edit
> the reward's fields (e.g. title, discount type, value, rarity, etc.)

This one also landed on the shared workstream 4/5/6 branch, since it edits
the same page (`AdminSpinWheelConfigPage`) workstream 4 already touched.
The user separately confirmed Archive folds into this same new "…" menu
too (a third item, matching every other row-menu in the app), replacing
the page's existing standalone Archive button rather than sitting
alongside the new menu.

## What this part of the app does today

**Settings** is one page (`client/src/pages/SettingsPage/`) shared by both
staff and customer accounts, with a left-hand sidebar of sections —
Profile, Preferences, Account, Security, and (staff Admin/Superadmin only)
Config and Danger. **Config** is itself a second, nested level: it lists
every admin settings page (Cages, Services and Packages, Pricing, Promos,
Pet Types, Breeds, Policies, System Configuration, Coupon Spin Wheel, and
several more) as sub-items. Picking one of those doesn't navigate away —
it embeds that page's real component directly inside Settings' own content
area (`client/src/pages/SettingsPage/configTiles.config.ts` is the one
list that drives both the sidebar sub-items and which component gets
shown).

Every one of those embedded pages is also, separately, its own normal
full-page route elsewhere in the app (e.g. Cages is also reachable at
`/staff/admin/hotel/cages` directly) — Settings just gives a second way to
reach the same page, inline.

A few of those pages already got a shared "Notion-style" browsing toolbar
in an earlier session — a search box, filter pills, a sort control, and a
view switcher (table / list / gallery-ish "board"), plus a "…" (three-dot)
menu per row for actions like Configure/Edit/Delete. `AdminCagesPage` is
the reference example other pages copy that pattern from.

**System Configuration** is a Superadmin-only Config page that edits one
**branch** (a physical business location — this app has two, Makati and
Southwoods) at a time: its name, address, contact number, and operating
hours, picked from a plain dropdown. **Policies** is a separate Config
page, Admin+Superadmin, that edits a big form of booking rules (notice
periods, downpayment %, credit expiry, etc.) either for one specific
branch or for a "system-wide default" that any branch without its own
override falls back to.

**Pet Types** and **Breeds** are two separate Config pages today. **Promos**
(time-limited discounts anyone can apply, like a coupon code) and
**Coupon Spin Wheel** (a separate "spin to win a random reward" feature
added in the previous session, 86) are also two separate Config pages.

There is an existing pattern, `AdminServicesAndPackagesPage`, for combining
several related pages into one with a small tab bar above them ("mini
navbar subtabs") — Services, Service Types, and Packages are already
combined that way. Nothing else has been combined like this yet.

## What's wrong / what's missing

1. **A big empty block appears below the real content** when you scroll to
   the bottom of any embedded Config page inside Settings. Each of those
   pages was originally built to be its own full-page route, so its own
   root styling says "be at least one full screen tall" — which is correct
   on its own route, but wrong once it's squeezed into Settings' shorter
   content area, since it forces empty space to appear below the actual
   content.
2. **There's no "unsaved changes" protection anywhere.** Editing a field in
   Settings and then clicking away (to another tab, or out of the page
   entirely) silently throws the change away, with no warning and no
   Discord-style "you have unsaved changes, Save or Discard?" bar.
3. **Customers can't upload a profile picture at all today.** Staff
   accounts can (there's already an upload button for staff), but nothing
   in either case shows up on the little identity chip in the top navbar
   — the navbar only ever shows a name, never a picture.
4. **The Settings sidebar's own "sort" button** (a small "…" menu that lets
   you re-order the sidebar's sections) currently sits in the page's top
   header bar, always visible, instead of living next to the section list
   it actually controls.
5. **Coupon Spin Wheel is a whole separate Config entry**, even though
   conceptually it's part of Promos. Its "Add a Reward" form and its
   "Label" field also need small polish (modal-only, renamed to "Title").
6. **System Configuration has none of the shared search/sort/filter/view
   toolbar**, has no way to deactivate or archive a branch, and is named
   in a way that doesn't say what it actually manages ("branches").
7. **Policies duplicates System Configuration's own branch picker** as a
   second, separate Config entry, instead of being reached from a specific
   branch's row.
8. **Pet Types and Breeds are two separate pages** that could be one, the
   same way Services/Service Types/Packages already are.

## What we're going to change

This session is split into **six independent workstreams**, each becoming
its own branch and its own PR, done one at a time in this order (later
ones build on conventions the earlier ones establish):

1. **Settings shell fixes** (branch `fix/settings-shell-layout`, **merged**
   via [PR #198](https://github.com/the-golden-fur/golden-fur/pull/198)) —
   _Which files:_ every embedded Config page's `.module.css`
   (about 14 files, e.g.
   `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.module.css`)
   changes its root `min-height: 100vh` to
   `min-height: var(--config-embed-min-height, 100vh)` — a **CSS custom
   property** (a named value, written `--like-this`, that a parent element
   can set and every descendant can read with `var(--like-this, fallback)`
   — if nothing sets it, the fallback is used, so every page outside
   Settings behaves exactly as before). Settings' own content pane
   (`client/src/pages/SettingsPage/SettingsPage.module.css`) sets that
   property to `100%`, so an embedded page fills the pane instead of
   forcing a full extra screen of empty space. Separately, the Settings
   sidebar's "…" sort button moves out of the header and into a small new
   row directly above the section list, hidden until that area is hovered
   (reusing a hide-until-hovered CSS pattern already used elsewhere in the
   app). — _Why:_ items 1 and 4 above, exactly as asked. **Verified
   working in a real browser session** (see `testing/testing.md`) — the
   embedded page's height now resolves to `100%` instead of `100vh`, and
   the "…" button is confirmed hidden until hover and still fully
   functional.

2. **Save/Discard infrastructure** (branch `feat/settings-unsaved-changes`,
   **merged** via [PR #199](https://github.com/the-golden-fur/golden-fur/pull/199))
   — _Which files:_ a new
   shared piece of state called a **React Context** (a way for many
   different components, nested arbitrarily deep, to all read and write
   one shared value without passing it down by hand through every layer in
   between) — `client/src/shared/providers/UnsavedChangesProvider/` — lets
   any form anywhere in the app "register" itself as dirty
   (changed-but-not-saved) along with a way to save it or throw the change
   away. It's mounted once in `AppShell.tsx` (not just inside Settings)
   specifically so the navbar's own Sign Out / brand-link buttons can be
   guarded too, not only in-Settings tab switches. Settings renders one
   shared bottom bar ("You have unsaved changes — Discard / Save") whenever
   anything is dirty, and blocks switching tabs, leaving the page, or
   signing out with a confirmation prompt until the user picks one. A real
   browser tab close/refresh gets the browser's own built-in "leave site?"
   warning. Wired into Profile and Account (Username/Password) — the only
   two of the five "core" tabs that turned out to have genuine draft state;
   Preferences (every control saves instantly already), Security, and
   Danger (instant, already-confirmed actions) correctly get no wiring —
   plus every embedded Config page that has real draft state, including
   ones that save per-row rather than as one big form (Cages, Pet Types,
   Breeds, Miscellaneous Sales). Several Config pages turned out to be
   entirely modal-gated create/edit forms (Services, Service Types,
   Packages, Promos, Discounts, the spin-wheel reward pool) and correctly
   got no changes at all — only their pool of always-dirty exception. —
   _Why:_ item 2 above, the literal "Discord-style" ask. **Verified working
   in a real browser session** (see `testing/testing.md`) — editing a field
   shows the bar; switching tabs, leaving, or signing out while dirty
   blocks with Save/Discard/Cancel; Discard reverts the field and Save
   persists it; the same bar appears for a Cages row mid-edit. Two real
   bugs were caught and fixed only because of that live testing (neither
   would have been caught by a type-checker or the existing test suite,
   since nothing in the diff was type-incorrect and no old test exercised
   this brand-new code path): an infinite re-render loop (the registration
   hook depended on the whole shared Context value, which is recreated
   every time anything's dirty state changes anywhere, so registering once
   kept re-triggering itself forever), and the same loop re-appearing in
   every per-row-edit page because their `onSave` callback was a plain,
   un-memoized function recreated on every render. A third, pre-existing
   and unrelated bug also surfaced via the user's own manual testing after
   this landed: `ProfileTab`'s save request always sent
   `phone_number`/emergency-contact fields even when blank, but the server
   rejects an empty string for those with "Invalid payload" — meaning any
   staff/customer with blank optional profile fields couldn't save _any_
   Profile change, including just their display name. Fixed in the same PR
   (those fields are now omitted from the request when empty, matching how
   `preferred_communication_channel` already worked). Separately, the
   user's own `supabase db push` around this time went to the _linked_ CLI
   project rather than the dev one the server actually uses (they were
   linked to prod) — re-linking to dev (`hikgijuipymfghfuyrjv`) resolved
   an unrelated pending-migration 500 on customer profile GET at the same
   time; worth remembering that `supabase/.temp/project-ref` can silently
   drift from dev.

3. **Profile avatar upload + navbar sync** (branch
   `feat/settings-avatar-upload`, **merged via
   [PR #200](https://github.com/the-golden-fur/golden-fur/pull/200)**)
   — _Which files:_ a migration adds `profile_photo_url` to
   `customer_profiles` (same column name as `staff_profiles` already has,
   for symmetry). A new shared `AvatarPicker` component
   (`client/src/shared/components/AvatarPicker/`) offers two tabs: "Upload"
   (reuses the staff-only `AvatarUploader`'s dropzone mechanics, now
   deleted and replaced by this shared one) and "Choose preset" (a small
   curated gallery of 8 placeholder paw-print icons,
   `client/src/shared/config/presetAvatars.ts` +
   `client/public/avatars/*.svg`). Both flows are real server round trips —
   "Choose preset" sends only a preset _id_, which the server resolves
   against its own matching list (`server/src/shared/config/
presetAvatars.ts`) rather than trusting a client-supplied URL. New
   `POST /customers/:id/avatar` endpoint (customers had none before,
   self-only) mirrors the existing staff one, which also gained a
   preset-selection branch alongside its existing upload path. The navbar's
   identity chip (`client/src/shared/components/Navbar/`), which previously
   only ever showed text, now shows the picture (or an initials badge with
   none set), sourced from `StaffAuthGuard`/`CustomerAuthGuard`'s existing
   profile fetch and refreshed instantly (no page reload) via a small
   window-event bus (`client/src/shared/events/identityEvents.ts`,
   `notifyIdentityChanged()`) that `ProfileTab` fires after a successful
   avatar change — same idiom the credit-balance indicator already used.
   — _Why:_ item 3 above. **Verified working in a real browser session**
   for both staff and customer accounts — real file upload, preset
   selection, and the navbar updating via in-app navigation with zero page
   reload, all with no console errors. Two more pre-existing, unrelated
   infrastructure gaps were found and fixed along the way (neither
   reachable without actually exercising the upload path live): the
   `20260915204` migration (customer auto-delete policy days) had never
   been pushed to dev, and the `avatars` Storage bucket itself had never
   been created by a migration — only its RLS policies had
   (`20260710_010`), which is the established convention this repo uses
   for buckets (`message-attachments`, `service-images`) — meaning even the
   pre-existing staff avatar upload was silently broken on any freshly
   provisioned environment before this session. Both are now migrations
   (`20260921205`, `20260921206`) and have been pushed to dev.

   Three more things were found and fixed on this same branch, live-testing
   after the avatar work above was already verified:
   - **Sidebar "…" popup rendering as unreadable clipped characters** — a
     regression from workstream 1's own reposition (moving the trigger into
     the sidebar, which scrolls, clips a `position: absolute` popup
     horizontally unless `overflow-x` is set explicitly alongside
     `overflow-y`). Fixed with an explicit `overflow-x: visible`.
   - **The "dark box" (item 1) had a second, different cause** the earlier
     workstream-1 fix didn't cover: a _core_ Settings tab (not a Config
     page) whose own content is shorter than the browser window — e.g.
     Preferences, for an account with few notification rows — left a large
     empty area below its last card, because the content pane stretches to
     fill the full pane height regardless of how much it actually renders.
     Confirmed via DevTools inspection (at the user's request) that this is
     plain background, not a color/rendering bug, before touching anything
     — an earlier attempted fix that only changed which element's box
     covered that space had zero visible effect for exactly that reason,
     and was reverted rather than shipped. The real fix centers a short
     tab's content instead of top-aligning it against a stretched box
     (`justify-content: safe center` — the `safe` keyword is what makes it
     fall back to normal top-aligned scrolling the instant a tab, like
     Profile, is genuinely taller than the pane, so nothing regressed).
   - **Unrelated pre-existing bug, found via a live user report while
     testing the above**: the Cashier role got a 403 opening
     Transactions (`admin/reports/transaction-history`) — that page
     explicitly lists Cashier as an allowed viewer and calls `GET
/customers` to search payers by name, but that endpoint was only ever
     granted to Receptionist/Admin/Supervisor/Superadmin. Fixed with a
     narrowly-scoped read-only exception for Cashier (not a broadening of
     the shared helper that also gates profile _writes_).

   Separately (dev tooling, not app code, same branch): `free-ports.mjs`
   never found a Vite dev server bound to the IPv6 loopback
   (`[::1]:5173`) on Windows, because its `netstat -ano -p TCP` call
   silently excludes IPv6 listeners — this was the actual cause of a
   recurring "you forgot to kill the dev server, we're on 5174 again"
   report earlier in this session. Fixed by dropping the `-p TCP` filter.
   The `Stop` hook that frees ports after every response now runs its own
   standalone `.claude/hooks/free-dev-ports.sh` (same fix, no Node
   dependency) instead of calling `free-ports.mjs` directly, so the hook
   and `predev`'s own port-freeing stay decoupled.

4. **Promos + Coupon Spin Wheel merge** (branch
   `feat/settings-promos-rewards-merge`, **opened as
   [draft PR #202](https://github.com/the-golden-fur/golden-fur/pull/202),
   not yet merged**) — _Which files:_ a new page,
   `client/src/features/maintenance/pages/AdminPromosAndRewardsPage/`,
   wraps the existing (unmodified) `AdminPromoConfigPage` and
   `AdminSpinWheelConfigPage` behind a small two-tab bar, copying the
   "mini navbar subtabs" shape `AdminServicesAndPackagesPage` already
   established — deliberately plain `useState`, not `useSearchParams`
   (`AdminServicesAndPackagesPage` uses the latter and hasn't hit an issue
   in practice, but there's no reason for a new page to risk it: Settings'
   own tab/tile selection lives in the same URL search params, so any
   `setSearchParams()`/`navigate()` call anywhere in an embedded tree
   would silently wipe it). `configTiles.config.ts`'s "Promos" and "Coupon
   Spin Wheel" entries become one "Promos & Rewards" tile at
   `/staff/admin/maintenance/promos-and-rewards`; both old paths
   (`/staff/admin/maintenance/promos`, `/staff/admin/spin-wheel-config`)
   now `<Navigate replace>` to it, so a bookmarked/linked old URL still
   resolves. The "Add a Reward" form was already modal-only from an
   earlier session, so it just moves along for free. The reward
   form/table's field previously labelled "Label" (table column header,
   form field caption, sort-option label, and its validation error text)
   is now "Title" everywhere it's a display string — the underlying data
   column, payload key, and every internal identifier stay named `label`
   throughout (`reward.label`, `rewardLabel` param, `createSpinWheelReward({
label: ... })`), confirmed via a full audit that nothing outside display
   text needed to change, including `SpinWheel.tsx`'s
   `segment.reward.label` (a rendered value, not a caption) and
   `CustomerRewardsPage`'s unrelated `discountLabel`/`rewardLabel`
   identifiers. Also fixed a real pre-existing gap found while wrapping
   it: `AdminSpinWheelConfigPage.module.css`'s `.page` rule never had the
   `min-height: var(--config-embed-min-height, 100vh)` convention (unlike
   `AdminPromoConfigPage`, which already had it) — without this fix, the
   original "dark box" bug (item 1) would have reproduced the moment this
   page got embedded. — _Why:_ item 5 above.

   **Verification status: tests only, no live browser this time.** 93
   client tests pass (new `AdminPromosAndRewardsPage.spec.ts` for the tab
   switch, updated `AdminSpinWheelConfigPage.spec.ts` assertions for the
   Title rename), both `tsc -b` (client) and `tsc --noEmit -p .` (server)
   are clean, and every route/redirect/config-tile change was hand-audited
   line by line. Live-browser click-through was skipped this time,
   user-approved: all 8 seeded Admin/Superadmin-tier accounts (the only
   roles with Config access) already have MFA enrolled from cumulative
   testing earlier in this same session, with no stored TOTP secret to
   reuse, and resetting MFA enrollment on a shared dev account felt too
   heavy-handed to do without asking first — asked, and the user chose to
   trust the tests/code review over that. Worth actually clicking through
   once a fresh-enough test account exists, before this ships.

5. **(workstream 6) Pet Types + Breeds → Pets merge** (branch/PR: shared with
   workstream 4, `feat/settings-promos-rewards-merge` / draft PR #202,
   **implemented, tests passing, committed locally
   (`a592b63`), not yet pushed/added to the PR**) — _Which files:_ a new
   page, `AdminPetsPage`, wraps the existing (unmodified) Pet Types and
   Breeds pages behind the same two-tab bar shape as workstream 4,
   replacing their two separate Config entries with one "Pets" entry. —
   _Why:_ item 8 above, directly mirroring the already-proven
   Services/Service-Types/Packages pattern. Built first (of the three
   remaining pieces) since it's the smallest/lowest-risk, matching the
   proven wrapper pattern exactly with no schema or plumbing changes.

6. **(reward-pool task, unnumbered in the original nine) "…" menu** (branch/PR:
   shared with workstream 4, **implemented, tests passing, committed
   locally (`3f91e24`), not yet pushed/added to the PR**) — the tenth,
   newly-surfaced task (see "What you asked for" addendum above).
   Everything it needs already existed server-side (`PATCH
/rewards/spin-wheel/rewards/:id` already accepted every field a
   "Configure" edit needs, and the Deactivate/Archive actions already
   existed too, just as two always-visible plain buttons) - this was a
   UI-only change: the two buttons became one "…" menu (Configure /
   Deactivate / Archive, Archive only shown once inactive, matching
   Promos/Discounts' own row-menu convention), and "Configure" opens the
   reward pool's _first-ever_ edit modal (until now only creating a new
   reward was possible, not editing one), reusing the existing create
   modal/form rather than adding a second one.

7. **(workstream 5) System Configuration → Branches** (branch/PR: shared with
   workstream 4, **implemented, tests passing, deliberately left
   UNCOMMITTED** - by far the largest of the three pieces, built last on
   purpose) — _Which files:_ a new migration adds `is_active` and
   `archived_at` columns to the `branches` table, copying the exact same
   two-step "deactivate, then archive" pattern already used for
   discounts/promos/packages (so a branch can't be archived while still
   active — a safety rail, not a new idea; branches had neither column
   before this). A full new archive/deactivate service layer for branches
   was added server-side too (branches never had one) - `branches.service.ts`
   gained `archiveBranch`/`restoreBranch`/`listArchivedBranches`/
   `hardDeleteBranch`, mirroring `promos.service.ts`'s own four almost
   verbatim, plus 4 new routes and an `is_active` field on the update
   validator. The page (renamed `SystemConfigurationPage` →
   `BranchesPage`, old directory deleted) was rebuilt using the same
   shared search/sort/filter/view toolbar as `AdminCagesPage` (it used to
   be just a single-branch edit form with a plain dropdown, not a browser
   at all) - branch identity/operating-hours editing itself didn't change
   in substance, it just moved from being always on-page to a per-row
   "Edit" modal (the create/edit form got merged into one reusable modal,
   same pattern as the reward-pool task above). Each branch row's "…" menu
   ended up with **four** items, not three - Edit was a gap the original
   nine-task wording didn't call out (it only listed
   Configure/Deactivate/Archive) but the branch-editing capability the old
   page provided had to go somewhere once the page stopped being "one
   always-visible form for the selected branch." **Policies** stopped
   being its own separate Config entry — instead, clicking "Configure" on
   a branch row opens the Policies page pre-scoped to that one branch (its
   branch dropdown gets locked to that branch instead of showing a
   picker). Policies is still reachable as its own standalone page outside
   Settings for anyone with an old link to it, rendering with neither new
   prop set. — _Why:_ items 6 and 7 above.

   This required new plumbing that didn't exist anywhere in Settings
   before: `SettingsPage.tsx` could only ever render an embedded Config
   tile with zero props (`<activeConfigTile.Component />`, no way to pass
   anything in) - extended with a `pendingConfigProps` state and a second,
   optional argument to `selectConfigTile` so a tile can hand props to
   whatever it navigates to. A `POLICIES_HIDDEN_TILE` constant (same shape
   as a normal Config tile, but deliberately left out of the exported
   `CONFIG_TILES` list) lets Policies still be resolved and rendered
   on-demand without reappearing in the sidebar/tile grid - verified by
   reading `SettingsPage.tsx` directly that the sidebar's own tile list and
   the tile-lookup-for-rendering both read the same underlying list, so
   this had to be a second, separate lookup (`HIDDEN_CONFIG_TILES`) rather
   than just adding Policies back into the main one. `SYSTEM_CONFIG_TILE`
   was also renamed to `BRANCHES_TILE` for clarity (its content no longer
   matched its old name), and `ConfigTileConfig.Component`'s type widened
   from a bare prop-less `ComponentType` to `ComponentType<any>` so a tile
   can optionally accept props like this without every other tile needing
   to change.

   **Verification: 62 new/updated client tests + 19 server tests, all
   passing** (branches service archive/deactivate logic, the rebuilt
   page's list/edit/deactivate/archive/configure flows, both the
   pre-scoped-via-Settings and standalone-with-fallback-navigation paths
   for Configure). Full client suite (1241 tests) and full server suite
   (1184 tests) both run clean apart from a handful of pre-existing,
   unrelated timeout flakes (`AdminPackageBuilderPage`,
   `AdminPromoConfigPage`, `AdminServicesPage`, `staffAuth.api`,
   `AboutPage`, `AuthCard`, `CustomerBookingFlowPage` - confirmed by
   re-running each in isolation, where they pass cleanly; this machine
   gets flaky under heavy parallel jsdom load, not a real regression) -
   none of those files were touched this session. No live-browser
   click-through yet, same reason as workstream 4: every seeded
   Admin/Superadmin test account is still MFA-locked from cumulative
   testing this session.

## Words you might not know

- **migration** — a small file that changes the shape of the database
  (adds a table, a column, a rule) in a tracked, repeatable way, so every
  copy of the database (a developer's laptop, the shared test database,
  the live one) ends up with the exact same structure.
- **CSS custom property** — a named value (written `--like-this`) that CSS
  can set on a parent element and read on any descendant with
  `var(--like-this, fallback)`; used here so Settings can override one
  page's height rule only while that page is embedded inside it.
- **React Context** — a way to share one value (and functions to change
  it) across many components at different nesting depths, without manually
  passing it down as a prop through every component in between.
- **preset gallery** — a small, fixed set of ready-made pictures a user can
  pick from instead of uploading their own.
- **soft-delete / archive pattern** — instead of permanently deleting a
  row the moment someone clicks delete, it's first marked inactive
  (reversible), and only later, as a separate deliberate step, marked
  archived (a timestamp is set, meaning "soft-deleted" — the row still
  exists but is hidden from normal views). This app already uses this
  two-step pattern for several other things (discounts, promos, packages),
  and Branches is getting the same one rather than inventing something new.
- **mini navbar subtabs** — a small row of tab buttons placed above two or
  more existing pages, letting them share one Settings entry while staying
  otherwise unchanged — the same shape already used for Services/Service
  Types/Packages.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks — filled in as each
workstream finishes (workstream 1 is done and verified; workstreams 2–6
are not started yet).
