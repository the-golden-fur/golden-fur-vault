# Architectural-Change-History — rows in scope for session 67

Source: `golden-fur-vault/Inbox/Architectural-Change-History.docx` (Tasks table),
read 2026-09-02.

## In Progress — assignee Alarie

> Fix how date and time picker in bookings queue > new booking:
> Currently, when it's 1 PM today and I set a booking for tomorrow, it only
> shows booking time slots 2 PM and beyond (AS IF IT'S TREATING TODAY'S
> AVAILABLE BOOKING SLOTS FOR TOMORROW AND LATER DATES).
> Later dates should reset and show all available booking time slots based on
> branch operating hours and break times.
> Staff should not appear in staff picker when they're not available.
> Confirm if availability time is computed properly (does it take into account
> the monthly schedule that the supervisor set? Is staff on vacation leave?
> etc.)
> Right now, monthly schedule is not configured by admin role, so all staff
> should be available EXCEPT when they're chosen by a customer at X date/time
> (only on that date/time should they not be selectable)

## In Progress — assignee Alarie

> Fix not being able to book the next day or today in booking queue
> I think the 3 day notice period FOR RESCHEDULING ONLY, is ALSO applying to
> future online bookings
> You may add a separate config (for the online booking notice period) in admin
> settings > config > policies
> See the 2nd image below

## Related — Merged

> Investigate and fix the 3-day-minimum (or N-day) booking filter/configuration
> — verify it correctly applies date ranges instead of appearing to lock/pin
> schedules.
