# Context — 115-misc-sales-cashier-and-payment-removal

## Copied into ./context/

Nothing new - the original request (Stage A/B) and the Stage C follow-up
request are both already quoted verbatim in `plan.md`'s "What you asked
for" section and `testing/testing.md`'s "The request, verbatim" section,
which is where this session's context lived. Stage C's request was a
direct follow-up instruction in the same conversation, not a separate
document - "make it look like the booking step wizard, add steps to it:
first is customer ... then the product chooser ... then the promo/discount
step, then payment method step, then confirmation step" - reproduced there
in full, so nothing further needed copying here.

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.pdf` -
  the project-wide task/backlog log, skimmed during planning to confirm
  "Miscellaneous Sales" already appeared there as a report line item
  (Branch Reports > Daily Sales Report). Stays canonical in
  `shared/context/`, not session-specific. Its own later update (pushed
  separately to `main`, unrelated to this session's implementation) was a
  pre-existing edit already staged before this session started.
- `golden-fur` PRs [#208](https://github.com/the-golden-fur/golden-fur/pull/208)
  and [#210](https://github.com/the-golden-fur/golden-fur/pull/210) - the
  actual diffs this session's `testing.md` describes; not copied here since
  they're the live source of truth in the `golden-fur` repo itself. Stage
  C's commit (`9f7b086`, the wizard rebuild) is not yet pushed to
  `origin/feat/cashier-misc-sales-page`, so PR #210's diff on GitHub does
  not include it yet as of this update - see `testing/testing.md`'s Open
  items.
- `golden-fur`'s `client/src/features/booking/components/BookingStepper/BookingStepper.tsx`
  and `client/src/features/booking/pages/CustomerBookingFlowPage/` - the
  existing booking-flow wizard the new `MiscSaleWizard` is explicitly
  modeled on (per the Stage C request) and reuses `BookingStepper` from
  directly; read for pattern reference while implementing, not copied since
  the live source is the reference.
