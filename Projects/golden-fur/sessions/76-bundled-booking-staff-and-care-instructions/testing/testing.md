# Configurable staff concurrency + the Hotel "Care Instructions" crash fix + availability backfill

Branch (code): `fix/bundled-booking-staff-and-care-instructions` (base: `dev`)
Branch (this vault session PR):
`docs/golden-fur-session-76-bundled-booking-staff-and-care-instructions`
(base: `main`) — recorded here so the vault `pr-guard` can find this folder.

## The request, verbatim

Two "In Progress" backlog items from
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`
(copied in full to `context/architectural-change-history-in-progress.md`):

> **Currently, the new bundled booking feature allows selection of the same
> staff (from staff picker) on the same date/time**
>
> - Determine if staff assignment is 1 = 1 (e.g. 1 groomer = 1 pet only) or
>   1 = many (e.g. 1 groomer = 2 pets)
> - Sample booking chose groomer 1 for both Luna and Cooper on same date 11 AM
>
> Perhaps add a config in admin settings that will allow admins to set how
> many times a staff can be chosen by a booking customer at the same time on
> the same date

> **Fix booking > new booking > hotel type service > step 8 care
> instructions:**
>
> - When unchecking same instructions every night, and instructions in other
>   nights are not configured, booking fails
> - Should set the first night instructions the default for other nights (so
>   no need to set)
>
> Changing instructions for a specific night will only overwrite the
> instructions for that night
>
> - Or perhaps add a new tab that says default instructions, which will be
>   applied to all nights
> - Then apply overwrite on nights that are edited

Scope note: a third change (backfilling `service_branch_availability`) was
not requested — it was found while trying to reach the Hotel Care
Instructions step on the dev database, which showed "No Hotel services
available at this branch" for every category.

## Root cause / Context

### 1. Staff concurrency was hard-coded to 1 in three places

- **`get_staff_availability` RPC, Check 2** (last redefined in
  `20260904169`): a staff member appeared in the Staff Picker only if a
  `not exists (... overlapping booking ...)` subquery held — i.e. exactly
  zero overlapping bookings.
- **`confirmCapacityAfterInsert`** (`capacity.service.ts`): the post-insert
  race resolver for Grooming/Veterinary kept only the single
  earliest-created overlapping row (`rows[0].id === booking.id`).
- **`claimWindowOrThrow`** (`bookingGroup.service.ts`): the in-request guard
  that stops two sub-bookings of one bundled checkout from claiming the same
  staff member threw on the _first_ overlap.

Nothing let an admin say "one groomer can take 2 pets at once", and — the
reported bug — the bundled-booking Staff Picker did not even prevent the
customer from choosing the same person twice for the same window, so a
bundled booking could be built that either failed on Confirm or (as reported
for Luna + Cooper at 11 AM) slipped through.

Separately, `resolveStaffAssignment` (`booking.service.ts`) _silently
dropped_ a `specific` staff choice whenever `isStaffPickerEnabled(category)`
was false — leaving a booking with no staff assigned and no signal that the
client and server disagreed about whether a picker should exist.

### 2. Care Instructions submitted hidden, half-filled rows

In the Hotel Care Instructions step, unticking **"Same instructions every
night"** reveals per-night tabs; a row added on one night's tab is hidden
when another tab is active. `hotelPreferencesPayload` mapped **every** row
into the request regardless of fill state. The server's
`hotelPreferencesValidator` requires a feeding row to have food_type +
quantity, a medication row to have medication_name + dose, and a
walk/play row to have `duration_minutes > 0`; any half-filled row failed it
and the client surfaced only the generic **"Invalid payload"**. The per-night
data model already treats a dateless row as the fallback for every
un-overridden night, so no schema change was needed — only the client's
submit filtering and a blocking check.

### 3. `service_branch_availability` was empty on the dev DB

Both availability tables use "disable is opt-out": `listServices({ branchId })`
treats "no row for this service+branch" as "not offered here" and drops the
service. Those rows are created by the `m13-maintenance` seed, which runs
only on `supabase db reset`, never on `supabase db push`. The dev database
is kept current with `db push`, so services introduced by later migrations
(notably the fixed-price Hotel service "Overnight Stay (Aircon Room)",
`20260807105`) had **no** availability rows — and in fact the tables were
entirely empty — so the customer booking flow showed "No Hotel services
available at this branch" for every category.

## What changed

### Database (`golden-fur/supabase/migrations/`)

- **`20260908178_m03_policy_configurations_max_concurrent_staff.sql`** — adds
  `policy_configurations.max_concurrent_bookings_per_staff integer not null
