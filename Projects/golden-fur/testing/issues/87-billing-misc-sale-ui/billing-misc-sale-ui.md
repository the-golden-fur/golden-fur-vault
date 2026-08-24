# Issue #87 Verification: miscellaneous sale form UI

**Issue:** #87 — feat(billing): miscellaneous sale form UI
**Owner:** James
**Branch:** `feat/billing-misc-sale-ui` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** #85
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

A quick form for a counter sale that isn't tied to a booking, reachable independently of the booking-checkout flow. Reuses #86's `CreditApplicationPanel` and `PaymentMethodForm` as-is.

### Deviations from the original Guide, flagged for the reviewer

- **Item picker, not free-text-only** — mirrors #85's backend deviation. `MiscellaneousSaleForm` uses the Unified Product Catalog's `CatalogComboBox` (`testing/docs/custom/17-unified-product-catalog`) fed by every active catalog product across categories, plus a freetext fallback (description + manually entered amount) when nothing matches.
- **Customer picker added** — the original Guide's file list didn't call one out, but #82's schema requires `transactions.customer_id` even for a miscellaneous sale (denormalized, no `booking_id` to derive it from). `MiscellaneousSaleForm` reuses the existing `features/booking/components/CustomerPicker` as-is rather than building a new one.
- **`MiscSaleManagementPage` added** — per the same explicit full-CRUD follow-up request noted in #85's doc. Admin/Superadmin-only list of recorded misc sales with inline edit (description/amount) and delete, at `/staff/admin/misc-sales`. Not literally "reopens `MiscellaneousSaleForm` pre-filled" as originally sketched during planning — a simpler direct inline-edit-row pattern (mirroring `CatalogAdminPage`'s own edit-row UX) was used instead, since teaching the create form a second "edit mode" would have doubled its complexity for the same net capability.

## What Changed

- **Added** `client/src/features/billing/components/MiscellaneousSaleForm/MiscellaneousSaleForm.tsx` (+CSS module) — customer picker, catalog/freetext item picker + quantity, reused `CreditApplicationPanel`/`PaymentMethodForm`/`PayMongoServiceFeeNotice`.
- **Added** `client/src/features/billing/pages/MiscellaneousSalePage/MiscellaneousSalePage.tsx` (+CSS module) — thin page wrapper, registered at `/staff/billing/misc-sale`.
- **Added** `client/src/features/billing/pages/MiscSaleManagementPage/MiscSaleManagementPage.tsx` (+CSS module) — Admin/Superadmin CRUD list, registered at `/staff/admin/misc-sales` (see deviation above).
- **Modified** `client/src/features/billing/billing.routes.tsx` — registers both new pages (shared file, also carries #86's `CashierCheckoutPage` route).
- **Modified** `client/src/pages/SettingsPage/tabs/ConfigTab.tsx` — added a "Miscellaneous Sales" tile linking to `/staff/admin/misc-sales` (shared file, also carries the Unified Product Catalog's tile rename).

## Acceptance Criteria Map

| AC                                                                                                     | Automated                                                                                             | Manual  |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- | ------- |
| AC-1 the form captures a freetext item description and peso amount, and submits successfully           | not covered by an automated component spec (same test-coverage gap as #86, flagged)                   | step D2 |
| AC-2 credit application and payment method forms behave identically to the booking checkout flow (#86) | shared components (`CreditApplicationPanel`/`PaymentMethodForm`) — no divergent logic by construction | step D3 |

## Automated Verification

```powershell
npx tsc -b
npx eslint .
npx vitest run
```

Expected: typecheck clean, lint clean, full client suite passes (508/508 — see the Unified Product Catalog doc).

## Manual UI Verification

### Prerequisites

- Server + client running, migrations applied.
- A Cashier (or higher) login, an existing customer to pick.

### D. Steps

1. Go to `/staff/billing/misc-sale`. Pick a customer via the picker.
2. Pick a catalog item with quantity 2 — confirm subtotal is `price × 2`. Submit with Cash — confirm success and `transaction_type = 'miscellaneous_sale'` (AC-1).
3. Start a new sale, type a description not in the catalog and an amount — confirm the freetext fallback works. Confirm the credit panel and payment form behave identically to `CashierCheckoutPage` (AC-2).
4. As Admin, go to `/staff/admin/misc-sales` (Settings → Config → Miscellaneous Sales). Confirm both sales are listed. Edit one's description/amount inline, save, confirm it updates. Delete the other, confirm it's removed.
5. As a Cashier (non-Admin), confirm `/staff/admin/misc-sales` still loads the page shell but `PATCH`/`DELETE` calls made directly (bypassing the UI) are rejected server-side (403) — the client-side role gate matches `ProductCatalogPage`'s own pattern.

### E. Cleanup

Delete any remaining test sales via the management page.
