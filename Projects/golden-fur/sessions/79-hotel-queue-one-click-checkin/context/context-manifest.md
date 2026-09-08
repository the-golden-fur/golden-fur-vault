# Context — 79-hotel-queue-one-click-checkin

## Copied into ./context/

- `request.md` — the session request, transcribed from the chat message
  that started this session (the screenshot it included is described, not
  copied).

## Referenced only (not copied)

- `golden-fur/server/src/features/hotel/services/careInstructions.service.ts`
  — `checkInHotelStay` / `resolveAndClaimCage` /
  `insertMedicationInstructions`; the source of the "cage_id optional ->
  auto-suggest" and "medications omitted -> prescription auto-fill"
  behaviour this change relies on. No changes made to it.
- `golden-fur/client/src/features/hotel/hotel.types.ts` — `CheckInPayload`
  shape (`cage_id?`, `medications?`) and the `*InstructionPayload` types
  that `bookings.hotel_preferences.*` maps onto one-for-one.
- `golden-fur/client/src/features/booking/booking.types.ts` —
  `HotelBookingPreferences` and its `feeding/walking/playing/medications`
  row types.
- `Projects/golden-fur/sessions/78-drop-fully-booked-indicator/` — the
  immediately-preceding session in the same Aug-27 advisor review batch;
  same staff/customer seed-login conventions used in `testing/testing.md`.
- `golden-fur/supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts` —
  source of the staff login values (`<branch>.<role>N`, e.g.
  `makati.groomer1`, password `password123`; slugs `groomer`,
  `petassistant`).
- `golden-fur/supabase/seeds/m02-customers-pets/m02-customers-pets.seed.ts`
  — source of the customer login values (`customerN@goldenfur.com`,
  password `password123`).
- `golden-fur/server/.env`, `golden-fur/client/.env` — Supabase URL / keys
  for the dev database the manual test runs against. Secrets; never copied.