default 1 check (>= 1)`. Seeded onto existing rows by the default itself
  (`policy_configurations` is migration-seeded, no seed file). Follows the
  `downpayment_hold_hours` / `booking_notice_period_days` column pattern.
- **`20260908179_m03_get_staff_availability_staff_capacity.sql`** — plain
  `create or replace` of `get_staff_availability` (signature unchanged from
  `20260904169`, so grants from `169`/`172` are preserved). Body is `169`'s
  verbatim except: a new `v_max_concurrent` read using the same
  branch-row-wins-else-system-default precedence as the lunch break, and
  Check 2's `not exists (...)` becomes `(select count(*) ...) <
v_max_concurrent`.
- **`20260908180_m13_backfill_branch_availability.sql`** — idempotent
  backfill of `is_available = true` for every active service × branch and
  every service type × branch, `ON CONFLICT DO NOTHING` (preserves opt-outs,
  no-op on a fresh reset since migrations run before the m01 seed creates
  branches).

All three are already applied to the **dev** Supabase project
(`hikgijuipymfghfuyrjv`) — `supabase migration list --linked` shows Local and
Remote in sync through `20260908180`. **Not** applied to production
(`gtqncxqsofqtzrlgxdfm`) — see Open items.

### Server (`golden-fur/server/src/features/booking/`)

- **`booking.types.ts`** — `max_concurrent_bookings_per_staff` added to
  `PolicyConfiguration` and to the `EffectivePolicy` pick.
- **`modules/validators/booking.validator.ts`** — `updatePolicyValidator`
  gains `max_concurrent_bookings_per_staff: z.number().int().min(1).optional()`.
- **`services/capacity.service.ts`** — `confirmCapacityAfterInsert(booking,
staffConcurrency = 1)`. The Grooming/Veterinary branch now returns
  `rows.slice(0, staffConcurrency).some(r => r.id === booking.id)` — the same
  "rank by (created_at, id), keep the first N" tie-break the Hotel/Daycare
  branches already used. Walk-ins and the down-payment settlement re-check
  keep the default of 1 (documented: the pre-insert RPC still honours the
  configured number for them).
- **`services/booking.service.ts`** —
  - `createBooking` resolves `staffConcurrency` from the effective policy on
    the Online path (Walk-ins keep 1) and passes it to
    `confirmCapacityAfterInsert`.
  - `resolveStaffAssignment` now `throwWithStatus(409, …)` when the picker is
    server-side disabled **and** the caller sent a `specific` preference,
    instead of silently returning `{ assignedStaffId: null }`.
- **`services/bookingGroup.service.ts`** —
  - `claimWindowOrThrow` gains a `capacity = 1` param; the overlap test is
    now `overlapping.length >= capacity` (was: any overlap). Cage/pet claims
    still pass 1; the staff claim passes
    `policy?.max_concurrent_bookings_per_staff ?? 1` (null only for an
    all-Walk-in group, which stays strict).
  - `confirmCapacityAfterInsert` in the post-insert loop is passed
    `policy?.max_concurrent_bookings_per_staff ?? 1`.
- **`services/staffPicker.service.ts`** — `StaffPickerOptionsResult` gains
  `max_concurrent_per_staff`. `getStaffPickerOptions` now calls
  `resolveEffectivePolicy(params.branchId)` when the picker is enabled and
  returns `policy.max_concurrent_bookings_per_staff`; the disabled branch
  returns `1` without a policy read. `updatePolicyConfiguration` writes the
  new column. `DOCUMENTED_DEFAULTS` gains the field.

### Client (`golden-fur/client/src/features/booking/`)

- **`booking.types.ts`** — mirrors the server: `max_concurrent_per_staff` on
  `StaffPickerOptionsResult`; `max_concurrent_bookings_per_staff` on
  `PolicyConfiguration`, `EffectivePolicy`, `UpdatePolicyPayload`.
- **`pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`** — new
  **"Staff concurrency"** section: a `min={1}` number input bound to
  `max_concurrent_bookings_per_staff`, wired through `FormState`,
  `formStateFromPolicy`, `DOCUMENTED_DEFAULTS` and the submit payload.
- **`components/StaffPickerList/StaffPickerList.tsx`** — new optional
  `cartStaffOverlapCounts?: Record<string, number>` prop. Reads
  `max_concurrent_per_staff` from the endpoint into state. A specific staff
  card is `disabled` (with `styles.disabled`, a `title`, and a
  "Booked for another pet in this checkout" hint) once
  `cartStaffOverlapCounts[staffId] >= maxConcurrentPerStaff`. A `useEffect`
  resets a now-"full" `specific` selection back to `{ type: 'no_preference' }`.
  `.module.css` gains `.card.disabled` / `.cartFullHint`.
- **`components/NightTabs/NightTabs.tsx`** — new optional `allNightsLabel`
  prop (default `"All nights"`); `formatNightLabel` moved out to
  `utils/hotelNights.ts`.
- **`utils/hotelNights.ts`** — now exports `formatNightLabel`.
- **`pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`** —
  - `HotelCareRowStatus` type + `hotelFeedingRowStatus` /
    `hotelMedicationRowStatus` / `hotelWalkPlayRowStatus` helpers classify a
    row `empty` / `partial` / `complete` mirroring the server Zod rules.
  - `hotelCareIncompleteRows` memo lists every `partial` row with its
    section + `stay_date`.
  - `isStepValid('hotelDetails')` returns `hotelCareIncompleteRows.length ===
