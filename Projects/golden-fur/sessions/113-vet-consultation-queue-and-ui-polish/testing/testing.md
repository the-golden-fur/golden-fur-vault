# Fix the vet staff Forbidden error, fold Bookings Queue into Consultation Queue, and a batch of small UI fixes

Branch: `feat/vet-consultation-queue-integration` (branched from `dev`, not
yet committed at the time this record was written).

## The request, verbatim

Seven small-to-medium changes bundled from one context doc, most centered on
the Veterinarian staff role (see `plan.md` in this same session folder for
the full quote and the near-beginner walkthrough of each one). In short:

1. Hide the Forbidden error a Veterinarian sees when booking a patient.
2. Add a "..." row menu to Settings > Config > Pets > Breeds.
3. Remove the Veterinarian's separate Bookings Queue; add a "New
   Consultation" entry point from Consultation Queue instead, opening a
   booking builder already filtered to that vet's own patients/service
   type.
4. Stop auto-confirming customer-made online Veterinary bookings.
5. Verify the Cashier's Transactions page still shows vet transactions
   after #4.
6. Change tap-to-open into press-and-hold for the remaining Board/List
   "..." menus.
7. Bring Consultation Queue onto the shared search/sort/filter/group-by/
   view toolbar.

## Root cause / Context

See `plan.md`'s "What's wrong / what's missing" section for the full
explanation of each of the 7 items. Two things worth restating here because
they shape "What changed" below:

- Item 1's actual bug was that `CustomerPicker` always called the broad
  `GET /customers` list endpoint, which a Veterinarian is not authorized to
  call at all (`CUSTOMER_LIST_ROLES` on the server deliberately excludes
  Veterinarian) — the request 403'd before the component's own
  `restrictToCustomerIds` client-side filter ever got a chance to run.
