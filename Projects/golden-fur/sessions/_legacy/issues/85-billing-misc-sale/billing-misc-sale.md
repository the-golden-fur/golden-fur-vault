# Issue #85 Verification: miscellaneous sale entry backend

**Issue:** #85 — feat(billing): miscellaneous sale entry backend
**Owner:** Matthew
**Branch:** `feat/billing-misc-sale` (implemented here on the combined `feat/m08-billing-unified-catalog` branch)
**Base:** `dev`
**Depends on:** #82; the Unified Product Catalog change (`testing/docs/custom/17-unified-product-catalog`)
**Sprint:** Sprint 5 Epic A — M08 Sales & Billing

## Overview

Records a counter sale that isn't tied to any booking — `transactions.booking_id = NULL`, `transaction_type = 'miscellaneous_sale'`, enforced by #82's CHECK constraint — reusing the same credit-application code path as #84's checkout rather than duplicating it.

### Deviations from the original Guide, flagged for the reviewer

- **Item entry is catalog-driven, not free-text-only.** The original Guide specced Misc Sale as "free-text item label and peso amount... no SKU, stock count, or inventory management of any kind." Per an explicit user request during implementation, this is unified with M05's hotel food/medication catalogs into one shared `product_catalog` table (`testing/docs/custom/17-unified-product-catalog`) — the item picker shows every active catalog product across categories, snapshotting the catalog price server-side, **plus** a free-text fallback (description + manually entered amount) for anything not catalogued, preserving the original spec's flexibility for genuinely one-off items.
- **Full CRUD, not create-only** — per an explicit follow-up request during implementation. `listMiscSales`/`getMiscSale`/`updateMiscSale`/`deleteMiscSale` were added alongside `createMiscSale`. Create is open to every money-handling role (`BILLING_STAFF_ROLES`); update/delete are Admin/Superadmin only, enforced both at the route layer (`billing.routes.ts`) and by RLS (`transactions`/`transaction_line_items` policies in #82's migrations, scoped to Admin/Superadmin **and** `transaction_type = 'miscellaneous_sale'`). `updateMiscSale` recomputes `line_total`/`total_amount` server-side whenever the item shape changes, never trusting a client-supplied total.

## What Changed

- **Added** `server/src/features/billing/services/miscSale.service.ts` — `resolveItem` (catalog-vs-freetext resolution), `createMiscSale`, `listMiscSales`, `getMiscSale`, `updateMiscSale`, `deleteMiscSale`.
- **Modified** `server/src/features/billing/billing.controller.ts` / `billing.routes.ts` — misc-sale CRUD controllers/routes (shared files, also touched by #83/#84).
- **Modified** `server/src/features/billing/modules/validators/billing.validator.ts` — `createMiscSaleValidator`, `updateMiscSaleValidator` (shared file, also carries #84's `checkoutValidator`).

## Acceptance Criteria Map

| AC                                                                                                               | Automated                                                                                                                                 | Manual     |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AC-1 a miscellaneous sale is recorded with `booking_id = NULL`, correct `transaction_type`, description, amount  | manual — see step D2 (no dedicated `miscSale.service.spec.ts` was written given the batch's scope; test-coverage gap, same caveat as #84) | step D2    |
| AC-2 credit can be applied using the same atomic, overdraft-safe logic as a booking checkout                     | shares `creditStub.service.ts` with #84 — not meaningfully testable while credit is a stub (always 0)                                     | N/A (stub) |
| AC-3 miscellaneous sales are distinguishable from booking payments by `transaction_type` alone, no join required | schema-level, see #82's CHECK constraint verification                                                                                     | step D2    |

## Automated Verification

```powershell
npx tsc --noEmit
npx vitest run
```

Expected: typecheck clean, full suite passes (666/666 — see the Unified Product Catalog doc for the counts breakdown).

## Manual Verification

Import `billing-misc-sale.postman_collection.json` — fill in `cashier_identifier`/`cashier_password`, `admin_identifier`/`admin_password`, and `customer_id` (an existing `customer_profiles` row) before running.

### D. Steps

1. As Cashier, create a misc sale with a catalog item (`product_catalog_id` + `quantity`) — confirm `line_total = unit_price × quantity` and `transaction_type = 'miscellaneous_sale'`.
2. Create another with `description`/`amount` (freetext) — confirm it also records correctly, with `reference_id = null` on its line item.
3. As Cashier, attempt `PATCH`/`DELETE` on either sale — confirm 403.
4. As Admin, `PATCH` one (e.g. change `quantity`) — confirm the response's `line_total`/the transaction's `total_amount` are recomputed, not just the raw field echoed back.
5. As Admin, `GET /billing/misc-sale` — confirm both sales are listed. `DELETE` one — confirm 204 and it's gone from the list.

### E. Cleanup

Delete the remaining test sale from step 1 via `DELETE /billing/misc-sale/:id` as Admin.
