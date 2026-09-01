# Task 5 Report: 28 API Scenarios for Authentication, Lifecycle, and RBAC

## Status

`NEEDS_CONTEXT`

Implementation stopped at the brief's explicit plan-conflict boundary. Halo 2.26 does not satisfy the mandated R05 outcome for the exact fixture role set. No scenario was disabled, skipped, mocked, weakened, or committed with a false assertion.

## Blocking Finding

The fresh live investigation used exactly these assigned roles:

```text
role-template-post-author
role-template-post-contributor
```

Observed behavior:

| Operation | Live result | Finding |
|---|---:|---|
| Create user with the exact roles in `CreateUserRequest.roles` | 200 | The roles persisted in `rbac.authorization.halo.run/role-names`. |
| Authenticated current-user read before session fallback | 200 | The representation was `anonymousUser`, not the created author. |
| Console `POST /apis/api.console.halo.run/v1alpha1/posts` as author | 403 | This is the Task 4 `draftPost` route. |
| User-center `POST /apis/uc.api.content.halo.run/v1alpha1/posts` as the same author | 200 | The exact role set can create its own draft on Halo's role-compatible API. |
| User-center `PUT /apis/uc.api.content.halo.run/v1alpha1/posts/{name}/publish` as the same author | 200 | This contradicts the mandated R05 denial. |
| Task 4 `grantRoles` request with `roleNames` | 500 | Live `GrantRequest` schema requires `roles`. |
| Diagnostic grant using schema-correct `roles` | 200 | The later author draft also returned 200. |

The live role representation explains both route results. `role-template-post-contributor` grants `create` on `uc.api.content.halo.run/posts`, while `role-template-post-author` declares `role-template-post-publisher` as a dependency. Therefore an account assigned the exact author+contributor set can publish through its permitted user-center endpoint. Asserting R05 by sending the admin Console publish route would prove only that the user cannot invoke that route; it would falsely claim the user cannot publish.

## TDD Evidence

### Initial RED

The brief's exact P02 test was added before lifecycle wiring and run with:

```powershell
$env:JAVA_HOME=(Resolve-Path '.superpowers\runtime\jdk21').Path
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
.\gradlew.bat :api-tests:integrationTest --tests '*PostLifecycleIT.draftIsNotPublic'
```

Result: `BUILD FAILED in 1s`; one test ran and `P02 draft is absent from public API` failed with `NullPointerException` at the unwired fixture field. This is the required initial failure.

### Focused RBAC Investigation

A temporary diagnostic test used scoped resources, the Task 4 fixture, redacted evidence, and separate post names for each mutation. No denied mutation was retried. The first diagnostic produced:

```text
identity-before=200, Console draft-before=403, Task 4 grantRoles=500,
identity-after=200, Console draft-after=403
```

After inspecting the live OpenAPI and exercising the role-compatible user-center routes, the second diagnostic produced:

```text
identity-before=200, user-center draft-before=200, schema-correct grant=200,
identity-after=200, user-center publish=200, user-center draft-after=200
```

The temporary diagnostic methods and tests were removed after the finding. Generated evidence remains only under ignored `api-tests/build/evidence`; a targeted scan found no Basic credential, session identifier, setup password, or fixture password value.

### GREEN

Not reached. Continuing would require either changing the role set, changing R05's expected outcome, or knowingly testing the wrong authorization surface.

## Scenario Inventory

