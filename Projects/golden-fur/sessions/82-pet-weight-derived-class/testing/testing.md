# Pet weight recorded as a number, weight class derived from it, per-user kg/lb display

Branch: `feat/pet-weight-derived-class` (golden-fur), commit `a97608d`
Vault branch: `docs/golden-fur-session-82`

## The request, verbatim

> - When updating a pet's weight via an assessment type booking, automatically update its weight class
>   - No longer need to manually select the weight class
>   - It should derive from actual weight value
>   - Perhaps make it readonly, but still can be overridden
>   - Should be able to set it to lbs or kg
> - Add settings whether to view pet's weight as lbs or kg (per user, not admin control)
>
> see `Projects\golden-fur\shared\context\Architectural-Change-History.docx` for full task context
> make sure to include it in commits in the end

This is the "Matthew, Low Priority" row of the Architectural-Change-History
document. No GitHub issue.

## Root cause / Context

- A pet's assessment stored only two things: `weight_class` (the S/M/L/XL enum)
  and `coat_type` (SC/LC). `weight_class` was set directly by staff from a
  drop-down — an eyeball judgement. There was **no numeric weight column
  anywhere on the pet**. `weight_class` feeds Grooming pricing tiers and
  Hotel/Daycare cage sizing, so an inconsistent guess moves real money.
- `weight_class`/`coat_type` are already protected as staff-only: the server
  splits customer vs staff Zod validators (`.strict()` rejects the fields from
  a customer), and the DB trigger `enforce_pet_assessment_writes()`
  (migrations …073 / …075) is the defence-in-depth backstop for a direct
  Postgres write. This change extends the same treatment to the new column.
- The per-user kg/lb choice follows the existing per-user preference pattern
  (`theme_preference` migration …018, `font_size_preference` migration …065):
  one `NOT NULL DEFAULT` text column with a named CHECK on both
  `staff_profiles` and `customer_profiles`, exposed through the same
  `PATCH /auth/{staff,customers}/preferences` endpoint and the client
  `ThemeProvider`.
- No shared code module spans the client and server builds, so the
  weight→class derivation function is hand-duplicated in both trees with a
  comment on each copy pointing at the other.

## What changed

### Database (all four migrations NEW)

- `20260910184_shared_add_weight_unit_preference_columns.sql` —
  `weight_unit_preference text NOT NULL DEFAULT 'kg' CHECK IN ('kg','lbs')` on
  **both** `staff_profiles` and `customer_profiles`. The DEFAULT backfills
  existing rows, so it applies cleanly on `db push`.
- `20260910185_m02_pets_add_weight_kg.sql` — `pets.weight_kg numeric(5,2)`,
  nullable, `CHECK (weight_kg IS NULL OR (weight_kg > 0 AND weight_kg < 500))`.
  Canonical kilograms. `NULL` ("no number yet") is independent of
  `weight_class IS NULL` ("not assessed yet").
- `20260910186_m13_create_pet_weight_class_configuration.sql` — new singleton
  table `pet_weight_class_configuration` (`m_min_kg` / `l_min_kg` / `xl_min_kg`
  `numeric NOT NULL`, seeded **9.5 / 22 / 41** as a non-round starting point;
  `updated_by_staff_id`, `updated_at`). Singleton `unique index … ((true))`,
  ordered `CHECK (m_min_kg > 0 AND m_min_kg < l_min_kg AND l_min_kg <
  xl_min_kg)`, two-tier RLS (all staff read via `current_staff_role() IS NOT
  NULL`, Admin/Superadmin write). Same shape as `pricing_configuration`
  (…047); no `supabase/seeds` trio, matching that table.
- `20260910187_m02_pets_assessment_lock_weight_kg.sql` —
  `CREATE OR REPLACE FUNCTION enforce_pet_assessment_writes()` adding
  `weight_kg` to the untrusted-direct-write rejection on both INSERT and
  UPDATE. Body is otherwise a verbatim copy of …075; the trigger itself is
  unchanged and not recreated.

Reference copies: `testing/pet-weight-derived-class.sql`.

Seeds (`supabase/seeds/m02-customers-pets/*`): `PetSeed` gains `weightKg?`;
every already-assessed seed pet gets a `weight_kg` consistent with its class
under the seeded cut-offs (Max M/14.2, Luna S/4.1, Rex L/27.6, Bruno XL/48.3,
Mimi M/10.4, Coco L/23.1, Bella S/6.7, Simba XL/42.5); never-assessed pets
stay `null`. The `.sql` mirror and `.seed.spec.ts` are updated to match.

### Server

- `maintenance.types.ts` — new `PetWeightClassConfiguration` interface.
- `utils/deriveWeightClass.ts` (+ `.spec`) — pure
  `deriveWeightClass(weightKg, {m_min_kg, l_min_kg, xl_min_kg}): 'S'|'M'|'L'|'XL'`,
  lower bound inclusive (exactly `l_min_kg` → `L`). The DB CHECK guarantees the
  cut-offs increase, so the branches are exhaustive.
