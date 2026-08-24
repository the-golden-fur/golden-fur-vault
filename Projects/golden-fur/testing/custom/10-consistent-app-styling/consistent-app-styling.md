# Bring the rest of the app up to the Landing Page's visual polish

Custom request (not tied to an epic/issue). Branch:
`refactor/staff-dirs-and-custom-errors` (worked directly on the current
branch — no dedicated feature branch existed for this request). CSS-only
change: no `.tsx`/`.ts` files were touched anywhere in this pass.

## Why

`client/src/pages/LandingPage/` (the public marketing page) looks noticeably
richer than the rest of the app — rounded elevated cards, hover-lift
buttons, a warm gold/brown palette, a display font for headings. Every other
page/component was using the shared design tokens correctly but flatly (flat
borders, little/no shadow, no hover motion), so the app read as two
different products. Asked to bring everything else up to the same level of
polish, using the existing token system in `client/src/styles` rather than
copy-pasting the Landing Page's hand-rolled values, and to adjust the
Landing Page itself where it had drifted from those tokens.

## What changed

### 1. Shared tokens (`client/src/styles`)

- `variables/typography.css`: `--font-main` now leads with `'Poppins'`
  (previously `system-ui, Avenir, Helvetica, Arial, sans-serif` — Poppins
  was already loaded app-wide via the Google Fonts `<link>` in
  `client/index.html`, but only the Landing Page was using it). This one
  token change cascades Poppins as the body font to every page in the app,
  since virtually every `.module.css` already reads `var(--font-main)`.
- Added a new `--font-display: 'Luckiest Guy', cursive;` token (the Landing
  Page's heading font, also already loaded but previously hardcoded only in
  `LandingPage.module.css`) so any page can opt into it for a large title
  without duplicating the font stack string.

### 2. `LandingPage.module.css` — aligned to the tokens instead of drifting from them

- Replaced the 7 hardcoded `font-family: 'Poppins', sans-serif;` /
  `'Luckiest Guy', cursive;` declarations with `var(--font-main)` /
  `var(--font-display)`.
- Replaced the two hardcoded background gradients with the closest existing
  color tokens: body background now uses `var(--color-surface)` →
  `var(--color-nav-active-bg)` (was `#fff8eb`/`#f8e4c3` — `--color-surface`
  is an exact match for the first stop, `--color-nav-active-bg` is a
  near-exact match for the second); the booking "previous" button gradient
  now uses `var(--color-bg-secondary)` for its first stop.
- Left alone: a handful of one-off decorative `rgba()` shadow/overlay tints
  (glass-morphism navbar, feature-card overlays, footer's fixed dark
  gradient) that have no equivalent token in `colors.css` — forcing those
  into a token would either be a poor color match or, for the footer,
  incorrectly tie a deliberately-always-dark brand footer to the
  light/dark theme switch.

### 3. `client/src/pages/{SettingsPage,NotFoundPage,ServerErrorPage}` — reference calibration

Done by hand first, to set the polish bar for a _dashboard/utility_ context
(less flashy than the marketing page, but clearly "the same design family"):
elevated card container (`--shadow-card`, `--radius-xl`), `--font-display`
for the big `404`/`500` code and page title, pill-shaped primary
link/button with hover-lift, and a subtle mount transition using the
(previously unused) `.animate-fade-in`/`.animate-slide-up` utility classes
already defined in `client/src/styles/animations.css`.

### 4. The rest of the app — 62 CSS Modules across 4 areas

Applied the same treatment (token-only color fixes, `--shadow-card`/
`--shadow-sm/md/lg` elevation, hover-lift transforms, pill-radius primary
buttons/badges, `composes: animate-fade-in/animate-slide-up from global;`
on page containers) to every remaining `.module.css` in the app:

- **Shared components + auth** (18 files): `Footer`, `SessionExpiryModal`,
  `ThemeToggle`, `MfaSetupModal`, `TotpEnrollPanel`, `Navbar`, `StatusBadge`,
  `ToggleSwitch`, `ErrorBoundary`, both staff/customer login forms and
  pages, signup, MFA challenge, and password reset.