0` (was: always `true`).
  - `hotelPreferencesPayload` `.filter(... === 'complete')` on all four row
    types before mapping — `empty` rows are dropped silently.
  - The Care Instructions step passes `allNightsLabel="Default (all nights)"`
    to `NightTabs`, adds an explanatory `<p>`, and renders an `errorBanner`
    naming the first offending section/night with a "Go to that night"
    button when that night's tab is hidden.
  - `cartStaffOverlapCounts` memo (Online only; mirrors `samePetBundleWindows`)
    counts, per specific staff member, how many already-committed cart
    bookings overlap the draft window; passed to `StaffPickerList`.

### Tests added / updated

- `server` `bookingGroup.service.spec.ts` **(b4)** — capacity 2 lets two
  sub-bookings share one staff member + window.
- `server` `capacity.service.spec.ts` — `confirmCapacityAfterInsert` wins
  when ranked within a raised `staffConcurrency`, still loses past it.
- `server` `booking.validator.spec.ts` — `max_concurrent_bookings_per_staff`
  accepts `>= 1`, rejects `0`.
- `server` `staffPicker.service.spec.ts` + `booking.integration.spec.ts` —
  disabled-picker response now `{ ..., max_concurrent_per_staff: 1 }`;
  enabled path queues an extra `resolveEffectivePolicy` fetch; several
  existing specs updated for that extra mock-queue entry.
- `client` `StaffPickerList.spec.ts` — a staff member at capacity for an
  overlapping cart booking is disabled and, if selected, cleared to
  "No preference"; one still below capacity is not disabled.
- `client` `CustomerBookingFlowPage.spec.ts` — "a blank row is dropped
  silently, a half-filled row blocks Next".

## Manual test — step by step

You need the dev API + web app running against the seeded **dev** database
(`server`: `npm run dev` → `http://localhost:3000`; `client`: `npm run dev` →
`http://localhost:5173`). All three migrations are already on the dev DB.
Seed logins: staff are `<branch>.<role>N@goldenfur.com` (username form
`makati.admin1`), customers are `customer1@goldenfur.com` …
`customer5@goldenfur.com`; every seed account's password is **`password123`**.
`customer1` owns the assessed pets **Max** and **Luna**.

### Scenario A — the Hotel services actually show up (backfill)

1. Open a browser at `http://localhost:5173/login`. In **Email** type
   `customer1@goldenfur.com`, in **Password** type `password123`, click
   **Sign in**. You land on the customer portal home. A red error banner
   means the server/seed is not ready — stop.
2. Click **Book a service**. Pick **Max**, click **Next**. Pick a branch
   (e.g. **Golden Fur Makati**), click **Next**.
3. On the service-type step click **Hotel**, click **Next**. Pick a date and
   number of nights, click **Next**.
4. **Expect:** the services step lists at least one Hotel service (e.g.
   "Overnight Stay (Aircon Room)"). **Failure:** the message "No Hotel
   services available at this branch" — the `20260908180` backfill did not
   take (or the DB has been reset without it).

### Scenario B — Care Instructions no longer crashes on a half-filled row

1. Continue from Scenario A (or restart the wizard for **Max → Hotel**,
   choosing a stay of **at least 2 nights**). Select a Hotel service, click
   **Next** to reach the step titled **Care Instructions**.
2. Untick **"Same instructions every night"**. A row of tabs appears. The
   first tab now reads **"Default (all nights)"** (not "All nights"), and a
   caption below explains entries there apply to every night unless a
   specific night overrides them. **Failure:** the tab still says "All
   nights", or there is no caption.
3. Click the **second** tab (the first actual night). Under **Feeding**
   click **Add feeding time**. In the new row pick a **Food type** from the
   dropdown but leave **Quantity** empty.
4. Click a **different** night's tab. The row you just started is now hidden.
5. Click **Next**.
   **Expect:** you do **not** advance. A banner appears reading roughly
   _"Finish or remove the Feeding entry for <date> before continuing."_ with
   a **"Go to that night"** button.
   **Failure (the old bug):** the wizard advances and the Confirm step later
   shows "Invalid payload", **or** Next is blocked with no banner telling you
   which night.
