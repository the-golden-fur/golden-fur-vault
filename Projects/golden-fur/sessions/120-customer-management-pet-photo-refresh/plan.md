---
title: Show customers' new pet photos in staff Customer Management
date: 2026-10-17
tags: [session-plan, golden-fur]
project: golden-fur
session: 120-customer-management-pet-photo-refresh
branch: fix/customer-mgmt-pet-photo-refresh
---

# 120 — Show customers' new pet photos in staff Customer Management

## What you asked for

When a customer uploads a photo of their pet, staff should also see that photo when they look at the customer in Customer Management.

> it doesn't appear under customer management

(This was a follow-up to "does the optional uploading of photo inside pet manager work for across the system". When asked how the missing photo got there, you said the **customer uploaded it from the customer portal**.)

## What this part of the app does today

- **Customer portal → Pet Manager** is the customer's own list of their pets. When they add or edit a pet, they can pick an optional photo. The browser sends the photo to the server, the server saves the image file in Supabase Storage (a cloud folder for files) and writes the image's web address into the pet's `photo_url` column in the database.
- **Staff → Customer Management** is the page where receptionists and admins look up customers. Each customer row has actions such as **View Pets** and an **overview** panel. Both show the customer's pets as small cards (`PetCard`). If a pet has a `photo_url`, the card shows the picture. Otherwise it shows the first letter of the pet's name.

I checked the server first. The pets list endpoint (`GET /customers/:id/pets`) returns every column, `photo_url` included, and the card already knows how to draw the photo. So the data path is fine. The problem is on the page itself.

## What's wrong / what's missing

The Customer Management page keeps a **cache**, a short-term memory of data it already downloaded, so it doesn't ask the server again. It downloads a customer's pets **only the first time** staff open that customer's pets. After that it keeps reusing the saved copy until the whole page is reloaded.

Here is what a receptionist actually sees:

1. The receptionist opens Customer Management and clicks **View Pets** for a customer. The pets show the letter placeholder, because there's no photo yet.
2. Meanwhile, the customer uploads a photo from their phone.
3. The receptionist closes and reopens **View Pets**. The page reuses its old copy, so the photo still doesn't show. It only appears after a full browser refresh.

There's a second, smaller bug in the same page. If staff use **Add Pet** for a customer whose pets were never loaded, the page creates a cached list that contains **only the new pet**. When staff then click **View Pets**, the page believes it already has the list, skips the download, and hides that customer's other pets.

Bookings on this same page already avoid this problem: they are downloaded again every time the overview opens. A code comment even says pets "don't change from elsewhere", which stopped being true once customers could upload photos.

## What we're going to change

1. **Download the pets again every time View Pets or the overview opens.** _Which files:_ `client/src/features/staff/pages/CustomerManagementPage/CustomerManagementPage.tsx` (the `handleSelectAction` function). _Why:_ remove the "only if we don't already have them" check so the page always asks the server for the latest pets, including any new photos. We'll update the outdated comment too.
2. **Keep the old list on screen while the new one loads.** _Which files:_ same file, the `renderPets` function. _Why:_ show "Loading pets..." only when there's nothing saved yet. Otherwise the panel would flash empty every time it's reopened. Bookings already behave this way.
3. **Stop Add Pet from creating a half-filled list.** _Which files:_ same file, `handlePetCreated`. _Why:_ only add the new pet to the saved list if a list was already downloaded. If not, leave it alone so the next View Pets downloads the full list.
4. **Add automated tests.** _Which files:_ `CustomerManagementPage.spec.ts` next to the page. _Why:_ one test opens View Pets twice and checks that the second (newer) download's photo shows up as an image. Another test checks that View Pets still downloads the full list after Add Pet.

Not part of this change, noted for later:

- The Add Pet form quietly ignores a failed photo upload. This bug didn't cause what you saw, but it should eventually show an error message.
- Pet photos on other screens (booking flow, queues, vet console) are a separate improvement.

## Words you might not know

- **cache** — a saved copy of data the page already downloaded, reused to avoid asking the server again. It's fast, but it can go **stale**, meaning out of date.
- **stale-while-revalidate** — keep showing the old saved copy while quietly downloading a fresh one, then swap the fresh one in.
- **Supabase Storage** — the cloud file storage this project uses for uploaded images. The database only stores the image's web address (`photo_url`).
- **endpoint** — a specific server address the browser calls to get or send data, e.g. `GET /customers/:id/pets`.
- **spec file (`.spec.ts`)** — a file of automated tests that run with Vitest and check the page behaves as expected.

## How you'll know it worked

See `testing/testing.md` (written after implementation) for the click-by-click checks. In short: open a customer's View Pets as staff, have that customer upload a pet photo in another browser, then close and reopen View Pets. The photo should appear without refreshing the page.
