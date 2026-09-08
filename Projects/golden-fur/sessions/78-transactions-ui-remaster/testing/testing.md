# Transactions UI remaster — Customer column, Notion-style filter/sort tiles, Table + Board views

Branch: `feat/transactions-ui-remaster` (golden-fur). No vault branch — this
record is committed straight to the vault's working branch.

## The request, verbatim

> Remaster cashier > transactions UI:
>
> - Currently they cannot see transaction owners
> - Add col that specifies the customer
> - The filters and sort are too complex
> - Reduce it to 1 sort and filter controls, adding sorts/filters creates
>   round tiles like in Notion (you may look it up)
> - Each sort/filter tile instance can be removed via X button on hover
> - read Projects\golden-fur\shared\context\Architectural-Change-History.docx
>   for full context
> - perhaps add different views for it too, but default table — you can think
>   of other views like those in Notion

Decisions taken with the requester during planning: ship **Table + Board**
(no calendar this pass); Board grouping **fixed to payment status**; remaster
**both** the cashier page and the customer portal page.

## Root cause / Context

`/staff/reports/transaction-history` (component
`client/src/features/reports/components/TransactionHistoryTable/`) and its
customer twin `/portal/transactions` (`CustomerTransactionHistoryPage`) each
rendered a hand-rolled `<table>` under **nine** always-visible controls
(search box, sort `<select>`, "Due payments only" checkbox, plus
customer / pet / date-from / date-to / service / transaction-type /
payment-choice `<select>`s). The two pages share one CSS Module,
`TransactionHistoryTable.module.css`.

The `transactions` table stores `customer_id` (NOT NULL FK to
`customer_profiles.id`) but the list endpoint never resolved the name, so no
"Customer" column was possible without a change.

The repo already had a partial "Notion-style" toolkit —
`QueueFilterBar` + `SearchSortBar` + `ActiveFilterChips` (used by ~24 queue
pages) — but those chips are display-only (click = clear), not editable
value-bearing tiles, and the bar is not one-button-per-facet. Rather than bend
that shared set, this session adds a new `FilterSortBar` designed as its
eventual superset; **no other page was migrated** (documented follow-up).

## What changed

### Database

None. `transactions.customer_id` already exists and is indexed
(`transactions_customer_id_idx`, migration `20260731068`).

### Server

- **`server/src/features/reports/services/transactionHistory.service.ts`** —
  after the existing query resolves, collect the distinct `customer_id`s and
  resolve their names in **one** batched query
  (`customer_profiles.select('id, full_name').in('id', ids)` → `Map`), then
  attach `customer_name: string | null` to every row. This mirrors the
  established pattern in `bookingDetails.service.ts` and
  `messaging.service.ts` — a separate lookup, never a PostgREST FK embed. The
  service uses the service-role client, so **archived** customers still
  resolve. `!inner`/left-join logic and the selected `bookings(...)` columns
  are unchanged. Return type is now `TransactionHistoryRecord[]`.
- **`server/src/features/reports/reports.types.ts`** — new
  `TransactionHistoryRecord extends Transaction { customer_name: string | null }`.
  Billing's `Transaction` type is untouched.
- Both controllers (`transactionHistoryController`,
  `customerTransactionHistoryController`) — no code change; both endpoints now
  emit `customer_name`.

### Client

**New shared components**

