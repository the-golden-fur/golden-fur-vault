# Customer-uploaded pet photos now show in staff Customer Management

Branch: `fix/customer-mgmt-pet-photo-refresh`

## The request, verbatim

> does the optional uploading of photo inside pet manager work for across the system

> it doesn't appear under customer management

When asked how the photo got there, the answer was: the **customer uploaded it from the customer portal**.

## Root cause / Context

**Follow-up ("picture still won't show"): the real cause.** The `pet-photos` Storage bucket **does not exist** in the dev Supabase project. A read-only check found the buckets `message-attachments`, `service-images`, `avatars` and `vet-medication-images`, but no `pet-photos`. No row in `pets` has a `photo_url`. Migration 20260725044 only added the bucket's RLS policies and assumed someone would create it manually in the Dashboard, which never happened. 20260921206's comment claiming 20260914203 created it is wrong. So every `POST /pets/:id/photo` (and `/care-item-photo`) failed, and PetForm/PetDetailPanel dropped the error without telling anyone. This is the same gap `avatars` had before 20260921206.

Fix: new migration `supabase/migrations/20261017271_custom_pet_photos_storage_bucket.sql` creates the public bucket idempotently. Upload failures are now shown to the user:
- `PetForm` passes `photoError` to `onCreated`.
- Customer Pet Manager and Customer Management show "Pet added, but the photo could not be uploaded: …".
- `PetDetailPanel`: after the follow-up "make uploading picture optional", a failed upload never blocks the save. The other changes save, edit mode closes, and a "Changes saved, but the photo could not be uploaded: …" warning shows on the profile.

The caching fix below is still valid: without it, a photo uploaded after staff opened View Pets would stay hidden until refresh.

The original analysis (still true for the caching part):

The upload itself was fine. `POST /pets/:id/photo` saves the image to the `pet-photos` Storage bucket and writes `pets.photo_url`. `GET /customers/:id/pets` returns `select('*')`, and `PetCard` draws `photo_url` when it's set.

The bug was in the staff **Customer Management** page. It cached each customer's pet list in `petsByCustomer` and downloaded it only the first time staff opened that customer's pets (`!petsByCustomer[customerId]` guard). If staff had already looked at a customer's pets, a photo the customer uploaded later stayed invisible until a full browser refresh.

There was a related bug in the same page. `handlePetCreated` appended the new pet to `prev[customerId] ?? []`. When the list had never been loaded, this saved a one-pet list, so the next **View Pets** skipped the download and hid the customer's other pets.

## What changed

### Client

- `client/src/features/staff/pages/CustomerManagementPage/CustomerManagementPage.tsx`
  - `handleSelectAction`: removed the "already cached" guard. **View Pets** and the overview now download the pets every time they open, just as bookings already did.
  - `renderPets`: "Loading pets..." shows only when there's no cached list. On a reopen, the previous list stays on screen while the fresh one loads.
  - `handlePetCreated`: appends only to a list that has already been loaded. Otherwise it leaves the cache alone, so the next **View Pets** fetches everything.
  - Reworded the bookings comment. It said "Unlike pets…", which is no longer true.
- `CustomerManagementPage.spec.ts`: new `pet list freshness (session 120)` block:
  - Opening **View Pets** twice downloads twice, and the second response's photo renders as `<img alt="Buddy's photo">`.
  - **Add Pet** first, then **View Pets**: the full list is still downloaded and both pets show.

No server, database or migration changes.

## Manual test — step by step

You need two browsers (or one normal window and one private/incognito window), plus the dev servers running: client on `http://localhost:5173`, server on `http://localhost:3000`. Use the seeded staff and customer test accounts. Their passwords are in the repo's seed files, not here.

**A. Customer uploads a photo while staff are looking**

1. **Browser 1 (staff):** go to `http://localhost:5173` and log in as a Receptionist or Admin. Open **Customer Management** from the side menu.
2. Click **Table** (view switcher above the list). On the seeded customer's row, click the **…** (customer actions) button, then **View Pets**. A popup titled **Pets - <customer name>** lists their pets. Note a pet that shows a **letter** instead of a photo.
3. **Browser 2 (customer):** log in to the customer portal as that same customer. Open **My Pets** (the pet manager), click the same pet, and upload a photo (PNG/JPEG/WebP, under 5 MB). The photo should appear on the customer's pet card.
4. **Browser 1 (staff):** close the Pets popup (**×** top-right), then open **… → View Pets** again **without refreshing the page**.
   - ✅ Pass: the pet card now shows the photo.
   - ❌ Fail: it still shows the letter placeholder. That's the old bug.
5. Also click the customer's name to open the **overview** popup. The photo should show there too.

**B. Add Pet doesn't hide existing pets**

1. **Browser 1 (staff):** refresh the page so nothing is cached. On a customer that **already has at least one pet**, click **… → Add Pet** (don't open View Pets first).
2. Fill in **Name**, **Pet Type**, **Breed**, and click **Add pet**. You should see **Pet added.**
3. Close the popup and open **… → View Pets**.
   - ✅ Pass: both the old pet(s) and the new one are listed.
   - ❌ Fail: only the new pet is listed.

## Test suites

- `client`: `npx vitest run src/features/customers src/features/staff/pages/CustomerManagementPage src/features/booking/pages/CustomerBookingFlowPage`: **157/157 passing** (15 files), including the 2 new Customer Management tests and the new PetForm failed-upload test.
- `client`: `npx tsc -p tsconfig.app.json --noEmit`: clean. `npx eslint src/features/staff/pages/CustomerManagementPage`: clean.
- The full client/server suites were **not** run this session.

## Open items

- `PetForm` silently ignores a failed photo upload (the pet is created without the photo and no error is shown). This was not the cause here; it's a follow-up.
- Pet photos aren't shown on other screens (booking flow pet picker, Groomer dashboard, Hotel/Daycare queues, Vet console). That's a separate enhancement.