| ID | Mandated outcome | Result |
|---|---|---|
| A01 | Admin valid credentials = 200 | NOT RUN |
| A02 | Wrong password = 401 | NOT RUN |
| A03 | Missing auth = 401 | NOT RUN |
| A04 | Author valid credentials = 200 | NOT RUN |
| A05 | Readonly valid identity endpoint = 200 | NOT RUN |
| A06 | Disabled author = 401 | NOT RUN |
| A07 | Denied disabled request creates no post | NOT RUN |
| A08 | Re-enabled author = 200 | NOT RUN |
| P01 | Create draft phase = DRAFT | NOT RUN |
| P02 | Draft public API = 404 | REQUIRED RED ONLY |
| P03 | Publish phase = PUBLISHED | NOT RUN |
| P04 | Public API title/slug match | NOT RUN |
| P05 | Status permalink serves title | NOT RUN |
| P06 | Unpublish sets publish = false | NOT RUN |
| P07 | Unpublished public API = 404 | NOT RUN |
| P08 | Recycle sets deleted = true and public = 404 | NOT RUN |
| P09 | Publish unknown name = 404 | NOT RUN |
| P10 | Two publish calls preserve one releaseSnapshot and public resource | NOT RUN |
| P11 | Same-version concurrent PUTs yield 200 + 409 and one complete pair | NOT RUN |
| R01 | Admin creates draft | NOT RUN |
| R02 | Author creates own draft | DIAGNOSTIC 200 ON USER-CENTER ROUTE; SCENARIO NOT IMPLEMENTED |
| R03 | Readonly create is denied | NOT RUN |
| R04 | R03 leaves no resource | NOT RUN |
| R05 | Author without publisher role cannot publish | BLOCKED: LIVE USER-CENTER PUBLISH RETURNED 200 |
| R06 | R05 leaves the post in DRAFT | BLOCKED BY R05 |
| R07 | Admin can publish author's post | NOT RUN |
| R08 | Author cannot update another owner's post | NOT RUN |
| R09 | Unauthenticated create is denied | NOT RUN |

## Required Full Validation

The two full integration runs were not started after the confirmed plan conflict. Consequently:

- There is no claim that 28 scenarios passed.
- JUnit XML was not claimed to contain 28 scenario display names.
- A second-run collision comparison was not performed.
- The full unit suite was not run for an implementation that was intentionally not produced.

## Cleanup And Teardown

Successful diagnostic posts were deleted through the generic extension DELETE. Fixture users were deleted in reverse creation order. The disposable environment was then torn down with `scripts/environment.ps1 -Action Down` using the runtime-only local Docker CLI setting.

Output confirmed removal of both containers, both disposable volumes, and the `halo-qe_default` network. A subsequent Compose `ps --all --format json` produced no entries. No test wrote Halo's database directly.

## Files

- Added this report only: `.superpowers/sdd/2026-08-31-halo-quality-engineering-mvp/task-5-report.md`
- Removed the temporary P02 RED class and RBAC diagnostic class after the stop decision.
- Reverted all temporary diagnostic changes to `HaloApi` and `PostPayloads`.

## Self-Review

- Preserved all 28 mandated outcomes without broadening statuses or hiding the conflict.
- Did not leave placeholder, assertion-free, disabled, or skipped tests.
- Did not retry a denied mutation or poll a mutation.
- Used unique scoped names and deleted every successfully created diagnostic resource.
- Confirmed tracked product-test sources match the pre-task state before writing this report.
- Ran `git diff --check` before report creation; no whitespace errors were reported.
- Did not include generated passwords, cookies, authorization values, tokens, or storage state in this report.

## Concerns And Required Ruling

The controller must choose a coherent contract before Task 5 can continue:

1. Use a contributor-only content account for R02/R05 so it can create but cannot publish, and change the fixture's mandated role set accordingly.
2. Keep `role-template-post-author` and change R05/R06 to reflect that Halo's author template includes publisher capability.
3. Explicitly redefine R05 as denial on the admin Console route, without claiming that the author cannot publish through its permitted user-center route.

There is a separate Task 4 client defect: `grantRoles` sends `roleNames`, but Halo 2.26's live `GrantRequest` requires `roles`. Authentication scenarios also need an identity assertion stronger than HTTP 200 because the current-user endpoint returned an anonymous 200 before a Console mutation established the session.

## Commit

No commit created. The required subject `test: cover Halo lifecycle and permission matrix` would be false while the mandated matrix is blocked and unimplemented.

## Controller Ruling / Resumed Implementation

### Current Status

`COMPLETE`

The controller resolved the role conflict by retaining the full author's author and contributor roles for authentication/disable scenarios and assigning a fourth contributor-only account to R02 and R05-R08. The contributor scenarios use the applicable User Center API. The client grant payload now sends the live `roles` property, and authenticated identity is proved by the protected User Center principal name rather than an anonymous HTTP 200.

### Implemented Coverage

- Added exactly 28 scenario display prefixes and evidence paths: A01-A08, P01-P11, and R01-R09.
- Added deadline-based GET-only observation with a 15-second monotonic deadline, 100 ms initial delay, exponential backoff, and a one-second cap.
- Added exact denial-state invariants, idempotent publish coverage, and same-version concurrent update coverage.
- Added User Center create/read/publish/update routes, protected and unauthenticated identity routes, exact-name collection observations, snapshot/permalink reads, and in-process credential-scoped session reuse.
- Added contributor-only fixture provisioning, settled post cleanup, and complete reverse-order resource cleanup.
- Added the scenario ledger and synchronization/evidence policy in `docs/test-strategy.md`.