- `services/petWeightClassConfiguration.service.ts` (+ `.spec`) — `get` /
  `update` for the singleton, a copy of `pricingConfiguration.service.ts`.
  `update` re-checks `m < l < xl` against the **merge** of the PATCH body and
  the stored row (the validator only sees the fields in the request), stamps
  `updated_by_staff_id` / `updated_at`.
- `modules/validators/maintenance.validator.ts` —
  `updatePetWeightClassConfigurationValidator`: all three fields optional
  (`.positive().max(499)`), `.strict()`, a `superRefine` that checks ordering
  among *supplied* fields; inferred type exported.
- `maintenance.controller.ts` — `get` / `update`
  `PetWeightClassConfigurationController` (copy of the pricing pair; returns
  `{ configuration }`).
- `maintenance.routes.ts` — `GET` (`staffRead`) / `PATCH` (`adminWrite`)
  `/maintenance/pet-weight-class-configuration`.
- `customers/pets/pet.types.ts` — `weight_kg: number | null` on `Pet`.
- `customers/pets/modules/validators/pet.validator.ts` — `weight_kg` added to
  the `*Staff` create/update variants only (`z.number().positive().max(499)`,
  `.nullable()` on update); customer variants still `.strict()`-reject it.
  Header comment updated.
- `customers/pets/pet.controller.ts` — new `resolveFinalWeightClass(submitted)`:
  an explicit `weight_class` in the payload always wins (staff override);
  otherwise if `weight_kg` is present, load `getPetWeightClassConfiguration()`
  and derive. Both create and update persist `weight_kg` and the
  derived/overridden class. Update re-stamps `assessed_by` / `assessed_at`
  when the **effective** class changes (a weigh-in that moves the band counts
  as a fresh assessment), replacing the old "is the `weight_class` key
  present" check.
- `auth/staff/staffAuth.routes.ts` + `auth/customers/customerAuth.routes.ts` —
  `staff` / `customerPreferencesController` now also accepts, validates
  (`WEIGHT_UNIT_PREFERENCES` const + `isWeightUnitPreference` guard),
  persists, and returns `weight_unit_preference`. No new route; the "no
  preferences provided" 400 now also considers this field.

### Client

- `shared/providers/ThemeProvider/themeContext.ts` — `WeightUnitPreference`
  type; `weightUnit` + `setWeightUnit` added to the context (default `'kg'`).
- `shared/providers/ThemeProvider/ThemeProvider.tsx` — loads and persists
  `weightUnit` alongside theme / font size (same load-on-mount +
  fire-and-forget PATCH wiring). A new doc comment notes the provider has
  outgrown its name; a rename to `UserPreferencesProvider` is left as a
  follow-up.
- `shared/api/preferences.api.ts` — `getWeightUnitPreference` (direct Supabase
  select) + `updateWeightUnitPreference` (PATCH the preferences endpoint).
- `shared/utils/petWeight.ts` (+ `.spec`) — `KG_PER_LB`, `lbsToKg` / `kgToLbs`,
  `toDisplayValue` (kg → viewer unit, 1 dp), `toCanonicalKg` (entered value →
  kg, 2 dp), `formatWeight` ("20.4 kg" / "45.0 lb"), `weightUnitLabel`.
- `shared/components/WeightUnitToggle/` (new) — a kg/lb radiogroup, wired to
  the context; dropped into `pages/SettingsPage/tabs/PreferencesTab.tsx` as a
  "Pet weight" section (shared by the staff and the customer Settings screen).
- `features/maintenance/utils/deriveWeightClass.ts` (+ `.spec`) — hand-kept
  client mirror of the server function.
- `features/maintenance/maintenance.types.ts` +
  `api/maintenance.api.ts` — `PetWeightClassConfiguration` /
  `UpdatePetWeightClassConfigurationPayload` types + `get` / `update` API pair.
- `features/maintenance/pages/WeightClassConfigurationPage/` (new) — an
  Admin/Superadmin "Weight Classes" config sub-page: three kg inputs and a
  live "S — under 9.5 kg / M — 9.5 up to 22 kg / …" band preview. Route
  `/staff/admin/maintenance/weight-classes`, registered in
  `maintenance.routes.tsx` and added to `configTiles.config.ts` as a new
  `CONFIG_TILES` entry (`Scale` icon). Non-Admin viewers are redirected.
- `features/customers/components/PetWeightAssessmentFields/` (new) — a shared
  staff-only control: numeric weight input + kg/lb entry-unit toggle +
  read-only derived weight class + "Override the derived weight class"
  checkbox. Fetches the cut-offs itself; switching the entry unit reinterprets
  the visible number so the real weight doesn't change.
