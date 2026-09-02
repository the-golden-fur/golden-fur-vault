# Epic A — Revision Batch 1 (Issues #71-#78)

Type: Epic implementation, sourced from `temp/context/1-Architectural_Change_Suggestions-EpicA-Guide.md.docx` + `...EpicA-Design.xlsx` + `...EpicStructure.xlsx`.
Branch: `dev` (this batch spans 8 issues that the Guide itself splits across 8 feature branches — `chore/pet-profile-schema`, `chore/pet-health-conditions-schema`, `chore/admin-branch-parity-rls`, `feat/resend-account-email`, `feat/staff-management-rename`, `feat/customer-management-action-menu`, `feat/pet-profile-fields`, `feat/health-conditions-to-veterinary` — but everything landed together here on `dev` in one pass).

## Scope

- **#71** `chore(db)`: `breeds` lookup table + `pets.pet_type`/`breed_id`/`photo_url` (species→pet_type rename, free-text breed→FK).
- **#72** `chore(db)`: `pet_health_conditions` table (M07-maintained), RLS, backfill from `pets.health_conditions`.
- **#73** `chore(db)`: staff-creation RLS/policy — Admin gets full branch-assignment parity with Superadmin.
- **#74** `feat(m01)`: resend account-created credential email — **via the Resend API** (resend.com).
- **#75** `feat(m01)`: Staff Management rename + branch-name-not-UUID fix + duplicate approval-queue button removed.
- **#76** `feat(m02)`: Customer Management rename + "…" action menu (Check Profile / View Pets / Add Pet).
- **#77** `feat(m02)`: pet profile form — Pet Type label, searchable breed dropdown, optional photo upload.
- **#78** `feat(m07)`: health-condition recording moves to the Veterinary console; pet profile shows a read-only badge.

## Correction from the original brief (Issue #74)

The Guide's dev notes for #74 assumed a Sprint 1 email service already existed ("reuses the existing account*created email flow"). It didn't — `staffManagement.service.ts` only ever returned the temporary password in the API response, with a comment explicitly noting "no notification/email infrastructure yet." Per direction, this batch builds the actual send path on **Resend** (the transactional email API, not just the English verb) and wires the resend \_action* on top of it:

