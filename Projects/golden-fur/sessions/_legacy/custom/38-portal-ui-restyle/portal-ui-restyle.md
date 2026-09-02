# Adapt the portal UI to the temp/design mockups

Custom request (not tied to an epic/issue). Suggested branch:
`style/portal-ui-restyle`. CSS/token-only change plus one Google Fonts
`<link>` edit: no `.tsx`/`.ts` file was touched.

## Why

`temp/design/{admin,cashier,customer,groomer,receptionist,super_admin,vet}.png`
are Figma exports of a refreshed look for every portal. The request was to
adapt the app's existing color palette/typography to match those mockups —
not to build any new page or feature, and not to reintroduce role-based
theming (`data-theme='staff'/'customer'` already carries no color tokens per
`tokens.css`'s own header comment; only `data-color-mode` light/dark should
control color).

The mockups themselves show a wrinkle: every staff portal (admin, vet,
groomer, cashier, receptionist) uses a white/cream nav sidebar, while the
customer portal keeps a dark-brown gradient sidebar. That reads as a
role-based split. Flagged this to the requester before touching any code —
resolution was to keep a single light/dark switch for everyone (Settings >
Appearance), not a role split: **light mode → cream/white sidebar** (matches
the majority of the mockups), **dark mode → the existing dark-brown gradient
sidebar** (matches the customer mockup's look, and doubles as a coherent
"dark mode" everywhere else in the app).

## What changed

### 1. `client/src/styles/tokens.css` — palette

- Light mode: `--color-bg-primary` and `--color-surface` nudged to the
  cream/white sampled from the mockups (`#fdf6e6` / `#fffefb`, previously
  `#f7f2e8` / `#fff8eb` — both very close, low-risk shift).
