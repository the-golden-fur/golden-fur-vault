---
title: Digital prescription builder, a vet-defined consultation form builder, and retiring Procedures from My Catalog
date: 2026-09-29
tags: [session-plan, golden-fur]
project: golden-fur
session: 117-vet-prescription-and-consultation-form-builder
branch: not yet created - staged on dev
---

# 117 — Digital prescription builder, a vet-defined consultation form builder, and retiring Procedures from My Catalog

## What you asked for

Three related asks about the Veterinarian staff role, bundled from one context doc (`Projects/golden-fur/shared/context/Architectural-Change-History.pdf`):

> As a vet staff, I want to be able to create a detailed digital prescription for my patients, where I can set the medicine type, the dosage, the frequency, etc.
>
> As a customer, I want a copy of this created prescription that is tied directly to my pet, I want to be able to view a history of them too
>
> As a developer, perhaps create some sort of dedicated prescription builder, where the vet can choose and fill the necessary fields, include a search, sort, filter, group by and view options
>
> As a vet staff, I want to be able to record anything for my consultation type services, since I'm mainly writing down unstructured data
>
> As a patient, I want to be able to view the results and history of my pet's transactions
>
> As a developer, perhaps create a form builder, where the vet staff can create and choose from in his consultation type services
>
> As a developer, I want the procedures in vet staff > my catalog dropped, since it will have no use

Mid-planning, you also corrected two things: (1) the Hotel check-in medication auto-fill (`getCurrentPrescription`) should conceptually pull from a customer's own registered food/medicine items, not from vet consultation data — but fixing that is explicitly a separate, later task, not part of this one; and (2) a related but separate future roadmap item exists (receptionist/groomer play-and-walk-time-only booking config, staff-made-booking notifications, read-only feeding/medical instructions for staff at hotel/daycare check-in) — also explicitly deferred, not part of this plan.

You also answered three scoping questions that shape this plan:

1. **Procedures removal**: go all the way — remove the Procedures tab from My Catalog _and_ the Procedures section inside the consultation form _and_ stop generating procedure billing rows.
2. **Consultation form builder**: scope it **per-Veterinarian** — each vet builds their own reusable set of custom fields (the same "personal catalog" shape already used for Medications), not a set tied to one specific bookable service.
3. **Prescription storage**: enrich the data that's already there (the `medications` list already saved on a consultation) with new fields, instead of building a whole new database table for prescriptions.

## Words you might not know