6. Click **"Go to that night"**. You land on the tab with the unfinished
   row. Type a quantity (e.g. `2`) into **Quantity**. Click **Next**.
   **Expect:** you advance to the next step; the completed row is kept.
7. Restart the step. Untick "Same instructions every night", click **Add
   feeding time**, and this time **do not touch any field** in the new row.
   Click **Next**.
   **Expect:** you advance normally — a completely blank row is dropped
   silently, no banner.

### Scenario C — admin "Staff concurrency" setting

1. New tab → `http://localhost:5173/staff/login`. In **Username or email**
   type `makati.admin1`, **Password** `password123`, click **Sign in**.
2. Click the **gear icon** in the top bar to open **Settings**. In the
   Settings sidebar click **Config**, then the **Policies** tile.
3. Scroll to the **"Staff concurrency"** section. **Expect:** a number field
   labelled _"Max concurrent bookings per staff member (1 = one pet at a
   time)"_ showing **1**, with explanatory copy below.
4. Change it to **2**, click the page's **Save** button. **Expect:** a
   success message; reloading the page shows **2** retained.
   **Failure:** a validation error on a valid value `2`, or the value
   resetting to 1 after reload.
5. Try to set it to **0** and Save. **Expect:** rejected (the field's
   `min` is 1 and the server validator rejects `< 1`).
6. Leave it at **2** for Scenario D, then set it back to **1** when done.

### Scenario D — bundled-booking Staff Picker honours the number

Do this with **Staff concurrency = 2** (Scenario C step 4) still in effect.

1. As `customer1`, start **Book a service**. Pick **Max**, a branch,
   **Grooming**, a date/time. On the date/time step the **Staff Picker**
   appears. Pick a specific groomer (note the name, e.g. "Makati Groomer 1").
   Pick a service, click **Next** through to the step titled **Your
   bookings**.
2. Click **Add another booking**. Pick **Luna**, the same branch,
   **Grooming**, and the **same date and start time** as booking 1. The
   Staff Picker appears again.
   **Expect (capacity 2):** "Makati Groomer 1" is still selectable — pick
   them again. Proceed to **Your bookings**: 2 cards, both with the same
   groomer.
3. Click **Add another booking** a third time. Pick **Cooper**, same branch,
   **Grooming**, same date/start time again.
   **Expect:** "Makati Groomer 1" is now **greyed out / disabled** with the
   hint **"Booked for another pet in this checkout"** (they are already used
   twice for this overlapping window, and capacity is 2). "No preference"
   and any other groomer stay selectable.
4. Go **back** to booking 2's date/time step and change its start time so it
   no longer overlaps booking 1. Return to booking 3's Staff Picker.
   **Expect:** "Makati Groomer 1" is selectable again (only one overlapping
   cart booking now uses them).
5. Set **Staff concurrency back to 1** (Scenario C). Repeat step 2:
   **Expect:** "Makati Groomer 1" is greyed out on the **second** pet
   already — one overlapping cart booking is now the limit.
6. If you had previously selected that groomer for booking 2 and then
   lowered the limit, re-opening booking 2's Staff Picker should show the
   selection quietly reverted to **"No preference"** (no error).

### API-level checks

See `bundled-booking-staff-and-care-instructions.postman_collection.json`:
logs in as an Admin and as `customer1`, reads `GET /bookings/policy` (new
column present, `>= 1`), rejects `PATCH /bookings/policy` with
`max_concurrent_bookings_per_staff: 0`, raises it to `2`, confirms
`GET /bookings/staff-picker` returns `max_concurrent_per_staff: 2` for
Grooming and `1` (no policy read) for the picker-disabled Hotel category,
then restores it to `1`.

## Test suites

Per this session's verification run (task hand-off — full suites, both
packages, on `fix/bundled-booking-staff-and-care-instructions`):

- `server`: **1008 passing**; `npx tsc --noEmit` clean; lint clean.
- `client`: **787 passing**; `npx tsc -b` clean; lint clean.
- Repo-wide: `format:check` clean.

## Open items

- Migrations `20260908178`–`180` are on the **dev** Supabase project only.
  Before this reaches an environment backed by production
  (`gtqncxqsofqtzrlgxdfm`), run the `supabase-migration-push` skill (it
  confirms the linked ref is not production first). `20260908180` in
  particular is a data-recovery backfill that production may or may not need
  depending on whether its availability tables are already fully populated —
  it is a safe no-op either way.
- The `resolveStaffAssignment` 409 only fires when a client shows a picker
  the server says should not exist (a stale `staff_picker_enabled` flag). It
  is defensive; no known flow currently triggers it.
- Raising `max_concurrent_bookings_per_staff` above 1 is a global/branch
  policy only — there is no per-staff or per-service override.
