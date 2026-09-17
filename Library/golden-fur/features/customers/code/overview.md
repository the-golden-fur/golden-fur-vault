---
title: Customers — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, customers]
project: golden-fur
---

This feature is the data backbone for every customer and pet record in the
system: customer self-registration and profile fields, the pet roster tied
to each customer (name, breed, weight, coat type, photo), the staff-only
physical assessment that unlocks pricing/cage sizing, and the read-only
vaccination/medical-note/health-condition history shown on a pet's profile.

**Part of:** [[M02-customer-portal-pet-management]]

## Client-side (`client/src/features/customers/`)

### pages/
- **`CustomerPetManagerPage.tsx`** — the "Pet Manager" screen at
  `/portal/pets`. Loads the signed-in customer's pets via `listCustomerPets`,
  renders them as `PetCard`s, and toggles an inline `PetForm` for adding a
  new pet. Split out of an older combined profile page — pets are no longer
  part of Settings.
- **`CustomerPortalPage.tsx`** — the portal home at `/portal` ("Welcome
  back..."). Fetches the customer's profile (for the name) and any
  slot-conflicted bookings via `listMyConflictedBookings`, then renders
  `CustomerPortalWidgets` and, if any bookings lost their slot to another
  customer's payment, pops open `SlotConflictModal` automatically.
- **`PetProfilePage.tsx`** — a single pet's page at `/portal/pets/:petId`.
  Fetches the pet with `getPet` and hands it to `PetDetailPanel` in
  always-editable mode (a customer can only ever reach their own pet here,
  since the server 403s anyone else's).

### components/
- **`badges/PetHealthConditionBadge/PetHealthConditionBadge.tsx`** — a small
  read-only chip that fetches `getPetHealthConditions` and renders nothing
  if there's no text (no health issues recorded is a normal state, not an
  error). Health conditions are written only from the Veterinary console.
- **`cards/PetCard/PetCard.tsx`** — the clickable tile shown in a pet grid
  (photo or initial, name, pet type, weight class/coat type badges or "Not
  yet assessed", last-assessed time). Links to the pet's detail page; a
  `linkBasePath` prop lets staff screens point it at `/staff/pets` instead.
- **`CustomerPortalWidgets/CustomerPortalWidgets.tsx`** — the dashboard body
  under the portal's welcome message: a notification board plus a 2×2 grid
  of My Pets / Book a Service / View Transactions / Account Credit tiles.
  Internally composed of `NotificationBoardWidget`, `MyPetsWidget`, and
  `CreditsWidget` (the last reads `useCreditBalance`).
- **`forms/BreedSelect/BreedSelect.tsx`** — a searchable breed dropdown
  scoped to the chosen pet type, backed by `listBreeds`. Replaced an older
  free-text breed input.
- **`forms/PetForm/PetForm.tsx`** — the "Add a pet" form. Collects name, pet
  type (from `listPetTypes`), breed (`BreedSelect`), optional photo/gender/
  date of birth, and calls `createPet` then `uploadPetPhoto`. When rendered
  with `isStaff`, it also shows `PetWeightAssessmentFields` and a coat-type
  select — those fields are hidden entirely for a self-service customer
  because the server rejects them from a non-staff caller.
- **`lists/MedicalNoteList/MedicalNoteList.tsx`** — read-only list of a
  pet's medical notes (`listMedicalNotes`). Permanently read-only: there is
  no edit/delete route for notes at all, by design (append-only trail).
- **`lists/VaccinationRecordList/VaccinationRecordList.tsx`** — read-only
  list of a pet's vaccination records (`listVaccinationRecords`), showing
  vaccine name, date administered, and next-due date if set.
- **`menus/CustomerRowActionMenu/CustomerRowActionMenu.tsx`** — the "…" menu
  on a staff-facing customer row (Check Profile / View Pets / Add Pet, plus
  Deactivate/Archive when `canArchive` is passed). Purely a menu of choices;
  it doesn't call the API itself, it reports the chosen action via
  `onSelect`.
- **`panels/PetDetailPanel/PetDetailPanel.tsx`** — the shared view+edit body
  for a pet's profile, used by both the customer portal
  (`PetProfilePage`, always editable) and a staff route (editable only for
  CUSTOMER_MANAGER_ROLES). Shows photo, health-condition badge, attributes
  (type/gender/DOB/weight/weight class/coat type), an edit form that calls
  `updatePet` and `uploadPetPhoto`, plus embedded `VaccinationRecordList`
  and `MedicalNoteList` sections. Only staff-authorized editors see the
  weight/coat-type inputs.
- **`PetWeightAssessmentFields/PetWeightAssessmentFields.tsx`** — the
  shared staff-only weight-capture widget reused by `PetForm` and
  `PetDetailPanel`: a numeric weight input with a kg/lbs unit toggle, a
  weight class that's auto-derived from the Admin-configured cut-offs
  (`getPetWeightClassConfiguration`, `deriveWeightClass`), and an "override"
  checkbox for a receptionist to hand-pick the class instead.
- **`SlotConflictModal/SlotConflictModal.tsx`** — a modal that lists any
  bookings whose date/time/staff/cage slot was lost to another customer who
  paid first. Opens automatically when the portal home has conflicted
  bookings to show; each row links to the booking on My Bookings to
  reschedule it.

### config/
- **`customerPortal.config.ts`** — `CUSTOMER_SIDEBAR_SECTIONS`, the static
  list of sidebar links every customer sees (Notifications, Book a Service,
  My Bookings, Transactions, Credits, My Rewards, Pet Manager, Food &
  Medication). Unlike the staff dashboard, this list never varies by role.

### api/
- **`customer.api.ts`** — every fetch call this feature makes: customer
  profile read/update/list, the deactivate → archive → restore → hard-delete
  lifecycle for both customers and pets, pet CRUD (`listCustomerPets`,
  `createPet`, `getPet`, `updatePet`), vaccination-record/medical-note
  reads, pet-photo and care-item-photo uploads, and `listBreeds`/
  `listPetTypes` (these two read straight from Supabase via open RLS
  instead of going through an Express endpoint, the same pattern
  `maintenance.api.ts` uses for branches).

### Routing & types
- **`customer.routes.ts`** — the client-side route table: `/portal/pets`
  (`CustomerPetManagerPage`), `/portal/pets/:petId` (`PetProfilePage`), and
  `/portal/food-medication`, all gated behind `CustomerAuthGuard`.
- **`customer.types.ts`** — the client's shape definitions: `CustomerProfile`,
  `Pet` (note `weight_class`/`weight_kg`/`coat_type` are all
  staff-set-only, enforced server-side, never client-writable by a
  customer), `Breed`, `PetTypeRow`, and the vaccination/medical-note/
  health-condition record shapes.

Each component's `.module.css` file is a CSS Modules stylesheet scoped to
that one component — not documented individually.

## Server-side (`server/src/features/customers/`)

### Controller & routes
- **`customer.controller.ts`** / **`customer.routes.ts`** — customer CRUD:
  `GET/PATCH /customers/:id` (self or authorized staff/lookup role),
  `GET /customers` and `/customers/archived` (staff only), and the
  deactivate/activate/archive/restore/hard-delete endpoints (Admin-tier
  only, via `CUSTOMER_ARCHIVE_ROLES`). Because a route can be reached by
  either a customer acting on their own record or staff acting on anyone's,
  these routes only run `jwtMiddleware` and each controller resolves "self,
  or authorized staff" itself, rather than using a single role gate.
- **`pets/pet.controller.ts`** / **`pets/pet.routes.ts`** — pet CRUD
  (`GET/POST /customers/:customerId/pets`, `GET/PATCH /pets/:id`), the same
  deactivate/archive/restore/hard-delete lifecycle for pets, photo upload
  (`POST /pets/:id/photo`) and care-item photo upload
  (`POST /pets/:id/care-item-photo`), plus vaccination-record and
  medical-note sub-routes and a read-only health-conditions endpoint. This
  file also decides, per request, whether the caller is the pet's owner
  (customer validator, no weight/coat fields allowed) or authorized staff
  (staff validator, weight/coat fields allowed) — that's the actual
  enforcement point behind "only staff can record an assessment."

### Service
- **`services/customerArchive.service.ts`** — the customer lifecycle:
  `deactivateCustomer` (also cascades `is_active: false` to all the
  customer's pets), `activateCustomer`, `archiveCustomer` (stamps
  `archived_at` on the customer and any still-active pets), `restoreCustomer`
  (does **not** auto-restore pets — a pet may have been archived
  independently), `listArchivedCustomers`, and `hardDeleteCustomer` (deletes
  the row and the underlying Supabase auth user, since
  `customer_profiles.id` is `auth.users.id`).
- **`pets/services/petArchive.service.ts`** — the same lifecycle for an
  individual pet, independent of the customer-level cascade above (a pet can
  be archived on its own, e.g. deceased or rehomed).
- **`pets/services/medicalNote.service.ts`** — `createMedicalNote` (staff
  only) and `listMedicalNotes` (pet owner or authorized staff). Deliberately
  create+list only — no update/delete function exists, matching the
  append-only annotation trail design.
- **`pets/services/vaccinationRecord.service.ts`** — full CRUD for
  vaccination records (`createVaccinationRecord`, `listVaccinationRecords`,
  `updateVaccinationRecord`, `deleteVaccinationRecord`), gated to
  `VACCINATION_MANAGER_ROLES` (Receptionist, Veterinarian, Admin, Supervisor,
  Superadmin) for writes; reads are owner-or-staff.
- **`pets/services/petPhotoUpload.service.ts`** — validates and uploads a
  pet's profile photo to the `pet-photos` storage bucket, replaces any
  previous photo for that pet, and writes the resulting URL onto
  `pets.photo_url`.
- **`pets/services/petCareItemPhotoUpload.service.ts`** — the sibling
  upload for a single feeding/medication item's photo captured during the
  booking Care Instructions step. Reuses the same bucket and RLS as the
  profile-photo upload, but never touches `pets.photo_url` and never removes
  prior uploads — many care-item photos can coexist per pet.

### Types & validators
- **`customer.types.ts`** — `CustomerProfile`, `CUSTOMER_MANAGER_ROLES`
  (Receptionist/Admin/Supervisor/Superadmin — general staff access) and the
  narrower `CUSTOMER_ARCHIVE_ROLES` (Admin/Superadmin — the
  deactivate/archive/restore/hard-delete tier, matching the same gate used
  for Products and Staff).
- **`modules/validators/customer.validator.ts`** — `updateCustomerProfileValidator`,
  a `.strict()` Zod schema that deliberately excludes `account_email` (email
  changes only ever go through Supabase Auth's own flow, never a raw
  profile update) — any unrecognized key, including `account_email`, fails
  validation instead of being silently dropped.
- **`pets/pet.types.ts`** — `Pet`, `Breed`, `PetHealthCondition`,
  `PetVaccinationRecord`, `PetMedicalNote` shapes as the server sees them.
- **`pets/modules/validators/pet.validator.ts`** — `createPetValidator` /
  `updatePetValidator` (customer-facing, no `weight_class`/`weight_kg`/
  `coat_type` keys allowed at all — a customer payload containing any of
  them is rejected outright by `.strict()`) and
  `createPetValidatorStaff`/`updatePetValidatorStaff` (extend the above with
  those three fields). This split is the documented reason a customer can
  never self-declare a weight class or coat type — it's not just a hidden
  UI field, the server won't accept the key.

## How it connects

The client always calls `customer.api.ts`, which hits the Express routes in
`customer.routes.ts`/`pets/pet.routes.ts`; those controllers resolve
authorization (self vs. staff role) and then either query
`customer_profiles`/`pets` directly or delegate to one of the services above
for anything with side effects (archiving, photo storage, stamping an
assessment). Pet weight class and coat type feed the pricing/cage-size logic
in [[M03-appointment-booking|M03]] and
[[M13-maintenance-packages-services-promos|M13]]; breed and health-condition
data connect to [[M07-health-veterinary-management|M07]] (health conditions
are written only from there). See [[M02-01-customer-registration-and-account-merge|Customer Registration, Login & OAuth Account Merge]],
[[M02-02-pet-profile-creation-and-staff-assessment|Pet Profile Creation & Staff Physical Assessment]],
and [[M02-03-customer-pet-deactivation-archive-lifecycle|Customer & Pet Deactivate → Archive → Hard-Delete Lifecycle]]
for the step-by-step workflows this code implements.