- `features/customers/components/forms/PetForm/PetForm.tsx` +
  `components/panels/PetDetailPanel/PetDetailPanel.tsx` — the lone
  weight-class `<select>` is replaced by `PetWeightAssessmentFields`. Submit
  `weight_kg`; send `weight_class` only when there is no weight or staff
  overrode. `PetDetailPanel`'s read view gains a "Weight" row via
  `formatWeight` in the viewer's unit.
- `features/customers/customer.types.ts` — `weight_kg` on `Pet` and
  `PetCreatePayloadStaff`.
- `features/booking/components/AssessmentModal/AssessmentModal.tsx`
  (+ new `.spec`) — weight input + entry-unit radiogroup + derived/disabled
  class `<select>` + override checkbox. "Save & Start" is now gated on a
  positive weight **and** a coat type (was: a class + a coat type).
- `features/booking/pages/AssessmentQueuePage/AssessmentQueuePage.tsx` — new
  state, fetches the cut-offs, prefills the weight from `pet.weight_kg`.
  `confirmAssessment` sends
  `{ weight_kg: toCanonicalKg(...), coat_type, ...(overridden ? { weight_class } : {}) }`.
- `features/veterinary/pages/VeterinaryConsolePage/ConsultationDetailPanel.tsx`
  + `VeterinaryConsolePage.tsx` — the consultation's own `weight` field
  (treated as canonical kg) is shown and entered in the viewer's unit; the
  label reads "Weight (kg)" / "Weight (lb)".

## Manual test — step by step

Start the app first: in the `golden-fur` folder run `npm run dev` and wait
until the client (`http://localhost:5173`) and server (`http://localhost:3000`)
are both up. **If you rebuilt or re-provisioned the database, apply the new
migrations first** (`npm run supabase:push`) — otherwise the `weight_kg`
column and the `pet_weight_class_configuration` table won't exist and every
screen below will error.

Staff logins are the m01 seed accounts: `makati.receptionist1@goldenfur.com`,
`makati.admin1@goldenfur.com`, etc., all with password `password123` (exact
list: `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts`).
Customer logins: `customer1@goldenfur.com` … also `password123`.

### A. Assessment Queue — derive the class from a weight, then override it

1. Go to `http://localhost:5173`. Click **Staff Login** (top-right). Sign in as
   `makati.receptionist1@goldenfur.com` / `password123`. You land on a page
   headed **Dashboard**.
2. In the left sidebar open **Bookings → Assessment Queue**. You see a list of
   booked assessment appointments. (If it's empty, first create an
   "Initial Assessment" booking for any pet via **New booking**.)
3. On any row, click **Start** (or **Start assessment**). A pop-up headed
   **Record pet assessment** opens.
4. Confirm the pop-up now has: a **Weight (kg)** number box, an **Entered in**
   kg/lb radio pair, a **Weight class** drop-down, and a **Coat type**
   drop-down. Before this change there was only Weight class + Coat type.
   - Failure: no weight box at all.
5. Click the **lb** radio. In **Weight (kg)** — the label now reads
   **Weight (lb)** — type `30`.
6. The **Weight class** drop-down fills in by itself (30 lb ≈ 13.6 kg → **M**
   under the default 9.5/22/41 cut-offs) and is **greyed out / disabled**.
   - Failure: the drop-down stays "Not yet assessed", or stays editable.
7. Tick **Override the derived weight class**. The drop-down becomes editable.
   Change it to **L**.
8. Pick a **Coat type** (e.g. **SC**). Click **Save & Start**.
   - The pop-up closes and the booking moves to "in progress".
   - Failure: "Save & Start" stayed disabled (it needs a positive weight + a
     coat type), or an error banner appeared.
9. Open the pet's profile (**Customers → the customer → the pet**, or from the
   booking). The **Weight** row shows about **13.6 kg** (or **30.0 lb** if
   your preference is pounds — see scenario B) and **Weight class** shows
   **L** (your override), and **Last assessed** shows "just now".
   - Optional DB check: `select weight_kg, weight_class, assessed_at from
     public.pets where name = '<pet>';` — `weight_kg ≈ 13.61`,
     `weight_class = 'L'`.
10. Start the assessment again (or edit the pet) and this time enter a weight
    but **don't** tick Override. The class follows the number: `25` kg → **L**,
    `5` kg → **S**, `45` kg → **XL**.

### B. Per-user kg/lb preference — staff and customer, independent

1. Still signed in as the receptionist, click the **gear / Settings** icon in
   the sidebar, then the **Preferences** tab.
2. Find the **Pet weight** section with two buttons: **Kilograms (kg)** /
   **Pounds (lb)**. Click **Pounds (lb)**.
