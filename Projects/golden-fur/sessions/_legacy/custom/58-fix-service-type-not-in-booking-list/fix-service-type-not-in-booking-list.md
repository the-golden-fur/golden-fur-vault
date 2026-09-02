# New active service type never appeared in the booking Service Type step

Branch: `feat/service-type-selection-visibility` (golden-fur code);
`filing/service-type-booking-list-verification` (this vault doc).

## The request, verbatim

> Fix the bug preventing a newly created and activated service type from
> appearing in the service selection list.

## Root cause / Context

The Service Types admin addendum (migration
`20260809113_custom_create_service_types.sql`, plus `AdminServiceTypesPage`)
explicitly promises that a brand-new row created in **Admin Settings >
Service Types** "will show up as selectable (if active)" in the customer/
receptionist booking flow's Service Type step — only its category-specific
behavior (availability, capacity, pricing, eligibility) is deferred to code.

`CustomerBookingFlowPage`'s `availableCategories` broke that promise. It was
built by filtering the hardcoded `SERVICE_CATEGORIES` array
(`Grooming / Hotel / Daycare / Veterinary / Misc`) and keeping only entries
whose `service_types` row is active:

```ts
return SERVICE_CATEGORIES.filter(
  (candidate) =>
    (candidate !== "Veterinary" || (selectedBranch?.is_vet_branch ?? true)) &&
    (serviceTypeByKey.get(candidate)?.is_active ?? true),
);
```

A newly created service type carries a **free-text `key` outside**
`SERVICE_CATEGORIES` (e.g. `Boarding`), so it was never in the array being
iterated and could never render — regardless of being active. The DB rows
fetched by `listServiceTypes()` were only ever consulted as a lookup map
for label/active overrides on the hardcoded keys, never as the source of
the list itself.

## What changed

### Client

- `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
  - `availableCategories` now returns the seeded categories (unchanged
    logic — same Veterinary vet-branch rule, same "missing/failed fetch
    degrades to shown" fallback via `?? true`) **plus** every active
    `service_types` row whose `key` is not one of the hardcoded
    `SERVICE_CATEGORIES`. Custom active types are appended after the seeded
    ones. `serviceTypes` added to the `useMemo` dependency list.
  - The Service Type step's card renderer now falls back to the generic
    `ClipboardList` icon when `CATEGORY_ICONS[candidate]` is undefined (a
    custom key has no dedicated icon) instead of rendering `undefined` as a
    component and crashing the step.
  - Behavior for the four seeded categories, unassessed-pet ("Misc" only)
    handling, and the empty/failed-fetch degradation are all unchanged.

No server, schema, or API-contract changes — `listServiceTypes()` and its
route already returned the custom rows; only the client's use of them was
wrong. No Postman collection or SQL reference for this change.

## Verification

Prereq: log in as Admin, go to **Settings > Service Types**, "New service
type" with Key `Boarding`, Name `Overnight Boarding`, leave both pickers
off, keep at least one branch checked, Add. Confirm it lists as active
(has at least one available branch).

1. **Customer portal** (`customer1@goldenfur.com`) → Book. Pick an
   assessed pet (has weight class + coat type), pick the branch you made
   `Boarding` available at, advance to the **Service Type** step.
   - Expect: a card labelled **Overnight Boarding** appears alongside
     Grooming / Hotel / Daycare / Veterinary, with the generic clipboard
     icon.
2. Select **Overnight Boarding** and continue. The item-selection step
   shows "No Overnight Boarding services available at this branch" — this
   is the documented "selectable now, behavior built later" state, not a
   regression.
3. Back in **Settings > Service Types**, open **Branch Availability** for
   `Overnight Boarding` and turn every branch off (this flips
   `is_active` false via `setServiceTypeBranchAvailability`'s sync).
   Re-open the booking flow → Service Type step.
   - Expect: **Overnight Boarding** is gone; the four seeded cards remain.
4. Rename a seeded type (e.g. Grooming → "Spa & Grooming") in the admin
   page. Booking flow Service Type step shows the new label on the
   Grooming card; selecting it still submits `service_category: "Grooming"`.
   (Regression check — unchanged behavior.)
5. Receptionist booking flow (staff console → new booking): repeat step 1
   and confirm the custom type shows there too (same component).
6. Pick an **unassessed** pet in the customer flow: Service Type step
   still shows only the Initial Assessment path, no `Boarding`.
   (Regression check.)

## Test suites

- `client`: `npx vitest run` — **732/732 passing (142 files)**. Added 2
  cases to
  `src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.spec.ts`
  — one asserting a newly created active custom type (`Boarding`) renders
  in the Service Type step, one asserting an inactive custom type stays
  hidden. `npx tsc --noEmit` — clean. `npx eslint` on the changed files —
  clean. `npx prettier --check` — clean.
- `server`: no changes; suite not re-run.

## Open items

- Selecting a custom service type still leads to an empty item list and no
  category-specific availability/pricing/capacity logic — deferred by
  design (migration `20260809113` header, `AdminServiceTypesPage` copy).
  Wiring real behavior for a custom type is a separate piece of work.
- `DEFAULT_DURATION_MINUTES[category]` is `undefined` for a custom key on
  the availability step; not addressed here since that step isn't reached
  in the normal "no services offered" path, but worth a guard when custom
  types get real behavior.