- New token pair, **light and dark**: `--color-portal-nav-*` (`bg-start`,
  `bg-end`, `text`, `hover-bg`, `border`, `active-bg`, `active-border`,
  `active-text`). This is what `Sidebar.module.css` now reads, deliberately
  kept separate from `--color-sidebar-grad-*`/`--color-text-on-sidebar`,
  which stay untouched and keep serving the login-page hero panel
  (`StaffLoginPage`, `CustomerLoginPage`/`CustomerSignupPage`) and the
  marketing pages (`LandingPage`, `AboutPage`, `BranchesPage`,
  `PackagesPromosPage`) — those are brand moments that should keep their
  dark-gold-gradient look regardless of the in-app light/dark toggle, same
  as before this change.
  - Light mode: `--color-portal-nav-bg-start/-end` → white/cream,
    `--color-portal-nav-text` → dark brown, `--color-portal-nav-active-bg` →
    vivid gold pill (matches the mockups' active nav item).
  - Dark mode: mirrors the existing `--color-sidebar-grad-*` dark values
    (already the right look, so it's a straight alias).

### 2. `client/src/shared/components/Sidebar/Sidebar.module.css`

Every color reference (`background`, `border-right`, link/section-label
text, hover state, active-item pill) swapped from
`--color-sidebar-grad-*`/`--color-text-on-sidebar`/`--color-nav-active-*` to
the new `--color-portal-nav-*` tokens. No selectors added/removed/renamed —
`Sidebar.tsx` was not touched.

### 3. Typography — serif headings

- `client/src/styles/variables/typography.css`: added
  `--font-heading: 'Playfair Display', Georgia, 'Times New Roman', serif;`
  (the elegant serif used for every page title / wordmark in the mockups),
  distinct from the existing `--font-display` (`'Luckiest Guy'`, the
  playful cursive used only on public marketing pages — untouched).
- `client/index.html`: added `Playfair Display` to the existing Google
  Fonts `<link>` (alongside Great Vibes/Luckiest Guy/Poppins, which were
  already there).
- Swapped `font-family: var(--font-main)` → `var(--font-heading)` on every
  heading-like class (`.title`, `.sectionTitle`, `.modalTitle`, `.logo`,
  `.brand`, `.card h1`, `.hero h2`) across **31 `.module.css` files** — done
  with a small one-off script that only rewrites the declaration when the
  _immediately enclosing selector_ is one of that set, so body text, form
  labels (`.label`), buttons, and the error-page `.code` digits (which
  intentionally keep `--font-display`) were left alone. Verified via
  `git diff` that every changed line is exactly that one swap, nothing else.
  Two more `.logo` classes (`CustomerLoginPage`, `CustomerSignupPage`) had
  no explicit `font-family` at all (inherited `--font-main` from `body`) —
  added `font-family: var(--font-heading)` to those by hand for wordmark
  consistency with `StaffLoginPage`/`Navbar`'s `.logo`/`.brand`.

### 4. Login hero panel unified across staff + customer (follow-up)

After the first pass, side-by-side screenshots showed the two login pages'
hero panels diverging in an inconsistent way: `StaffLoginPage`'s `.left`
used `--color-sidebar-grad-*` (always brown, in both modes), while
`CustomerLoginPage`/`CustomerSignupPage`'s `.left` used
`--color-hero-gradient-*` (gold in light mode, but a flat near-black
gradient in dark mode). Feedback: keep staff's dark-mode look (the warm
brown gradient), keep customer's light-mode look (the gold gradient), and
make both pages share it — the customer page's dark mode specifically read
as broken/flat next to staff's.

- Replaced `--color-hero-gradient-*` with a new shared
  `--color-login-hero-bg-start/-mid/-end` pair in `tokens.css`: light mode
  keeps the old gold values (`#d9b36b`/`#c88a1b`/`#d0a24d`), dark mode is now
  a warm brown gradient (`#4f2d17`/`#3a2010`/`#2a180c`) instead of the old
  near-black one.
- `StaffLoginPage.module.css` `.left` now uses the same
  135deg/3-stop gradient shape as the customer pages (was a 160deg 2-stop
  brown-only gradient) with these new tokens, and its text
  (`.logo`/`.hero h2`/`.hero p`/`.feature .label`) switched from
  `--color-text-on-sidebar` to `--color-text-on-heropanel` (the token the
  customer pages already used, already tuned to read on both a gold and a
  dark-brown background).
- `CustomerLoginPage`/`CustomerSignupPage.module.css` `.left` now reads the
  new `--color-login-hero-bg-*` tokens instead of the removed
  `--color-hero-gradient-*`, and their stray `.hero p` (which used
  `--color-text-on-sidebar`, not `--color-text-on-heropanel` like the rest
  of the panel — a pre-existing inconsistency) now matches the rest of the
  panel.
- `--color-sidebar-grad-*` and `--color-text-on-sidebar` are untouched and
  still back the marketing pages (Landing/About/Branches/Packages) and
  `ThemeToggle` — only `StaffLoginPage` stopped reading them.
- Re-verified: `npm run build` clean; re-screenshotted both login pages in
  both `prefers-color-scheme` values — staff and customer hero panels are
  now pixel-identical in shape/color per mode (gold in light, warm brown in
  dark).

### 5. Login card/button/watermark parity (second follow-up)

Side-by-side review after §4 still showed the staff and customer login
cards reading as different colors, and asked for the customer pages' paw
watermarks on staff too. Investigated with the actual rendered CSS (not
just the shared gradient tokens) and found two real token bugs, plus the
watermark gap:

- **Card background bug**: `CustomerLoginPage`/`CustomerSignupPage`'s
  `.card` (and `.tabActive`) used `var(--color-bg-primary)` - the _page_
  background - instead of `var(--color-surface)`, which
  `StaffLoginPage`'s `.card` correctly uses. In dark mode
  `--color-bg-primary` (`#1f140b`, near-black) and `--color-surface`
  (`#33220f`, lighter warm brown) are visibly different, so the customer
  card barely stood out from the page while staff's clearly did. Fixed
  both files to use `--color-surface`, matching staff.
- **Submit button bug**: `CustomerLoginForm`/`CustomerSignupForm`'s
  `.submit` used `background: var(--color-text-primary); color:
var(--color-bg-primary);` - a text/bg color inversion - instead of the
  accent-gold treatment (`background: var(--color-accent); color:
var(--color-accent-fg);`) `StaffLoginForm`'s `.button` already used. This
  is why the customer "Sign in"/"Create account" button rendered
  cream/off-white instead of gold in both modes. Fixed both files to match
  staff's accent-gold button.
- **Input background inconsistency**: `StaffLoginForm`'s `.input` used
  `var(--color-bg-primary)` where every other form in the app (including
  `CustomerLoginForm`/`CustomerSignupForm` and the global bare-input
  fallback in `styles/base/forms.css`) uses `var(--color-surface)`. Fixed
  `StaffLoginForm.module.css` to match the app-wide convention instead of
  changing everyone else to match the outlier.
- **Paw watermarks**: extracted the `Paw` SVG component (previously
  copy-pasted identically in `CustomerLoginPage.tsx` and
  `CustomerSignupPage.tsx`) into a new shared
  `client/src/shared/components/PawWatermark/PawWatermark.tsx`, both
  customer pages now import it instead of duplicating it, and
  `StaffLoginPage.tsx`/`.module.css` now render the same three watermarks
  in the same positions (`.paw`/`.p1`/`.p2`/`.p3`, plus `overflow: hidden`
  on `.left` and `position: relative; z-index: 1;` on `.hero`/`.features`
  so the in-flow text still paints above the absolutely-positioned
  watermarks, mirroring the customer pages' existing stacking setup).

Re-verified: `npm run build`/`lint` clean; re-screenshotted all three pages
(`StaffLoginPage`, `CustomerLoginPage`, `CustomerSignupPage`) in dark mode
side-by-side - hero gradient, paw watermarks, card surface color, and
primary button color are now all pixel-consistent across the three.

**Aside - dev server port collision:** while investigating a "staff login
suddenly stopped working" report during this pass, found a leftover `vite`
dev server of mine still bound to port 5173, which had pushed the
requester's own `npm run dev` to port 5174 - not in the backend's
`CORS_ALLOWED_ORIGINS` allowlist, so every API call (including login) was
being rejected by CORS. Not a code regression; killed the stray process.
Worth knowing if this ever recurs: check `netstat -ano | findstr :5173`
before assuming a login failure is code-related.

### 6. Paw watermark shape fix (third follow-up)

The `PawWatermark` ellipses added in §5 didn't actually read as a paw
print: the old layout (inherited as-is from the original `Paw` component)
put all 5 ellipses in a single row at roughly the same height, so it
rendered as a loose cluster of dots rather than a paw. Rewrote
`client/src/shared/components/PawWatermark/PawWatermark.tsx`'s coordinates
to the standard paw silhouette instead: one large rounded main pad at the
bottom-center (`cx:50, cy:68, rx:22, ry:18`), with 4 toe pads fanned above
it in an arc, narrower/higher toward the middle
(`cx:20/38/62/80, cy:40/18/18/40`). Same component, same
`--color-text-on-heropanel` fill, same call sites (`StaffLoginPage`,
`CustomerLoginPage`, `CustomerSignupPage` all pick this up automatically
since they all render the shared component) - only the ellipse coordinates
changed. Re-verified: `npm run build`/`lint` clean; screenshotted
`StaffLoginPage` in dark mode and visually confirmed all 3 watermarks now
read as paw prints (one big pad, 4 toes fanned above).

### 7. Sidebar responsiveness + smooth collapse animation (fourth follow-up)

Two more issues from a screenshot of the actual dashboard sidebar (dark
mode): the `Navbar` brand wordmark ("Golden Fur Staff") wrapped to two
lines and overlapped the navbar's bottom border at narrow widths, and the
sidebar's collapse/expand was asked to be "extra smooth."

- **`Navbar.module.css`**: `.brand` had no width constraint, so at
  narrower viewports (below where the mobile hamburger breakpoint kicks
  in) it could wrap instead of truncating. Added `min-width: 0;
flex-shrink: 1; overflow: hidden; white-space: nowrap; text-overflow:
ellipsis;` so it truncates with an ellipsis instead of wrapping, and
  `flex-shrink: 0` on `.menuToggle`/`.links` so they hold their size and
  the brand shrinks first. Also added the same `overflow: hidden;
white-space: nowrap; text-overflow: ellipsis;` safety net to
  `Sidebar.module.css`'s `.sectionLabel` (nav item labels already had
  equivalent protection via `.link`'s `white-space: nowrap`, inherited by
  `.linkText`).
- **`Sidebar.module.css`/`Sidebar.tsx` - smooth collapse**: previously,
  collapsing snapped the nav-item text to screen-reader-only instantly
  (`clip: rect(0,0,0,0)` + absolute positioning) while only the sidebar's
  own `width` animated, and section headings (`<h2>{section.label}</h2>`)
  were removed from the DOM outright on collapse (`{section.label &&
!collapsed ? ... : null}` in `Sidebar.tsx`), so they could only pop in
  instantly on expand. Changed both to animate:
  - `Sidebar.tsx`: section headings now always render
    (`{section.label ? ... : null}`); the collapsed state hides them
    with CSS instead of unmounting them.
  - `.linkText`: replaced the clip-hack with `opacity`/`max-width`/
    `margin-left` transitions (`280ms cubic-bezier(0.4, 0, 0.2, 1)`), so
    text fades and shrinks in sync with the sidebar's own width
    transition instead of disappearing instantly. Moved the icon-to-text
    gap from `.link`'s `gap` (a non-animatable container property) onto
    `.linkText`'s `margin-left` so it collapses to 0 smoothly too, instead
    of leaving a stray gap next to the centered icon.
  - `.sectionLabel`: same treatment (`opacity`/`max-height` transition)
    instead of a hard mount/unmount.
  - `.sidebar`/`.sidebarCollapsed`: eased the width transition from
    `180ms ease` to `320ms cubic-bezier(0.4, 0, 0.2, 1)` (a slower,
    standard "ease-out" curve) to read as noticeably smoother rather than
    a quick snap.
  - Accessibility note: swapping the clip-rect sr-only technique for
    opacity/max-width doesn't change what's exposed to assistive tech -
    neither `opacity` nor `max-width` remove an element from the
    accessibility tree, so collapsed nav labels are still announced by
    screen readers either way (same as before).
  - `Sidebar.spec.ts`: updated the one test that asserted the old
    unmount-on-collapse behavior (`expect(...).not.toBeInTheDocument()`
    for the section heading) to assert the heading **is** still in the
    document when collapsed, matching the new CSS-only hide.

Re-verified: `npm run build`/`lint`/`test:run` all clean (591/591 tests,
including the updated Sidebar spec). Visually confirmed via a standalone
harness built from the real CSS: brand truncates cleanly instead of
wrapping at 500px width; the collapsed end-state has no stray gap next to
the centered icons and no leftover empty space from the now-invisible
section labels.

### 8. Sidebar: actually fix wrapping, spacing, and the collapse toggle (fifth follow-up)

§7's ellipsis-truncation fix for `.linkText` still wasn't enough - the real
bug (confirmed by tracing the actual flexbox math, not just eyeballing
screenshots) was that `.linkText` had no `min-width: 0`. Flex items default
to `min-width: auto`, i.e. "never shrink below my own content's width" -
so `text-overflow: ellipsis` was defined but could never actually trigger;
long labels just pushed `.link` wider than the sidebar and got hard-clipped
by `.sidebar`'s `overflow-x: hidden` instead of truncating or wrapping.
Follow-up feedback confirmed the actual desired behavior is wrapping, not
truncation (losing words to an ellipsis is worse for a functional nav
label than the row growing taller), plus more breathing room generally,
plus the collapse toggle button looking inconsistently placed/sized
between expanded and collapsed.

- **`.sidebar` width**: `15rem` → `16.5rem` - more breathing room for
  labels at the default width before wrapping is ever needed.
- **`.itemList` gap**: `--space-0-5` (4px) → `--space-1` (8px) - less
  cramped vertically between nav items.
- **`.link`**: dropped `white-space: nowrap` (the actual root cause,
  combined with the missing `min-width: 0` below); added `line-height: 1.3`
  for readable wrapped text.
- **`.linkText`**: added `min-width: 0` (the real fix) and
  `overflow-wrap: break-word`; removed the `overflow:
hidden`/`text-overflow: ellipsis` single-line truncation in favor of
  natural wrapping. Long labels now wrap onto a second line at the
  sidebar's normal width instead of being clipped or overlapping
  neighboring content.
- **Regression caught before shipping**: enabling wrap on `.linkText`
  while it still animates toward `max-width: 0` on collapse meant the
  browser reflowed the wrapping text word-by-word (eventually
  letter-by-letter) into a tall single-character column as its available
  width approached zero - `opacity: 0` hid it visually, but it still
  occupied layout height, ballooning `.link`'s height for the entire
  collapse transition (caught via the CSS harness screenshot, not the
  build/lint/test suite - none of those exercise real layout). Fixed by
  adding `white-space: nowrap; overflow: hidden; max-height: 0;` to the
  existing `.sidebarCollapsed .linkText` override, alongside the
  `opacity`/`max-width`/`margin-left` it already had - forces a single
  suppressed line instead of a reflow cascade while collapsing.
- **`.collapseToggle`**: added an explicit `width: 2.25rem; height:
2.25rem;` (previously auto-sized from icon + padding with nothing
  pinning it, so it had no guaranteed consistent footprint) and a new
  `.sidebarCollapsed .collapseToggle { align-self: center; }` - it
  previously stayed `align-self: flex-end` in both states, which
  right-aligned it against the _expanded_ 16.5rem column but looked
  off-center against the _collapsed_ column's center-aligned icons below
  it (the "shrinks to oblivion"/"not proportional" look - the button
  wasn't shrinking, it just wasn't aligned consistently with the rest of
  the rail once the column narrowed).

Re-verified: `npm run build`/`lint`/`test:run` clean (591/591). Rebuilt the
CSS harness with a deliberately absurd long label
("A Really Unreasonably Long Nav Item Label Here") alongside real ones and
confirmed: normal labels sit comfortably on one line at the new width,
long ones wrap cleanly onto 2-3 lines without overlapping siblings, the
collapsed state has no leftover tall boxes or misaligned toggle button,
and the active item's pill still hugs just the icon when collapsed.

### 9. Collapsed sidebar: measured the actual bug instead of eyeballing it (sixth follow-up)

§8 didn't fully fix the collapsed rail - a follow-up screenshot showed the
toggle button, nav icons, and section spacing all still reading as
inconsistent. Screenshot-comparison had stopped being reliable at this
point (the CSS harness had produced two false leads already: a missing
`layout.css` import in §7 and a viewport accidentally under the 640px
mobile breakpoint this round, which zeroes the collapsed sidebar's width
entirely by design and made early measurements nonsensical). Switched to
measuring actual `getBoundingClientRect()`/`getComputedStyle()` values via
a scripted CDP session instead of trusting screenshots, which surfaced the
real, previously-misdiagnosed bug:

- **The actual root cause**: `.link`'s horizontal padding
  (`var(--space-2)` = 16px each side = 32px total) was tuned for the
  16.5rem _expanded_ rail and was never adjusted for the 3.75rem
  _collapsed_ one. The collapsed rail only has ~28px of interior width
  once the sidebar's own padding is subtracted - so the padding alone
  already exceeded the available space before the icon was even added.
  The icon wasn't failing to center _within_ the rail; `.link` itself was
  being forced wider than the rail (measured 53px, then 42.6px, in two
  successive investigation passes) and centering fine _within its own
  oversized, off-axis box_. Fixed with a `.sidebarCollapsed .link`
  override: `padding: var(--space-1) var(--space-0-5)` (8px/4px instead
  of 8px/16px) - confirmed by measurement afterward that the link's
  center now lands within ~2px of the sidebar's true center (the small
  residual is a test-harness artifact - an emoji placeholder character
  instead of the app's actual 17px SVG icon - not a real app issue).
- **Contributing bug found along the way**: `.section` and `.itemList`
  (both `display: grid`) and the `<li>` items didn't have `min-width: 0`
  either, so - independent of the padding issue - they could also grow
  past their grid track's available width instead of being constrained to
  it (the same `min-width: auto` flex/grid default that caused the §8
  wrapping bug, recurring one level up the tree). Added `min-width: 0` to
  `.nav`, `.section`, `.itemList`, and `.itemList > li`, plus `width:
100%; min-width: 0; box-sizing: border-box;` to `.link` itself.
- **Uneven section spacing** (the "no spacing"/"not even" part of the
  feedback): confirmed by measurement that collapsed sections were 32px
  apart (the expanded state's 24px `.nav` gap plus an 8px leftover from
  `.section`'s own label-to-list gap, which doesn't disappear just because
  the label above it is invisible) while items _within_ one section were
  only 8px apart - a 4x jump with no visual explanation once the section
  label itself is hidden. Added `.sidebarCollapsed .nav { gap:
var(--space-2); }` (16px) and `.sidebarCollapsed .section { gap: 0; }`
  (dropping the now-pointless label-row gap entirely) so every section
  boundary is a uniform 16px - confirmed by measurement (`[16, 16, 16,
16]` across all 5 section boundaries in the test sidebar).
- **Toggle button**: re-measured and confirmed §8's fix
  (`align-self: center` in the collapsed state, explicit `36×36px` size)
  was already correct on its own - `toggleButtonCenterX` measured 29.5
  against a true sidebar center of 30, well within a rounding error. It
  never actually needed a §9 change; it was the nav _links_ that were off,
  not the toggle, despite them looking similarly displaced in the
  screenshot.

Re-verified: `npm run build`/`lint`/`test:run` clean (591/591). This round
leaned on programmatic measurement (`getBoundingClientRect` center-point
math, section-gap deltas) rather than visual screenshot comparison, since
screenshot-eyeballing had already produced two wrong conclusions earlier
in this same investigation.

### Deliberately left alone

- Every other color token (accent/status/booking/grooming/cage/etc. badge
  pairs, dark-mode palette) — already closely matched the mockups' warm
  brown/gold hue family, including deliberate past contrast tuning noted in
  `tokens.css`'s own comments (the "poop brown" dark-mode history). Changing
  hues there wasn't needed and risked undoing that tuning.
- The mockups' "Staff Availability" busy/available/absent card feature
  (`temp/design/admin.png`, Staff Accounts page) — no such page/component
  exists in the codebase yet. Per the request ("you're just adapting...
  color palettes", "YOU ARE NOT creating new pages"), this pass only
  restyled what already exists; it didn't build that feature or invent a
  "busy" purple status token for it.
- `LandingPage`/`AboutPage`/`BranchesPage`/`PackagesPromosPage` and their
  hardcoded hex colors — out of scope (design/ only covers portal
  dashboards) and just went through their own restyle in the immediately
  prior commit (`087d98c`).
- Login-hero-panel / marketing-page dark-gold-gradient tokens
  (`--color-sidebar-grad-*`, `--color-text-on-sidebar`,
  `--color-hero-gradient-*`) — kept exactly as-is (see §1).

## Verification performed

- `npm run build` (client) — `tsc -b && vite build` — clean, no type/CSS
  errors.
- `npm run lint` (client) — clean.
- `npm run test:run` (client) — **128 files / 591 tests passed**, confirming
  no regressions (expected: no `.tsx`/`.ts` logic was touched anywhere).
- `git diff --stat` — 33 files changed (32 restyled + `tokens.css` +
  `typography.css` + `index.html`), no `.tsx`/`.ts` in the list.
- Rendered and screenshotted (headless Chrome, both `prefers-color-scheme`
  values) `StaffLoginPage` and `CustomerLoginPage` against the real running
  dev server, and a standalone harness built from the real
  `tokens.css`/`Sidebar.module.css`/`Navbar.module.css` (mimicking the
  Admin "Overview" page structure from the mockup) for light **and** dark
  mode, since logging into an actual dashboard route requires a local
  Supabase/Docker stack that isn't running in this environment. All four
  visually matched the mockups' look: cream/white sidebar with a gold
  active-nav pill and serif page title in light mode; the existing
  dark-brown gradient sidebar in dark mode; serif "Golden Fur"
  wordmark/headings; pill-shaped gold primary buttons; white/cream elevated
  cards.

## How to verify yourself

1. From `client/`: `npm run dev` (serves on `:5173`).
2. Visit `http://localhost:5173/staff/login` and
   `http://localhost:5173/login` (customer). Both should show a
   serif "Golden Fur" wordmark, a serif page heading, and a gold pill
   primary button. The left/right split hero panel stays dark-brown-gradient
   on both — that's intentional (see §"Deliberately left alone").
3. Log in as a seeded staff account (e.g. `makati.admin1@goldenfur.com` /
   `password123` — see `testing/docs/custom/04-reset-supabase-seed-data` for
   how to stand up the local Supabase stack if it isn't already running) and
   open any dashboard page, e.g. Staff Accounts or the main Overview:
   - **Light mode** (Settings > Appearance): the left nav sidebar should be
     white/cream with a gold pill around the active nav item, not the old
     dark-brown bar.
   - **Dark mode**: the sidebar should still be the familiar dark-brown
     gradient — unchanged from before this pass.
   - Page titles ("Golden day, ...", "Staff Accounts", etc.) should render
     in the serif `Playfair Display` font; body text/labels/buttons stay in
     Poppins.
4. Log in as a customer account and open the dashboard/portal pages — the
   sidebar stays the dark-brown gradient in both light and dark mode (by
   design, matching the mockups — see §"Why").
5. Toggle Settings > Appearance between Light/Dark/Device default on a few
   pages in each portal and confirm nothing looks half-themed (no
   light-mode color stranded on a dark background or vice versa).

## No Postman collection or SQL file for this request

Purely a client-side CSS/typography styling pass — no API routes or DB
objects were touched.
