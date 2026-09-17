---
title: Veterinary — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, veterinary]
project: golden-fur
---

Runs the Makati-only vet clinic inside golden-fur: a daily console where any
Veterinarian can check patients in, record vitals/diagnosis/medications/
procedures, log vaccinations, and complete a visit; a personal "My Patients"
roster with pet history; and a personal medication/procedure catalog each vet
can reuse instead of retyping the same items every visit.

**Part of:** [[M07-health-veterinary-management|M07 · Health & Veterinary Management]]

## Client-side (`client/src/features/veterinary/`)

### pages/

- **`VeterinaryConsolePage/VeterinaryConsolePage.tsx`** — the main clinic
  queue. Gated to Veterinarian/Admin/Supervisor/Superadmin
  (`ALLOWED_VIEWER_ROLES`), but only a Veterinarian gets write controls
  (`canWrite`, mirroring the server's `VETERINARY_WRITE_ROLES`). Loads the
  day's consultations via `listConsultationQueue`, polls every 15 seconds
  (no realtime/WebSocket infra exists yet in this codebase), joins in pet and
  owner names, and supports date-range/status filters, search, and sort. A
  "Start Consultation" button flips a booking to `Ongoing`
  (`updateConsultation`); selecting a row opens the detail panel; a
  read-only "View Details" modal shows a finished visit's vitals/diagnosis/
  medications without opening the editable panel.
- **`VeterinaryConsolePage/ConsultationDetailPanel.tsx`** — the actual
  consultation form: temperature/weight/heart rate/respiratory rate,
  diagnosis, a `HealthConditionsField`, a medications list (typed manually or
  picked from the vet's own catalog), a procedures list (same), an optional
  vaccination sub-section, and a professional fee. Weight is stored in the
  database in kilograms but shown/entered in the viewer's kg/lbs display
  preference, converted back to kg on save. "Complete Consultation" calls
  `onComplete`, which the console page wires to `updateConsultation` with
  `status: 'Completed'`.
- **`MyPatientsPage/MyPatientsPage.tsx`** — a Veterinarian-only personal
  roster (unlike the console, this is not visible to Admin/Supervisor/
  Superadmin) of every distinct pet that vet has finished a consultation
  for, with search, sort, and a pet-type filter. Selecting a patient's "..."
  menu opens `PetHistoryTab` with that pet's full consultation history via
  `getPetConsultationHistory`.
- **`VetCatalogPage/VetCatalogPage.tsx`** — lets a Veterinarian manage their
  own reusable list of medications and procedures (with default dose/price),
  shown as two tabs with search/sort/filter and a modal add/edit form. Only
  the owning vet can see or edit their own catalog.

### components/

- **`HealthConditionsField/HealthConditionsField.tsx`** — a textarea for a
  pet's known chronic conditions/allergies, embedded inside the consultation
  form. Loads the current value via `getPetHealthConditions` (a customers-
  feature API, since it's read from the general pet profile too) and saves
  via `upsertPetHealthConditions`. Any Veterinarian may edit any pet's
  conditions — there's no per-pet assigned-vet restriction anywhere in this
  feature.
- **`PetHistoryTab/PetHistoryTab.tsx`** — read-only list of a pet's past
  consultations (date, booking status badge, reason, diagnosis,
  medications), newest first.

### api/

- **`veterinary.api.ts`** — every fetch call this feature makes to the
  server: the consultation queue and single-consultation updates, the
  personal patients list, pet consultation history, health-condition
  upserts, and full CRUD for both the medication and procedure catalogs.
  Each function returns a plain `{ data, error }` result rather than
  throwing.

### Other

- **`veterinary.routes.tsx`** — registers `/staff/veterinary/console`,
  `/staff/veterinary/my-patients`, and `/staff/veterinary/catalog` behind
  `StaffAuthGuard`; role gating itself happens inside each page.
- **`veterinary.types.ts`** — client-side shapes mirroring the server's:
  `Consultation`, `PROCEDURE_TYPES`, `MedicationInput`/`ProcedureInput`,
  `UpdateConsultationPayload`, `PetHealthCondition`, `VeterinarianPatient`,
  and the medication/procedure catalog item and payload types.
- **`*.module.css`** (one per component/page) — component-scoped styling
  only, no logic; not covered individually below.

## Server-side (`server/src/features/veterinary/`)

### Controller & routes

- **`veterinary.controller.ts`** — one thin handler per endpoint: parses the
  request, runs the Zod validator when there's a body, calls the matching
  service function, and maps thrown errors to an HTTP status via
  `sendServiceError` (reads a `statusCode` off the error, defaults to 500).
- **`veterinary.routes.ts`** — wires up every `/veterinary/*` route with two
  middleware stacks: `staffRead` (any `VETERINARY_READ_ROLES`) and
  `vetWrite` (`VETERINARY_WRITE_ROLES`, Veterinarian only). Notably, the
  personal medication/procedure catalog endpoints use `vetWrite` even for
  their GET routes, since — unlike the rest of this feature — only the
  owning vet may read their own catalog at all.

### Services

- **`services/consultation.service.ts`** — the core of the feature.
  `listConsultationQueue` builds the day's (or a given date range's) queue:
  it pulls Veterinary bookings that are `In Progress` (checked-in) or
  `Completed`, auto-creates ("vivifies") a `consultations` row for any
  checked-in booking that doesn't have one yet (no DB trigger exists for
  this anywhere in the codebase, so it happens in application code, mirroring
  the Grooming feature's own pattern), and re-validates Makati-branch
  eligibility as a defense-in-depth check before inserting. `getConsultation`
  and `listPetConsultationHistory` are straightforward reads.
  `listVeterinarianPatients` computes "My Patients" by fetching every
  finished consultation for a vet and deduping to one row per pet in
  JavaScript (no aggregate/distinct query pattern exists elsewhere in this
  codebase). `updateConsultation` is the write path for starting/completing
  a visit: a status change delegates to `booking.service.ts`'s
  `startBooking`/`completeBooking` (which own the Pending → In Progress →
  Completed ordering and reject an invalid jump with 409); completing also
  inserts `consultation_line_items` rows (professional fee + one row per
  medication/procedure, marked `TODO` for real M08 billing integration) and,
  if a vaccination was recorded, writes it to `pet_vaccination_records` via
  the existing customers-feature service.
- **`services/currentPrescription.service.ts`** — `getCurrentPrescription`
  returns a pet's most recent *finished* consultation's medications array,
  read-only and computed on demand (nothing is cached). Kept as its own
  service (not folded into consultation.service.ts) because the Hotel
  feature (M05) is expected to call it directly for check-in auto-fill.
- **`services/followUp.service.ts`** — `linkFollowUpBooking` links an
  already-created follow-up booking (made through the normal booking
  pipeline, same as a receptionist walk-in) back onto the originating
  consultation. Rejects if the source consultation isn't finished yet, if a
  follow-up is already linked, or if the follow-up booking is for a
  different pet.
- **`services/petHealthConditions.service.ts`** — `upsertPetHealthConditions`
  (Veterinarian-only, checked in code since it uses the service-role client
  which bypasses RLS) upserts one row per pet (`pet_id` is unique, so this
  is update-in-place, not an append-only log). `getPetHealthConditions`
  allows the pet's own owner or any authenticated staff member to read, and
  returns `null` rather than a 404 when nothing has been recorded yet.
- **`services/vetCatalog.service.ts`** — full CRUD for both
  `vet_medication_catalog` and `vet_procedure_catalog`. Every function
  re-checks `veterinarian_id = requesterId` in the query itself (not just
  relying on RLS), since this is the one part of the feature that's
  owner-scoped rather than open to every Veterinarian.

### Types & validators

- **`veterinary.types.ts`** — server-side shapes plus the two role lists
  that drive route gating: `VETERINARY_READ_ROLES` (Veterinarian, Admin,
  Supervisor, Superadmin, Receptionist) and `VETERINARY_WRITE_ROLES`
  (Veterinarian only). Also defines `Consultation`, `ProcedureType`,
  `ConsultationLineItem`, `CurrentPrescription`, `VeterinarianPatient`, and
  the catalog item types.
- **`modules/validators/veterinary.validator.ts`** — Zod schemas for every
  write endpoint. `updateConsultationValidator` is the most involved: it
  allows vitals/diagnosis/medications/procedures to be saved while a
  consultation is `Ongoing`, but a `superRefine` step requires
  `professional_fee` and an `amount` on every medication only when
  `status` is being set to `Completed` — so a visit can be worked on
  incrementally before it's billed. The rest (`linkFollowUpValidator`,
  `upsertHealthConditionsValidator`, and the four catalog
  create/update validators) are simpler shape checks.

## How it connects

A staff member opens the Veterinary Console, which calls
`GET /veterinary/consultations/queue`; that hits
`consultation.service.ts`'s `listConsultationQueue`, which reads and writes
the `bookings` and `consultations` tables (auto-creating a consultation row
the moment a Veterinary booking becomes `In Progress`). Completing a
consultation (`PATCH /veterinary/consultations/:id`) pushes the booking
through `booking.service.ts`'s shared status machine, writes
`consultation_line_items` (flagged for future M08 billing), and can touch
`pet_vaccination_records`. Health conditions recorded here are surfaced
read-only on the pet profile in M02, and `getCurrentPrescription` is meant
to be called by the Hotel feature (M05) for check-in auto-fill. See
[[M07-01-consultation-visit-flow|Consultation Visit Flow]],
[[M07-02-follow-up-visit-scheduling|Follow-Up Visit Scheduling]], and
[[M07-03-pet-health-conditions-recording|Pet Health Conditions Recording]]
for the step-by-step business workflows this code implements.
