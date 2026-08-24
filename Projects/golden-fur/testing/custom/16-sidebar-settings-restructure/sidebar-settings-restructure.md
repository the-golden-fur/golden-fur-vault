# Sidebar Navigation + Settings Restructure

Type: Custom cross-cutting batch spanning the staff dashboard, the customer portal, and the shared Settings page for both roles.
Branch: `16-sidebar-settings-restructure` (suggested; based off `dev`).

## Scope

1. **Collapsible sidebar (staff + customer).** New `AppShell` (Navbar + `Sidebar`) replaces the bare `<Navbar/><Outlet/>` previously rendered by `StaffAuthGuard`/`CustomerAuthGuard`. The sidebar collapses/expands (persisted per role in `localStorage`) and highlights the active route. For staff, Admin/Superadmin see their nav grouped into labeled sections - Management, Receptionist, Groomer, Veterinarian, Cashier, Pet Assistant, Supervisor - since they already pass every one of those pages' `ALLOWED_VIEWER_ROLES` gate (confirmed by reading each one before writing this); every other staff role and the customer portal keep a single flat, unlabeled section, unchanged in appearance from before. Two previously-unlinked pages are now reachable: Daycare Checkout (`/staff/daycare/checkout`) under Receptionist for Admin/Superadmin, and (already-existing) Hotel Check-in/Checkout/Daycare Check-in are now also reachable from the Admin/Superadmin dashboard, not just Receptionist's own.
2. **Navbar identity chip.** Staff see `username · role`; customers see their full name (no role badge - customers don't have one). Clicking the chip opens Settings. The old "My Profile"/"Settings" text links are gone from the navbar dropdown - navigation now lives in the sidebar.
3. **Settings restructure: Profile / Account / Security / Config.** `SettingsPage` is now tabbed (`?tab=profile|account|security|config`, default `profile`):
   - **Profile** - display name, phone, emergency contact, comms preference (+avatar for staff). Moved unchanged from the retired `StaffProfilePage`/`CustomerProfilePage`.
   - **Account** (new) - username self-change (staff only - customers log in by email, no username column) and password self-change (both roles).
   - **Security** - MFA, moved unchanged from the pre-tabs `SettingsPage`.
   - **Config** (new, Admin/Superadmin only) - one entry point linking to every existing admin-config page (Services, Pricing, Packages, Promos, Promo Cap, Breeds, Hotel Food/Medication Catalogs, Discounts, System Configuration - System Configuration only shown to Superadmin). The pages/routes themselves are untouched; only their entry surface moved here from the admin dashboard, which now holds only day-to-day operational tiles (scope item 1).
4. **Pet Manager separated from Profile.** The customer's "My Pets" section, previously embedded in `CustomerProfilePage`, is now its own page at `/portal/pets` (`CustomerPetManagerPage`), reusing the same `PetCard`/`PetForm` components the old page used. `/portal/profile` and `/staff/profile` no longer exist - every internal `Navigate`/`Link` that pointed at either now points at Settings (`/staff/settings` / `/portal/settings`).

### Revision 2 (same branch, follow-up feedback pass)

1. **Days Off reviewer picker + reusable search/sort.** `UnavailabilityBlockForm` (staff self-service only, `showReviewerPicker` prop - not shown for the on-behalf-of usage in `StaffManagementPage`) gets an optional "Send to" picker over Admin/Supervisor/Superadmin at the requester's branch, with search + sort. Purely a non-binding hint - stored as `staff_unavailability_blocks.requested_reviewer_id`, shown as "Requested for: X" on `UnavailabilityReviewCard`, but any eligible manager can still approve/deny it (unchanged review rule). New shared `useSearchAndSort` hook + `SearchSortBar` component extracted from - and now used by - `ReceptionistBookingsQueuePage` and `HotelBookingPicker`, which previously hand-duplicated the identical search/sort logic and markup.
2. **Staff ↔ customer login cross-links.** `StaffLoginPage` now links to `/login` and `/signup` (the reverse link, `CustomerLoginPage` → `/staff/login`, already existed).
3. **Navbar Settings icon.** The identity chip (username/role or full name) is now plain text, not a link - a separate gear-icon "Settings" link sits next to it, so Settings isn't a hidden side effect of clicking your own name.
4. **Appearance settings.** New Settings tab (all roles): theme (Device default/Light/Dark, wired to the already-built-but-unused `ThemeToggle`) and a 4-step font-size slider (Small/Medium/Large/Extra Large) with live sample text. Font size persists per-account (`font_size_preference` column, mirrors the existing `theme_preference` pattern) and applies globally via a `--font-scale` CSS variable multiplied into every `--text-*` size in `typography.css`.
5. **Dashboard landing pages simplified.** `StaffDashboardPage` and `CustomerPortalPage` now show a welcome message instead of a navigation tile grid - that navigation already lives in the Sidebar (Revision 1) and was redundant here.
6. **Font normalization.** Swept every `.module.css` in the authenticated app for hardcoded `font-size`/`font-weight` values outside `styles/variables/typography.css`; found and fixed 2 (`StaffLoginPage` icon size, `TimeSlotInput`'s selected-option weight). `LandingPage.module.css` (public marketing page, hand-tuned one-off sizes) deliberately left as-is - out of scope for the authenticated app's font-scale slider.
7. **MFA page centering fix.** `MfaChallengePage`/`MfaEnrollPage` were rendering un-styled and pinned to the top-left - both referenced `shell`/`title`/`copy` classes that were never defined in the `StaffLoginPage.module.css` they imported (a stale copy-paste from an earlier version of that file). Extracted a shared `AuthCard` component (centered card layout) now used by both of those plus `StaffResetPasswordPage` and `CustomerMfaChallengePage`, which each had their own near-identical copy of the same CSS.

### Revision 3 (same branch, second follow-up pass)

1. **Theme mode actually restyles the whole app (real bug fix).** The Revision 2 theme toggle set a `data-color-mode` attribute, but no CSS ever consumed it - every color/shadow token in `tokens.css` was keyed on `data-theme` (staff/customer role) instead, and role happened to be pinned one-to-one with a mode (customer=light, staff=dark) by coincidence of which values were chosen, not by design (confirmed: literally every token pair - backgrounds, text, borders, every status-badge set - is a light/dark pair, not a brand pair). Fixed by re-keying every color/shadow token in `tokens.css` (and `color-scheme` in `global.css`) onto `data-color-mode` instead of `data-theme`; `--radius-*` (identical in both blocks) hoisted to an unconditional `:root`. `data-theme` (role) no longer carries any color token - the toggle now genuinely restyles the whole app (sidebar, navbar, every page) regardless of role, and either role can use either mode.
2. **StaffLoginPage layout fix.** The new customer-login cross-link (Revision 2) was rendering beside the login card instead of below it, because `.right` was a single-child centered flex row and the link became a second flex item. Added `flex-direction: column` + `gap` to `.right`.
3. **Days Off reviewer picker simplified.** Removed the search/sort UI over reviewer candidates (kept the plain `<select>`, already showing `display_name - role` per option) - branches only have a handful of Admin/Supervisor/Superadmin, so a search/sort toolbar was unnecessary chrome. `useSearchAndSort`/`SearchSortBar` stay in use by `ReceptionistBookingsQueuePage`/`HotelBookingPicker` (unaffected).
4. **Days Off quick-select times.** Start/End custom-range fields each get a row of quick-pick time buttons (8/9 AM, 12/1/5/6 PM) that fill in that field's time for the currently-selected date (or today, if no date chosen yet) - mirrors the convenience of the booking flow's time picker without pulling in its slot-availability machinery (day-off requests aren't bound to real booking slots).
5. **Past-time validation.** A custom-range start time or Entire Day date that's already passed is now rejected, client-side (immediate form error) and server-side (`400`, defense in depth) - previously nothing stopped submitting e.g. a 7 AM start when it was already 8 AM.

### Revision 4 (same branch, dark-theme consistency pass)

1. **Dark-palette revamp.** Replaced the muddy, over-saturated brown dark palette in `tokens.css` with desaturated neutral charcoal surfaces/borders/text (teammate feedback: "doesn't like the poop brown") - gold accent tokens (`--color-accent-gold-*`, `--color-brand-gold-logo`, etc.) unchanged, so warmth now comes only from the accent, not the base surfaces.
2. **Systemic hardcoded-color sweep (the actual "theme switch is inconsistent" bug).** Revision 3 fixed the token-wiring bug (colors were keyed on role instead of mode), but ~20 dashboard/admin-config pages plus the landing, customer login, and customer signup pages never referenced color tokens at all - they had fully opaque hardcoded hex/rgba values (e.g. `#ffe9d6`/`#ffdbbb` gradients, `#3d2b1f`/`#6f5945` text) that couldn't respond to either mode. Fixed by converting every one to `var(--color-*)` references:
   - `StaffDashboardPage` + 19 sibling pages (bookings queue, daycare/hotel check-in/out, grooming, veterinary console, every admin-config page, catalogs, staff/customer management, the unavailability approval queue) - identical `background`/`color` hardcoded pattern, all mechanically re-pointed at `--color-bg-primary`/`--color-bg-secondary`/`--color-text-primary`/`--color-text-secondary`.
   - `CustomerLoginPage`/`CustomerSignupPage` hero panel (the paw-print side) - was using the gold accent tokens directly, which stayed gold-toned in both modes ("bg on the left is not supposed to be yellow on dark theme"). New dedicated `--color-hero-gradient-start/-mid/-end` and `--color-text-on-heropanel` tokens (gold in light mode, neutral charcoal in dark mode) decouple this panel from the brand-accent tokens used everywhere else.
   - `CustomerLoginForm`/`CustomerSignupForm` - three hardcoded box-shadow values swapped for the existing `--shadow-sm`/`--shadow-md` tokens. Google/Facebook lettermark colors (`#4285f4`/`#1877f2`) deliberately left hardcoded - real brand colors, not theme-dependent.
   - `shadows.css` - was keyed on the OS-level `prefers-color-scheme` media query instead of the app's own `data-color-mode` attribute, so shadow depth could silently disagree with the in-app theme choice (`ThemeProvider` already resolves "Device default" itself and writes `data-color-mode` either way). Re-keyed onto `data-color-mode`.
   - `LandingPage.module.css` - the largest, most design-heavy file (marketing page, ~1800 lines). Every "glass card" panel (hero text card, branch card, service cards, booking-flow steps, scroll-story copy, help-mascot bubble/menu) used a hardcoded translucent-white background while hosting already-mode-aware text - readable in light mode, unreadable in dark (light text on a background that stayed white). New `--color-landing-glass-bg-rgb`/`--color-landing-glass-border-rgb` tokens (RGB-only, so each card keeps its own hand-tuned alpha via `rgba(var(...), X)`) swap the panel to a translucent dark surface in dark mode. Separately, `--color-text-on-accent` (an app-wide token meaning "text sitting on the gold accent color") was misapplied to elements sitting on the navbar pill, the feature-strip photo overlay, and the footer - all permanently-dark surfaces unrelated to the accent color - so in dark mode this text resolved to near-black-on-near-black. Fixed by using this file's own already-established "light text on fixed-dark chrome" convention (`rgba(255, 247, 234, X)`) for those spots instead, and `--color-brand-gold-logo` for the two footer link-hover states (already used unchanged for footer headings). Decorative low-alpha shadows and gold-accent-button text (both already using the app-wide accent-button convention used correctly in dozens of other files) were left as-is - out of scope, not a readability bug.
   - `TimeSlotInput.module.css` - `.hint` referenced a nonexistent `--color-danger` token with a hardcoded `#b3261e` fallback, so the fallback silently fired in every mode (dark red on the dark-mode background = poor contrast). Pointed at the real, already mode-aware `--color-error-text` token instead.
   - Audited every other flagged file (`Sidebar`, `MfaSetupModal`, `SessionExpiryModal`, `TotpEnrollPanel`, `ServerErrorPage`, `NotFoundPage`, `StaffLoginPage`) - all already correct as-is: modal backdrops are a universal dark scrim (not theme-dependent by convention), the sidebar/staff-login hero panel is deliberately always-dark chrome in both modes, and the TOTP QR code is deliberately pinned to a fixed white background (QR modules need real light/dark contrast to scan, not `--color-bg-primary`, which is near-black in dark mode) - each already had an inline comment explaining the deliberate exception.
     3b. **Revision 5 (quick follow-up).** Dark theme was over-corrected to neutral charcoal in Revision 4 - restored warm espresso/mahogany browns (bg/surface/border/text/sidebar tokens + hero-gradient/landing-glass tokens derived from them), keeping `--color-border`/`--color-surface` a shade darker than the original "poop brown" values so they don't pop as a lighter muddy stripe. Also removed the `background: linear-gradient(160deg, var(--color-bg-primary), var(--color-bg-secondary))` rule the 20-file dashboard sweep had re-tokenized rather than removed - those pages now inherit the same flat single-color background every other staff page (e.g. Days Off, Daycare Checkout) already used, instead of a one-off gradient.
     3c. **Availability badge removed from the persistent shell.** `UnavailabilityBlockBadge` ("Off until X" pill) no longer renders inside `AppShell` on every staff page - redundant now that Days Off / the approval queue already surface this status where it's actually actionable.

## Migrations

- `20260729065_shared_add_font_size_preference_columns.sql` - adds `font_size_preference` (`small`/`medium`/`large`/`x-large`, default `medium`) to `staff_profiles` and `customer_profiles`, mirroring the existing `theme_preference` columns.
- `20260729066_m01_staff_unavailability_blocks_requested_reviewer.sql` - adds nullable `requested_reviewer_id` (FK to `staff_profiles`) to `staff_unavailability_blocks`. No RLS changes needed (existing policies are row-, not column-, scoped).

Username self-service (Revision 1) needed no migration - `staff_profiles.username` was already `unique` (migration `20260625005`); password self-change goes through Supabase Auth directly from the client, not through a new Express route.

## New API surface

- `PATCH /staff/:id/username` - self-service username change (Revision 1). Staff-only, strictly self (`id` must match the caller's own id, `403` otherwise). Body: `{ "username": string (min 3 chars) }`. `409` if the username is already taken by a different staff member.
- `PATCH /auth/staff/preferences` and `PATCH /auth/customers/preferences` - now accept `font_size_preference` (`small`/`medium`/`large`/`x-large`) in addition to the existing `theme_preference`, either or both in the same request. `400` if neither field is provided, or either fails validation.
- `POST /staff/:id/unavailability` - accepts a new optional `requested_reviewer_id` (uuid). `400` if it doesn't resolve to a Supervisor/Admin/Superadmin at the same branch as the target staff member.

## Files changed (high level)

**Server (Revision 1)**: `features/staff/modules/validators/staff.validator.ts` (`updateStaffUsernameValidator`), `features/staff/services/staffManagement.service.ts` (`updateStaffUsername`), `features/staff/staff.controller.ts` (`updateStaffUsernameController`), `features/staff/staff.routes.ts` (mounts the new route).

**Server (Revision 2)**: `features/auth/staff/staffAuth.routes.ts` + `features/auth/customers/customerAuth.routes.ts` (both preferences controllers accept `font_size_preference`); `features/staff/staff.types.ts` (`requested_reviewer_id`, `RequestedReviewerSummary`); `features/staff/staff.controller.ts` + `services/unavailabilityBlock.service.ts` (`requestedReviewerId` param, branch/role validation, joined into `listPendingUnavailabilityBlocks`); the 2 new migrations above.

**Client (Revision 1)**: new `shared/components/AppShell/*`, `shared/components/Sidebar/*`; `shared/components/Navbar/Navbar.tsx` (+css, identity chip); `features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` + `features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx` (render `AppShell`); `features/staff/config/staffDashboard.config.ts` (`sections` instead of flat `tiles`, admin grouped by role, config tiles removed) + `features/staff/pages/StaffDashboardPage/StaffDashboardPage.tsx`; new `features/customers/config/customerPortal.config.ts` + `features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx`; new `features/customers/pages/CustomerPetManagerPage/*`; deleted `features/staff/pages/StaffProfilePage/*` and `features/customers/pages/CustomerProfilePage/*`; rewrote `pages/SettingsPage/SettingsPage.tsx` + new `pages/SettingsPage/tabs/{ProfileTab,AccountTab,SecurityTab,ConfigTab}.tsx`; new `shared/auth/password.validator.ts`; `features/auth/customer/api/customerAuth.api.ts` (`updateCustomerPassword`) + `features/staff/api/staff.api.ts` (`updateStaffUsername`); every `ALLOWED_VIEWER_ROLES`-gated page's denied-redirect target updated from `/staff/profile` to `/staff/settings` (mechanical, ~20 files).

**Client (Revision 2)**: new `shared/hooks/useSearchAndSort/*`, `shared/components/SearchSortBar/*`; `features/booking/pages/ReceptionistBookingsQueuePage/*` + `features/hotel/components/HotelBookingPicker/*` (refactored onto the two above); `features/staff/components/forms/UnavailabilityBlockForm/*` (reviewer picker) + `features/staff/pages/DaysOffPage/DaysOffPage.tsx` (`showReviewerPicker`) + `features/staff/components/review/UnavailabilityReviewCard/*` ("Requested for"); `features/staff/staff.types.ts` + `modules/validators/staff.validator.ts` (`requested_reviewer_id`); new `pages/SettingsPage/tabs/AppearanceTab.tsx`; `shared/providers/ThemeProvider/{themeContext,ThemeProvider}.tsx` + `shared/api/preferences.api.ts` (font size) + `shared/components/ThemeToggle/ThemeToggle.tsx` (relabeled, now actually used); new `shared/components/FontSizeSlider/*`; `styles/variables/typography.css` (`--font-scale`); `shared/components/Navbar/{Navbar.tsx,Navbar.module.css}` (Settings icon, plain-text identity); `features/staff/pages/StaffDashboardPage/*` + `features/customers/pages/CustomerPortalPage/*` (welcome message) + `features/customers/config/customerPortal.config.ts` (simplified); `features/auth/staff/pages/StaffLoginPage/*` (customer cross-link); new `shared/components/AuthCard/*`; `features/auth/staff/pages/{MfaChallengePage,MfaEnrollPage,StaffResetPasswordPage}/*` + `features/auth/customer/pages/CustomerMfaChallengePage/*` (all now use `AuthCard`); `features/booking/components/TimeSlotInput/TimeSlotInput.module.css` (font-weight variable).

**Client (Revision 4)**: `styles/tokens.css` (dark-palette revamp; new `--color-hero-gradient-*`, `--color-text-on-heropanel`, `--color-landing-glass-bg-rgb`, `--color-landing-glass-border-rgb`); `styles/variables/shadows.css` (`data-color-mode` instead of `prefers-color-scheme`); `pages/LandingPage/LandingPage.module.css`; `features/auth/customer/pages/{CustomerLoginPage,CustomerSignupPage}/*.module.css`; `features/auth/customer/components/forms/{CustomerLoginForm,CustomerSignupForm}/*.module.css`; `features/booking/components/TimeSlotInput/TimeSlotInput.module.css` (`--color-danger` → `--color-error-text`); `features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` (badge removed); 20 dashboard/admin-config `.module.css` files (`ReceptionistBookingsQueuePage`, `DaycareCheckInPage`, `AdminDiscountManagementPage`, `GroomerDashboardPage`, `CatalogAdminPage`, `HotelCareLogPage`, `HotelCheckInPage`, `HotelCheckoutPage`, `AdminBreedsPage`, `AdminPackageBuilderPage`, `AdminPromoConfigPage`, `AdminServicesPage`, `PricingConfigurationPage`, `PromoCapConfigurationPage`, `SystemConfigurationPage`, `CustomerManagementPage`, `StaffDashboardPage`, `StaffManagementPage`, `UnavailabilityApprovalQueuePage`, `VeterinaryConsolePage`).

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **661/661 tests pass** (71 files).

From `client/`:

```powershell
npx tsc -b --noEmit
npx vitest run
```

Expected: typecheck clean, **508/508 tests pass** (114 files).

Both reconfirmed clean as of Revision 4 (same counts: 661/661 server, 508/508 client - this revision was CSS-only plus one guard-component edit, no test/type surface changed). `npx eslint .` also clean in both - the server run surfaces 7 pre-existing `no-console` warnings, all in code this batch didn't touch.

## Manual Verification

You'll need the `server/` and `client/` dev servers running (`npm run dev` from the repo root) and at least two staff logins across different roles (ideally one Admin/Superadmin and one lower-privilege role, e.g. Groomer) plus a customer login. No migrations to apply for this batch.

### 1. Sidebar - staff

1. Log in as a non-admin role (e.g. Groomer). Confirm the sidebar shows one flat, unlabeled list (Days Off, Grooming Queue) - same items as the old dashboard tiles, just in the sidebar too now.
2. Log in as Admin or Superadmin. Confirm the sidebar shows labeled sections: Management, Receptionist, Groomer, Veterinarian, Cashier, Pet Assistant, Supervisor. Confirm **Receptionist** includes Hotel Check-in, Hotel Checkout, Daycare Check-in, and **Daycare Checkout** (previously unreachable from any dashboard - click it and confirm `DaycareCheckoutPage` loads without a session id, per its route).
3. Click the collapse button at the top of the sidebar. Confirm it shrinks to an icon rail (section headings disappear, link labels are screen-reader-only). Reload the page - confirm it stays collapsed. Expand it again and reload - confirm it stays expanded.
4. Click each sidebar link once and confirm the active one is visually highlighted and the correct page loads.

### 2. Sidebar - customer portal

1. Log in as a customer. Confirm the sidebar shows Home, Book a Service, My Bookings, Pet Manager, Settings.
2. Collapse/expand and reload, same as staff step 3 above - confirm the customer's collapsed state persists independently of a staff session's (log in as staff in another tab/profile if you want to confirm the two don't share state - they use separate `localStorage` keys, `sidebar-collapsed-staff` vs `sidebar-collapsed-customer`).

### 3. Navbar identity

1. As staff: confirm the navbar shows your username and role (e.g. `gwash · Groomer`), and clicking it opens Settings.
2. As a customer: confirm the navbar shows your full name only, no role badge, and clicking it opens Settings.

### 4. Settings tabs

1. Open Settings. Confirm it lands on **Profile** by default and the fields/save behavior match what the old profile page did (edit display name, save, confirm it persists).
2. Click **Security** - confirm MFA status/enroll/disable behavior is unchanged from before this batch.
3. As a non-admin staff role or a customer: confirm there is **no Config tab**.
4. As Admin: confirm **Config** appears, lists every admin-config tile, and each link resolves to its existing (untouched) page. Confirm **System Configuration is not listed**.
5. As Superadmin: confirm **System Configuration** is listed in Config and its link works.

### 5. Account tab - password

1. On any role, go to Settings > Account, enter a new password (8+ chars) in both fields, and save. Confirm a success message appears.
2. Sign out and log back in with the new password.
3. Try mismatched password/confirmation - confirm a client-side "Passwords do not match" error and no request is sent.

### 6. Account tab - username (staff only)

1. As staff, go to Settings > Account. Confirm the Username field is pre-filled with your current username.
2. Change it to something new and save. Confirm success, and that the navbar identity chip updates to the new username without a reload.
3. Log in as a second staff member and try to set their username to the first staff member's (now-changed) username. Confirm a "Username already exists" error and no change is saved.
4. Confirm the customer Account tab has no username field at all.

### 7. Pet Manager

1. As a customer, navigate to `/portal/pets` (via the sidebar or the portal home tile). Confirm your pets list and "Add a pet" still work exactly as they did on the old profile page.
2. Confirm `/portal/profile` is gone - it's not linked anywhere, and Settings > Profile is where your contact details live instead.
3. Confirm a pet card link still opens the correct pet's profile page.

### 8. Old routes are fully retired

1. Grep the client source for `/staff/profile` and `/portal/profile` - both should return zero matches (already confirmed during implementation; re-check if you've made further changes).
2. Confirm every page that used to redirect a disallowed viewer to `/staff/profile` (e.g. open `Staff Management`, `Customer Management`, any admin-config page as a non-admin role) now redirects to `/staff/settings` instead.

### 9. Days Off reviewer picker (Revision 2)

1. Apply the two new migrations (`npm run supabase:push` from the repo root, or `supabase:reset` for a fresh DB + reseed).
2. As a plain staff member (e.g. Groomer), open Days Off. Confirm a "Send to (optional)" section appears above "Take the rest of today off", with a search box, a sort dropdown (Name/Role), and a select defaulting to "Any manager" listing only Admin/Supervisor/Superadmin at your branch (not yourself, not other roles).
3. Search/sort the list and confirm it filters/re-orders correctly. Pick a specific manager and submit a request (either the quick action or a custom range).
4. As that manager (or any other Admin/Supervisor/Superadmin at the branch), open the Days Off Approval Queue. Confirm the pending card shows "Requested for: <name>". Confirm a _different_ Admin/Supervisor/Superadmin (not the one requested) can still Approve/Deny it - the picker is a hint, not an access restriction.
5. As an Admin, open Staff Management, expand another staff member, and submit a day off on their behalf. Confirm there's no reviewer picker there (on-behalf-of requests auto-approve immediately, no review step to address).
6. On `/staff/bookings/queue` and the Hotel Check-in booking picker, confirm search-by-name and the sort dropdown still work exactly as before (behavior unchanged, only the implementation was de-duplicated).

### 10. Staff/customer login cross-links

1. Visit `/staff/login`. Confirm a line near the bottom links to "Customer sign in" (`/login`) and "create an account" (`/signup`), and both navigate correctly.
2. Visit `/login`. Confirm the existing "Staff sign in" link still works (unchanged).

### 11. Navbar Settings icon

1. On any authenticated page, confirm your username/name in the navbar is plain text (not clickable/no hover-link styling).
2. Confirm a separate gear-icon "Settings" button/link sits next to it, and clicking it opens Settings.

### 12. Appearance settings (theme + font size)

1. Open Settings > Appearance (new tab, between Profile and Account). Confirm three theme options: Device default (checked by default for a fresh account), Light, Dark.
2. Switch to Light, then Dark - confirm the whole app's color scheme changes immediately. Reload - confirm your choice persisted.
3. Switch back to Device default - confirm it follows your OS/browser color-scheme setting.
4. Drag the font-size slider through all 4 steps (Small/Medium/Large/Extra Large). Confirm the sample text directly below it visibly grows/shrinks at each step, and that text elsewhere on the page (e.g. the tab labels) scales too.
5. Reload the page - confirm your font-size choice persisted. Log in as a different role/customer and confirm their font size is independent (defaults to Medium if never set).

### 13. Dashboard landing pages

1. Log in as any staff role - confirm `/staff/dashboard/<role>` shows "Welcome back, <your name>!" and a one-line subtitle, not a tile grid. Confirm every link that used to be a dashboard tile is still reachable, just from the sidebar now.
2. Log in as a customer - confirm `/portal` shows the same style of welcome message instead of the old 4-tile grid.

### 14. Font normalization spot-check

1. On `/staff/login`, confirm the feature-row icons (📅🩺💊👥) render at a normal, consistent size (this was the one real hardcoded `font-size: 17px` found outside the landing page - now `var(--text-lg)`).
2. Anywhere a `TimeSlotInput` renders (booking flow's date/time step), confirm the selected time option still reads visually bold/emphasized (was a hardcoded `font-weight: 600`, now `var(--weight-semibold)` - should look identical).

### 15. MFA page centering

1. Trigger the staff MFA challenge (log in as an Admin/Supervisor/Superadmin with MFA already enrolled) - confirm the "Verify MFA" card is centered on the page, not pinned to the top-left.
2. Trigger staff MFA enrollment (an Admin/Superadmin without MFA set up yet, via `/staff/mfa/enroll` or the mandatory setup popup) - confirm "Set Up MFA" is centered too.
3. Confirm `StaffResetPasswordPage` (the forgot-password email link) and the customer MFA challenge page (`/portal/mfa/verify`) still look the same as before (both already used this centered-card layout; just spot-check they weren't broken by the shared-component extraction).

### 16. Theme mode actually restyles everything (Revision 3)

1. Open Settings > Appearance and switch between Device default/Light/Dark while watching the **sidebar, navbar, and page background all at once**. Confirm all three visibly change together on every click - not just text/accents.
2. With Dark selected, open a page with status badges (e.g. a Bookings Queue with a few different booking statuses, or Hotel's cage status grid) - confirm badges are still legible (each has its own background+text pair, independent of the page background).
3. Switch to Light and reload - confirm the choice persisted (this already worked before Revision 3; only the actual restyling was broken).
4. Log in as a customer and repeat step 1 - confirm mode works identically regardless of role (a customer can now use Dark, a staff member can now use Light - neither was possible before Revision 3, since role and mode were the same axis).
5. Set mode to Device default, toggle your OS/browser's light/dark preference, and confirm the app follows it live without a manual reload.

### 17. StaffLoginPage layout

1. Visit `/staff/login` on a normal-width viewport. Confirm "Booking an appointment for your pet? Customer sign in or create an account." sits centered **below** the login card, not floating beside it.
2. Resize narrow (< 900px) - confirm it still reads sensibly stacked under the card.

### 18. Days Off reviewer picker + quick times + validation (Revision 3)

1. Open Days Off as a plain staff member. Confirm the "Send to (optional)" dropdown has **no search box or sort dropdown** anymore - just the select, with each option reading `Name - Role`.
2. Uncheck "Entire day" (custom range mode). Confirm a row of quick-time buttons (8:00 AM, 9:00 AM, 12:00 PM, 1:00 PM, 5:00 PM, 6:00 PM) appears under both Start and End. Click one - confirm it fills that field with today's date (or whatever date was already there) at that time.
3. Manually set a Start time earlier than the current clock time (e.g. if it's 8 AM, pick 7 AM today) and any End time, then submit. Confirm a "Start time cannot be in the past" error appears and no request is created.
4. Check "Entire day" and pick yesterday's date (if the date picker allows typing past its `min`) - confirm the same rejection happens (client-side, and server-side if you bypass the picker via Postman - see the collection's item 9/10 area, or add a dedicated past-date case).
5. Submit a valid future custom range or Entire Day request - confirm it still succeeds as before.

### 19. Dark theme consistency (Revision 4)

1. Set Settings > Appearance to Dark (or Device default with your OS set to dark). Visit `/` (landing page, logged out) - confirm the hero text card, branch cards, service cards, booking-flow step cards, scroll-story copy panels, and the floating help-mascot bubble/menu all render as dark translucent panels with clearly readable light text - none should show light/white text on a still-white card.
2. On the same page, confirm the top nav pill's links/hamburger icon and the footer's links/socials are all clearly visible (light text on their always-dark backgrounds, unchanged from light mode) - including hovering a footer link (should turn gold, not disappear).
3. Visit `/signup` and `/login` in dark mode - confirm the left hero panel (paw prints) renders as a neutral dark charcoal gradient, **not gold/yellow**, with clearly readable light text and heading.
4. Visit any staff dashboard (e.g. `/staff/dashboard/receptionist`) and a few of the admin-config pages (Services, Pricing, System Configuration) in dark mode - confirm backgrounds are dark and all body text is clearly readable (no dark-on-dark or light-on-light text anywhere).
5. Switch back to Light mode and spot-check the same four areas (landing, signup/login, staff dashboard, admin-config pages) - confirm nothing regressed and they still look as they did before this revision.
6. Open a booking flow's date/time step, trigger a validation hint (e.g. an invalid/past time) - confirm the red hint text is clearly legible in both light and dark mode.
7. Confirm the "Off until X" availability badge no longer appears anywhere in the staff shell (it previously showed next to the sidebar/navbar on every page for a staff member with an active day-off block).
