# Cancellation now goes through an explicit modal dialog

Branch: `feat/cancel-confirmation-dialog` (golden-fur);
`filing/cancel-confirmation-dialog-verification` (this vault doc).

## The request, verbatim

> Add an explicit confirmation dialog ('Are you sure you want to cancel this
> booking?') before a cancellation is executed.

From the Aug-27 advisor demo (`Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`):
_"So ngayon, ano pa pwede nating gawin? Pwede ba akong magpa-cancel? … Are you
sure you want? — It's done. Parang checkbox lang siya."_ and later
_"nagpindot kasi matam— bilis. Nag-cancel kaagad."_

## Root cause / Context

Both cancel flows — `CustomerBookingsPage` (customer self-service) and
`ReceptionistBookingsQueuePage` (staff on the customer's behalf) — already
had a two-step confirm, but it was an **inline panel that replaced the
row's action buttons in place**. The "Yes, cancel booking" button rendered
at roughly the same screen position the "Cancel" button had just occupied,
so a fast double-click or a stray second click landed on it and cancelled
immediately. It read as "just a checkbox", not a deliberate confirmation.

## What changed

Client only — no server, schema, or API change.

- `client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`
- `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx`
  - The inline `isCancelling` confirm panel is replaced by the shared
    `ConfirmDialog` (`shared/components/ConfirmDialog`), rendered once per
    page and keyed to `activeAction` (`cancelTarget`).
  - `ConfirmDialog` is a fixed full-screen backdrop (`z-index: 50`,
    `inset: 0`) with a `role="dialog"`, `aria-modal` panel — it intercepts
    every click behind it, so the row's "Cancel" button cannot be
    re-triggered while it's open. Confirm button is `tone="danger"`
    (red), labelled **"Yes, cancel booking"**; dismiss is **"Keep
    booking"**.
  - Dialog body: **"Are you sure you want to cancel this booking?"**
    (customer wording adds "… and may forfeit your downpayment depending
    on notice given" when a downpayment exists; receptionist wording adds
    "… on the customer's behalf"), plus the existing optional Reason
    textarea and inline error banner.
  - `cancelBooking()` is called **only** from `ConfirmDialog.onConfirm`.
    The row "Cancel" button just sets `activeAction` → opens the dialog.
  - `openCancel` / `confirmCancel` / `closeAction` / `cancellationReason`
    state and the `!isCancelling` guard on the row's action row are
    unchanged.

The `ConfirmDialog` confirm button shows "Working..." while `isConfirming`
(the shared component's convention) rather than the old "Cancelling...".

## Verification

1. **Customer portal → My bookings**, a Pending/Confirmed booking →
   **Cancel**.
   - A centred modal appears over a dimmed backdrop: title "Cancel this
     booking?", body "Are you sure you want to cancel this booking? …",
     Reason field, red "Yes, cancel booking" + "Keep booking".
   - Click the dimmed backdrop / anywhere outside → nothing happens (no
     accidental dismiss into a cancel).
   - **Keep booking** → dialog closes, booking unchanged, no API call.
   - Re-open, type a reason, **Yes, cancel booking** → booking flips to
     Cancelled; `cancellation_reason` persisted; the
     "did not meet the notice period" banner shows when applicable.
   - Rapidly double-click the row's **Cancel** button → the dialog opens
     once and waits; the booking is never cancelled by the second click.
2. **Receptionist Bookings Queue**, a cancellable booking → same flow,
   with the "on the customer's behalf" wording. A Cancelled booking shows
   no Cancel button and no dialog.
3. Downpayment booking (customer): the body includes the forfeiture
   warning line.

## Test suites

- `client`: `npx vitest run` — **731/731 passing (142 files)**.
  - `CustomerBookingsPage.spec.ts` "AC-5" strengthened: asserts a
    `role="dialog"`, that "Keep booking" dismisses it without an API call,
    then that "Yes, cancel booking" calls `cancelBooking`.
  - `ReceptionistBookingsQueuePage.spec.ts`: new case for the full
    open → dismiss → re-open → confirm dialog flow (+1 test, 24 total).
  - `npx tsc --noEmit`, `npx eslint`, `npx prettier --check`,
    `npx vite build` all clean.
- `server`: no changes.

## Open items

- `ConfirmDialog` has no Escape-to-close or backdrop-click-to-close — for a
  destructive action that's arguably correct (you must pick "Keep
  booking"), but it's inconsistent with `Modal` elsewhere. Left as-is.
- The dialog is not focus-trapped (the shared component doesn't do it).
  Acceptable for now; a future a11y pass on `ConfirmDialog` would cover
  every caller at once.
