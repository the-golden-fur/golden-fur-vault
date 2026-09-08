# Session request — verbatim

> [screenshot: the current Hotel Queue check-in success page, showing
> "Pet checked in successfully." with "Go to checkout" and "Check in
> another pet" buttons]
>
> do this next:
>
> - On http://localhost:5173/staff/hotel/queue:
>   - Clicking on check in on hotel queue should immediately check in the
>     pet, does not open
>     http://localhost:5173/staff/hotel/queue/check-in/e0aff74e-44e8-48a6-9007-008a7603a1a4
>   - Move
>     http://localhost:5173/staff/hotel/queue/check-in/e0aff74e-44e8-48a6-9007-008a7603a1a4
>     to the … button > View booking details with an edit option at the
>     bottom
>   - Do not open this page with go to checkout and check in another pet
>     options after checking it, just return to the queue and show a modal
>     if success or fail
>
> you may update the documentation in golden-fur-vault repo if needed
> you may file and promote notes to library, i'll leave decision making to you
> and make the pr after