- `server/src/shared/email/resend.client.ts` — thin wrapper over the `resend` SDK, reads `RESEND_API_KEY`/`RESEND_FROM_EMAIL`.
- `server/src/shared/email/accountCreatedEmail.ts` — the one `account_created` template, shared by both the original send (on staff creation) and the resend action.
- `staffManagement.service.ts` now actually emails the new hire on creation (best-effort — a delivery failure doesn't fail account creation; `temporary_password` is still returned in the response as a fallback).
- A staff member's temporary password can't be re-read from Supabase Auth after creation (it's never stored in plaintext there), so a **resend** literally re-delivering the _same_ password (AC-2) required somewhere durable to hold it. `staff_profiles` gained two columns — `temp_credential_ciphertext`/`temp_credential_iv` — holding it AES-256-GCM-encrypted (key: `STAFF_TEMP_CREDENTIAL_KEY`), cleared automatically on the staff member's first successful login. This is additive beyond the Guide's listed Affected Files for #74, but was necessary to satisfy AC-2 without either storing a plaintext password or silently reinterpreting "resend" as "reset."
- `RESEND_API_KEY` (the development key provided) is in `server/.env`; a placeholder is in `server/.env.example`. `STAFF_TEMP_CREDENTIAL_KEY` was generated fresh (`openssl rand -base64 32`-equivalent) and is also in both files.

## Other deviations worth knowing about

The Guide's file paths/component names were approximate — this repo's actual conventions won when they differed:

- **#73**: the `staff_profiles` INSERT policy already read `current_staff_role() in ('Admin', 'Superadmin')` (since migration `20260701015`) — Admin already had DB-level permission. The real gap was one layer up: `createStaffAccount()` restricted Admin to `branchId === requesterBranchId`, while Superadmin could pick either branch. That restriction is now removed entirely (full parity, not just same-branch parity). Migration `20260725043` re-states the policy for traceability under this issue number even though it's a no-op against current state — see the migration's own comment.
- **#75/#76**: the actual pages are `AdminStaffListPage`/`AdminCustomerListPage` (both under `client/src/features/staff/pages/`), not `StaffDirectoryPage`/`CustomerDirectoryPage` under separate feature folders as the Guide assumed. Renamed **in place** to `StaffManagementPage`/`CustomerManagementPage`, keeping the existing `staff` feature location and both existing routes (`/staff/admin/staff`, `/staff/admin/customers`) unchanged.
- **#76**: `CustomerRowActionMenu` lives at `client/src/features/customers/components/menus/CustomerRowActionMenu/`, matching how this codebase already shares pet-domain components (`PetCard`, `PetForm`) between the `customers` and `staff` features, rather than under `staff/components/` as literally listed.
- **#71/#77**: `pets.breed` (free text) is gone; a few _other_ pages outside this epic's issue list display pets (`GroomerDashboardPage`, `CustomerBookingFlowPage`, `PetCard`) previously showed the free-text breed inline. Resolving `breed_id → breed name` for those is out of scope here (not in #71-#78's Affected Files) — they now simply omit the breed line rather than show a raw UUID. Flagged as a small follow-up if a "breed" column is wanted back on those cards.
- **#77**: the pet-photo upload endpoint/bucket (`pet-photos`) isn't in the Guide's Affected Files either, but "optional pet photo, uploads to Supabase Storage" (AC-3) isn't buildable without one — added `server/src/features/customers/pets/services/petPhotoUpload.service.ts` + `POST /pets/:id/photo`, mirroring the existing staff-avatar upload pattern exactly (same size/MIME limits, same replace-on-reupload behavior).

## Migration strategy: add-then-drop, not rename-and-drop

`20260725041`/`20260725042` originally renamed/dropped `pets.species`,
`pets.breed`, and `pets.health_conditions` in the same migration that
added their replacements — a breaking change for anything still reading
the old columns the moment it shipped. Both are now **additive-only**:
`pets.pet_type` is added alongside `species` (backfilled from it, not a
column rename) and `breed`/`health_conditions` are left in place after
their data is copied to the new table/column. The actual drop is its own
migration — `20260725046_m02_drop_deprecated_pet_columns.sql` — deliberately
**not** meant to run automatically with the rest of this batch; apply it
once you've confirmed nothing else still reads the three old columns.

One consequence: `GET /pets/:id` (and any other `select('*')` pet read)
now returns `species`/`breed`/`health_conditions` as extra fields
alongside `pet_type`/`breed_id` until 046 runs. Harmless — the typed
client only reads the new fields — but expected, not a bug.

## Files changed (high level)

**Migrations** (`supabase/migrations/`):
`20260725041_m02_create_breeds_and_pet_fields.sql`, `20260725042_m02_m07_create_pet_health_conditions.sql`, `20260725043_m01_admin_branch_assignment_rls.sql`, `20260725044_m01_staff_temp_credential_and_pet_photos_storage.sql`, `20260725045_m02_breeds_admin_crud_rls.sql`, `20260725046_m02_drop_deprecated_pet_columns.sql` (deferred cleanup — see above, not run as part of this batch's "done" state).

**Server**: `shared/email/{resend.client,accountCreatedEmail}.ts`, `shared/crypto/tempCredential.ts`, `features/staff/services/{staffManagement,resendAccountEmail}.service.ts`, `features/staff/staff.{controller,routes}.ts`, `features/auth/staff/staffAuth.controller.ts` (clears temp credential on login), `features/customers/pets/{pet.types,pet.routes}.ts`, `features/customers/pets/modules/validators/pet.validator.ts`, `features/customers/pets/services/petPhotoUpload.service.ts`, `features/veterinary/services/petHealthConditions.service.ts`, `features/veterinary/{veterinary.controller,veterinary.routes}.ts`, `features/veterinary/modules/validators/veterinary.validator.ts`.

**Client**: `features/staff/pages/StaffManagementPage/*` (renamed from `AdminStaffListPage`), `features/staff/pages/CustomerManagementPage/*` (renamed from `AdminCustomerListPage`), `features/staff/components/buttons/ResendEmailButton/*` (new), `features/staff/components/cards/StaffCard/StaffCard.tsx`, `features/staff/components/forms/CreateStaffAccountForm/CreateStaffAccountForm.tsx`, `features/staff/api/staff.api.ts`, `features/customers/components/menus/CustomerRowActionMenu/*` (new), `features/customers/components/forms/{PetForm,BreedSelect}/*`, `features/customers/components/badges/PetHealthConditionBadge/*` (new), `features/customers/components/cards/PetCard/PetCard.tsx`, `features/customers/pages/PetProfilePage/PetProfilePage.tsx`, `features/customers/{customer.types,api/customer.api}.ts`, `features/veterinary/components/HealthConditionsField/*` (new), `features/veterinary/pages/VeterinaryConsolePage/*`, `features/veterinary/{veterinary.types,api/veterinary.api}.ts`, `styles/tokens.css` (new `--color-health-flag-bg/-text`).

**Seeds**: `supabase/seeds/module-2-customers-pets/*` (species→pet_type).

Every `species`/`pets.breed`/`pets.health_conditions` reference across both apps' source and tests was renamed/removed to match — confirmed via full-repo grep (excluding `node_modules` and the immutable pre-Epic-A migration files, which correctly still say `species`/`pet_species` since that's the historical schema they created).

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, **513/513 tests pass** (54 files).

From `client/`:

```powershell
npx tsc -b
npx vitest run
```

Expected: typecheck clean, **326/326 tests pass** (80 files).

Both confirmed clean as of this revision.

## Manual Verification

You'll need: the `server/` and `client/` dev servers running (`npm run dev` from the repo root runs both), a Supabase project with this batch's 5 immediately-applied migrations (041-045; **not** 046 — see above) applied, and Postman (or the included collection) for the API-level checks.

### 0. Apply migrations + create the `pet-photos` storage bucket

1. From the repo root: `npm run supabase:push` (or, for a fresh local database, `npm run supabase:reset`, which also re-runs the seeds). If your local dev database already had the old (breaking) version of 041/042 applied from earlier testing, run `supabase db reset` so the corrected, additive versions apply cleanly — this is local/dev data only, safe to reset.
2. In Supabase Studio → **Storage**, click **New bucket**, name it exactly `pet-photos`, and mark it **Public** — same as the existing `avatars` bucket. (No migration creates this automatically, matching how `avatars` itself was set up — migration `20260725044` only adds the bucket's RLS policies.)
3. If you haven't already, re-run `npm run seed:module-1` and `npm run seed:module-2` against this database so the Postman collection's default identifiers (`makati.admin1`, `makati.superadmin1`, `makati.veterinarian1`, `makati.receptionist1`, `customer1@goldenfur.com`, all password `password123`) resolve to real accounts.
4. Do **not** run `20260725046_m02_drop_deprecated_pet_columns.sql` yet — it's the deferred, deliberately-breaking cleanup step (see above), not part of this batch's expected "done" state.

### 1. Schema checks (#71/#72) — `epic-a-revision-batch-1.sql`

Open the SQL file in this folder in Supabase Studio's SQL Editor and run Sections 1-4 (all read-only). Confirm: `breeds` has seeded Dog/Cat rows; `pets` has `pet_type`/`breed_id`/`photo_url` **and still also has** `species`/`breed`/`health_conditions` (deprecated, deferred to migration 046 — this is expected, not a bug); `pet_health_conditions` exists with a UNIQUE `pet_id` and the 4 expected RLS policies; the staff-creation RLS policy already grants Admin the `branch_id` write.

### 2. API checks (#73/#74/#77/#78) — `epic-a-revision-batch-1.postman_collection.json`

Import the collection and **Run** it top-to-bottom (Collection Runner, or click through manually). It logs in as Admin/Superadmin/Receptionist/Veterinarian/a customer and exercises, in order:

1. **#73** — an Admin token creates a staff account at a branch **other than their own** and gets `201` (previously would've been blocked).
2. **#74** — that new account's `POST /staff/:id/resend-account-email` succeeds (`200`) for the Admin who created it, and `403`s for a Receptionist token.
3. **#71/#78** — `GET /pets/:id` on a seeded pet returns `pet_type`/`breed_id`/`photo_url` (the old `species`/`breed`/`health_conditions` fields are still present too, deprecated, until migration 046 runs — not asserted absent).
4. **#78** — `GET /pets/:id/health-conditions` returns `null` (not an error) before any vet has recorded one; a Receptionist token gets `403` trying to `PATCH /veterinary/pets/:petId/health-conditions`; a Veterinarian token succeeds and the change is immediately visible via the read-only `GET` (no stale cache).
5. **#77** — `PATCH /pets/:id` accepts the renamed `pet_type` field.

Expected: every request's inline test script passes (Postman shows all green).

### 3. Resend delivery (#74)

1. In the Resend dashboard (resend.com → your account → **Emails**), after running Postman requests 4 and 5 above, confirm two `account_created`-shaped emails landed for the same test address — the original send (during account creation, request 4) and the resend (request 5), with the subject "...(resent)" on the second and the **same** temporary password in both bodies.
2. In the app: log in as an Admin/Superadmin (`/staff/admin/staff`), use the **Create staff account** panel to create one more account. Confirm the success banner shows the temporary password _and_ a "Resend account email" button; click it and confirm a "Account email resent." confirmation appears.
3. Log in as that new staff member once (any password works only if it matches — use the temporary password shown). Then, as an Admin, try **Resend account email** on that same staff member's card in the grid — expect a `409`-driven error message ("No pending temporary credential to resend...") since it was cleared on their first login.

### 4. Staff Management (#75)

1. Visit `/staff/admin/staff` as an Admin or Superadmin. Confirm the page heading reads **"Staff Management"**, not "Staff Directory".
2. Confirm every staff card shows a real branch name (**Makati** or **Southwoods**), never a raw UUID.
3. Confirm there is **no** "Unavailability approval queue" link/button anywhere on this page.
4. From the staff dashboard (`/staff/dashboard`), confirm the **branch operations dashboard** still has its own "Unavailability approval queue" tile linking to `/staff/admin/unavailability`, and that it still works — the queue wasn't deleted, only the duplicate entry point here.
5. Confirm a "Resend account email" button appears on every staff card, not just at creation time.

### 5. Customer Management (#76)

1. Visit `/staff/admin/customers` as a Receptionist/Admin/Supervisor/Superadmin. Confirm the heading reads **"Customer Management"**.
2. Click the "…" button on any customer row. Confirm a menu opens with **Check Profile**, **View Pets**, **Add Pet** — and that a create-pet form does **not** open automatically.
3. **Check Profile**: confirm it shows the customer's contact number, emergency contact, and preferred communication channel.
4. **View Pets**: confirm it lists that customer's existing pets (or "No pets on file yet."), with each pet card linking to its profile.
5. **Add Pet**: confirm the same pet-creation form as before opens, now reached via this menu instead of automatically.

### 6. Pet profile form (#77)

1. As a customer (or via Add Pet above), open the pet form. Confirm the species field now reads **"Pet Type"**.
2. Type into the Breed field — confirm it's a searchable dropdown (type a few letters, a filtered list appears), not a free-text box, and that it's scoped to the selected Pet Type (switch Pet Type and confirm the breed list changes / your prior selection clears).
3. Try submitting with no breed selected — confirm a clear validation message blocks it ("Please select a breed.").
4. Upload a photo (PNG/JPEG/WEBP, under 5MB) and submit. Confirm the new pet's card/profile shows the photo; a pet with no photo shows the placeholder initial instead.

### 7. Health conditions on the Veterinary console (#78)

1. Log in as a Veterinarian and open the Veterinary Console (`/staff/veterinary/console`). Select any consultation.
2. Confirm a "Known health conditions" field is present and editable, separate from Diagnosis. Enter a value (e.g. "Seasonal allergies") and click "Save health conditions" — confirm a "Health conditions updated." confirmation.
3. As a Receptionist or the pet's owner, open that pet's profile (`/portal/pets/:petId` for the owner, or via Customer Management → View Pets → pet card for staff). Confirm a rose-toned "Health:" badge shows the value you just saved, and that it is **not** editable from this page.
4. Pick a different pet that has never had a health condition recorded — confirm its profile shows no badge at all (not an error, not a blank placeholder).
