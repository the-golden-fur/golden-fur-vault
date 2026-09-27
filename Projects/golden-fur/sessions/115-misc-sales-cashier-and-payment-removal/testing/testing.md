# Cashier Misc Sales page + removing the PayMongo online-payment pipeline

Branches:

- Stage A: `chore/remove-paymongo-online-payments` (PR [#208](https://github.com/the-golden-fur/golden-fur/pull/208), merged into `dev`)
- Stage B: `feat/cashier-misc-sales-page` (PR [#210](https://github.com/the-golden-fur/golden-fur/pull/210), draft, branched fresh off `dev` after #208 merged) - commit `5adbc78` "feat(billing): give the Cashier their own Miscellaneous Sales page"
- Stage C: same branch and PR as Stage B, commit `9f7b086` "feat(billing): rebuild Misc Sale creation as a booking-style step wizard" - not yet pushed to `origin/feat/cashier-misc-sales-page` as of this update, so PR #210's diff on GitHub doesn't reflect it yet

## The request, verbatim

> As a developer, I want misc sales to be moved out of admin settings, to cashier's sidebar as a page
>
> - As a cashier, I want CRUD access to misc sales (I can create new sales via a button that opens a form, and view a history of such sales in my transactions page)
> - As an admin/superadmin, I want CRUD access to both misc sales and misc items, where I can create new misc items cashiers can choose from
>
> Always include the shared search, sort, filter, group by and view options
>
> Also remove all traces of online payment
>
> - We're switching to just having gcash and paymaya as payment methods, not actual online payment processes

**Scope note:** this landed as two sequential stages on two branches rather than one, because `dev` moved (merging #208 and another unrelated PR) between the two - Stage B branches fresh off the post-merge `dev` instead of rebasing a now-closed branch. See `plan.md` for the full reasoning on why Stage A (remove online payments) had to go before Stage B (build the Cashier page) rather than the other way around.

**Stage C follow-up request, verbatim:**

> update how new misc sales look like, make it look like the booking step wizard, add steps to it: first is customer (auto filtered, same branch only, no more branch step), then the product chooser (multiple products can be chosen), then the promo/discount step, then payment method step, then confirmation step

Once Stage B's single-item "New Misc Sale" modal was live, the ask changed to: model it after the booking flow's own step wizard, support multiple products in one sale, and add a real discount/promo step. This is still the same branch/PR as Stage B - not a new session.

## Context / what existed before

Before this session, "misc sales" (a counter sale with no booking attached, e.g. selling a bag of dog food) lived in two disconnected places: a creation form at `/staff/billing/misc-sale` that nothing in the app linked to, and an Admin/Superadmin-only list under Settings > Config with no search/sort/filter tooling. Separately, GCash and Maya were wired to a real payment processor (PayMongo) that the business never actually provisioned a merchant account for - the whole webhook/checkout-redirect/fee-notice/online-toggle pipeline was live code with no real payment ever flowing through it.

By the time Stage B shipped, "New Misc Sale" was a single popup form (`MiscellaneousSaleForm`) with exactly one item (a catalog product with a quantity, or a typed description + amount) and one payment method - no discounts, no promos, and editing a recorded sale meant typing directly into the list's own table cells. Stage C replaces that form with a 5-step wizard and a real multi-item cart, and gives misc sales real discounts/promos for the first time.

## What changed

### Database

- `supabase/migrations/20260927216_custom_remove_online_payment_columns.sql` (Stage A) - drops `transactions.webhook_confirmed_at`, `transactions.initiated_by`, and `policy_configurations.online_payments_enabled`. No migration in Stage B (client-only change).
- `supabase/migrations/20260927217_custom_discounts_add_misc_sale_scope.sql` (Stage C) - adds `'misc_sale'` as a fourth allowed value of `discounts.scope_type` (alongside `'service'`, `'package'`, `'category'`), and updates the `discounts_scope_matches_type` CHECK constraint so a `misc_sale`-scoped discount requires `scope_service_id`/`scope_package_id`/`scope_category` to all be NULL - mirrors how a promo's `'all_services'` scope needs no further scoping. Deliberately a new, isolated scope value rather than adding `'Miscellaneous Sale'` to the shared `service_category` enum, which also drives the category dropdown on real bookable services. See `misc-sales-cashier-and-payment-removal.sql` in this folder for reference copies of both migrations.

### Server (Stage A and Stage C only - Stage B touched no server code)

Stage A:

- Deleted the PayMongo service, its webhook route, and `webhookConfirmation.service.ts`; removed their registration in `app.routes.ts`/`app.ts`.
- `paymentMethod.service.ts`'s `resolvePaymentConfirmation()` now confirms every payment method (including GCash/Maya) immediately - no more "stay Pending until the webhook fires" branch.
- Deleted the checkout-redirect calls in `miscSale.service.ts` and `checkoutAggregation.service.ts`, and the `paymongoCheckoutUrl` response field everywhere it appeared.
- Deleted the customer portal's self-service "pay via GCash/Maya online" flow (`payForBooking`, `POST /bookings/:id/pay`) outright - a remote customer has no cashier to confirm a QR scan; account credit remains their self-service option.
- Deleted the `GET /billing/paymongo/fee-rate` endpoint and the `online_payments_enabled` policy toggle (server + validator).
- Moved `addCustomerBalancePayment` out of the deleted `customerBookingPayment.service.ts` into `transactionPayment.service.ts` (it's a credit/manual-balance helper, unrelated to PayMongo).

Stage C:

- `server/src/features/billing/modules/validators/billing.validator.ts` rewritten: `createMiscSaleValidator` now takes `items: MiscSaleItem[]` (min 1, each the same hybrid catalog-or-freetext shape as before, just repeatable) plus `senior_citizen_eligible`/`pwd_eligible`, instead of a single `product_catalog_id`/`description`/`amount`. New `previewMiscSaleValidator` (cart + `payment_method` + eligibility, no customer/payment-reference fields - just what the live preview needs). `updateMiscSaleValidator` is narrowed to payment fields only (`payment_method`/`bank_name`/`payment_reference`) - a deliberate scope cut, not an oversight, now that a sale can carry more than one `transaction_line_items` row.
- `server/src/features/billing/services/discountPromoEvaluation.service.ts`: two new functions, `evaluateMiscSaleDiscounts` (misc-sale counterpart of `evaluateDiscounts` - Cash-only gate, Senior/PWD eligibility gate, branch-availability filtered, matches only the new `scope_type = 'misc_sale'` discounts) and `evaluateMiscSalePromos` (thin wrapper around the existing `evaluatePromos`, passing `items: []` since only an `'all_services'`-scoped promo can ever match a misc sale). `evaluatePromos`'s own parameter type was loosened to `Pick<BookingForBilling, 'branch_id' | 'items'>` so this wrapper doesn't need to fabricate a whole fake booking.
- `server/src/features/billing/services/miscSale.service.ts` fully rewritten around a preview-then-create split, mirroring `buildCheckoutPreview`/`checkoutBooking`: new `buildMiscSalePreview` resolves every cart item, runs the two new discount/promo evaluators, and returns item/discount/promo lines plus a `preCreditTotal`; `createMiscSale` calls it and inserts one `transaction_line_items` row per item/discount/promo line (previously exactly one row, always `misc_sale_item`); a new `summarizeDescription` helper joins the resolved items' descriptions into the one `transactions.misc_sale_description` text column (e.g. "Dry Kibble x2, Leash") since that column's shape didn't change; `updateMiscSale` no longer touches line items at all, only the transaction's payment fields.
- `server/src/features/billing/billing.controller.ts` / `billing.routes.ts`: new `POST /billing/misc-sale/preview` route + `previewMiscSaleController`, `requireBranch`-gated like the checkout preview. Code-review fix in the same commit: `GET /billing/misc-sale` was missing `requireBranch` entirely, and `listMiscSalesController` trusted (or ignored) a client-supplied `branch_id` query param with no fallback - any authenticated staff member could see every branch's misc sales. Now mirrors `transactionHistoryController`'s pattern: Superadmin may pass `branch_id` to see any branch or omit it to see all; every other role is always forced to their own `req.user.branch_id`.
- `server/src/features/discounts/discounts.types.ts` and `server/src/features/discounts/modules/validators/discounts.validator.ts`: `DiscountScopeType` gains `'misc_sale'`; `validateScopeShape` now treats `misc_sale` as needing **zero** scope fields set (every other scope type still needs exactly one).

### Client

Stage A:

- Removed the cashier's "Customer portal vs. Scan QR at counter" channel choice from `PaymentMethodForm.tsx` - GCash/Maya now just show the same reference-number field Card/Bank Transfer already do.
- Removed the PayMongo fee-notice banners, the customer portal's GCash/Maya pay option (`CustomerTransactionHistoryPage.tsx` - account credit is now the only self-service option there), and the admin "online payments enabled" toggle (`PolicyConfigurationPage.tsx`).
- Hardened a pre-existing flaky test in `DailySalesReportPage.spec.ts` (unrelated file, found while fixing this PR's CI) and fixed a `Format Check` failure on 3 files.
- Separately: removed the `.claude/hooks/free-dev-ports.sh` Stop hook (was force-killing the developer's own manually-started dev servers after every Claude Code turn) and hardened `scripts/free-ports.mjs`'s `predev` check to only free a port that isn't actually answering requests.

Stage B:

- `MiscSaleManagementPage.tsx` rewritten from a bare Admin/Superadmin-only bullet list into the shared page every money-handling role (Cashier included) reaches from their own sidebar, using the same `FilterSortBar` + `ViewSwitcher` + `useGroupBy` + `DataTable`/`DataBoard` toolbar the rest of the app uses (`CatalogAdminPage.tsx`'s pattern). New `miscSaleBrowserFields.ts` defines the filter/sort/group-by rules (payment method, status, date range, customer).
- "New Misc Sale" now opens as a modal on this page (reusing `MiscellaneousSaleForm`, stripped of its now-redundant heading/card chrome) instead of navigating to the old, unlinked `/staff/billing/misc-sale` route - that page and route are deleted.
- Edit/Delete stay visible only to Admin/Superadmin inside the page; every viewer gets a "View in Transactions" link.
- Added a "Miscellaneous Sales" tile to the Cashier's sidebar and to the mirrored Cashier section of the Admin/Superadmin dashboard (`staffDashboard.config.ts`); removed the old tile from Settings > Config (`configTiles.config.ts`) - the "Product Catalog" tile (misc _items_, unchanged) now notes it's also where a cashier's item picker draws from.

Stage C - **`MiscellaneousSaleForm` is deleted outright**, replaced by a new `client/src/features/billing/components/MiscSaleWizard/` folder:

- `MiscSaleWizard.tsx` drives 5 steps (Customer, Products, Discount/Promo, Payment, Confirmation) using `BookingStepper` (unchanged except a new optional `ariaLabel` prop, defaulting to `"Booking steps"` so every existing caller is unaffected - the wizard passes `"Miscellaneous sale steps"`). It live-previews the cart via the new `previewMiscSale` API call every time the items, payment method, or Senior/PWD checkboxes change, so the Discount/Promo and Confirmation steps always show a real, current total.
- `CustomerStep.tsx` - reuses `CustomerPicker` as-is; there is no branch step because a misc sale is always recorded at the cashier's own branch (server-derived via `requireBranch`, never client-chosen).
- `ProductsStep.tsx` + `miscSaleCart.ts` - multiple rows, each a `CatalogComboBox` (catalog product + quantity) or freetext (description + amount), with an "Add another item" button and a live subtotal. `miscSaleCart.ts` holds the `CartRow` shape, per-row/cart validity checks, and `buildMiscSaleItems` (converts valid rows into the `MiscSaleItem[]` the API expects, silently dropping an in-progress empty row).
- `DiscountPromoStep.tsx` - Senior Citizen/PWD checkboxes (same auto-apply-by-scope model `CashierCheckoutPage` already uses, not a manual code field) plus the live-previewed discount/promo lines and running total; a note that government-mandated discounts only apply when paid in Cash.
- `PaymentStep.tsx` - unchanged `CreditApplicationPanel`/`PaymentMethodForm`, just relocated onto their own step.
- `ConfirmationStep.tsx` - shows the same live preview (now reflecting whichever payment method was actually picked - a Cash-only discount can appear or disappear versus what Discount/Promo showed), item/discount/promo lines, credit applied, and the final amount due, with the "Confirm & record sale" button and the post-submit success banner.
- `MiscSaleManagementPage.tsx`: "New Misc Sale" now opens `MiscSaleWizard` instead of the deleted `MiscellaneousSaleForm`, and no longer auto-closes the modal on success (the wizard's own Confirmation step shows the result and its own Close button). The old inline "type into the table cell, Save/Cancel" editing is replaced by a small **"Edit payment method"** modal (payment fields only, reusing `PaymentMethodForm` with its `hideCashTendered` option) - consistent with the server validator narrowing. Two code-review fixes landed in the same commit: a customers-list load failure now shows a real error banner instead of every row silently reading "Unknown customer"; and a new `TRANSACTION_HISTORY_ROLES` set (`Superadmin`/`Admin`/`Supervisor`/`Cashier`) hides the "View in Transactions" menu item for Receptionist specifically, since the server's transaction-history endpoint doesn't allow that role and it used to 403 on click.
- `AdminDiscountManagementPage.tsx` + `discountBrowserFields.ts`: the scope-type dropdown, filter options, and scope-summary/label helpers all gained a `"Miscellaneous Sale"` / `misc_sale` option, shown as "Any miscellaneous sale" in the discount list.

## Manual test - step by step

Assume the reader does not know how to navigate this app.

### Scenario A - Cashier records a misc sale through the new wizard (Stage C, supersedes the old single-modal steps)

1. Open `http://localhost:5173` and log in as a **Cashier**-role staff account.
2. In the left sidebar, click **Miscellaneous Sales** (a new tile, between "Checkout & Billing" and "Transactions"). You should land on a page headed **Miscellaneous Sales** with a search bar, Filter/Sort buttons, and a Table/Board switcher at the top.
3. Confirm no **Edit** or **Delete** buttons appear on any row - only a "..." menu with **View in Transactions**.
4. Click **New Misc Sale** (top right). A popup opens showing a step bar across the top with five steps: **Customer**, **Products**, **Discount/Promo**, **Payment**, **Confirmation**. You're on **Customer**.
5. Pick a customer from the list shown (there is no branch to choose - only customers at your own branch are offered). Click **Next**. You should now be on **Products**, and clicking the **Customer** step in the bar above should let you jump back to it.
6. On **Products**, search for a real catalog product and pick it (a **Quantity** box should appear next to it, defaulting to `1`) - or instead type a custom item name into the same search box and enter an **Amount** (e.g. "Dog leash", `250`). Click **Add another item** and add a second item the same way. Confirm a running **Subtotal** at the bottom adds both items together, and confirm **Next** stays disabled if any row is left incomplete.
7. Click **Next** to reach **Discount/Promo**. If your dev database has an active discount scoped to Miscellaneous Sale, it should already be listed with a running total below the subtotal (no code to type in - discounts/promos apply automatically the same way checkout's do). Tick **Senior Citizen** or **PWD** if testing a mandated discount - a note reminds you these only apply when paying in Cash.
8. Click **Next** to reach **Payment**. Choose **GCash** as the payment method and confirm there is no "Customer portal / Scan QR" choice - just a reference-number field, exactly like Card. Type any reference number.
9. Click **Next** to reach **Confirmation**. Confirm every item you added is listed with its price, any discount/promo line is shown, the payment method is shown, and a final **Amount due** total is shown. Click **Confirm & record sale**.
10. The step should show "Sale recorded - Fully Paid." immediately - no redirect to any external checkout page. Click **Close**; the new sale should now appear at the top of the list, and its **Description** column should list every item you added (e.g. "Dry Kibble x2, Dog leash").
11. Click **Transactions** in the sidebar - the same sale should appear there too, filterable by "Miscellaneous sale".

### Scenario B - Admin/Superadmin has full control, editing is now payment-only (Stage B, edit flow updated in Stage C)

1. Log in as an **Admin** or **Superadmin** account. The sidebar's **Cashier** section (grouped under their own dashboard) also shows **Miscellaneous Sales**.
2. Open it - the same sales list now shows **Edit** and **Delete** buttons per row. Click **Edit** on a sale - a popup titled **Edit payment method** opens, showing only the payment method/bank/reference fields (no item, amount, or description fields - those can no longer be edited after the fact). Change the payment method and click **Save**; confirm it saves and the popup closes.
3. Click **Delete** on a sale and confirm it disappears from the list.
4. Go to **Settings > Config** - confirm **Miscellaneous Sales** is no longer listed there. **Product Catalog** is still present and unchanged.

### Scenario C - a misc_sale-scoped discount auto-applies, and only for Cash (Stage C)

1. Log in as **Admin** or **Superadmin** and open **Discount Management**. Click **New Discount**, fill in a name (e.g. "Counter Sale Flat Discount"), a **Flat** value (e.g. `50`), pick your branch(es), and for **Scope**, pick the new **Miscellaneous Sale** option (previously only Service/Package/Category were offered). Save it - the list should show it with a scope summary of "Any miscellaneous sale".
2. Log in as **Cashier** and open **Miscellaneous Sales > New Misc Sale**. Add any item(s) on **Products**, reach **Discount/Promo**, and on **Payment** pick **Cash** - go back to **Discount/Promo** (or check **Confirmation**) and confirm the discount you just created is listed and subtracted from the running total.
3. Go back to **Payment** and switch to **GCash** instead - confirm the discount line disappears from the total (Senior/PWD and other Cash-only discounts only ever apply when paying in Cash).
4. As cleanup, deactivate the test discount's branch availability (or archive it) so it doesn't affect real sales going forward.

### Scenario D - a branch-scoping bug is fixed on the misc sales list (Stage C)

1. As a Superadmin, note that two branches (Makati and Southwoods) each have at least one misc sale on record.
2. Log in as a **Cashier** or **Receptionist** scoped to one specific branch (not Superadmin) and open **Miscellaneous Sales**. Confirm every sale shown belongs to your own branch only - previously (before this fix), this list silently showed every branch's sales to any logged-in staff member regardless of their own branch.
3. As a **Superadmin**, confirm you can still see all branches' sales (or filter to one specific branch, if the page exposes that).

### Scenario E - online payment is really gone (Stage A)

1. As any staff role, open **Checkout & Billing** (or the Transactions page's "Mark as paid" modal) and pick **GCash** as the payment method. Confirm there is no "Customer portal / Scan QR" choice - just a reference-number field, exactly like Card.
2. As a customer (portal login), open **Transaction History** and click **Pay** on a Pending charge - confirm the only option offered is paying with account credit, no GCash/Maya button.
3. As an Admin/Superadmin, open **Policy Configuration** (Settings > Config > Branches > a branch's Configure, or the old `/staff/admin/maintenance/policies` link) - confirm the "Online payments" checkbox section is gone entirely.

See `misc-sales-cashier-and-payment-removal.postman_collection.json` in this folder for the API-level checks (misc_sale discount scope, cart preview, multi-item creation, Cashier 403 on edit/delete, Admin payment-only edit, and confirming `/billing/paymongo/*` now 404s) rather than repeating every request here.

## Test suites

**Stage A** (branch `chore/remove-paymongo-online-payments`, before merge):

- Server: `npm run test` - 107/107 files, 1206/1206 passing; `npx tsc --noEmit -p .` clean.
- Client: `npx tsc -b` clean; `npm run test` - 217-221/219-222 files passing across several runs (varying only by 2 known pre-existing/environmental flakes - see below), 0 failures attributable to this branch.
- CI (`gh pr checks 208`, final run after the format/flake fixes): Client Build, Client Lint, Client Tests, Format Check, Server Build, Server Lint, Server Tests, Vercel - all pass.

**Stage B** (branch `feat/cashier-misc-sales-page`, commit `5adbc78`):

- Server: unaffected (client-only change) - re-verified 107/107 files, 1206/1206 tests, clean `tsc`.
- Client: `npx tsc -b` clean; `npm run test` - 221/222 files, 1315/1318 tests passing. New specs `MiscSaleManagementPage.spec.ts` (8 cases, incl. the full create-modal flow end to end) and `miscSaleBrowserFields.spec.ts` (8 cases) both pass in full.
- CI (`gh pr checks 210`): Client Build, Client Lint, Client Tests, Format Check, Server Build, Server Lint, Server Tests, Vercel - all pass.

**Stage C** (same branch/PR, commit `9f7b086`, run 2026-09-27 as part of this vault update - not yet pushed to `origin`, so `gh pr checks 210` doesn't reflect it):

- Server: `npm run test` - 109/109 files, 1236/1236 passing; `npx tsc --noEmit` clean. New/extended specs all pass: `billing.validator.spec.ts` (new, 12 tests), `miscSale.service.spec.ts` (new, 9 tests), `discountPromoEvaluation.service.spec.ts` (extended, 12 tests), `discounts.validator.spec.ts` (extended, 16 tests).
- Client: `npx tsc -b` clean; `npm run test` - 221/223 files, 1326/1330 tests passing. The 2 failing files/4 failing tests are the same pre-existing, unrelated flakes documented below (confirmed the diff touches neither file); every billing-feature spec passes in full, including `MiscSaleManagementPage.spec.ts` (rewritten for the wizard create-flow and modal edit-flow), the new `miscSaleCart.spec.ts`, and `miscSaleBrowserFields.spec.ts`.
- Billing-scoped client run (`npx vitest run src/features/billing`): 5 files, 36 tests, all passing.
- Billing-scoped server run (`npx vitest run` on `miscSale.service.spec.ts` + `discountPromoEvaluation.service.spec.ts` + `discounts/**`): 5 files, 59 tests, all passing.
- CI (`gh pr checks 210`): not yet re-run for this commit - see Open items below.

**Known pre-existing flakes, unrelated to this session's changes** (confirmed via repeated isolated re-runs and by checking the actual diff touches neither file):

- `staffAuth.api.spec.ts` fails only on this developer's own machine, because their local `client/.env` sets `VITE_API_BASE_URL` (not present in CI, so this never fails there).
- `VeterinaryConsolePage.spec.ts` and `DailySalesReportPage.spec.ts` showed one-off, order/timing-dependent failures during Stage A's local test runs; `DailySalesReportPage.spec.ts`'s two affected assertions were hardened with `waitFor` as part of Stage A's CI-fix commit (an unrelated file touched only because it was the one CI actually flagged - see PR #208's `fix(ci)` commit). `VeterinaryConsolePage.spec.ts` reproduced the same known flake again during Stage C's full-suite run (one modal-confirmation timing assertion) - unrelated to any file this session touched.

## Open items

- No manual browser click-through was performed by the AI session itself for any stage - the steps above are written for a human (or a future session) to actually run through before merging PR #210.
- `npm run lint` was not run repo-wide this session; only the specific changed files were linted (clean).
- Stage C's commit (`9f7b086`) has not been pushed to `origin/feat/cashier-misc-sales-page` yet, so PR #210's diff and CI checks on GitHub don't reflect it - push and re-run `gh pr checks 210` before merging.
- Scenario C/D in the manual test above (misc_sale discount scope, branch-scoping fix) need real seeded discount/branch data in a dev environment to walk through by hand; not covered by an automated end-to-end browser run.
