---
title: Keep booking selections when going back, add icons/images to service config, fix landing page theme
date: 2026-09-14
tags: [session-plan, golden-fur]
project: golden-fur
session: 106-booking-persistence-icons-landing-theme
branch: staged on dev
---

# 106 — Keep booking selections when going back, add icons/images to service config, fix landing page theme

## What you asked for

Three separate but small fixes/features, bundled into one request (see
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`,
"Development" tab, all rows tagged **Matthew / In Progress**):

> As a customer, I want my booking progress to be saved when I come back to
> previous steps. Currently, going back to the pet step deselects my
> selected pet, services, etc. and other stages that follow it.
>
> At admin acc > settings > config > add new service type: should be able to
> select icon for new service type. Do the same for when adding new
> service/packages (can choose icon/image attachment).
>
> Fix landing page always set to dark theme. Make it so that it adapts the
> theme of the system automatically, if light, light. Add a basic
> light/dark theme switch at landing page navbar.

When asked to clarify the icon/image question, you chose: give **both** a
predefined icon picker **and** an image-upload option, on **all three**
things (service type, service, and package) — not icon-only for types and
image-only for services as the wording could have implied.

## What this part of the app does today

### A. The customer booking wizard

A **wizard** is a multi-step form: the user fills in one screen ("step"),
clicks Next, fills in the next one, and so on, with a way to click Back to
revisit an earlier step. In this app, the whole customer-facing booking flow
— picking a branch, a pet, a service, a time slot, promos, and finally
reviewing payment — is one single wizard.

All of that lives in one big file:
`client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
(about 4,300 lines). Every piece of information the wizard is holding onto
— which pet you picked, which services, which time slot, which promo codes —
is its own **piece of state** (a React concept: a value that a component
remembers between renders, declared with `useState`). All of these pieces of
state live directly in this one file, not spread across separate
step-components. The little numbered progress bar at the top of the booking
screen is a separate, "dumb" component,
`client/src/features/booking/components/BookingStepper/BookingStepper.tsx`,
that only knows how to draw buttons and tell the big file which step was
clicked — it doesn't hold or touch any of the actual booking data itself.

There is already a separate, unrelated feature that saves your half-finished
booking to your browser's **localStorage** (a small on-device key/value
store that survives page reloads) so that if you close the tab and come back
within 24 hours, your in-progress booking is still there. That's the
`PersistedBookingDraft` / `readBookingDraft` / `writeBookingDraft` code
(same file, roughly lines 375-466 and 1090-1250). It already works
correctly and was recently patched in PR #181 so it doesn't resurrect a
booking that was just submitted. This feature is about page _reloads_, not
about the bug below — we are not touching it.

### B. Admin > Settings > Config > Services and Packages

Staff with the Admin or Superadmin role can open **Settings** (a gear icon
in the staff console) and go to a tab called **Config**, which shows a grid
of tiles — one tile per configurable thing (Services and Packages, Promos,
Policies, etc.). Clicking the "Services and Packages" tile opens
`client/src/features/maintenance/pages/AdminServicesAndPackagesPage/AdminServicesAndPackagesPage.tsx`,
a page with three tabs:

- **Service Types** — the top-level categories bookings are grouped under
  (Grooming, Hotel, Daycare, Veterinary, Assessment). Managed in
  `client/src/features/maintenance/pages/AdminServiceTypesPage/AdminServiceTypesPage.tsx`.
- **Services** — the individual bookable items under a service type (e.g.
  "Basic Bath" under Grooming). Managed in
  `client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`.
- **Packages** — bundles of two or more services sold together at one
  price. Managed in
  `client/src/features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx`.

Each of these pages has an "Add new" button that opens a popup form (a
**modal**). Right now none of the three forms has any way to pick a picture
or icon — a service type is just a name plus some checkboxes and role
pickers; a service is a name, category, price, duration, etc.; a package is
a name plus the services bundled into it.

Every field that goes into these forms has to pass a **Zod schema** on the
server (`server/src/features/maintenance/modules/validators/maintenance.validator.ts`)
before it's allowed into the database — Zod is a library that checks
incoming data has the right shape and types. These particular schemas are
marked `.strict()`, meaning any field the schema doesn't explicitly list
gets _rejected_, not just ignored — so a new field has to be added to the
schema on purpose, or the request will fail.

