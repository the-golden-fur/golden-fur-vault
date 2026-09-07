# Backlog items driving session 75

Transcribed verbatim from
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`
(the full document is project-wide reference material and is not copied here —
see the manifest). These are the two rows this session implements.

## Item 1 — "Production" section (owner: Matthew)

> Add new option to … in customer account > bookings page:
>
> - Add View Details option
> - Should be able to see all details (e.g. branch, pet, date time, assigned
>   staff/cage, price, payments, etc.)
> - Currently only cancel is available (and reschedule if booking hasn't been
>   confirmed)

## Item 2 — "Low Priority" table, Difficulty: Easy

> Fix unknown pet owner and unknown pet when viewing bookings as cashier

Accompanying backlog screenshot: the staff Booking Details page
(`/staff/bookings/<id>`) headed **"Grooming booking"** with the subtitle
**"Unknown pet · Owner Unknown owner"**, viewed while signed in as
`makati.cashier1` (Cashier). Schedule section shows a real branch (Makati) and
real dates, but the pet and owner are the literal fallback strings.