- Item 4's "Confirmed" label was a real special case in two independent
  places (`booking.service.ts`'s single-booking path and
  `bookingGroup.service.ts`'s multi-booking checkout path) that both treated
  a Veterinary booking as "confirmed the instant it's created", the same way
  a Walk-in is. This was found by grepping the booking services for
  "Veterinary" during implementation — the plan's own exploration had only
  found the `booking.service.ts` copy.

## What changed

No database migration — no schema changed for any of the 7 items.

### Server

- `server/src/features/booking/services/booking.service.ts` —
  `isConfirmedAtCreation` (around what was lines 1260-1261) dropped
  `|| input.service_category === 'Veterinary'`, so only
  `bookingSource === 'Walk-in'` triggers the immediate "booking confirmed"
  notification. `requiresUpfrontCharge` and the check-in payment-gate
  exemption for Veterinary bookings (both elsewhere in this file) are
  **unchanged** — those implement the real "a vet visit is priced during
  the visit, not upfront" rule, which is a separate question from whether
  the status badge is allowed to say "Confirmed" before anyone has paid.
- `server/src/features/booking/services/bookingGroup.service.ts` — the same
  fix, applied to a second, independent copy of the identical special case
  inside the multi-booking checkout path's own `isConfirmedAtCreation`. Not
  originally called out in the plan; found during implementation.
- No API route's request/response shape changed in this session — item 1
  moved which existing, already-public endpoint a client component calls
  (`GET /customers/:id` instead of `GET /customers`); item 4 only changed
  internal status-derivation logic. No new Postman collection was written
  for this session, since nothing about a request/response contract itself
  changed.

### Client

- `client/src/features/booking/components/CustomerPicker/CustomerPicker.tsx`
  — when given a `restrictToCustomerIds` set (the Veterinarian case), `load()`
  now fetches each id via `getCustomerProfile` (`Promise.all`) instead of
  calling `listCustomers`/`GET /customers`. `restrictToCustomerIds` was
  added to the `load` callback's own dependency array.
- `client/src/features/maintenance/pages/AdminBreedsPage/AdminBreedsPage.tsx`
  — `renderBreedActions` (Table view's row actions, and inside the old
  combined row renderer) now renders a single `MoreOptionsMenu` (Rename/
  Delete) via a new `buildBreedActionItems(breed)` helper, replacing two
  separate buttons. The List/Board card renderer wraps its row in
  `CardContextMenu` using the same helper (see item 6 below).
- `client/src/features/staff/config/staffDashboard.config.ts` — the
  Veterinarian sidebar section's "Bookings Queue" tile was deleted; the
  "Consultation Queue" tile's description was updated to mention scheduling
  a new consultation from there. No other role's config changed.
- `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`
  — a Veterinarian viewer is now redirected to `/staff/veterinary/console`
  (`<Navigate to="..." replace />`) if they land on this page directly; the
  page's own data-loading `useEffect` also now skips fetching for a
  Veterinarian viewer (`viewerRole === 'Veterinarian'` added to its guard
  clause and dependency array), since the redirect makes that data pointless.
- `client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx`
  — this file changed the most (418 insertions / a large chunk of
  deletions). Two logically separate things landed here together:
  - **Item 3 — "New Consultation" button**: a new button next to the page
    title calls `navigate('/staff/bookings/new', { state: { lockedServiceCategory: 'Veterinary' } })`.
  - **Item 7 — shared toolbar rewrite**: the old bespoke `QueueFilterBar` +
    `SearchSortBar` + flat `<ul>` of rows was replaced with the shared
    `FilterSortBar` + `ViewSwitcher` + `DataTable`/`DataList`/`DataBoard`
    set (same components `AdminBreedsPage`/`TransactionHistoryTable`/
    `AdminSpinWheelConfigPage` already use). New filter/sort state is a
    `FilterTile[]` array (`filterTiles`), pre-seeded with a `date` tile
    defaulting to "Today" so the queue keeps its old default; removing that
    tile is now a deliberate "show every date" choice rather than the
    starting point. Board view groups by a fixed Status axis (`STATUS_GROUP_AXIS`
    — Pending/In Progress/Completed columns; not a page-picked axis, since
    Status is the only grouping that makes sense here). Table view's row
    actions keep a visible, tap-to-open "..." (`renderRowActions`/
    `MoreOptionsMenu`, "View Details"); List/Board use a new
    `renderQueueCard` wrapped in `CardContextMenu` (hold/right-click) per
    item 6 — a plain tap still selects the consultation.
- `client/src/features/veterinary/pages/VeterinaryConsolePage/consultationQueueFilterFields.ts`
  (new file) — `CONSULTATION_QUEUE_FILTER_FIELDS` (Date date-range + Status
  select), `CONSULTATION_QUEUE_SORT_FIELDS` (Scheduled time / Pet name),
  `CONSULTATION_STATUS_GROUPS`, and the `deriveDateRange`/`deriveStatusFilter`
  helpers that read those filter tiles back out for the page's existing
  server query and client-side status filter.
- `client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.module.css`
  — new styles for the title row/"New Consultation" button and the
  List/Board card layout.
- `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
  — reads `location.state.lockedServiceCategory` once on mount
  (`lockedServiceCategory`, read the same render as `isReceptionistMode`).
  When present: `category` state initializes to it instead of `''`; the
  "Service Type" step is omitted from the wizard's `steps` list entirely
  (`if (!lockedServiceCategory) { list.push({ key: 'category', ... }) }`);
  every place that used to reset `category` back to `''` (pet re-selection,
  branch re-selection, "Start over"/reset-for-next-booking, the draft-restore
  effect) now resets it to `lockedServiceCategory ?? ''` instead, so the lock
  survives every reset point in the flow; and the draft-restore effect bails
  out entirely when a lock is present, so New Consultation always starts
  fresh rather than silently restoring an unrelated earlier draft.
- `client/src/features/booking/bookingConfirmation.ts` —
  `deriveBookingConfirmationState`'s `awaitingPayment` check dropped
  `booking.service_category !== 'Veterinary' &&`, so an unpaid online
  Veterinary booking now derives to `Unconfirmed` like every other category
  (a Walk-in Veterinary booking, or any paid one, is still `Confirmed`). The
  explanatory comment above the function was updated to match.
- **Item 5, verification only, no code change** —
  `client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`
  and `server/src/features/reports/services/transactionHistory.service.ts`
  were read and confirmed to never filter on the confirmation-state label
  from item 4, and never exclude `service_category: 'Veterinary'` — a
  Cashier can already query any service category. No diff exists for either
  file.
- **Item 6 — tap-to-open replaced with `CardContextMenu` (hold/right-click)**,
  for each page's List and/or Board card renderer only (Table's own "..."
  column stays a normal visible, tap-to-open control everywhere):
  `AdminBreedsPage.tsx`, `AdminPetTypesPage.tsx`,
  `AdminDiscountManagementPage.tsx` (**Board only** — its List view is
  deliberately kept as the page's primary tap-friendly browsing surface,
  per an existing product decision (Epic B #85), so List's visible
  `MoreOptionsMenu` there is untouched — a scope narrowing from the plan,
  made explicit in a new code comment), `AdminPromoConfigPage.tsx`
  (**List only** — this page has no Board view; its Gallery view uses a
  different, non-`MoreOptionsMenu` card component with always-visible
  buttons and was left alone), `AdminServicesPage.tsx`,
  `AdminServiceTypesPage.tsx`, `AdminPackageBuilderPage.tsx`,
  `HotelBookingPicker.tsx`, `HotelStayPicker.tsx`, `VetCatalogPage.tsx`,
  `CustomerBookingsPage.tsx`, `MyPatientsPage.tsx`. Each page's action-item
  list was pulled into its own `build<X>ActionItems(...)` helper so the
  same list of menu items feeds both the Table view's `MoreOptionsMenu` and
  the List/Board view's `CardContextMenu`. Consultation Queue's own new
  List/Board (item 7) used this pattern from the start rather than being
  converted separately.

## Manual test — step by step

Both dev servers need to already be running (client on port 5173, server on
port 3000) — check for an existing listener on those ports before starting
either (see the `dev-servers` skill) rather than starting a second copy.

### A. The Forbidden-error fix (item 1)

1. Open your web browser and go to `http://localhost:5173/staff/login`.
2. Log in as a **Veterinarian** staff account (e.g. `makati.veterinarian1`
   with its seeded password). You should land on the staff **Dashboard**.
3. In the sidebar, click **Consultation Queue**, then click the new **New
   Consultation** button near the page title (see scenario C below — this
   also exercises item 3's entry point). You should land on **Book a
   service**, already on the **Customer** step.
4. Confirm you do **not** see a red "Forbidden" error banner or the text "0
   customers". You should instead see a list of customer cards — only
   customers whose pets this vet account has actually treated a consultation
   for. If the vet account has treated zero patients so far, you should see
   an empty state explaining that, not an error.
5. To see the "before" behavior for comparison, you'd need to check out the
   base `dev` branch (before this session's changes) and repeat steps 1-4 —
   there you'd see a red "Forbidden" banner and "0 customers" instead.

### B. Breeds "..." row menu (item 2)

1. Log in as an **Admin** or **Superadmin**. Go to **Settings > Config >
   Pets > Breeds** (or navigate to `/staff/settings` and find Breed
   Management under Config).
2. In **Table** view, confirm each breed row shows a single **"..."**
   button instead of separate "Rename"/"Delete" buttons. Click it — confirm
   a dropdown with **Rename** and **Delete** appears, matching the same
   pattern as the Pet Types page.
3. Switch to **List** view — confirm there is no visible "..." button on
   each card (see scenario E below for the hold/right-click behavior that
   replaced it).

### C. Vet Bookings Queue folded into Consultation Queue (item 3)

1. Still logged in as the Veterinarian account from scenario A, look at the
   sidebar. Confirm there is **no "Bookings Queue" item** — only
   **Consultation Queue**, **My Patients**, etc.
2. Manually type `http://localhost:5173/staff/bookings/queue` into the
   address bar and press Enter. Confirm you are **redirected** to
   `/staff/veterinary/console` (Consultation Queue) rather than seeing the
   Bookings Queue page.
3. On Consultation Queue, click **New Consultation**. Confirm the booking
   builder opens directly on the **Customer** step (no "Service Type" step
   appears anywhere in the step list at the top of the page) and that
   **Veterinary** services are what show up once you reach the Services
   step — you never had to pick a service type yourself.
4. Partway through the builder, go back and re-pick a different **Pet**, or
   click **Start over**. Confirm the wizard still has no Service Type step
   and still only offers Veterinary services — the lock survives these
   resets.

### D. Unpaid online vet bookings show "Unconfirmed" (item 4)

1. Log out and log in as a **Customer** account (or use the customer
   portal at `http://localhost:5173/portal/book` while not staff-logged-in).
2. Book a **Veterinary** service online, and stop **before** paying anything
   (leave it unpaid — a Pending, Online booking).
3. Go to **My bookings**. Confirm the new booking's status badge reads
   **Unconfirmed** — not "Confirmed". (Compare against a Grooming/Hotel/
   Daycare booking made the same way, which should also read Unconfirmed —
   they should now look consistent.)
4. As a Cashier, record a payment for that booking (or use the customer
   portal to pay online, if available). Confirm the badge changes to
   **Confirmed** once payment settles.

### E. Cashier Transactions page still shows vet transactions (item 5)

1. Log in as a **Cashier**. Go to **Transactions**.
2. Confirm the vet booking's payment from scenario D (or any existing paid
   Veterinary booking) still appears in the list, with **Veterinary** shown
   as its service. Nothing here should look any different than before.

### F. Tap-to-open became press-and-hold on List/Board cards (item 6)

1. Open your browser's device toolbar (e.g. Chrome DevTools > Toggle device
   toolbar, `Ctrl+Shift+M`) and pick a mobile width/profile (e.g. "iPhone
   SE" or similar) so touch emulation is active.
2. Go to **Settings > Config > Pets > Breeds** (from scenario B), switch to
   **List** view. Tap once, quickly, on a breed card. Confirm **nothing**
   opens (a plain tap is ignored). Press and hold the card for about half a
   second without moving your finger. Confirm the **Rename/Delete** menu
   opens at that point.
3. On a desktop-width browser (no touch emulation), right-click a breed
   card in List view. Confirm the same menu opens there instead, and your
   browser's own right-click context menu does not appear.
4. Repeat the "tap does nothing, hold opens the menu" check on at least one
   other converted page for confidence, e.g. **Settings > Config >
   Services** (List/Board) or **Discounts** (**Board** view only — remember
   Discounts' **List** view was deliberately left as tap-to-open, so
   confirm the visible "..." button is still there and still opens on a
   single tap in List view specifically).

### G. Consultation Queue's shared toolbar (item 7)

1. Go to **Consultation Queue** as the Veterinarian account.
2. Confirm the toolbar looks like Transactions'/Breeds' toolbar — a search
   box, a **Filter** control, a **Sort** control, and a **Table/List/Board**
   view switcher — instead of the old separate date-range dropdown/status
   dropdown/search box.
3. Confirm a **Date** filter tile is present by default, reading "Today".
   Remove it (its own "x") — confirm the queue now shows consultations from
   every date, not just today.
4. Add a **Status** filter tile, set it to e.g. "Pending" — confirm the
   queue narrows to just Pending consultations.
5. Switch to **Board** view. Confirm three columns appear: **Pending**, **In
   Progress**, **Completed**, each holding the matching consultations.
6. Switch to **Table** view. Confirm each row still has a visible,
   tap-to-open **"..."** button (View Details) — Table view was
   deliberately left as tap-to-open, unlike List/Board (scenario F).
7. Switch to **List** or stay on **Board**; confirm cards there have **no**
   visible "..." button, and that press-and-hold (or right-click on
   desktop) opens **View Details**, same as scenario F.

## Test suites

Both suites were run this session by the implementing agent before this
record was written; not re-run here.

- `server`: `npx vitest run` — **1184/1184 tests passing** (106 files).
  `npx tsc --noEmit` — clean. `npx eslint` on touched files — clean.
- `client`: `npx tsc -b` — clean (whole project; this repo's root
  `tsconfig.json` is solution-style, so `npx tsc --noEmit -p .` alone would
  silently check zero files). `npx vitest run` — **1259/1263 tests passing**
  (213/215 files). The 4 failures are not regressions from this session:
  - 3 in `client/src/features/auth/staff/api/staffAuth.api.spec.ts` — a
    pre-existing `VITE_API_BASE_URL` env-var mismatch (expects a relative
    URL, gets an absolute `http://localhost:3000/...` one); this file was
    never touched in this session (not in `git diff`/`git status`).
  - 1 in `VeterinaryConsolePage.spec.ts` ("starting a Pending consultation
    from its queue row..."), a timeout that only occurs under full-suite
    parallel load (stuck on "Loading consultations..." when the assertion
    ran). Running that spec file alone
    (`npx vitest run src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.spec.ts`)
    passed 9/9 cleanly, confirmed twice.
- New/updated spec files worth highlighting:
  - `CustomerPicker.spec.ts` — new `describe('restrictToCustomerIds (vet-bookings-queue-access)')`
    block, including `'fetches only the restricted customers by id, never
the broad list endpoint (Forbidden-error fix)'`.
  - `CustomerBookingFlowPage.spec.ts` (107 lines changed) — new
    `describe('veterinarian bookings queue access (custom change)')` block,
    including `'New Consultation: a locked service category removes the
Service Type step entirely, not just auto-advances past it'`.
  - `ReceptionistBookingsQueuePage.spec.ts` — new
    `'vet-bookings-queue-access: redirects a Veterinarian away (Consultation
Queue is their entry point now)'`.
  - `VeterinaryConsolePage.spec.ts` (106 lines changed, 9 tests total) —
    new `'vet-bookings-queue-access: New Consultation opens the booking
builder locked to Veterinary'`,
    `'shared-toolbar-and-tap-to-hold: adding a Status filter tile narrows
the queue to just that status'`, and
    `'shared-toolbar-and-tap-to-hold: switches to Table view, where row
actions are a persistent "..." button (tap stays tap)'`.
  - `bookingConfirmation.spec.ts` — the old `'a Veterinary Pending booking
is Confirmed...'` test was replaced with `'an unpaid online Veterinary
Pending booking is Unconfirmed, same as every other category'` plus a
    new `'a walk-in Veterinary Pending booking is Confirmed (customer is
present)'` case.
  - `bookingGroup.service.spec.ts` — mocked rows in the vet-confirmed-at-
    creation test helper now explicitly carry `booking_source: 'Walk-in'`,
    since Online Veterinary no longer auto-confirms in that path either.
    `booking.service.spec.ts` itself did not need a diff — no existing test
    there asserted the old Online-Veterinary-is-confirmed-at-creation
    behavior, so nothing broke and nothing needed updating.
  - New files: `consultationQueueFilterFields.ts` +
    `consultationQueueFilterFields.spec.ts`.
  - The tap-to-hold conversion (item 6) added an equivalent long-press/
    right-click test to each of the 12 converted pages' own spec files.

## Open items

None outstanding from this session's own 7 requests. Two things flagged
during implementation as deliberate, in-session scope calls rather than
final product decisions — worth re-confirming with whoever owns the
request if they expected otherwise:

- **AdminDiscountManagementPage's List view stays tap-to-open** (Board
  only converted to hold/right-click) — an existing product decision
  (Epic B #85) that List is this page's primary, tap-friendly browsing
  surface, not a dense card grid like the others.
- **AdminPromoConfigPage's Gallery view was left untouched** (only its
  List view converted) — Gallery uses a different card component with
  always-visible buttons, not `MoreOptionsMenu`, so it wasn't in scope for
  this pattern to begin with.
