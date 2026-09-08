# One-click check-in from the Hotel Queue

Branch: `feat/hotel-queue-one-click-checkin` (base: `dev`)

## The request, verbatim

> On http://localhost:5173/staff/hotel/queue:
>
> - Clicking on check in on hotel queue should immediately check in the pet,
>   does not open http://localhost:5173/staff/hotel/queue/check-in/<id>
> - Move http://localhost:5173/staff/hotel/queue/check-in/<id> to the "..."
>   button > View booking details with an edit option at the bottom
> - Do not open this page with go to checkout and check in another pet
>   options after checking it, just return to the queue and show a modal if
>   success or fail

## Root cause / Context

The Hotel Queue's **Check In** tab renders `HotelBookingPicker`, a
searchable list of *Pending* Hotel bookings. Its **Check in** button used
to `navigate()` to a routed form page (`HotelCheckInFormPage` at
`/staff/hotel/queue/check-in/:bookingId`), which mounts `HotelCheckInPanel`
— a five-section cage + care-instructions form that loads read-only,
pre-filled from `bookings.hotel_preferences` (what the customer captured at
booking time), with one **Edit** toggle at the bottom. Submitting it called
`POST /hotel/check-in` and then replaced the page body with a success
banner + **Go to checkout** / **Check in another pet** controls.

Nothing about the check-in *endpoint* forced that form to exist:

- `CheckInPayload.cage_id` is **optional** — omitted, `resolveAndClaimCage`
  (`server/.../careInstructions.service.ts`) auto-suggests the pet's
  weight-class size and claims the first Available cage, or 409s with
  `No available cage of the suggested size (<size>)`.
- `CheckInPayload.medications` is **optional** — omitted (not `[]`),
  `insertMedicationInstructions` auto-fills from the pet's current vet
  prescription (#75 AC-3).
- `feeding` / `walking` / `playing` are required arrays but accept `[]`,
  and the `hotel_preferences.*` shapes are field-for-field identical to the
  `*InstructionPayload` shapes, so they pass straight through.

So the common path — customer already entered care instructions, any cage
of the right size is fine — needs no form at all. The form only earns its
keep when staff must change the cage or correct an instruction first.

Decision: the row button does a one-click check-in and reports the result
in a modal; the form moves down one level to the row's "..." menu (**View
booking details**), keeping its URL and its **Edit** toggle. No server or
DB changes.

## What changed

No database changes. No server changes.

### Client

