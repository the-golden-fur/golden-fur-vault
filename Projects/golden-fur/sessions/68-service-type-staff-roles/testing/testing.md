# Service Types — staff-role multi-select, dropped Key field, removed the redundant Policies toggle

Branch: `feat/service-type-staff-roles` (golden-fur) · vault: N/A — no
vault-side branch, this session only changed files in the golden-fur repo
(plus two `.agent/` doc files there, not in this vault).

## The request, verbatim

> When creating new service type > staff picker, it doesn't specify what
> staff roles are available to choose from. Extend it by adding options to
> choose staff roles (multi-select). Since grooming services > groomer, vet
> services > vets, etc. Do the same for existing service types and update
> seed scripts. Also remove the key field, this should be randomly generated
> anyway, only leave out name. Just drop key field, it seems redundant, I
> don't like it showing in the list either.

> Scope note — a mid-session follow-up, same person, chat only (no source
> document):
>
> while you're at it, I think there's a stray staff picker config at admin
> settings > policies, even though it can already be configured now at
> service type. get rid of it.

## Root cause / Context

Two independent problems, both rooted in `service_types` never actually
driving Staff Picker behavior:

1. **Role eligibility was two byte-identical hardcoded maps in server code**
   (`staffPicker.service.ts` and `availability.service.ts`):
   `{ Grooming: 'Groomer', Veterinary: 'Veterinarian' }`. Nothing in
   `service_types` recorded which roles applied, and the Staff Picker step
   was hardcoded to only ever exist for those two categories — Hotel/Daycare
   or any future custom type could never get one, regardless of the
   `staff_picker_enabled` toggle Admin Settings > Service Types already
   exposed for every row.
2. **Two toggles for the same thing, and the "real" one was the wrong one.**
   `policy_configurations.staff_picker_enabled_grooming`/`_veterinary` was an
   older, separate, per-branch on/off switch for the exact same two
   categories, and — until this session — it was the _only_ one of the two
   `isStaffPickerEnabled` actually read. `service_types.staff_picker_enabled`
   sat in the database unused, even though the Service Types admin page made
   it look live.
3. **`service_types.key`** (confirmed by reading the code) is genuinely
   load-bearing in two places — `cagePicker.service.ts`'s
   `isCagePickerEnabled`, and `CustomerBookingFlowPage.tsx`'s category-tab
   derivation — so the column itself can't disappear. It just never needed
   to be admin-typed or admin-visible; it's an internal join key, not a
   setting.

## What changed

### Database

- `supabase/migrations/20260904168_custom_service_types_eligible_staff_roles.sql`
  — adds `service_types.eligible_staff_roles public.staff_role[] not null
default '{}'`; backfills `Grooming -> {Groomer}`,
  `Veterinary -> {Veterinarian}` (mechanical match of the old hardcoded map);
  Hotel/Daycare stay `{}`.
- `supabase/migrations/20260904169_m03_get_staff_availability_multi_roles.sql`
  — `get_staff_availability` changes from a single `p_role public.staff_role`
  parameter to `p_roles public.staff_role[]`, matching via
  `sp.role = any(p_roles)`. Since the parameter list changes, this `drop
function`s the exact old six-argument signature first, then
  `create function`s the new one — a plain `create or replace` against a
  different signature would have left a stale second overload instead of
  replacing it. Body is otherwise a verbatim copy of the prior definition
  (`20260901156_m03_get_staff_availability_payment_status.sql`).
- `supabase/migrations/20260904170_custom_drop_policy_staff_picker_toggle.sql`
  — drops `policy_configurations.staff_picker_enabled_grooming` and
  `_veterinary` (the mid-session follow-up).

All three are now applied to the linked Supabase project (`npm run
supabase:push`) — see Open items.

No new `supabase/seeds/` files: `service_types` has no dedicated seed
`.ts`/`.sql`/`.spec.ts` trio today (it's migration-seeded only, alongside the
existing precedent of small fixed-row tables like `breeds`), and that
remains correct after this change — a seed-sync pass confirmed nothing new
is needed.

### Server