- **`client/src/shared/components/FilterSortBar/`** —
  `filterField.types.ts` (the `FilterField` / `FilterValue` / `FilterTile` /
  `SortFieldDescriptor` / `SortTile` descriptor model — `select`,
  `async-select`, `date-range` field types),
  `FilterTile.tsx` (the pill: two sibling buttons — a body that opens a
  `role="dialog"` popover editor, and an ✕ that is `opacity:0` → shown on
  `.tile:hover` **and** `:focus-visible`, forced visible under
  `@media (hover:none)`; closes on outside-click / Escape),
  `FilterSortBar.tsx` (persistent search box + a **Filter** dropdown +
  a **Sort** dropdown + the tile row + a right-edge `children` slot;
  dropdown open/close copied from `MoreOptionsMenu`'s idiom).
  Fully controlled — the page owns `filterTiles` / `sortTile`.
- **`client/src/shared/components/ViewSwitcher/`** — generic segmented
  control (`aria-pressed`), used for Table / Board.

**New, co-located with the table**

- **`transactionFilterFields.ts`** — the staff & customer field/sort
  descriptor sets, plus pure mappers: `deriveServerParams(tiles)` →
  `getTransactionHistory` query params, `deriveStatusFilter(tiles)` → DB
  `payment_status` (client-side), `deriveSortKey(sortTile)` +
  `COMPARATORS` (the original 4 comparators verbatim + `customer-az/za`).
- **`transactionDisplay.ts`** — shared `paymentChoiceLabel` /
  `transactionTypeLabel` / `paymentStatusLabel` (previously duplicated inline
  in both pages).
- **`TransactionBoard.tsx`** (+ `.module.css`) — fixed 3 columns by payment
  status, reusing `PaymentStatusBadge context="billing"`; empty column shows
  "Nothing here."; card = headline (customer name, or the type on the portal
  where `showCustomer={false}`) + amount + type·service + date·choice·method,
  with the same `MoreOptionsMenu` (staff) / Pay button + card-click-to-details
  (portal). No whole-card click on staff.

**Rewired pages**

- **`TransactionHistoryTable.tsx`** — the two `.filters` rows, `SearchSortBar`,
  `useSearchAndSort`, `pendingOnly`, and the 8 scalar filter states are
  replaced by `filterTiles` / `sortTile` / `view` state + `FilterSortBar` +
  `ViewSwitcher`. Server refetch keyed on
  `JSON.stringify(deriveServerParams(filterTiles))` so a client-only tile
  (Status) or a sort change does **not** round-trip. New **Customer** column
  (2nd). Removing the Customer tile cascades away the Pet tile; Pet is only
  offered in the Filter menu once a Customer tile exists. Both modals,
  `payableBalances`, `listStaff`/`listCustomers`/`listCustomerPets` effects,
  and RBAC are unchanged. Amount cell keeps `PHP {n.toFixed(2)}` (the board
  uses `formatCurrency` → `₱`).
- **`CustomerTransactionHistoryPage.tsx`** — same treatment with
  `CUSTOMER_FILTER_FIELDS` (date / service / payment / status) and
  `CUSTOMER_SORT_FIELDS` (date / amount). Existing behaviour preserved:
  row/card opens `BookingDetailsModal`; the credit / GCash / Maya pay modal;
  `addBalancePaymentForBooking`; `notifyCreditBalanceChanged()`.
- **`client/src/features/reports/reports.types.ts`** — `customer_name:
string | null` on `TransactionRecord`. `reports.api.ts` unchanged (generic
  body parse). `RecentTransactionsWidget` unchanged (additive field).

## Manual test — step by step

Assumes the dev servers are up (client `http://localhost:5173`, server
`:3000` — start both with `npm run dev` from the `golden-fur` repo root).

### A. Cashier — Customer column + filter tiles (Table)

1. Open a browser at `http://localhost:5173/staff/login`.
2. In **Username or email** type `makati.cashier1@goldenfur.com`, in
   **Password** type `password123`, click **Sign in**. You land on a page
   headed **Cashier** dashboard. (Red banner instead → dev server / seed not
   ready.)
3. In the left sidebar click **Transactions**. You land on a page headed
   **Transactions** with a table.
4. **Check:** the table's 2nd column header reads **Customer**, and every row
   shows a name (e.g. "Customer 1"), not a blank or a UUID. Failure: no
   Customer column, or the cell is empty / shows a long id.
5. Above the table there is exactly one **Search** box, one **Filter ▾**
   button, one **Sort ▾** button, and a **Table / Board** toggle on the right.
   Failure: a row of many dropdowns is still there.
6. Click **Filter**. A menu lists Customer, Pet (greyed out), Date, Service,
   Transaction type, Payment, Status. Click **Status**.
7. **Check:** a rounded tile appears reading **`Status: Due payment`**, and the
   table now shows only rows whose Status column reads "Due payment". Failure:
   no tile, or the table did not filter.
8. Move the mouse over the tile. **Check:** an **✕** appears at its right
   edge. Click it. The tile disappears and all rows return. Failure: no ✕ on
   hover, or clicking it does nothing.
9. Click **Filter → Service**, then in the tile's popup pick **Grooming**.
   Open the browser dev-tools Network tab and confirm the request to
   `/reports/transaction-history` now carries `service_category=Grooming`.
10. Click **Filter → Customer**, pick a customer in the popup list. **Check:**
    "Pet" is now selectable in the **Filter** menu. Remove the Customer tile
    via its ✕ — any Pet tile is removed with it.
11. Click **Sort → Amount · High to low**. **Check:** a `Sort: Amount (High to
low)` tile appears and the Amount column is now descending.
12. Type part of a payment method / status / customer name in the **Search**
    box — rows filter live.

### B. Cashier — Board view

1. On the same page click **Board** (top-right toggle).
2. **Check:** three columns — **Due payment**, **Partially Paid**, **Fully
   Paid** — each with a count; cards show the customer name + amount; an empty
   column reads "Nothing here." Any filter/sort tiles from part A still apply.
3. On a card click the **⋮** menu → **View booking**. **Check:** you navigate
   to that booking's detail page. Back, then **⋮ → Pay** on a Due-payment card
   opens the **Mark as paid** modal (unchanged behaviour — the cash box is
   pre-filled, "Credit" is an option, one "Mark as paid" button).
4. Click **Table** to switch back.

### C. Customer portal

1. Sign out (top-right). Go to `http://localhost:5173/login`, sign in as
   `customer1@goldenfur.com` / `password123`.
2. Left sidebar → **Transactions**. Page headed **Transaction History**.
3. **Check:** same Search + **Filter** + **Sort** + **Table/Board** layout.
   The **Filter** menu offers only **Date, Service, Payment, Status** (no
   Customer / Pet / Transaction type). The table has **no** Customer column.
4. Click a table row (not the Pay button). **Check:** the **Booking details**
   pop-up opens. Close it.
5. Switch to **Board**. **Check:** three status columns; Due-payment cards
   have a **Pay** button; clicking a card body (not the button) opens Booking
   details. The card headline is the payment type, not the customer's own
   name.
6. On a Due-payment row/card click **Pay** → the credit / GCash / Maya modal
   opens (unchanged).

## Code review

`/code-review` (high), read-only, before the PR —
`../reviews/2026-09-08-1927-pre-pr.md` (also under
`Projects/golden-fur/testing/reviews/feat/transactions-ui-remaster/`).
Verdict **APPROVE**; four client-side findings, all fixed before the commit:

1. **Date tile default `this_month`** silently scoped the list to the current
   month on add — changed to `'all'` (adds no restriction).
2. **Fetch effect** never cleared a stale `error` and had no rejection
   handler — both pages now `setError(null)` on success + a `.catch`.
3. **`filterFields` / `serverFilterKey`** recomputed every render — both
   `useMemo`'d.
4. **Portal board misc-sale cards** were focusable `role="button"` no-ops —
   card is activatable only when `onCardActivate && booking_id`.

## Test suites

Full `ci-verifier` (both repos, tests + lint + format + builds) — **PASS**,
run against the branch after `git merge origin/dev` (HEAD `62a3d11`):

- **`server`**: `vitest run` — **1025/1025 passing (93 files)**; `tsc --noEmit`
  clean; lint clean. (Includes 2 new `customer_name`-merge tests in
  `transactionHistory.service.spec.ts`; the 4 pre-existing tests pass
  unchanged.)
- **`client`**: `vitest run` — **821/821 passing (158 files)** (816 on the
  branch alone + 5 from unrelated hotel-queue specs the `dev` merge brought
  in), incl. the new `FilterSortBar.spec.tsx` (5), `ViewSwitcher.spec.ts` (2),
  `transactionFilterFields.spec.ts` (8) and the reworked
  `TransactionHistoryTable.spec.ts` / `CustomerTransactionHistoryPage.spec.tsx`;
  `tsc -b` clean; lint clean; `prettier --check` (repo root) clean;
  client + server builds pass.
- Verified live in a headless browser as both a seeded cashier and a seeded
  customer, dark and light themes: filter-tile add / edit / remove, sort,
  Table↔Board, and the Board grouping all behave as described above.

## Open items

- **`FilterSortBar` vs `QueueFilterBar`.** The new bar is used only by the two
  Transactions pages. Its descriptor model is deliberately a superset of
  `QueueFilterBar` + `SearchSortBar` + `ActiveFilterChips`, so migrating the
  ~24 other queue pages later is mechanical — but that migration is **not**
  done here. Call this out in the PR body as a known follow-up.
- **Calendar view** deferred (`ViewSwitcher` already takes an arbitrary option
  list; `TransactionBoard` has a `groupBy`-shaped seam for future
  by-service / by-method grouping).
