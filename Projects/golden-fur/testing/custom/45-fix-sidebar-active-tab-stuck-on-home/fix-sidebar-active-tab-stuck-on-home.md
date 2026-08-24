# Sidebar: item sort verification + fix for "stuck on Home" active-tab bug

Branch: `bug/45-fix-sidebar-active-tab-stuck-on-home` (suggested - see note
below; not yet split out of `bug/44-fix-unpaid-pet-duplicate-booking`,
which was checked out first in this session and has its own uncommitted
changes on top of the same `dev` base).

## The request, verbatim

> Add the sidebar items sort option to customer and other staff roles
>
> - So far only admin and superadmin has it

Then, live-review follow-up in the same conversation:

> also sidebar seems to be always stuck at home even when I switch tabs

## Part 1: sidebar item sort - already shipped, no code change

Investigation found the per-item sort control (the "..." menu offering
Sort: Custom order / Alphabetical / Recently accessed, plus drag-and-drop
under Custom order) was already extended to every non-admin staff role and
the customer portal in a prior revision of branch
`40-sidebar-cages-bookings-calendar` (see that folder's `.md`, Revision 2,
point 4: "This '...' menu now also appears on every non-admin role's flat
(unlabeled) section and the customer portal's own nav ... previously those
had no sort control at all"). `Sidebar.tsx`'s `SidebarCategory` renders
`MoreOptionsMenu` unconditionally for every section, labeled or not - there
is no admin-only gate on it in the current code.

Confirmed live (not just by reading source/docs): logged in as a Groomer
and as a customer (`customer1@goldenfur.com`), hovered the nav list to
reveal the hover-revealed "..." trigger, opened it, and confirmed all three
sort options render and clicking one applies/checks correctly for both.

What's still admin/superadmin-only is a different control: the
**"Categories"** row that reorders entire _labeled sections_ (Management,
Groomer, Cashier, etc.) against each other - it only renders once a role
has 2+ labeled sections (`hasMultipleCategories` in `Sidebar.tsx`), which
today only Admin/Superadmin's grouped dashboard has. Every other role (and
the customer portal) has a single flat, unlabeled section, so there's
nothing to group. Per your reply, no new category groupings were invented
for other roles - the per-item sort (the literal ask) is already covered,
and category-level grouping was left alone as a separate design decision
you didn't ask for.

No files changed for this part.

## Part 2: fix - Home stayed "active" on every /portal/\* page

While confirming Part 1 live, you found a real, separate bug: the customer
portal's **Home** sidebar item kept its active-tab highlight (the orange
pill/border) no matter which page you actually navigated to - Transactions,
My Bookings, etc. all still showed Home as active alongside (or instead of)
themselves.

### Root cause

`Sidebar.tsx`'s per-item `<NavLink to={item.to} ...>` never passed React
Router's own `end` prop. Without it, `NavLink` treats a route as active
whenever the current location is that path _or any nested descendant of
it_ - by design, so e.g. a "Bookings" nav item can stay highlighted while
you're on a `/bookings/:id` detail sub-page. Every sidebar item happens to
be a genuine leaf page **except** the customer portal's Home
(`to: '/portal'`) - `/portal` is the literal path-segment ancestor of
every other `/portal/*` route (Transactions, My Bookings, Pet Manager,
Settings, ...), so it satisfied NavLink's "current location is a
descendant of `to`" check unconditionally, on every portal page.

A blanket fix (adding `end` to every sidebar `NavLink`) would have traded
this bug for a different regression: Pet Manager (`/portal/pets`) has its
own genuine nested detail route (`/portal/pets/:petId`, `PetProfilePage`)
that's expected to keep Pet Manager highlighted while you're looking at one
pet - `end` would have broken that. No other sidebar item (customer or
staff) has this "is a path-segment ancestor of some other route" property,
confirmed by checking every `to` value in `customerPortal.config.ts` and
`staffDashboard.config.ts` against the full route table.

### What changed

- `client/src/shared/components/Sidebar/Sidebar.tsx`
  - `SidebarItem` gains an optional `end?: boolean`, passed straight
    through to the `NavLink`'s own `end` prop. Defaults to `undefined`
    (NavLink's own default, i.e. unchanged behavior) for every existing
    caller that doesn't set it.
- `client/src/features/customers/config/customerPortal.config.ts`
  - The Home item now sets `end: true` - the only item that needed it.

No other sidebar config (staff dashboard's own "Dashboard" tile,
`/staff/dashboard/${slug}`, or any other tile) needed this: none of them
is a path-segment ancestor of another route, staff or customer.

### Verification

1. Log in as a customer, land on Home (`/portal`) - confirm it shows
   active (orange pill).
2. Click **Transactions** (or any other sidebar item). Confirm **only**
   Transactions is highlighted now - Home's highlight is gone.
3. Click back to **Home** - confirm it re-highlights correctly.
4. Open **Pet Manager**, then click into one specific pet's profile page.
   Confirm **Pet Manager** stays highlighted while viewing that pet's
   detail page (this is the "don't regress nested-detail highlighting"
   case the fix was deliberately scoped around).
5. Repeat steps 1-3 for a staff role (e.g. Groomer) as a sanity check -
   staff sidebars had no bug here (their "Dashboard" link is already a
   leaf page), so behavior should be unchanged, still correct.

Confirmed live via a scripted Playwright check (login -> navigate to
Transactions -> read `aria-current` off both Home and Transactions):
before the fix, Home kept `aria-current="page"` after navigating away;
after the fix, only Transactions has it.

## Test suites

- `client`: 2 new cases added to `Sidebar.spec.ts` - one reproducing the
  bug scenario (an `end: true` item must lose `aria-current` once the
  route moves past it) and one guarding the thing a blanket fix would have
  broken (a non-`end` item stays active on its own nested detail route).
  `npx vitest run src/shared/components/Sidebar/Sidebar.spec.ts` -
  16/16 passing. Full `client` suite run separately to confirm no
  unrelated regressions.
- `npx tsc -b --noEmit` (client) - clean.
- `npx eslint` on all three changed files - clean.
- No server changes in this batch.

## Note on branching

This work happened in the same session as, and on top of, uncommitted
changes for `bug/44-fix-unpaid-pet-duplicate-booking` (an unrelated fix,
already documented in `testing/docs/custom/44-fix-unpaid-pet-duplicate-booking/`).
Neither has been committed yet. Recommend splitting into two commits/PRs
before pushing: stage and commit the `server/src/features/booking/**`
files under `bug/44-...`, then create `bug/45-fix-sidebar-active-tab-stuck-on-home`
off `dev` for the three `client/src/shared/components/Sidebar/**` +
`client/src/features/customers/config/customerPortal.config.ts` files.