The app already has a working example of uploading a picture: staff profile
photos. `client/src/features/staff/components/forms/AvatarUploader/AvatarUploader.tsx`
is a ready-made "drag a file in, see a preview, watch it upload" component,
backed by `server/src/features/staff/services/avatarUpload.service.ts`,
which stores the file in **Supabase Storage** (a file-hosting bucket that's
part of the same Supabase backend the app already uses for its database) and
saves the resulting URL. There's also a generic helper,
`server/src/shared/services/storage/storage.service.ts`, that any feature
can use to upload/fetch/delete a file from a named storage bucket, so we
don't have to write bucket-upload code from scratch.

For icons (not photos), the app already depends on **lucide-react**, an
icon library — a package of hundreds of small, consistent line-drawing icons
you refer to by name in code (e.g. `Package`, `Gift`). Today every icon
usage in the app is a developer typing a specific icon's name into the code
once; there's no screen anywhere where a _user_ picks an icon from a list.

### C. The public landing page's color theme

The site has a **theme** system already: every screen can render in light
mode or dark mode (or follow the device's own system setting), controlled
by `client/src/shared/providers/ThemeProvider/ThemeProvider.tsx`. It reads
the browser's `prefers-color-scheme` media query (the OS-level "I prefer
dark/light apps" setting) when no explicit choice has been made, and it
already wraps every route in the app, landing page included — this is set
up in `client/src/pages/App/App.tsx`.

Colors throughout the app are **CSS custom properties** (also called CSS
variables), like `--color-text-primary`, defined twice in
`client/src/styles/tokens.css` — once under a `[data-color-mode='light']`
selector and once under `[data-color-mode='dark']`. The `ThemeProvider`
just flips a `data-color-mode` attribute on the page's root element, and
every element that uses `var(--color-text-primary)` (etc.) instantly
switches. There's already a working toggle component for this,
`client/src/shared/components/ThemeToggle/ThemeToggle.tsx` (a 3-way
System / Light / Dark switch), currently only placed on the authenticated
Settings > Preferences tab.

The public landing page (`client/src/pages/LandingPage/LandingPage.tsx`,
styled by `LandingPage.css`) and its navbar
(`client/src/pages/LandingPage/components/LandingNavbar/LandingNavbar.tsx`
— also reused by the Branches, Packages & Promos, and About pages) mostly
**don't use those variables**. Their navbar, footer, and hero sections use
literal hardcoded colors (e.g. `background: rgba(35, 26, 16, 0.78)`,
`color: #fff6e6`) written directly into `LandingPage.css`, so they always
look the same dark-brown/off-white regardless of what `data-color-mode` is
currently set to. `tokens.css` even has a comment explaining this was a
deliberate earlier decision to keep marketing pages as a fixed "brand
moment" — a decision we're now reversing per this request.

## What's wrong / what's missing

- **A.** In the booking wizard, re-selecting your already-chosen pet on the
  Pet step (which is exactly what happens if you click Back to review your
  pet choice, then continue) wipes out every selection made after that step
  — the category, the chosen services/package, the time slot, staff/cage
  choice, promo codes, and hotel-specific details — even though nothing
  about the pet actually changed. The same bug exists on the Branch step for
  the same reason.
- **B.** There is no way for an admin to attach a picture or pick an icon
  for a service type, a service, or a package, when creating (or presumably
  editing) one.
- **C.** The landing page and the pages sharing its navbar are stuck looking
  dark even when the visitor's system is set to light mode, and there is no
  way for a visitor to manually flip it either.

## What we're going to change

### A. Booking wizard — stop resetting on re-selection

1. **Guard the pet-selection handler.** _File:_
   `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`,
   function `handlePetSelect` (~line 2046). _Change:_ if the clicked pet ID
   is already `selectedPetId`, don't reset any of the downstream state
   (category, selections, slot, staff/cage prefs, promos/coupons/discount,
   hotel nights/prefs) — just move to the next step (or no-op, matching
   whatever the "confirm and continue" behavior for an unchanged step should
   be). Only run the full reset when the pet actually changes to a
   _different_ pet (since a different pet can have different eligible
   services — e.g. an unassessed pet can only book "Initial Assessment").
   _Why:_ this is the exact root cause of the reported bug — the pet
   _does_ stay visually selected across Back navigation already; it's this
   handler firing again on the same value that wipes everything else.
2. **Apply the same guard to branch selection.** _File:_ same file,
   function `handleBranchSelect` (~line 2074). _Change:_ identical guard —
   skip the reset when `branchId === selectedBranchId`. _Why:_ this handler
   has the identical unconditional-reset bug; it wasn't named in the bug
   report but is the same class of problem and would surprise the user the
   same way.
3. No other files change for this item — `BookingStepper.tsx` and the
   existing localStorage draft-autosave code are already correct and don't
   need touching.

### B. Icon picker + image attachment for service types, services, and packages

1. **Add database columns.** New migration under `supabase/migrations/`
   adding two nullable text columns — `icon` (a Lucide icon name, e.g.
   `"Scissors"`) and `image_url` (a public Supabase Storage URL) — to all
   three tables: `service_types`, `services`, `packages`. _Why:_ per your
   answer, every one of the three should support both an icon and an
   optional photo, not just one or the other.
2. **New Storage bucket** for these images (e.g. `service-images`), with
   the same kind of Row-Level Security policy pattern already used for the
   `avatars`/`pet-photos` buckets (only Admin/Superadmin can write; public
   read), following
   `supabase/migrations/20260710_010_m01_avatars_storage_rls.sql` as the
   template.
3. **Extend the server-side validation and types.** _Files:_
   `server/src/features/maintenance/modules/validators/maintenance.validator.ts`
   (add optional `icon`/`image_url` fields to `createServiceTypeValidator`,
   `createServiceValidator`, `createPackageValidator` — remember these are
   `.strict()`, so the field must be added or every request with it gets
   rejected), and `server/src/features/maintenance/maintenance.types.ts`
   (mirror the new fields on the payload/response types). _Why:_ the
   server won't accept or return the new fields otherwise.
4. **Extend the client-side types and API calls.** _File:_
   `client/src/features/maintenance/maintenance.types.ts` and the
   `createServiceType`/`createService`/`createPackage` API functions, to
   send and receive `icon`/`image_url`.
5. **Build a shared icon-picker component.** New component under
   `client/src/shared/components/` (e.g. `IconPicker`) — a small grid of
   buttons, each rendering one Lucide icon from a curated allowlist (a
   fixed, hand-picked list of icon names relevant to a pet-care business —
   not every icon Lucide ships), clicking one sets the form's `icon` field.
   _Why:_ no such component exists yet; this is a new, reusable building
   block used by all three forms below.
6. **Generalize the avatar uploader into a shared image-upload component.**
   New component under `client/src/shared/components/` (e.g.
   `ImageUploader`), based on the existing
   `client/src/features/staff/components/forms/AvatarUploader/AvatarUploader.tsx`
   pattern (dropzone, file-type/size validation via a Zod schema like the
   existing `avatarFileSchema`, preview, upload progress) but generalized to
   accept a bucket name and an "on uploaded" callback instead of being
   hardcoded to avatars. _Why:_ reuse the proven upload UX instead of
   writing three near-duplicate uploaders.
7. **Add a small server upload endpoint/service per entity** (or one
   generic one, parameterized by bucket + record type), modeled on
   `server/src/features/staff/services/avatarUpload.service.ts` and the
   generic `server/src/shared/services/storage/storage.service.ts` helper,
   so the client can upload an image and get back a URL to store as
   `image_url`.
8. **Wire both pickers into the three admin forms:**
   `AdminServiceTypesPage.tsx`, `AdminServicesPage.tsx`, and
   `AdminPackageBuilderPage.tsx` — add the `IconPicker` and `ImageUploader`
   to each "Add new" (and "Edit") modal, alongside the existing fields.
9. **Show the chosen icon/image** wherever these entities are already
   listed or shown to customers (e.g. the admin list rows, and the
   customer-facing service/package selection step in the booking wizard) —
   exact list of display spots to be confirmed during implementation by
   grepping where `service_types`/`services`/`packages` are currently
   rendered.

### C. Landing page — follow system theme + add a toggle

1. **Convert the hardcoded colors to theme tokens.** _File:_
   `client/src/pages/LandingPage/LandingPage.css`. Replace the literal
   dark-brown/off-white color values in `.navbar`, `.nav-links a`,
   `.nav-toggle`, `.btn-outline`, and `.site-footer` (plus its child
   classes) with the existing `var(--color-*)` custom properties from
   `client/src/styles/tokens.css`, adding any new light/dark token pairs
   there if a needed color doesn't have one yet. _Why:_ these are the
   specific rules keeping the navbar and footer permanently dark regardless
   of `data-color-mode`; everything else on the page (services, reviews,
   visit, CTA sections) already uses tokens and will "just work" once the
   provider's mode changes.
2. **Leave the hero and feature-strip photo overlays as a judgment call** —
   flag during implementation whether their fixed dark-overlay-on-photo
   styling should also flip with theme, or is intentionally kept as-is
   since it sits on top of a photograph rather than a plain background
   (confirm with Matthew if unsure rather than guessing silently).
3. **No provider/context changes needed.** `ThemeProvider.tsx` already
   defaults anonymous visitors to `'system'` mode and already wraps the
   landing route (`client/src/pages/App/App.tsx`) — once (1) is done, the
   page will already open in light mode on a light system and dark mode on
   a dark one, live-updating if the OS setting changes while the tab is
   open.
4. **Add a toggle switch to the landing navbar.** _File:_
   `client/src/pages/LandingPage/components/LandingNavbar/LandingNavbar.tsx`
   — render the existing `client/src/shared/components/ThemeToggle/ThemeToggle.tsx`
   component inside the `.nav-actions` area. It already reads/writes
   `ThemeContext` with no required props, and already degrades correctly
   for a signed-out visitor (it just won't persist the choice to an
   account, since persistence only runs when a user is logged in — the
   choice still applies for the rest of that browser session via local
   state). _Why:_ this is the exact reusable control already used
   elsewhere in the app; no new toggle component needs to be built. Because
   `LandingNavbar` is shared by the Branches, Packages & Promos, and About
   pages too, this toggle will appear on all of them — confirm that's
   acceptable (it matches "make the whole public site theme-aware", which
   seems to be the intent, but flag it explicitly since only the landing
   page was named).

## Words you might not know

- **Wizard** — a form split across several screens ("steps") with Next/Back
  navigation, instead of one long page.
- **State** — a value a React component remembers between renders (e.g.
  "which pet is selected right now"), declared with `useState`.
- **localStorage** — a small storage area in the browser tied to the site's
  domain, that survives page reloads and browser restarts (unlike normal
  variables, which reset every time the page reloads).
- **Zod schema** — a set of rules describing what shape/type incoming data
  must have; the server checks every request against one before touching
  the database. `.strict()` means extra fields not in the schema cause the
  whole request to be rejected, not silently dropped.
- **Migration** — a versioned SQL file that changes the database structure
  (e.g. adding a column); each one is applied once, in order, and left in
  `supabase/migrations/` as a permanent record.
- **Row-Level Security (RLS)** — a Postgres/Supabase feature that restricts
  which rows a given user is allowed to read or write, enforced by the
  database itself rather than trusted to application code.
- **Supabase Storage bucket** — a named folder-like container in Supabase's
  file-hosting service, separate from the database tables, used for
  uploaded files like photos.
- **Lucide** — the icon library (`lucide-react`) already used throughout
  this app's UI; icons are referred to by name (e.g. `"Scissors"`) and
  rendered as small React components.
- **CSS custom property (CSS variable)** — a named value (e.g.
  `--color-text-primary`) defined once and reused via `var(--color-text-primary)`
  everywhere that color is needed, so changing the one definition changes
  every usage at once.
- **`prefers-color-scheme`** — a browser feature that reports whether the
  user's operating system is set to a light or dark appearance, so a
  website can match it automatically.
- **`data-color-mode` attribute** — this app's own mechanism: an attribute
  set on the page's root HTML element (`light` or `dark`) that the CSS
  color variables key off of; flipping this attribute flips every themed
  color on the page at once.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (written when
implementation begins on this session — this is a plan-only session, no
code has been changed yet).