- **`pages/HotelQueuePage/buildQuickCheckInPayload.ts`** (new) — pure
  function `Booking -> CheckInPayload`. Sends `booking.hotel_preferences`'s
  feeding/walking/playing verbatim (or `[]` when there are none); omits
  `cage_id` entirely; sends `medications` only when the booking named at
  least one (otherwise omitted, so the server falls back to the pet's
  prescription rather than recording an empty list); `notify_opt_in: false`
  (matches the form's own submit).
- **`pages/HotelQueuePage/HotelQueuePage.tsx`** — new `handleQuickCheckIn`:
  calls `checkInHotelStay` with the built payload, then sets a
  `checkInFeedback` state (`{status:'success'}` or
  `{status:'error', message}`) rendered as a shared `<Modal>` over the
  still-visible queue. On success it also bumps a `pickerReloadKey` that
  remounts `HotelBookingPicker` so the just-checked-in booking leaves the
  Pending list. The `?checkedIn=success` query param (set by the details
  page's redirect) seeds `checkInFeedback` to success on mount. The "..."
  menu's **View booking details** is wired to
  `navigate('/staff/hotel/queue/check-in/<id>')`.
- **`pages/HotelQueuePage/HotelQueuePage.module.css`** — added
  `.modalActions` / `.modalButton` for the modal's single **Done** button.
- **`components/HotelBookingPicker/HotelBookingPicker.tsx`** — prop
  `onSelect` split into `onCheckIn` (row button, one-click) and
  `onViewDetails` ("..." menu). New optional `checkingInBookingId` — the
  matching row's button shows **Checking in...** and is disabled. The menu
  item no longer hard-codes `navigate('/staff/bookings/<id>')`; it delegates
  to `onViewDetails`. Dropped the now-unused `useNavigate` import.
- **`pages/HotelCheckInFormPage/HotelCheckInFormPage.tsx`** — page title
  **Check in** -> **Booking details**; `onCheckedIn` now redirects to
  `/staff/hotel/queue?checkedIn=success` instead of
  `?tab=check-out&stayId=<id>`. Doc comment rewritten.
- **`pages/HotelQueuePage/HotelCheckInPanel.tsx`** — removed the
  `checkedInStayId` state and the entire post-check-in success screen
  (**Go to checkout** / **Check in another pet**). On a successful submit it
  now calls `onCheckedIn(stayId)` directly and lets the parent leave.
  Dropped the unused `Link` import; header/prop doc comments updated.
- **`pages/HotelQueuePage/HotelCheckInPanel.module.css`** — removed the now
  orphan `.successBanner` and `.controls` rules.
- Specs: `HotelBookingPicker.spec.ts` updated for the new props (+ cases for
  the "..." menu -> `onViewDetails` and for `checkingInBookingId`);
  `HotelCheckInPanel.spec.ts`'s "#22 freetext" case now asserts
  `onCheckedIn('stay-1')` instead of waiting for the removed success banner;
  new `HotelQueuePage.spec.tsx` (5 cases) and
  `buildQuickCheckInPayload.spec.ts` (3 cases).

## Manual test — step by step

Assumes `golden-fur` is running locally: server on `http://localhost:3000`,
client on `http://localhost:5173` (run `npm run dev` at the repo root, or
the "🚀 Dev: Start All" VS Code task). The Hotel Queue is visible to
**Groomer**, **Pet Assistant**, Admin, Supervisor, Superadmin — **not**
Receptionist. Staff logins are `<branch>.<role>N` / `password123`
(e.g. `makati.groomer1`); customer logins are `customerN@goldenfur.com` /
`password123`.

You need at least one **Pending Hotel booking** at the branch. If there
isn't one: log in as a customer, **Book an appointment** -> pick an
assessed pet -> a branch -> **Hotel** -> a hotel service -> pick check-in
and checkout dates -> pay the downpayment. That booking shows up in the
queue.

### A. One-click check-in succeeds (the main path)

1. Open `http://localhost:5173`, click **Log in**, sign in as
   `makati.groomer1` / `password123`.
2. Go to `http://localhost:5173/staff/hotel/queue`. You land on a page
   headed **Hotel Queue** with **Check In** / **Check Out** tabs; **Check
   In** is selected and shows a list of bookings.
3. Find a card with a **Check in** button (a *Pending* booking). Click
   **Check in**.
   - **PASS:** the button briefly reads **Checking in...**, then a pop-up
     titled **Pet checked in** appears saying "Pet checked in
     successfully." with a **Done** button. Behind it, that booking has
     dropped off the list. The URL is still `/staff/hotel/queue` — no form
     page opened.
   - **FAIL:** a full page titled **Check in** or **Booking details** opens,
     or a "Go to checkout / Check in another pet" screen appears.
4. Click **Done**. The modal closes; you're on the queue.
5. Click the **Check Out** tab, widen the date filter if needed, and
   confirm the pet you just checked in is now listed as checked-in / ready
   for checkout. (This proves the stay was really created.)

### B. One-click check-in fails cleanly

1. Force a no-cage situation: as an Admin, open **Settings -> Config ->
   Cages** and set every cage of the pet's size to **Under Maintenance**
   (or check in enough other pets to fill them).
2. Back on the Hotel Queue **Check In** tab, click **Check in** on that
   booking.
   - **PASS:** a pop-up titled **Check-in failed** appears with the
     server's reason, e.g. "No available cage of the suggested size (S)",
     and a **Done** button. The booking stays in the list. Nothing
     navigates.
   - **FAIL:** a success modal appears, or an unhandled error/blank screen.

### C. "View booking details" (the old form, one level down)

1. On the **Check In** tab, click the **"..."** (three-dots) button in the
   top-right of a *Pending* booking's card. A small menu opens with **View
   booking details**.
2. Click **View booking details**.
   - **PASS:** you land on a page headed **Booking details** (URL
     `/staff/hotel/queue/check-in/<booking id>`) — the five-section cage +
     care-instructions form, loaded read-only, with **Edit** and **Check
     in** buttons at the bottom.
   - **FAIL:** it opens `/staff/bookings/<id>` (the generic booking page)
     instead, or the page is titled **Check in**.
3. Click **Edit** — every field unlocks, the button becomes **Done
   editing**, and "Add ..." buttons appear. Change something (or don't),
   then click **Check in**.
   - **PASS:** you're taken back to the **Hotel Queue** and the **Pet
     checked in** success modal is showing. No "Go to checkout / Check in
     another pet" screen.
   - **FAIL:** the page stays on a "Pet checked in successfully" screen with
     **Go to checkout** / **Check in another pet**.
4. If the check-in from this page fails (e.g. no cage), you stay on the
   **Booking details** page with a red error banner so you can fix a field
   and retry — this path deliberately does not bounce you to the queue, so
   in-progress edits aren't lost. (See Open items.)

### D. Receptionist still can't see the queue

1. Log in as `makati.receptionist1` / `password123`, go to
   `/staff/hotel/queue`.
   - **PASS:** you're redirected to `/staff/settings` (unchanged behaviour).

## Test suites

Run this session (no `ci-verifier` available in this environment):

- `client`: `npx vitest run` — **807/807 passing (157 files)**;
  `npx tsc --noEmit` clean; `npx eslint` clean on the changed files;
  `npx vite build` succeeds.
- `server`: `npx vitest run` — **1023/1023 passing (93 files)** (no server
  files changed this session; run as a regression check).
- Root `npm run format:check` clean.

## Open items

- A check-in that **fails from the "Booking details" page** shows an inline
  error banner there and lets staff retry, rather than redirecting to the
  queue with a failure modal. This is a deliberate reading of "return to the
  queue and show a modal if success or fail" — bouncing away on failure
  would discard any edits the receptionist just made in the form. Success
  from that page does return to the queue + modal, as asked. Revisit if the
  advisor wants the failure case to bounce too.