- **Staff feature area** (13 files): `StaffProfilePage`, staff/customer
  admin forms, `UnavailabilityReviewCard`/`ApprovalQueuePage`,
  `AdminCustomerListPage`, `AdminStaffListPage`, `DashboardTile`,
  `StaffDashboardPage`.
- **Customers + maintenance + discounts** (13 files): `PetCard`, `PetForm`,
  medical/vaccination lists, customer profile/pet/portal pages,
  `ServiceMultiSelect`/`ServicePricingTierEditor`, and the admin package
  builder / services / discounts / promo pages.
- **Booking + grooming/vet/daycare** (17 files): `BookingStepper`,
  `SlotPicker`, `StaffPickerList`, `BookingStatusBadge`, the customer
  booking flow/list and receptionist queue pages, daycare check-in/out,
  `AppointmentCard`/`GroomingStatusBadge`/`GroomerDashboardPage`,
  `ConsultationStatusBadge`/`PetHistoryTab`/`VeterinaryConsolePage`.

**Deliberately left alone:** `HomePage`/`ProfilePage` (both the `.tsx` and
`.module.css` are empty stub files — nothing to style yet),
`UnavailabilityBlockBadge` (non-interactive status badge, already correct),
`StaffCard`/`StatusBadge` (already at the target polish level), a couple of
third-party OAuth brand-color buttons (Google/Facebook blues are brand
identity, not app palette), and modal backdrop scrims (kept a neutral dark
overlay rather than tinting them gold, since a scrim should read as
theme-independent).

**Guardrails every batch followed:** no `.tsx`/`.ts` file was edited; no CSS
class was renamed, added, or removed (each agent grepped the sibling `.tsx`
before touching a selector); no semantic status-color pairing changed
(booking confirmed/pending/cancelled/no-show, grooming/consult/daycare
status tiers, slot available/partial/full, active/inactive, etc. all still
map to the exact same tokens as before — only their chrome/shape/motion
changed).

## Verification performed

- `npm run build` (client) — `tsc -b && vite build` — clean, no type errors,
  CSS compiled without error.
- `npm run lint` (client) — clean.
- `npm run test:run` (client) — 78 files / 292 tests passed.
- `git diff --stat` — 63 files changed (62 restyled + `typography.css`),
  895 insertions / 114 deletions, no `.tsx`/`.ts` in the list.
- Manually spot-checked every `composes: ... from global;` usage resolves to
  a real class in `animations.css` (confirmed by the successful `vite
build` — an unresolved `composes from global` target fails the build).

## How to verify yourself

1. From the repo root: `npm run dev` (client on :5173).
2. Visit `/` (Landing Page) — should look the same as before, just
   confirm the fonts still render (Poppins body copy, Luckiest Guy
   headings) and the hero/footer colors look unchanged.
3. Visit `http://localhost:5173/this-does-not-exist` and
   `http://localhost:5173/error` — both should now show an elevated card
   with a gold "Luckiest Guy" 404/500 code, a pill "Back to home" button
   that lifts on hover, and a brief fade/slide-in on load.
4. Log in as a customer account and check a light-themed page, e.g. the
   booking flow or pet profile — buttons should be pill-shaped with a
   hover-lift + shadow, cards should have visible elevation that grows on
   hover.
5. Log in as a staff account (e.g. `makati.groomer1` / `password123`) and
   check a dark-themed page, e.g. the Staff Dashboard or Groomer Dashboard —
   confirm the same pill-button/hover-lift/elevation treatment reads
   correctly against the dark palette (nothing should look washed out or
   use a stray light-theme color).
6. Resize to mobile width on a couple of the touched pages to confirm no
   layout/breakpoint regressions were introduced (only chrome — radius,
   shadow, color, motion — was changed, not layout).

## No Postman collection or SQL file for this request

Purely a client-side CSS styling pass — no API routes or DB objects were
touched.
