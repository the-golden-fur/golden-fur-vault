# Package Pricing: Matrix & Downpayment Interaction — Recommendations

Type: Custom analysis + recommendations (no code changed in this pass)

## Summary

This is a recommendations doc, not a fix — the request was to investigate how
package pricing interacts with the coat/size pricing matrix and downpayments,
and to propose next steps. The short version: **the calculation itself is
already implemented correctly end-to-end for bookings**, but the **package
create/edit UI has real gaps** — several DB-backed pricing flags aren't
exposed in the form at all, and the checkout "receipt" the customer sees
before paying shows flat (non-matrix) prices even when the final server-side
charge will differ. The four sections below map to the four checklist items,
each with current-state evidence and a recommendation.

## 1. How package pricing is calculated today, and its pricing-matrix interaction

**Calculation chain** (server-authoritative):

- A package has no stored price. Its flat list price is derived by
  [`deriveBundledPrice`](server/src/features/maintenance/utils/deriveBundledPrice.ts#L17-L27):
  `sum(member services' base_price) * (1 - bundle_discount_percentage)`.
- At booking time,
  [`resolvePackagePrice`](server/src/features/booking/services/booking.service.ts#L308-L342)
  decides which price to actually charge:
  - If `pkg.use_pricing_matrix` is `false` (or the package has no members) →
    the flat `bundled_price` above.
  - If `true` → **each member service's own per-pet price** is resolved via
    [`resolveServicePrice`](server/src/features/booking/services/booking.service.ts#L95-L113)
    (Grooming services with their own `use_pricing_matrix` on look up the
    pet's `weight_class`/`coat_type` cell in `service_pricing_tiers`; Cats and
    non-Grooming/non-matrix services fall back to `base_price`), then
    `deriveBundledPrice` is re-applied across those per-pet prices.
- So the matrix is **already resolved per service**, not per package — a
  package's `use_pricing_matrix` flag is a gate that decides whether to even
  attempt that per-service resolution, not a second, independent pricing
  scheme.

**Gap: the checkout "receipt" doesn't reflect this yet.** In
[`CustomerBookingFlowPage.tsx`'s payment step](client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx#L2686-L2743),
every line item is shown at its **flat** price
(`service.base_price` / `pkg.bundled_price`, lines 2697-2699 and 2711-2713),
with only a static disclaimer — "Grooming price may be adjusted for your
pet's size and coat at confirmation" (line 2716-2721). The `estimatedTotal`
and even the **downpayment amount** shown to the customer
([lines 1149-1175](client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx#L1149-L1175))
are computed off that same flat price — never the matrix-resolved one. The
actual matrix-resolved `price_at_booking` only exists after the server
creates the booking, and is first shown to the customer afterward, in the
[`BookingDetailsPage`](client/src/features/booking/pages/BookingDetailsPage/BookingDetailsPage.tsx#L288-L448)
receipt. This means the number a customer commits to pay at checkout can
legitimately differ from what they're actually charged once weight/coat is
factored in.

**Recommendation:**

- **Package create/edit**: add a matrix-aware breakdown preview next to the
  existing flat-total preview
  ([`PackagePricingPreview`](client/src/features/maintenance/components/PackagePricingPreview/PackagePricingPreview.tsx)),
  modeled on the existing
  [`PricingMatrixPreview`](client/src/features/maintenance/components/PricingMatrixPreview/PricingMatrixPreview.tsx)
  grid component. It would render the same S/M/L/XL × SC/LC grid, but for
  each cell sum: each matrix-enabled member's `deriveGroomingMatrix` price at
  that weight/coat combination, plus every other (non-matrix) member's flat
  `base_price`, then run the total through `deriveBundledPrice`. This only
  needs to appear when the package's `use_pricing_matrix` toggle (see §3) is
  on.
- **Checkout payment step**: since the real price can only be known once a
  pet (with weight/coat) is selected, either (a) resolve and display the
  matrix-adjusted per-pet price client-side using the same
  `resolveServicePrice`/`resolvePackagePrice` logic (there's already a
  precedent for a parallel client-side copy of this math — see the comment at
  [booking.service.ts:297-306](server/src/features/booking/services/booking.service.ts#L297-L306)
  and [CustomerBookingFlowPage.tsx:1141-1148](client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx#L1141-L1148)
  describing the existing downpayment-math duplication), once pet
  weight/coat is known at that point in the flow; or (b) keep it a rough
  estimate but make the disclaimer more specific ("final total confirmed
  after weight/coat check-in") and make sure `BookingDetailsPage`'s
  post-booking receipt is what customers are told is authoritative. (a) is
  more accurate but duplicates pricing logic client-side (already accepted
  practice here, per the downpayment precedent); (b) is a documentation-only
  fix.

## 2. Label for pricing-matrix / downpayment status per service in package create/edit

The service picker in
[`AdminPackageBuilderPage`](client/src/features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx#L709-L714)
uses `ServiceMultiSelect`, whose option sublabel currently shows only
`category - PHP base_price` (no mention of matrix or downpayment status).
Down in the same page's **package list row** (not the form), there's already
a working badge pattern for exactly this kind of label:

```tsx
// AdminPackageBuilderPage.tsx:774-785
<span className={styles.packageMeta}>
  PHP {pkg.bundled_price.toFixed(2)}
  {pkg.use_pricing_matrix ? " (varies by weight/coat)" : ""}
</span>;
{
  pkg.requires_downpayment && pkg.downpayment_amount !== null ? (
    <span className={styles.branchBadge}>
      {pkg.downpayment_type === "Percentage"
        ? `Requires ${pkg.downpayment_amount}% downpayment`
        : `Requires PHP ${pkg.downpayment_amount.toFixed(2)} downpayment`}
    </span>
  ) : null;
}
```

**Recommendation:** reuse this exact `branchBadge`/`packageMeta` span
pattern inside each `ServiceMultiSelect` option row (or its sublabel string)
for services, e.g. "Matrix pricing" when `service.use_pricing_matrix` is true,
and "Downpayment: 50%" / "Downpayment: PHP 500" when
`service.requires_downpayment` is true — mirroring the copy already used for
packages so the two surfaces read consistently.

## 3. Should the matrix/downpayment apply to the package's total, or only that service?

This is already a settled design decision in the existing calculation code,
not an open question — but it's worth writing down explicitly since the
package create/edit form doesn't currently let anyone act on it (see below):

- **Pricing matrix → applies per service**, already implemented as described
  in §1. A package's own `use_pricing_matrix` flag doesn't add a _second_
  pricing scheme on top — it's a switch that decides whether to honor each
  member's own matrix flag at all, or ignore all of them and use the flat sum.
- **Downpayment → applies at the package level, not decomposed from
  members.** [`createBooking`](server/src/features/booking/services/booking.service.ts#L836-L862)
  computes downpayment purely from the _item's own_ (service-or-package)
  `requires_downpayment`/`downpayment_amount`/`downpayment_type` — a
  package's downpayment is never summed from its member services' individual
  downpayment flags, and a downpayment-required item can't be combined with
  anything else in one booking
  ([booking.service.ts:800-812](server/src/features/booking/services/booking.service.ts#L800-L812)).
  Recommend **keeping it this way**: decomposing a package's downpayment into
  per-member contributions would conflict with that no-combine rule (which
  member's downpayment would "win," or would they all need to be paid
  separately?), and a single package-level downpayment is simpler for both
  the admin to configure and the customer to understand.

**The actual gap:** the DB columns for both flags already exist on
`packages` (`use_pricing_matrix` added in migration `20260807106`,
`requires_downpayment`/`downpayment_amount` in `20260808110`,
`downpayment_type` in `20260808112`) and are fully wired into booking-time
pricing — but
[`AdminPackageBuilderPage`'s form](client/src/features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx#L646-L753)
has **no fields for any of them**. They're only ever shown read-only in the
list row. Today, an admin can only set these by editing the database or seed
data directly — there's no in-app way to turn matrix pricing or a downpayment
on for a package at all.

**Recommendation:** before anything else in this doc, expose
`use_pricing_matrix` (a `ToggleSwitch`, same as the service form's
"Derive price from weight/coat matrix" toggle) and
`requires_downpayment`/`downpayment_amount`/`downpayment_type` (same
conditionally-revealed type-select + amount-input pattern already used at
[`AdminServicesPage.tsx:939-998`](client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx#L939-L998))
directly in the package form. Additionally, since `use_pricing_matrix` only
does anything when at least one selected member service also has its own
`use_pricing_matrix` on, consider **auto-checking (and locking, or at least
defaulting) the package's toggle** whenever such a member is present, rather
than leaving two independently-settable flags that can silently disagree —
today an admin could enable a service's matrix but never realize the
package-level flag also needs to be turned on for it to take effect.

## 4. Advanced section: gate service selectability by matrix/downpayment status

**No accordion/collapsible component exists anywhere in this codebase**
today (checked `client/src/shared/components/` and grepped for
Accordion/Collapsible/`<details>`/expand patterns — none found). The
established "progressive disclosure" idiom instead is a `ToggleSwitch`
conditionally rendering extra JSX inline, e.g. the downpayment
type/amount fields at
[`AdminServicesPage.tsx:939-998`](client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx#L939-L998).

**Recommendation:** don't introduce a new Accordion component for this alone
— there's no other evidence yet that this codebase needs general-purpose
collapsible sections, and one form section doesn't justify a new shared
component. Instead, add two `ToggleSwitch`es to the package form ("Allow
pricing-matrix services in this package" / "Allow downpayment services in
this package") that filter the `options` array passed into
`ServiceMultiSelect` — when off (the default), services flagged
`use_pricing_matrix`/`requires_downpayment` are excluded from the pickable
list entirely; when on, they become selectable (and would show the label
from §2). Per your note, these toggles should **only gate selectability** —
they must not themselves set the package's `use_pricing_matrix` /
`requires_downpayment` fields from §3; those stay governed by the package's
own explicit fields (and the auto-check-on-matrix-member behavior
recommended above), so a package can allow-list matrix services without
being forced into matrix pricing itself if none are actually selected.

## Recommended build order

If these get implemented, the natural order (each unblocks the next) is:
§3's form fields (`use_pricing_matrix`/downpayment on the package) → §2's
per-service labels (needs to distinguish matrix/downpayment services in the
picker) → §4's advanced-section toggles (needs the labels to filter on) →
§1's matrix breakdown preview + checkout accuracy fix (needs the toggle to
know when to render).

## Verification

Since this pass only produced this document, "verification" means confirming
the current-state claims above, not testing new UI:

1. Confirm the package form has no matrix/downpayment fields today: open the
   app as Admin/Superadmin, go to **Maintenance → Packages**, click **New
   package** or edit an existing one — note that Name, Branches, Active, and
   the service picker + bundle-discount % preview are the only fields; there
   is nothing for pricing matrix or downpayment.
2. Confirm the flags exist in the DB and are read-only in the UI: run the
   query in
   [package-pricing-recommendations.sql](package-pricing-recommendations.sql)
   against your Supabase project (SQL Editor) to see any packages/services
   that already have `use_pricing_matrix`/`requires_downpayment` set (from
   seed data), then find that same package in the Packages list — the
   "(varies by weight/coat)" / "Requires ... downpayment" badges should
   appear next to it, confirming those columns are read but not writable
   from the form.
3. Confirm the checkout flat-price behavior: as a customer, start a Grooming
   booking, add a pet, select a matrix-enabled Grooming service or a
   matrix-enabled package, and reach the **Payment** step — note the shown
   price is the flat `base_price`/`bundled_price` plus the static "may be
   adjusted" disclaimer, not a size/coat-specific number.
4. Confirm the server resolves the real price separately: complete that same
   booking, then open it from **Bookings** (or **Booking Details**) — compare
   `price_at_booking` shown there against the flat price you saw at checkout;
   for a pet whose weight/coat maps to a different matrix cell than the
   flat `base_price`, these two numbers should differ, demonstrating the gap
   described in §1.
5. Read through the cited file/line references above directly in the editor
   to confirm they still match this description before treating any of the
   recommendations as ready to implement (this doc is a snapshot of the
   codebase as of 2026-08-19).

## Suggested branch name

`docs/package-pricing-matrix-downpayment-recs`

(No code changes are proposed for this pass, so a branch is only needed if
you want this doc tracked/reviewed on its own before any implementation work
begins.)
