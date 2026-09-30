# Let a Superadmin move a cage to a different branch

Branch: `feat/cage-branch-reassignment`

## The request, verbatim

> As an admin, I want to be able to configure what branches certain cages
> are available at, via ... button > configure

Scope note: clarified with the user before implementing that this means
reassigning a cage to a different _single_ branch (not making one cage
available at multiple branches simultaneously, which would have meant
following the existing Services/Packages/Promos "branch availability"
join-table pattern instead), and that only the Superadmin role can do the
reassigning (Admin/Supervisor keep managing only their own branch's cages,
unchanged).

## Root cause / Context

Cages are physical, per-branch inventory (`cages.branch_id`, e.g.
"Makati-S-01"). Before this change, nobody — not even Superadmin — could
move a cage to a different branch: `updateCageController` always scoped its
query to the caller's own `req.user.branch_id`, and the "Configure cage"
modal only edited label/size/pet types. No database migration was needed:
`cages`' own RLS already let Superadmin `for all` on any branch's rows with
no branch condition in its `with check` clause - the only blocker was the
Express-layer query filter and the client form not offering a branch field.

## What changed

### Server

- `server/src/features/hotel/modules/validators/hotel.validator.ts` -
  `updateCageValidator` gains an optional `branch_id` (uuid), included in
  the existing "at least one field" refinement.
- `server/src/features/hotel/hotel.controller.ts` - `updateCageController`
  returns 403 if a non-Superadmin includes `branch_id` (role is read from
  `req.user.role`, already freshly resolved by the `requireRole` middleware
  already on this route - no extra DB lookup added). Otherwise forwards it
  to the service as `newBranchId`.
- `server/src/features/hotel/services/cageStatus.service.ts` - `updateCage`
  accepts `newBranchId` and, when given, includes `branch_id` in the
  Supabase update payload. The existing `.eq('branch_id', branchId)` (the
  cage's _current_ branch) still locates the row, so a Superadmin can only
  move a cage already visible in their own branch's list, not reach into
  another branch's inventory directly.

### Client

- `client/src/features/hotel/api/hotel.api.ts` - `updateCage`'s `updates`
  type gains an optional `branch_id`.
- `client/src/features/hotel/pages/AdminCagesPage/AdminCagesPage.tsx` -
  fetches the branch list (reusing `listBranches()` from the
  maintenance feature, the same client-side-Supabase-read helper the
  Services/Packages branch pickers already use - no new server endpoint
  needed) only when the viewer is Superadmin; adds a "Branch" dropdown to
  the Configure modal only, only for Superadmin; on a successful
  reassignment, removes the cage from the local list instead of updating it
  in place (it no longer belongs to the viewer's own-branch list), showing
  "Cage moved to `<branch name>`." instead of "Cage updated."

## Manual test - step by step

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login**, sign in as a **Superadmin** account. You should
   land on the staff Dashboard.
3. Go to **Settings > Config > Cages**.
4. Pick any cage row and click its **"..."** menu, then **Configure**.
5. In the popup, you should now see a **Branch** field (a dropdown)
   alongside Cage label, Size, and Pet types, currently set to the cage's
   own branch.
6. Change it to the other branch and click **Save changes**. You should see
   a message like "Cage moved to Southwoods." and the cage should
   disappear from the list you're currently viewing (it now belongs to the
   other branch).
7. Sign out, sign back in as a **regular Admin** account, go to the same
   Cages page, open **Configure** on any cage - the **Branch** field should
   not appear at all; Cage label/Size/Pet types still work exactly as
   before.

## Test suites

- `server`: `npx vitest run` - 116 files / 1394 tests passing.
- `client`: `npx vitest run` - 234 files / 1452 tests passing.
- `npx tsc --noEmit` clean on both `server` and `client`.
- `npm run lint` clean on both (0 errors; the same pre-existing
  `no-console` warnings baseline, none new).

## Open items

None.
