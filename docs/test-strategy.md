# Halo Quality Engineering Test Strategy

## Scope

The API suite exercises Halo 2.26 as a black box through its Console, User Center, extension, public-content, and rendered permalink surfaces. Each scenario owns scoped resources, records successful creations for reverse cleanup, writes redacted HTTP evidence under its scenario ID, and performs no direct database writes.

The full author account has `role-template-post-author` and `role-template-post-contributor`. A separate contributor-only account has `role-template-post-contributor`; it is the truthful Halo 2.26 principal for create-without-publish permission scenarios.

## Scenario Ledger

| ID | Scenario |
|---|---|
| A01 | Admin valid credentials return the authenticated admin identity. |
| A02 | Wrong password is denied with HTTP 401. |
| A03 | Missing authentication is denied with HTTP 401. |
| A04 | Full author valid credentials return the authenticated author identity. |
| A05 | Readonly valid credentials return the authenticated readonly identity. |
| A06 | Disabled full author is denied with HTTP 401. |
| A07 | Disabled full author cannot create a post and state/count remain unchanged. |
| A08 | Re-enabled full author returns its authenticated identity. |
| P01 | Admin creates a draft that reaches DRAFT. |
| P02 | Draft is absent from the public API. |
| P03 | Publish reaches PUBLISHED. |
| P04 | Public API title and slug match. |
| P05 | The status permalink serves the published title. |
| P06 | Unpublish sets `spec.publish` false. |
| P07 | Unpublished post is absent from the public API. |
| P08 | Recycle sets `spec.deleted` true and removes the public post. |
| P09 | Publishing an unknown name returns HTTP 404 without state/count changes. |
| P10 | A second publish after observed PUBLISHED preserves one release snapshot and public resource. |
| P11 | Two same-version Console updates yield exactly HTTP 200 and 409, leaving one complete title/content pair. |
| R01 | Admin creates a draft. |
| R02 | Contributor creates its own draft through the User Center API. |
| R03 | Readonly User Center create is denied. |
| R04 | Readonly create denial leaves no resource. |
| R05 | Contributor cannot publish through its applicable User Center API. |
| R06 | Contributor publish denial leaves the post in DRAFT. |
| R07 | Admin can publish a contributor-owned post. |
| R08 | Contributor cannot update another owner's post through the User Center API. |
| R09 | Unauthenticated create is denied with HTTP 401. |

## Synchronization And Evidence

Mutations are sent once. Asynchronous state is observed only through GET requests using a 15-second monotonic deadline, a 100 ms initial delay, and exponential backoff capped at one second. Denied mutations snapshot metadata version, phase, and exact-name resource count before the request and prove them unchanged afterward.

Evidence redacts authorization, cookies, response cookies, passwords, tokens, and storage state. Generated credentials and session cookies stay in memory and are never committed.

The disposable environment raises Halo's IP-based authentication rate-limiter period capacity to 100 so the declared matrix and its required same-environment repeat can establish independent principals deterministically. The pinned one-minute refresh period and zero-duration timeout remain unchanged. Authentication rate-limit and brute-force-control validation are non-goals; A02 still exercises an actual wrong password and A03 still exercises a request without authentication, with both requiring exact HTTP 401 responses.