3. Go back to the pet from scenario A. The **Weight** row is now shown in
   pounds (e.g. **30.0 lb**). The number in the vet console (scenario D) and
   every assessment pop-up defaults to lb too.
4. Reload the whole page (F5). The **Pounds (lb)** choice is still selected —
   it saved to your account.
   - Failure: it reverted to kg.
5. Sign out. Sign in as a **customer** (`customer1@goldenfur.com` /
   `password123`). Open **Settings → Preferences**. The **Pet weight** section
   is there too, still on **Kilograms (kg)** (the customer's own default — the
   staff choice did not leak across). Switch it to **Pounds (lb)**; the
   customer's pet cards / pet detail now render in lb.
6. Confirm this toggle is **not** on any Admin-only Config screen — it lives
   only in Settings → Preferences, per person.

### C. Weight Classes config page (Admin/Superadmin only)

1. Sign in as `makati.admin1@goldenfur.com` / `password123`.
2. Click the **gear / Settings** icon → the **Config** area. There is a new
   tile **Weight Classes** ("Set the kg cut-offs that derive a pet's S/M/L/XL
   weight class…"), with a scale icon. Click it.
3. The page shows three inputs — **M / L / XL minimum (kg)** — pre-filled
   **9.5 / 22 / 41**, and a live band list ("S — under 9.5 kg", "M — 9.5 kg up
   to (but not including) 22 kg", …).
4. Change the **L minimum** to `18`. The band list updates live. Click
   **Save**. A success message shows.
5. Try to save **M = 30, L = 20** (M ≥ L). It is rejected with a validation
   message — cut-offs must increase.
6. Go back to the **Assessment Queue** and start an assessment for a pet.
   Enter a weight of **20 kg**. With the new L cut-off of 18, the derived
   class is now **L** (it would have been **M** under the old 22). This proves
   the derivation reads the live config.
7. Sign in as a non-Admin (the receptionist) and browse directly to
   `/staff/admin/maintenance/weight-classes` — you are redirected away, and
   the tile is not shown.

### D. Vet console shows/enters weight in the viewer's unit

1. Sign in as `makati.veterinarian1@goldenfur.com` / `password123`. Open
   **Veterinary Console** from the sidebar.
2. Open a consultation (a Veterinary booking that's in progress). The
   **Weight** field label reads **Weight (kg)** or **Weight (lb)** depending
   on your Preferences setting. A value entered here is stored canonically in
   kg regardless.
3. On a completed consultation's "View details", the **Weight** read-out is
   formatted in your unit.

### E. API — a customer cannot set the weight number

Run the Postman collection `testing/pet-weight-derived-class.postman_collection.json`
top to bottom (fill in the login variables and two pet ids first). It covers:
derive-on-write (req 3), override-wins (req 4), the Admin-only config gate
(reqs 5 & 7), and the key rejection: **req 9 — a customer PATCHing
`{ "weight_kg": 5 }` on their own pet gets a 400** (unknown key, `.strict()`),
plus the preference endpoint accepting `weight_unit_preference` (req 10) and
rejecting a bad value (req 11).

## Test suites

Run and confirmed green this session (no `ci-verifier` run yet — that happens
at PR time):

- `server`: `npx vitest run` — **1046 / 1046 passing** (95 files);
  `npm run typecheck` (`tsc --noEmit`) clean; `npx eslint .` — 0 errors
  (33 pre-existing `no-console` warnings, none in changed files).
- `client`: `npx vitest run` — **839 / 839 passing** (164 files); `npx tsc -b`
  clean; `npx eslint .` clean.
- `supabase/seeds`: `npm run test:seed` — **26 / 26 passing** (6 files).

## Open items

- **`supabase db push` to the dev project (`hikgijuipymfghfuyrjv`, confirmed
  not prod `gtqncxqsofqtzrlgxdfm`) has NOT been run** — Docker was not running
  locally this session. All four migrations must be pushed as the closing step
  once the PR is green, or the dev database will be missing `pets.weight_kg`,
  `pet_weight_class_configuration`, both `weight_unit_preference` columns, and
  the extended trigger. The seed `weight_kg` values only land on a full
  `db reset`, not on `db push` (see the "Supabase seeds push gap" note) — a
  pushed-but-not-reset dev database will simply have `weight_kg = NULL` on
  existing pets until they're re-assessed, which is acceptable.
- `deriveWeightClass` is duplicated in the client and server trees (no shared
  build). Each copy carries a comment pointing at the other; keep them in sync.
- `ThemeProvider` now also owns the kg/lb preference, which is not a theme
  concern. A rename to `UserPreferencesProvider` is noted in the file as a
  future follow-up, deliberately not done here.
- `AssessmentModal` keeps its own inline copy of the weight/derive/override
  interaction rather than reusing `PetWeightAssessmentFields`, matching the
  "kept local" precedent already in that file.