### Authentication Limiter Contract

Bytecode/config inspection of the pinned Halo 2.26 image confirmed that local login uses one IP-keyed Resilience4j `authentication` bucket with `limitForPeriod: 3`, `limitRefreshPeriod: 1m`, and `timeoutDuration: 0s`. Session/device revocation does not replenish this time-based bucket.

The disposable Compose environment now sets `RESILIENCE4J_RATELIMITER_CONFIGS_AUTHENTICATION_LIMITFORPERIOD` to `100`, while retaining Halo's refresh period and timeout. A static configuration test proves the override and proves that refresh/timeout are not overridden. Authentication rate-limit and brute-force-control testing is explicitly a non-goal; A02 still submits an actual wrong password and A03 still omits authentication, and both require exact HTTP 401.

### Live Contract Results

| Area | Result |
|---|---|
| Authentication | A01-A08 passed; wrong password, missing auth, disabled identity, and disabled mutation returned exact 401. |
| Permissions | R01-R09 passed; readonly/contributor denials returned the exact observed 403/404 statuses and preserved settled version, phase, and count. |
| Lifecycle | P01-P11 passed; P10 preserved one release snapshot and one exact-name public item; P11 produced exactly 200 + 409 and one complete title/content pair. |
| Public collection | Halo advertises `fieldSelector` on the public list but returned zero for a directly retrievable matching post; P10 therefore counts the exact unique name from a bounded public collection response. |

### Final Validation

One fresh environment was initialized and the full integration command was executed twice in that same environment. The integration task is configured to bypass Gradle up-to-date skipping so the second invocation executes the tests.

| Check | Result |
|---|---|
| Full integration run 1 | PASS, 29 live tests including all 28 scenarios, 39 seconds |
| Full integration run 2 | PASS, 29 live tests including all 28 scenarios, 39 seconds |
| JUnit XML | 29 total, exactly 28 A/P/R scenario prefixes, 0 failures, 0 skipped |
| Evidence paths | Exactly 28 scenario ID directories |
| Second-run naming | 0 collisions with first-run scoped resource names |
| Unit suite | PASS, 4 seconds |
| Evidence redaction | No fixed/generated password, session value, Basic/Bearer value, or unredacted sensitive header found |
| Whitespace | `git diff --check` passed |
| Teardown | Containers, volumes, and network removed; final Compose project listing empty |

No denied mutation was retried, no mutation was used for polling, and no fixed-duration sleep or direct database access was introduced.

## Fix Round 1

### Status And Controller Contract

`COMPLETE`

All controller rulings remain unchanged: the contributor-only account owns R02 and R05-R08 on User Center routes; role grants use `roles`; identity checks assert the protected real-principal name; the disposable login limit remains 100; and P10 counts the exact unique name from the bounded public collection. All 28 scenario IDs and outcomes are unchanged, including P11's exact 200 + 409 concurrency contract.

### Changes

- Replaced post-redirect mutation retry with a pre-mutation User Center identity GET. Cold sessions log in and validate before the write; warm sessions validate before the write; a login redirect on that idempotent GET clears and refreshes the session before the write. POST, PUT, PATCH, and DELETE requests are each sent exactly once, and preflight request/response pairs are independently redacted in evidence.
- Added MockWebServer coverage for cold then warm User Center POST/PUT calls and stale-session refresh. The tests assert the complete wire sequence, exactly one domain mutation per call, expected evidence pair counts, and absence of password/session values.
- Changed P10 so the first publication reconciles through a direct public GET, the second publish remains a single PUT, and success then requires three consecutive bounded-collection GET observations containing exactly one item whose `metadata.name` equals the scoped post name. Zero or duplicate counts reset stability.
- Made fixture settling validate the returned deadline observation. Every tracked post is settled best-effort, ledger cleanup always follows, deletion still runs in reverse order, and one aggregate exception exposes settling and deletion issues separately while retaining each cause as suppressed. A focused try-with-resources test proves an original assertion remains primary while two settling failures and five deletion failures remain inspectable.

### Focused TDD

RED commands and observed results:

```powershell
$env:JAVA_HOME=(Resolve-Path '.superpowers\runtime\jdk21').Path
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
.\gradlew.bat :api-tests:test --tests '*HaloApiWireTest.preflightsColdAndWarmSessionsAndSendsEachDomainMutationOnce' --tests '*HaloApiWireTest.refreshesAStaleSessionOnTheIdentityPreflightWithoutRetryingTheMutation'
.\gradlew.bat :api-tests:test --tests '*StablePublicPostCountTest'
.\gradlew.bat :api-tests:test --tests '*HaloFixtureTest.settlingFailuresDoNotPreventReverseCleanupAndRemainSeparateFromDeletionFailures'
```

- Authentication: 2 tests failed against the old write-first/redirect-retry sequence.
- P10: compilation failed because the new stable-count helper did not exist.
- Cleanup: compilation failed because the deadline injection and cleanup aggregation contract did not exist.

Final focused command:

```powershell
.\gradlew.bat :api-tests:test --tests '*HaloApiWireTest' --tests '*EvidenceRedactorTest' --tests '*StablePublicPostCountTest' --tests '*HaloFixtureTest' --tests '*ResourceLedgerTest'
```

Output: `BUILD SUCCESSFUL in 5s`; 12 focused tests executed with zero failures and zero skips.

### Fresh Live Validation

The host-specific Docker executable was supplied only through runtime state and was not copied into the repository or recorded as a local absolute path. The equivalent portable assignment and exact repository commands are:

```powershell
$env:DOCKER_CLI=Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'
$env:JAVA_HOME=(Resolve-Path '.superpowers\runtime\jdk21').Path
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
.\scripts\environment.ps1 -Action Down
.\scripts\environment.ps1 -Action Up
.\scripts\environment.ps1 -Action Initialize
.\gradlew.bat :api-tests:integrationTest
.\gradlew.bat :api-tests:integrationTest
.\gradlew.bat :api-tests:test
.\scripts\environment.ps1 -Action Down
```

Startup output: Halo setup ready at HTTP 200; initialization completed at HTTP 204.

| Check | Fresh result |
|---|---|
| Full integration run 1 | `BUILD SUCCESSFUL in 42s`; 29 tests; 28 scenario prefixes; 0 failures; 0 errors; 0 skipped |
| Full integration run 2 | `BUILD SUCCESSFUL in 40s`; 29 tests; 28 scenario prefixes; 0 failures; 0 errors; 0 skipped |
| Evidence inventory | 28 A/P/R evidence directories in each run |
| Scoped names | 32 distinct names in each run; 0 cross-run collisions |
| P10 live sequence | 2 publish PUTs total; 3 bounded collection GETs after the second PUT |
| Full unit suite | `BUILD SUCCESSFUL in 14s`; 16 tests; 0 failures; 0 errors; 0 skipped |
| Evidence secret scan | 0 fixed/generated password, Basic/Bearer value, or session-cookie hits |
| Teardown | Both containers, both volumes, and network removed; final Compose entries = 0 |
| Whitespace/source audit | `git diff --check` passed; exactly 28 scenario display prefixes |

The structured audit parsed every `TEST-*.xml` file and summed `tests`, `failures`, `errors`, and `skipped`; it separately selected testcase names matching `^[APR][0-9]{2} `, enumerated evidence ID directories, extracted scoped names from redacted JSON, compared the two name sets for equality collisions, and scanned evidence with:

```powershell
$artifactRoot='.superpowers\runtime\task-5-fix-round-1'
$evidenceRoot=Get-ChildItem "$artifactRoot\evidence-run-*" -Directory
[xml[]]$run1=Get-ChildItem "$artifactRoot\junit-run-1\TEST-*.xml" | ForEach-Object {[xml](Get-Content -Raw $_)}
[xml[]]$run2=Get-ChildItem "$artifactRoot\junit-run-2\TEST-*.xml" | ForEach-Object {[xml](Get-Content -Raw $_)}
$run1.testsuite.testcase.name | Where-Object {$_ -match '^[APR][0-9]{2} '} | Measure-Object
$run2.testsuite.testcase.name | Where-Object {$_ -match '^[APR][0-9]{2} '} | Measure-Object
Get-ChildItem "$artifactRoot\evidence-run-1\local" -Directory | Where-Object Name -match '^[APR][0-9]{2}$' | Measure-Object
Get-ChildItem "$artifactRoot\evidence-run-2\local" -Directory | Where-Object Name -match '^[APR][0-9]{2}$' | Measure-Object
$namePattern='qe-\d{8}t\d{6}z-api-[0-9a-f]{8}-[a-z0-9-]+'
$names1=Get-ChildItem "$artifactRoot\evidence-run-1" -Recurse -File | Select-String $namePattern -AllMatches | ForEach-Object {$_.Matches.Value} | Sort-Object -Unique
$names2=Get-ChildItem "$artifactRoot\evidence-run-2" -Recurse -File | Select-String $namePattern -AllMatches | ForEach-Object {$_.Matches.Value} | Sort-Object -Unique
Compare-Object $names1 $names2 -IncludeEqual -ExcludeDifferent
$setup=Get-Content -Raw scripts\environment.ps1
$fixedFixturePassword=[regex]::Match($setup,"password = '([^']+)'").Groups[1].Value
$secretPattern=[regex]::Escape($fixedFixturePassword)+'|intentionally-wrong|fixture-[^\"\s]+-password|Basic\s+[A-Za-z0-9+/=]+|Bearer\s+[A-Za-z0-9._~-]+|SESSION='
Get-ChildItem $evidenceRoot -Recurse -File | Select-String -Pattern $secretPattern
```

Result: no matches.

### Artifact References

Generated, ignored validation artifacts are retained at `.superpowers/runtime/task-5-fix-round-1/`:

- `integration-run-1.txt`, `integration-run-2.txt`, and `unit-suite.txt`: exact Gradle console output.
- `junit-run-1/`, `junit-run-2/`, and `junit-unit/`: preserved JUnit XML snapshots.
- `evidence-run-1/` and `evidence-run-2/`: per-execution redacted HTTP evidence snapshots.
- `audit-summary.txt`, `scoped-names-run-1.txt`, `scoped-names-run-2.txt`, and `compose-after-down.txt`: counts, collision inputs, and empty-Compose proof.

### Files And Self-Review

- Changed `HaloApi`, `HaloApiWireTest`, `PostLifecycleIT`, `HaloFixture`, `HaloFixtureTest`, and `ResourceLedger`.
- Added `StablePublicPostCount` and `StablePublicPostCountTest`.
- Appended this fix record to the existing Task 5 report.
- Verified no mutation polling or retry, no fixed sleep, no direct database access, no status broadening, no skipped/disabled test, no local path in tracked files, and no weakening of P11.

### Fix Commit

Subject: `fix: harden Task 5 mutation and cleanup evidence`. The final SHA is recorded in the task handoff because a commit cannot contain its own stable SHA.

## Fix Round 2

### Status

`COMPLETE`

The round-1 teardown result was correct, but its retained `compose-after-down.txt` reference was false because the ignored file was absent. No product or test code changed, and the integration/unit suites were not rerun for this artifact-only correction.

### Read-Only Compose Verification

Docker was resolved only from the runtime-only installed user path through `LOCALAPPDATA`; no Docker executable, shim, or host absolute path was copied into or committed to the repository. The executed portable query was:

```powershell
$env:DOCKER_CLI=Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'
& $env:DOCKER_CLI compose --project-name halo-qe --env-file environment\image-lock.env --file environment\docker-compose.yml ps --all --format json
```

Captured result:

```text
exitCode=0
entryCount=0
stdout=<empty>
```

### Restored Artifact

Created the ignored `.superpowers/runtime/task-5-fix-round-1/compose-after-down.txt` with the exact portable command, exit code, entry count, and explicit `<empty>` stdout marker.

Verification command:

```powershell
$path='.superpowers\runtime\task-5-fix-round-1\compose-after-down.txt'
Test-Path -LiteralPath $path
$content=Get-Content -Raw -LiteralPath $path
$content.Contains('compose --project-name halo-qe --env-file environment\image-lock.env --file environment\docker-compose.yml ps --all --format json')
$content.Contains('Exit code: 0')
$content.Contains('Entry count: 0')
$content.Contains("Captured stdout:`n<empty>") -or $content.Contains("Captured stdout:`r`n<empty>")
```

Output: `True` for `Test-Path` and all four content assertions.

### Commit

The report update is committed separately, followed by the required empty audit marker commit with subject `test: restore Task 5 teardown audit evidence`; its final SHA is recorded in the task handoff.
