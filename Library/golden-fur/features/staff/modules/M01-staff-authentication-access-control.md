---
title: "M01 · Staff Authentication & Access Control"
date: 2026-08-26
tags: [architecture, golden-fur, module]
project: golden-fur
---

# M01 · Staff Authentication & Access Control

**Layer:** Foundation
**Code:** `features/auth`, `features/staff` (client + server), `features/branches` (server-only, system configuration)
**Part of:** [[Architecture|Golden Fur — System Architecture]]

The entry point of the whole system — who can log in, what they can see,
and what they can do.

## Staff availability

Availability is determined by four sources: branch operating hours, a
fixed daily lunch break, confirmed bookings, and manual Unavailability
Blocks / scheduled leave.

- A staff member's own custom-range Unavailability Block is **not
  self-service** — it's created as a pending request and doesn't count
  toward availability until an Admin, Supervisor, or Superadmin (who
  isn't the requester) approves it. The "now until end of shift" quick
  action stays self-approved (an emergency safety net), and anything an
  Admin/Supervisor/Superadmin creates _on behalf of_ another staff
  member is auto-approved.
- A block can be filed as an **Entire Day** (`is_full_day = true`)
  instead of a time range, for both the self-service flow and the
  on-behalf-of flow.

### `get_staff_availability(staff_id, date, time)`

A Postgres function — the single source of truth for availability,
queried by [[M03-appointment-booking|M03]]'s Slot/Staff Picker. Returns available only if:

1. The time falls within the branch's operating hours for that day.
2. It doesn't fall inside the branch's lunch break window (checked
   regardless of individual staff schedules — see [[M09-policy-enforcement|M09]]).
3. No booking already holds that slot for that staff member — checked
   against every status that still holds a slot: Pending, In Progress,
   Completed (Cancelled and No-show release it).
4. The staff member has no approved Unavailability Block or scheduled
   leave overlapping the window (pending/denied requests don't count).

## Monthly Schedule (Rest Day / Vacation / Sick Leave)

A shared branch-scoped calendar where Supervisor, Admin, and Superadmin
plot leave directly, with equal CRUD access at their branch (Superadmin
gets a branch selector for any branch). Two views: Calendar (one chip
per staff/day) and Staff Grid (spreadsheet-style, RD/VL/SL/O badges).
Entries are auto-approved immediately but log who added them and when.
Reuses the same `staff_unavailability_blocks` table/approval
infrastructure — `get_staff_availability()` respects it automatically.

## System Configuration — branch creation

Superadmin's System Configuration page can create a brand-new branch
(name, address, contact, timezone, is-vet-branch toggle), not just edit
one. A new branch defaults to Closed every day until hours are set, then
becomes selectable everywhere (e.g. the booking flow's branch picker).
Branch creation is Superadmin-only.

## Session management

Role-tiered, inactivity-based session timeouts (not a flat duration). A
modal warns the staff member shortly before expiry with a stay-signed-in
option.

## Settings & navigation

A collapsible sidebar groups navigation by role (Admin/Superadmin see
grouped multi-role sections). The navbar identity chip is plain text; a
gear-icon Settings link and a notification bell sit beside it. Settings
tabs: Profile, Account, Preferences (theme, font-size slider,
per-event-type notification toggles), and — Admin/Superadmin only — a
**Config** tab consolidating every admin configuration page: Services
and Packages, Pricing Configuration, Promos, Breed Management, Product
Catalog, Discounts, Miscellaneous Sales, Policies, Cages, and (Superadmin
only) System Configuration.

## Workflows

- [[M01-01-staff-account-creation|Staff Account Creation]]
- [[M01-02-unavailability-block-request-review|Unavailability Block Request & Review]]

## Relationship to other modules

Feeds staff identity/role into [[M03-appointment-booking|M03]] (Staff Picker), [[M04-grooming-management|M04]]
(groomer assignment), [[M07-health-veterinary-management|M07]] (veterinarian assignment), and
[[M11-notification|M11]] (staff-directed notifications). Branch operating hours and
lunch break are consumed by M03's Slot Picker.

## Open items

- Allow assigning multiple roles to a single staff user.