- `maintenance.types.ts` — `ServiceType` gains `eligible_staff_roles: string[]`.
  `CreateServiceTypePayload`/`CreateServiceTypeInput` drop `key`; both create
  and update payload types gain `eligible_staff_roles?: string[]`.
- `modules/validators/maintenance.validator.ts` — `createServiceTypeValidator`
  drops the required `key` field, gains
  `eligible_staff_roles: z.array(z.string()).optional()`.
  `updateServiceTypeValidator` gains the same optional field.
- `services/serviceTypes.service.ts` — `createServiceType` now generates
  `key: randomUUID()` server-side instead of taking `input.key`, and inserts
  `eligible_staff_roles: input.eligible_staff_roles ?? []`. The unique-key
  conflict error message no longer echoes back a client-chosen key (there
  isn't one) — kept only as defense-in-depth, since a `randomUUID()` key
  collision is practically unreachable. `updateServiceType` needed no code
  change — it already spreads `...updates` straight into the DB update.
- `services/staffPicker.service.ts` — the old `CATEGORY_STAFF_ROLE` const is
  replaced by one exported helper, `resolveServiceTypeStaffConfig(serviceCategory)`,
  which queries `service_types` by `key = serviceCategory` and returns
  `{ staff_picker_enabled, eligible_staff_roles }` (mirrors
  `cagePicker.service.ts`'s `isCagePickerEnabled` query shape; a missing row
  or query error degrades to disabled + empty). `isStaffPickerEnabled` drops
  its `branchId` parameter and its Grooming/Veterinary early-return — the
  helper's `staff_picker_enabled` flag is now the sole gate, for every
  category, with no secondary policy-config check. `listAvailableStaff` uses
  `eligible_staff_roles` (an array) instead of a single mapped role, and
  passes `p_roles` (array) to the RPC — an empty array still produces the
  existing 400 "Staff availability does not apply to X bookings" response.
  `DOCUMENTED_DEFAULTS` drops `staff_picker_enabled_grooming`/`_veterinary`.
- `services/availability.service.ts` — drops its own copy of
  `CATEGORY_STAFF_ROLE`; `getDaySlots` now calls
  `resolveServiceTypeStaffConfig` once per day and passes the resolved
  `eligible_staff_roles` through to `listAvailableStaff` via a new
  `eligibleStaffRoles` param (avoids re-resolving `service_types` once per
  candidate slot). `countActiveRoster`'s role filter changes from
  `.eq('role', role)` to `.in('role', roles)`, with an explicit
  `if (roles.length === 0) return 0;` guard first (Supabase's `.in()` with an
  empty array is unreliable).
- `booking.service.ts` — `resolveStaffAssignment`'s own separate hardcoded
  `category !== 'Grooming' && category !== 'Veterinary'` early-return
  survived this pass unnoticed (only `isStaffPickerEnabled` itself and
  `getStaffPickerOptions` were updated). It was caught and fixed while
  investigating a closely related follow-up request — see
  [session 69](../../69-assessment-service-type-seed/testing/testing.md) for
  the root cause, the fix itself, and the test-mock updates it required.
- `modules/validators/booking.validator.ts` — `updatePolicyValidator` drops
  `staff_picker_enabled_grooming`/`_veterinary`. The validator is `.strict()`,
  so sending either field in a `PATCH /bookings/policy` body now gets
  rejected outright as an unrecognized key (400 "Invalid payload"), not
  silently dropped.
- `booking.types.ts` — `PolicyConfiguration`/`EffectivePolicy` drop the same
  two fields.

### Client

- `staff/staff.types.ts` — new `ALL_STAFF_ROLES: readonly StaffRole[]`
  constant (the 8-role list; server already had its own copy).
- New `maintenance/components/StaffRoleMultiSelect/` — a plain
  `<fieldset>`/checkbox-list component (`{ label, selectedRoles, onChange,
disabled? }`), modeled on `BranchMultiSelect`'s prop shape but over the
  static `ALL_STAFF_ROLES` list rather than a fetched one (no
  search/sort machinery needed for a fixed 8-item list). Includes a
  `.module.css` and a `.spec.ts`.
- `maintenance/pages/AdminServiceTypesPage/AdminServiceTypesPage.tsx` —
  removes `key` from `CreateFormState`/`EMPTY_CREATE_FORM` and the search
  matcher; adds `eligibleStaffRoles: string[]` to both `CreateFormState` and
  `EditFormState`, wired through `openEditModal`, `handleCreate` (drops the
  key-required guard and the `key` field from the payload; adds
  `eligible_staff_roles`), and `handleEditSubmit`. Removes the Key `<input>`
  from the create form and the key badge `<span>` from the list item. Adds
  `<StaffRoleMultiSelect>` to both the create and edit forms, next to the
  existing Cage Picker toggle.
- `maintenance/maintenance.types.ts` — same `eligible_staff_roles` addition
  to `ServiceType`; `CreateServiceTypePayload` drops `key`; both payload
  types gain `eligible_staff_roles?: string[]`.
- `booking/components/StaffPickerList/StaffPickerList.tsx` — `serviceCategory`
  prop widens from the literal `'Grooming' | 'Veterinary'` to the full
  `ServiceCategory` type (it does no category-specific logic itself).
- `booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` — a new
  `staffPickerAppliesToCategory` value, read from the page's existing
  `serviceTypeByKey` map's `staff_picker_enabled`, replaces three separate
  hardcoded `category === 'Grooming' || category === 'Veterinary'` checks
  (the step label, `isStepValid('availability')`, and the render gate for
  `<StaffPickerList>`).
- `booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`
  and `booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx` — drop
  the hardcoded category clause from `showStaffPicker` entirely; both pages
  rely on `StaffPickerList`'s existing `onUnavailable` self-hide contract
  instead of computing eligibility themselves (neither page already fetches
  `service_types`, so this avoids adding a new network call to either).
- `booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx` —
  removes the entire "Staff Picker visibility" section (both checkboxes) and
  the two fields from `FormState`, `formStateFromPolicy`,
  `DOCUMENTED_DEFAULTS`, and the PATCH payload; the page's intro copy is
  updated to no longer mention Staff Picker visibility, and a code comment
  notes it moved to Admin Settings > Service Types.
- `booking/booking.types.ts` — `PolicyConfiguration`, `EffectivePolicy`, and
  `UpdatePolicyPayload` all drop `staff_picker_enabled_grooming`/`_veterinary`.

### Docs (golden-fur repo, not this vault)

- `.agent/skills/capacity-based-scheduling.md` and
  `.agent/agents/booking-capacity-agent.md` both got a short addition noting
  eligible staff roles per category are now admin-configurable via
  `service_types.eligible_staff_roles`/`resolveServiceTypeStaffConfig()`,
  not implied by category name.

## Manual test — step by step

**Not yet executed by a human** — only the automated test suites below have
been run this session. The three migrations are now applied to the linked
project (see Open items), so these steps are ready to follow.

Prereqs: dev servers up — client `http://localhost:5173`, server
`http://localhost:3000` (`npm run dev` from the repo root).

### A. Key field is gone, roles multi-select appears

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login** (top-right corner). Sign in as an **Admin** or
   **Superadmin** account. You should land on a page headed **Dashboard**. If
   you see a red error banner instead, stop — the dev server or seed data is
   not ready.
3. Open **Settings** (gear icon / sidebar) → **Maintenance** → **Service
   Types**.
4. In the list, confirm no row shows a small key badge next to its name
   anymore (only the name, and the Staff Picker/Cage Picker badges if
   enabled). Failure: a key-looking short code still appears next to a name.
5. Click **New service type**. Confirm the form has a **Name** field, an
   **Active**/branch-availability picker, **Staff picker enabled** and **Cage
   picker enabled** checkboxes, and a new **Eligible staff roles** checklist
   with all 8 roles (Superadmin, Admin, Supervisor, Receptionist, Groomer,
   Veterinarian, Cashier, Pet Assistant) — but **no Key field**. Failure: a
   Key input is still present, or the role checklist is missing.
6. Type a name (e.g. "Test Type"), tick **Groomer**, click **Save**/**Create**.
   It should succeed and appear in the list without you ever entering a key.

### B. Existing Grooming/Veterinary rows are pre-populated correctly

7. In the Service Types list, click **Edit** on the **Grooming** row. Confirm
   the **Eligible staff roles** checklist shows only **Groomer** ticked.
   Failure: no roles ticked, or the wrong role ticked.
8. Click **Edit** on the **Veterinary** row. Confirm only **Veterinarian** is
   ticked.
9. Untick/retick a role on either row, save, and confirm it round-trips (the
   row reopens with your change reflected) — the field is genuinely editable,
   not read-only.

### C. The old Policies-page toggle is gone

10. Open **Settings** → **Config** → **Policies**.
11. Confirm there is **no** "Staff Picker visibility" section, and no
    "Enabled for Grooming" / "Enabled for Veterinary" checkboxes anywhere on
    the page. Failure: either checkbox is still present.

### D. Staff Picker still works normally for Grooming/Veterinary (regression check)

12. Sidebar → **Bookings Queue** → **New booking**. Pick a branch, a pet,
    service type **Grooming**, a future date/time.
13. At the staff step, confirm the picker offers **only Groomers** (job title
    shown per staff card) — not vets, cashiers, etc. Failure: a non-Groomer
    role appears, or the step is entirely missing.
14. Repeat for a **Veterinary** booking — confirm only **Veterinarians**
    appear.

### E. Staff Picker can now be turned on for a category that never had one before

15. Back in **Service Types**, edit **Hotel** (or **Daycare**): tick **Staff
    picker enabled**, tick one role (e.g. **Pet Assistant**), save.
16. Start a new Hotel booking in Bookings Queue. Confirm a staff-selection
    step now actually appears, offering only staff with that role. (Before
    this session, this was impossible regardless of the toggle — the picker
    was hardcoded to Grooming/Veterinary only.)
17. Undo step 15 (untick Staff picker enabled for Hotel/Daycare) to restore
    the prior default behavior.

## Test suites

Run from the repo root on branch `feat/service-type-staff-roles`:

- **server**: `npm run test` — **965/965 passing** (88 files).
  `npm run typecheck` (`tsc --noEmit`) — clean.
- **client**: `npm run test` — **774/774 passing** (151 files).
  `npx tsc -b --noEmit` — clean.

New/changed tests (server): `serviceTypes.service.spec.ts` (drops `key`
fixtures, asserts a generated key + `eligible_staff_roles` on create),
`staffPicker.service.spec.ts` (role-map tests replaced with a `service_types`
mock and a `p_roles` array assertion; policy-toggle assertions dropped),
`availability.service.spec.ts` (roster-count role→roles), `capacity.service.spec.ts`
(mocks `resolveServiceTypeStaffConfig`'s underlying query for its
staff-count-path tests), `reschedule.service.spec.ts`,
`booking.validator.spec.ts` — all updated to drop the two removed policy
fields from fixture objects. `booking.integration.spec.ts` and
`booking.service.spec.ts` needed the same fixture cleanup, plus a further,
larger mock rewrite for the `resolveStaffAssignment` bugfix caught in
[session 69](../../69-assessment-service-type-seed/testing/testing.md) — see
that session's record for the detail.

New/changed tests (client): `AdminServiceTypesPage.spec.ts` (drops `key`
fixtures/assertions), `CustomerBookingFlowPage.spec.ts` (staff-picker gating
now keyed off `serviceTypeByKey`, not a hardcoded category check), and the
new `StaffRoleMultiSelect.spec.ts`.

## Open items

- ~~The three new migrations have not yet been pushed~~ — resolved. A
  hand-typed `supabase db push` was initially blocked by this session's
  sandbox permissions; `npm run supabase:push` (the
  `📤 Supabase: Push Migrations` VS Code task) is the correct way to apply
  it and has since been run successfully. `npm run supabase:status`
  confirms all three (`20260904168`, `20260904169`, `20260904170`) are now
  applied remotely.
- **Manual UI verification has not been performed** by a human in a running
  instance of the app — only the automated test suites above were run this
  session. The click-by-click steps above are ready to follow once the
  migrations are pushed.
- No PR has been opened yet for this branch, so `reviews/` has not been
  populated (`code-reviewer` writes there once a PR exists).
