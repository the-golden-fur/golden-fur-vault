# Archive workflow, responsive fix, search/filter/sort standardization, advanced filter builder, multi-night hotel bookings

Branch: `feat/staff-archive-search-and-multinight-booking`

## What changed

### 1. Deactivate-first CRUD safety + Archive (Products, Staff, Customers/Pets)

- New DB migrations: `supabase/migrations/20260731070_m02_add_customer_pet_is_active.sql`, `20260731071_shared_add_archived_at_columns.sql`.
- Server: shared guard `server/src/shared/archive/archiveGuard.ts` enforces "must be deactivated before archive, must be archived before hard-delete" for all three entities. New archive/restore/list-archived/hard-delete endpoints on `/catalog/products`, `/staff`, `/customers`, `/pets`.
- Client: new `ConfirmDialog` shared component, `ArchiveList` shared component, and `/staff/admin/archive` page with Products / Staff / Customers & Pets tabs. Each admin page's "Delete" button is now "Archive" (disabled until the record is deactivated) with a "View archive" link.

### 2. Responsive fix: `/staff/admin/unavailability`

- Added a `640px` breakpoint (matching the repo's existing convention) to `UnavailabilityApprovalQueuePage.module.css` and `UnavailabilityReviewCard.module.css`.

### 3. Search/filter/sort standardized across 6 pages

- Hotel Checkout, Daycare Check-in, Daycare Checkout (new `GET /daycare/sessions` endpoint + `DaycareSessionPicker`), Veterinary Console, Grooming Queue, Product Catalog all now use the shared `useSearchAndSort` hook + `SearchSortBar` component.
- Hotel Checkout's "0 active stays" issue: added a startup warning in `server/src/config/supabase/supabase.config.ts` for a missing `SUPABASE_SERVICE_ROLE_KEY` (confirmed it IS set locally, so this isn't the live cause here), refactored `HotelStayPicker` off its hand-rolled search/sort state, and fixed the empty-state copy to distinguish "no stays at all" from "search found nothing."

### 4. Notion-style advanced filter builder

- New shared component tree at `client/src/shared/components/AdvancedFilterBuilder/` (field/operator picker, chips, `useAdvancedFilters` hook). Rolled out to all 6 pages above alongside the search/sort bar.

### 5. Booking flow: multi-night Hotel bookings + booking-time-aware care schedule

- Added a "Number of nights" input (Hotel only) in `CustomerBookingFlowPage.tsx`; `scheduled_end` is computed client-side as `start + nights * per-night duration`. No DB/server changes needed — the existing capacity-overlap check and `scheduled_end > scheduled_start` constraint already handle any valid range correctly.
- Feeding/Walking/Medication now show an informational hint when a meal/time wouldn't apply on the arrival or departure day, based on check-in/checkout clock time. **Design correction from the original plan**: Hotel stays are overnight (check-in and checkout share the same clock time), so a hard "reject times outside check-in/checkout" validation is mathematically wrong — every clock time is guaranteed valid on at least one of the two edge days. The feature ships as an informational hint only, not a hard client bound or server rejection.

## Known limitations / follow-ups

- The Hotel Checkout "0 active stays" root cause could not be fully diagnosed without live DB access — `SUPABASE_SERVICE_ROLE_KEY` is confirmed set locally, so if the issue persists after this change, it needs a live check of an actual checked-in stay's `bookings.status` value and the logged-in staff user's `branch_id` against the cage's `branch_id`.
- Per-pet archive/deactivate isn't yet surfaced as a dedicated button in the pet-profile UI (the server endpoints exist: `PATCH /pets/:id/deactivate`, `DELETE /pets/:id`, `POST /pets/:id/restore`, `DELETE /pets/:id/permanent`, `GET /pets/archived` — only the Archive page's "Pets" tab and a customer's own pet self-archive via the existing delete-pet action currently use them).
- Server-side care-schedule time-of-day comparisons (if ever added) would need branch-timezone awareness; both the client hint and this design deliberately avoid that complexity for now (informational only).

## Verification steps

1. **Setup**: apply the two new migrations to your local Supabase (however you normally apply migrations - `supabase db reset` or `supabase migration up`). Re-run seed scripts if your reset wipes data.
2. **Automated tests** (already run and passing as of this change):
   - `cd server && npm run typecheck && npm run lint && npm test` — 669 tests passing.
   - `cd client && npx tsc -b && npm run lint && npm test` — all tests passing.
3. **Archive workflow** (as an Admin/Superadmin):
   - Go to Product Catalog (`/staff/admin/product-catalog`). Try to Archive an active product — the button is disabled with a tooltip. Deactivate it first, then Archive succeeds and it disappears from the list.
   - Click "View archive" (or go to `/staff/admin/archive?tab=products`) — the archived product appears. Restore it, confirm it's gone from the archive and back in the normal list. Archive it again, click "Delete permanently" — a warning dialog appears; Cancel does nothing, Confirm removes it for good.
   - Repeat the same flow for Staff Management (`/staff/admin/staff`, tab `staff`) and Customer Management (`/staff/admin/customers`, tab `customers`) — Customer Management additionally exposes Deactivate/Archive from the "..." row menu.
4. **Responsive check**: open `/staff/admin/unavailability` in your browser's responsive/device-emulation mode at 375px and 320px widths. The branch filter shouldn't overflow, the card grid should single-column, and the Approve/Deny/Cancel buttons on a card shouldn't clip.
5. **Search/filter/sort** on each of: Hotel Checkout, Daycare Check-in, Daycare Checkout, Veterinary Console, Grooming Queue, Product Catalog — type in the search box, change the sort dropdown, click "+ Add filter" and build a condition (e.g. Product Catalog: category is Grooming AND price > 500). Confirm results narrow and the filter chip is removable.
   - For Hotel Checkout specifically: check in a pet via Hotel Check-in, then confirm it now appears in the Hotel Checkout list (this is the regression test for the "0 active stays" report).
6. **Multi-night Hotel booking**: start a Hotel booking (customer portal `/portal/book` or staff `/staff/bookings/new`), pick a slot, set "Number of nights" to 3, and confirm the booking summary reflects a 3-night stay. On the Care Instructions step, add a Morning feeding and a walk time earlier than a late check-in time — confirm the informational hint text appears ("Not served on arrival day..." / "Applies daily - won't happen before check-in...").