- **Migration** — a versioned SQL file under `supabase/migrations/` that changes the database's structure (adds a table, a column, a permission rule). Migrations run in filename order and are never edited after the fact — a later change is always a _new_ migration file.
- **RLS (Row-Level Security)** — a Postgres/Supabase feature where the database itself enforces "who can see/change which rows," on top of whatever the server code checks. Every table in this app defines its own RLS rules in the same migration that creates it.
- **jsonb** — a Postgres column type that stores a JSON value (an object or array, like you'd see in JavaScript) directly in one column, instead of spreading it across several columns or a second table. This app already stores a consultation's list of prescribed medications this way — one `medications` column holding an array like `[{name: "Amoxicillin", dose: "250mg"}]` — rather than a separate "medications" table.
- **Zod validator** — a TypeScript library this app uses on the server to check that incoming request data (from the browser) has the right shape and types before anything is saved. If a field doesn't match what the validator expects, the request is rejected with a 400 error before it ever reaches the database.
- **Enum** — a fixed list of allowed text values (e.g. this app's `procedure_type` enum only allows `'Lab test'`, `'Dental'`, `'Vaccination'`, `'Surgery'`, `'Emergency'`, `'Wellness Exam'` — nothing else can be stored in that column).
- **Owner-scoped table** — a database table where each row belongs to one specific staff member, and that staff member is (by rule) the only one who can see or edit their own rows. The Medications and Procedures catalogs in My Catalog already work this way — my medications are private to me, not visible to other vets.
- **Consultation** — one veterinary visit's record in this app: a database row created automatically the moment a vet checks in a Veterinary booking. It holds vitals (temperature, weight, etc.), a diagnosis, and the medications prescribed.
- **Endpoint** — a specific URL + HTTP method the server responds to, e.g. `GET /veterinary/prescriptions`.
- **Component** — a reusable piece of UI in React (the library this app's frontend is built with).
- **Datalist** — a plain HTML input feature (`<input list="...">` + `<datalist>`) that shows a dropdown of suggestions as you type, but still lets you type anything else. Used here instead of a rigid dropdown, so a vet is never blocked from entering something not on the suggested list.

## What this part of the app does today

- **Golden Fur Staff app** — the internal side of the site, at URLs under `/staff/...`. A **Veterinarian** is one of eight staff roles.
- **My Catalog** (`/staff/veterinary/catalog`, `client/src/features/veterinary/pages/VetCatalogPage/VetCatalogPage.tsx`) — a Veterinarian-only page, currently two tabs: **Medications** and **Procedures**. Each tab is the vet's own personal, reusable shortcut list (e.g. "Amoxicillin, 250mg" saved once, so it doesn't need retyping every visit) — nobody else can see another vet's list. Both tabs already use this app's shared search/sort/filter/view toolbar (see below).
- **Consultation Queue** (`/staff/veterinary/console`, `VeterinaryConsolePage.tsx`) — a Veterinarian's worklist of the day's appointments. Selecting one opens **`ConsultationDetailPanel.tsx`**, the actual consultation form: vitals (temperature/weight/heart rate/respiratory rate), a free-text diagnosis box, a repeating "Medications" section (pick from your My Catalog list, or type your own; each row has a name, dose, notes, and a billing amount), a repeating "Procedures" section (same shape — description, a fixed procedure type, and a billing amount), an optional vaccination sub-section, a professional fee, and a "Complete Consultation" button.
- **How a medication is stored** — every consultation has one `medications` column (a jsonb array, see glossary) holding everything prescribed during that visit: `{name, dose, notes}`. There's no separate "prescription" record — the medications list _is_ today's de-facto prescription. A read-only helper, `getCurrentPrescription()` (`server/src/features/veterinary/services/currentPrescription.service.ts`), looks up a pet's most recent finished consultation's medications on demand. This is currently used by one other feature (Hotel check-in's medication auto-fill) — **not part of this task**, and per your correction, not something this plan should build on or extend.
- **How a procedure is billed** — completing a consultation writes one `consultation_line_items` billing row per medication and per procedure (plus one for the professional fee). Nothing outside the veterinary feature ever filters or reads those rows by their type — the page that pulls a consultation's charges into a customer's bill (`getVeterinaryLineItems` in `server/src/features/billing/services/lineItemSources.service.ts`) just reads every row's description and amount, so removing procedure rows doesn't break billing elsewhere — there are simply fewer rows.
- **Customer-facing pet history today** — a customer's own pet page (`PetProfilePage.tsx` → `PetDetailPanel.tsx`) already shows two simple, permanently-read-only lists: **Medical Notes** and **Vaccination Records** (`MedicalNoteList.tsx`/`VaccinationRecordList.tsx`), each just a plain bullet list fetched from the server for that one pet. There is currently **no** prescription or consultation-results view for customers at all.
- **The shared search/sort/filter/group-by/view toolbar** — most list pages in this app (My Catalog, the Consultation Queue, Misc Sales, Archive, etc.) already share one toolbar component (`FilterSortBar` + `ViewSwitcher` + `DataTable`/`DataList`/`DataBoard`) that offers a search box, removable filter/sort "pills," and a Table/List/Board view switcher. This plan reuses that component everywhere a new staff-facing list is needed — it is not rebuilt from scratch.

## What's wrong / what's missing

1. **No real "prescription."** A vet can type a medication's name and dose, but there's no field for medicine type, no dosage-frequency field ("twice daily," "every 8 hours"), and no dedicated place to build or review one — it's just two plain text inputs buried inside the general consultation form.
2. **Customers can't see any of it.** A customer has no way to see what medication was prescribed for their pet, or a history of past prescriptions.
3. **The consultation form is one-size-fits-all.** Every Veterinary visit shows the exact same fixed fields, with nowhere for a vet to jot down visit-specific structured notes of their own choosing (e.g. a reusable "Dental Check" note template) — today a vet can only use the single free-text Diagnosis box for anything that doesn't fit the fixed fields.
4. **Customers can't see visit results either.** There's no equivalent of Medical Notes/Vaccination Records for whatever a vet records during a consultation beyond diagnosis/medications.
5. **The Procedures tab in My Catalog no longer earns its place.** Once vets have a proper way to record whatever they need (the new form builder, below), the fixed Procedures catalog — a rigid, six-option list (Lab test/Dental/Vaccination/Surgery/Emergency/Wellness Exam) — has no further purpose.

## What we're going to change

### 1. Database changes (`supabase/migrations/`)

One migration file per change, using this repo's `custom_<description>.sql` naming pattern (see recent files like `20260913202_custom_universal_deleted_records_archive.sql`). Whoever implements this should re-check the actual highest-numbered file in `supabase/migrations/` at that time and continue the sequence from there — the newest file as of this plan is `20260929226_shared_trusted_devices_rls.sql`, so these are written as though implementation starts right after it; the real filenames will shift if time passes first.

1. **Add richer prescription fields.** `alter table public.consultations` needs no column change (medications stays one `jsonb` column) — the new fields (`medicine_type`, `frequency`, `duration`) simply get added _inside_ each medication entry in that same jsonb array. No migration needed for this part; it's a code-level (TypeScript type + validator) change only, covered in "Server changes" below.
2. **(Optional, recommended) Let a saved catalog medication suggest a type/frequency too.** `alter table public.vet_medication_catalog add column default_medicine_type text, add column default_frequency text;` — mirrors the existing `default_dose`/`default_price` columns, so picking a saved medication can pre-fill the new fields the same way it already pre-fills dose and price.
3. **New table: `vet_consultation_form_templates`** — one row per reusable custom form a vet has built, e.g. `{id, veterinarian_id, name, fields (a jsonb list of {id, label, type, options?, required?}), created_at, updated_at}`. Copy the exact ownership rules (RLS policies) already used by `vet_medication_catalog` in `supabase/migrations/20260825142_m07_create_vet_catalog_schema.sql` — only the owning vet can see/edit their own templates. Also attach the universal "if a row is hard-deleted, keep a copy in the archive" trigger every new table needs (the exact statement to copy is documented in `supabase/migrations/20260913202_custom_universal_deleted_records_archive.sql`).
4. **Add a place to store filled-in results.** `alter table public.consultations add column form_responses jsonb;` — one consultation can have zero or more filled-in results, each one recording which template was used, when, and the answers given (values are copied in at fill-time, so history still reads correctly even if the vet edits or deletes the original template later).
5. **Retire the Procedures catalog.** `drop table public.vet_procedure_catalog;` (its rules and archive trigger disappear automatically with it). We are **keeping** the `procedure_type` enum and the `consultation_line_items.procedure_type` column — those describe _already-completed_ visits' billing history and shouldn't be erased; only the personal shortcut-list table (dev/seed data, no historical significance) is dropped. Going forward, the app simply stops creating new procedure-type billing rows.

### 2. Server changes (`server/src/features/veterinary/`, plus two new customer-facing endpoints)

- **Types** (`veterinary.types.ts`, both the server copy and its near-identical client copy in `client/src/features/veterinary/veterinary.types.ts`): add `medicine_type`, `frequency`, `duration` (all optional text) to the medication shape; add a `ConsultationFormField`/`ConsultationFormTemplate`/`ConsultationFormResponse` set of types for the new form builder; remove `ProcedureType`, `ProcedureInput`, `VetProcedureCatalogItem` and friends.
- **Validation** (`modules/validators/veterinary.validator.ts`): extend the medication validator with the three new optional fields; add validators for creating/editing a form template and for a filled-in response; delete the procedure validators; drop `procedures` from the "update a consultation" validator.
- **`services/vetCatalog.service.ts`**: delete the four procedure-catalog functions; keep the medication-catalog ones (now also passing through the two new default fields).
- **New `services/consultationFormTemplate.service.ts`**: the four CRUD (create/read/update/delete) functions for a vet's own form templates — copied in shape from the existing medication-catalog service.
- **`services/consultation.service.ts`**: stop writing procedure billing rows on Complete; widen the medications save step to keep the three new fields instead of stripping them out; save `form_responses` when present; add two new **staff-facing** read functions — "every prescription across every patient" and "every filled-in result across every patient" (for the two new staff list pages below) — and two new **customer-facing** read functions that check the requester actually owns the pet before returning a trimmed view (just the medication list, or just the results — never the vitals/diagnosis, matching how the existing Medical Notes feature already limits what a customer can see).
- **`services/currentPrescription.service.ts`**: left alone. It will keep working automatically since the new fields are optional additions, not required ones — but this plan does not extend it or connect it to anything new (see "What we're deliberately not touching," below).
- **Controller + routes** (`veterinary.controller.ts` / `veterinary.routes.ts`): delete the four procedure-catalog routes; add matching create/read/update/delete routes for consultation form templates; add the two new staff-facing "list everything" read routes.
- **`server/src/features/customers/pets/pet.routes.ts`**: two new customer-facing routes, `GET /pets/:id/prescriptions` and `GET /pets/:id/consultation-results`, following the exact same pattern the existing `GET /pets/:id/health-conditions` route already uses (import the veterinary feature's new ownership-checked functions directly). No proxy config changes needed anywhere — `/veterinary` and `/pets` are both already registered.

### 3. Client changes

- **My Catalog** (`VetCatalogPage.tsx`): the "Procedures" tab and everything behind it is deleted. A new **"Consultation Forms" tab** takes its place: a list of the vet's own saved templates, with an "Add form template" button opening a small builder — a name field, plus an "Add field" button that appends a row (a label, a field-type dropdown — text / paragraph / number / dropdown-with-options / checkbox / date — and, only for a dropdown field, a place to type its options). The Medications tab/form gains the two new inputs (medicine type, frequency), each using the `<datalist>` suggestion pattern from the glossary so a vet is never boxed in to a fixed list.
- **Consultation form** (`ConsultationDetailPanel.tsx`): the whole Procedures section is deleted. The Medications section becomes the real **Prescription Builder** — each row now also has medicine type and frequency inputs (duration too), still with the existing "add from my catalog" shortcut. A new **Results section** lets the vet pick one of their saved form templates from a dropdown, which then displays exactly the fields that template defines, ready to fill in; a vet can attach more than one filled-in result to the same visit (e.g. both a "Dental Check" and a "Behavior Notes" template in one visit). Like the rest of this form, results are only actually saved when the vet clicks "Complete Consultation" — there's no separate save step, matching how vitals/diagnosis/medications already behave today.
- **Two new staff-facing pages**, reachable from the Veterinarian sidebar next to "My Patients"/"My Catalog": **Prescriptions** (`/staff/veterinary/prescriptions`) and **Consultation Results** (`/staff/veterinary/results`) — both full list pages using this app's shared search/sort/filter/group-by/Table-List-Board toolbar (the explicit ask from the request), one row per prescribed medication or per filled-in result across every patient, with filters like medicine type and date, and grouping by medicine type / template name.
- **Customer-facing pet page** (`PetDetailPanel.tsx`): two new sections, **Prescriptions** and **Consultation Results**, each a simple read-only list (matching the existing Medical Notes/Vaccination Records style — a customer viewing only their own pet's history doesn't need the full filter/sort toolbar, that's reserved for the staff pages above which browse across every patient).

### What we're deliberately not touching

- **Hotel check-in's medication auto-fill** (`getCurrentPrescription`, and `insertMedicationInstructions` in `server/src/features/hotel/services/careInstructions.service.ts`). You flagged that this should conceptually pull from a customer's own registered food/medicine items instead of vet consultation data — that's a real, separate fix for a future task, not this one. This plan only has to make sure that helper keeps compiling once the medication shape gains new optional fields (it does, with no code change needed) — nothing here builds any new connection to it.
- **Receptionist/groomer play-and-walk-time-only booking config, staff-made-booking notifications, and read-only feeding/medical instructions for staff at hotel/daycare check-in confirmation.** A separate future roadmap item from the same architecture doc — noted for the record, not designed here.
- **Reducing Veterinary services to just "Consultation" and "Vaccine," and giving vets a specialization field.** Separate, unstarted future roadmap items.
- **The `procedure_type` enum and `consultation_line_items.procedure_type` column.** Kept as-is, to preserve already-completed visits' billing history — only the personal catalog table is dropped, and the app stops writing _new_ procedure rows.

## Note: the design evolved after you reviewed the running app

Everything above is this plan as originally scoped and built. Once it was
running, you reviewed it screen-by-screen and asked for meaningfully more —
in your own words, to "break down my catalog > medications, have medications
AND prescriptions... prescriptions will allow vets to pull multiple
medications, assign the dose and frequency on them... making new medication
will just need the name, type, price... nothing related to frequency since
that belongs to prescriptions"; to "turn this [the consultation
detail panel] into a default form in my catalog > forms... can be loaded for
every new consultation on first open" (vitals/diagnosis stopped being fixed
form fields and became just another vet-built form template, seeded as
"General Consultation"); to "add a ... button for list/table view, rmb/hold
tap for board/gallery view in consultation queue"; and to "remove
consultation results, should just be an option in consultation queue > row
options > results" (the standalone Consultation Results page was deleted
outright).

None of this contradicts the plan above — it's the same three asks, taken
further after seeing them in the browser. `testing/testing.md` in this same
session folder documents the actual final state; where it and this plan
disagree on a specific detail (e.g. "two tabs" vs. the final three, or a
Medications catalog entry still carrying a dose), trust `testing/testing.md`.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks — updated in place to
reflect the design's later evolution (above), not just this plan's original
scope.
