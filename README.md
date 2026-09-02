# Halo 2.26 Quality Engineering

An external, black-box quality-engineering repository for Halo 2.26. It keeps the disposable Halo/PostgreSQL environment, Java API coverage, Playwright journeys, contract checks, and evidence collection separate from the Halo product repository.

## Architecture

Docker Compose starts digest-pinned Halo and PostgreSQL. Java 21, JUnit 5, RestAssured, and AssertJ exercise API state and authorization combinations. TypeScript and Playwright exercise the essential browser journeys. API and browser fixtures share the `runId-workerId` naming convention but remain independent. The layered gate starts a fresh environment, preserves redacted evidence on failure, and tears it down after each layer.

## Prerequisites

- Docker Compose
- Java 21
- Node.js 22 and pnpm 10
- PowerShell 7 for the documented commands

The qualified target is Halo `v2.26.1` at source commit `88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`. The environment uses `halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9`; see `environment/image-lock.env` for the complete image lock.

## Run

Start and initialize a disposable environment:

```powershell
pwsh ./scripts/environment.ps1 -Action Up
pwsh ./scripts/environment.ps1 -Action Initialize
```

Run one gate layer, or all merge-gate layers:

```powershell
pwsh ./scripts/quality-gate.ps1 -Layer L0
pwsh ./scripts/quality-gate.ps1 -Layer L1
pwsh ./scripts/quality-gate.ps1 -Layer L2
pwsh ./scripts/quality-gate.ps1 -Layer All
```

L0 compiles and unit-tests the API harness, validates quarantine policy, and compares OpenAPI. L1 executes the API matrix. L2 executes Chromium journeys, including the isolated expiry environment. L3 is the nightly regression scope: full API coverage, Chromium and Firefox qualification, and the 20-run stability command:

```powershell
pwsh ./scripts/stability.ps1 -Runs 20 -Layer All
pwsh ./scripts/verify-publication.ps1
```

## Scenario Map

The API matrix has exactly 28 scenarios: `A01-A08` authentication, `P01-P11` article lifecycle, and `R01-R09` role-based access control. Their exact requests and assertions are in [the API ledger](docs/test-strategy.md#scenario-ledger).

The ten browser journeys are `E01` administrator login, `E02` wrong-password denial, `E03` author/readonly routing, `E04` author draft creation, `E05` administrator publishing, `E06` anonymous permalink visibility, `E07` unpublish removal, `E08` readonly write denial, `E09` logout invalidation, and `E10` isolated session expiry. The suite permits zero retries.

## Evidence And Results

Generated failure evidence belongs under `artifacts/environment/`, API evidence under `api-tests/build/evidence/`, and browser reports, traces, screenshots, and video under the invocation artifact directory. Secrets, cookies, tokens, passwords, and browser state are redacted before publication.

## Measured Results

The machine-checked claim below is compared exactly with the authoritative tracked [raw qualification artifact](evidence/qualification-v1.json). The structured record is the only location for qualification values in this section.

<!-- qualification-claims-v1 -->
```json
{
  "schemaVersion": 1,
  "evidence": "evidence/qualification-v1.json",
  "facts": {
    "target": { "haloVersion": "2.26.1", "sourceCommit": "88c2ef14355c79a4dbd1d5c3246b3ea32836e06b", "haloImage": "halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9" },
    "stability": { "testedCommit": "04379a211124cd52f7a2d08920dd0866fe24ed55", "consecutivePassNoneRuns": 20, "minimumDurationSeconds": 163.37, "maximumDurationSeconds": 182.204, "averageDurationSeconds": 168.103 },
    "fullGate": { "layers": [{ "layer": "L0", "result": "PASS", "durationSeconds": 30.559 }, { "layer": "L1", "result": "PASS", "durationSeconds": 59.442 }, { "layer": "L2", "result": "PASS", "durationSeconds": 73.93 }], "preflightMissingEvidence": 0, "finalComposeRows": 0 },
    "firefox": { "ordinaryPassed": 11, "ordinaryExpected": 11, "isolatedExpiryPassed": 1, "isolatedExpiryExpected": 1, "userJourneys": 10, "retries": 0 }
  }
}
```

## Qualification Boundary

These are observed local qualification results, not design targets. No public CI run URL exists, and this quality repository has no remote; this repository does not claim hosted CI execution.

## Public Contributions

The upstream Issue is [halo-dev/halo#10282](https://github.com/halo-dev/halo/issues/10282), whose current page state is `OPEN`. The upstream PR is [halo-dev/halo#10283](https://github.com/halo-dev/halo/pull/10283), whose current page state is `OPEN` and whose contribution lifecycle is independently recorded as `SUBMITTED`, not merged. [Contribution ledger](docs/upstream-contributions.md)

## Non-Goals

This MVP does not claim complete Halo coverage, a test-management product, a dashboard, direct database manipulation, a shared online demonstration environment, Selenium coverage, comments, or attachments. Comments and attachments are a later P1 milestone after the article chain is stable.
