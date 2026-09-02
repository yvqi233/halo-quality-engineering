[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$verifierPath = Join-Path $PSScriptRoot 'verify-publication.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

function Write-Utf8File {
    param([string]$Path, [string]$Value)

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Get-QualificationFixtureFacts {
    return @'
{
  "target": { "haloVersion": "2.26.1", "sourceCommit": "0123456789012345678901234567890123456789", "haloImage": "halohub/halo@sha256:0123456789012345678901234567890123456789012345678901234567890123" },
  "stability": { "testedCommit": "0123456789012345678901234567890123456789", "consecutivePassNoneRuns": 1, "minimumDurationSeconds": 1, "maximumDurationSeconds": 1, "averageDurationSeconds": 1 },
  "fullGate": { "layers": [{ "layer": "L0", "result": "PASS", "durationSeconds": 1 }, { "layer": "L1", "result": "PASS", "durationSeconds": 1 }, { "layer": "L2", "result": "PASS", "durationSeconds": 1 }], "preflightMissingEvidence": 0, "finalComposeRows": 0 },
  "firefox": { "ordinaryPassed": 1, "ordinaryExpected": 1, "isolatedExpiryPassed": 1, "isolatedExpiryExpected": 1, "userJourneys": 1, "retries": 0 }
}
'@
}

function Write-ValidFixtureReadme {
    param([string]$Path)

    $facts = Get-QualificationFixtureFacts
    $value = '# Fixture' + [Environment]::NewLine + [Environment]::NewLine +
        '## Measured Results' + [Environment]::NewLine + [Environment]::NewLine +
        'Tracked facts are published below.' + [Environment]::NewLine + [Environment]::NewLine +
        '<!-- qualification-claims-v1 -->' + [Environment]::NewLine + '```json' + [Environment]::NewLine +
        '{ "schemaVersion": 1, "evidence": "evidence/qualification-v1.json", "facts": ' + $facts + ' }' +
        [Environment]::NewLine + '```'
    Write-Utf8File $Path $value
}

function New-PublicationFixture {
    $path = Join-Path ([IO.Path]::GetTempPath()) "halo-publication-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    & git -C $path init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize publication fixture repository.' }

    Write-Utf8File (Join-Path $path 'artifacts/evidence.txt') "redacted evidence`n"
    $facts = Get-QualificationFixtureFacts
    Write-Utf8File (Join-Path $path 'evidence/qualification-v1.json') "{ `"schemaVersion`": 1, `"facts`": $facts }"
    Write-ValidFixtureReadme (Join-Path $path 'README.md')
    Write-Utf8File (Join-Path $path 'docs/upstream-contributions.md') @'
# Upstream Contributions

<!-- upstream-ledger-v1 -->
```json
{
  "schemaVersion": 1,
  "records": [
    {
      "kind": "ISSUE",
      "url": "https://github.com/halo-dev/halo/issues/1",
      "pageState": "OPEN",
      "lifecycleStatus": "REPORTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "0123456789012345678901234567890123456789",
      "evidence": "artifacts/evidence.txt"
    },
    {
      "kind": "PR",
      "url": "https://github.com/halo-dev/halo/pull/2",
      "pageState": "OPEN",
      "lifecycleStatus": "SUBMITTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "0123456789012345678901234567890123456789",
      "headCommit": "fedcba9876543210fedcba9876543210fedcba98",
      "evidence": "artifacts/evidence.txt"
    }
  ]
}
```

## Contribution Purpose

Fixture purpose.

## Reproduction

Fixture reproduction.

## Expected And Actual

Fixture contract.

## Duplicate Search

Fixture duplicate search.

## PR Change And Validation

Fixture validation.

## AI Disclosure

Fixture disclosure.

## Review And Status

Fixture status.

## Modification History

Fixture history.

<!-- upstream-contribution-detail-v1 -->
```json
{"schemaVersion":1,"purpose":"x","reproductionEvidence":"artifacts/evidence.txt","expectedActual":"x","duplicateSearch":"x","prChangeHead":"x","validation":"x","aiDisclosure":"x","reviewFeedback":"x","modificationHistory":["x"]}
```
'@
    & git -C $path add README.md docs artifacts evidence
    if ($LASTEXITCODE -ne 0) { throw 'Could not track publication fixture files.' }
    return $path
}

function Invoke-Verifier {
    param([string]$FixtureRoot, [switch]$ExpectSuccess, [switch]$Raw, [string]$Case = 'fixture')

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierPath `
            -RepositoryRoot $FixtureRoot -SkipLiveChecks -Verbose 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($Raw) {
        return [pscustomobject]@{ exitCode = $exitCode; output = ($output -join [Environment]::NewLine) }
    }
    if ($ExpectSuccess) {
        Assert-True ($exitCode -eq 0) "Expected verifier success, got exit ${exitCode}: $($output -join [Environment]::NewLine)"
    } else {
        Assert-True ($exitCode -ne 0) "Expected verifier failure for $Case, but it succeeded: $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine)
}

function Assert-FailsOrRecordRed {
    param([string]$FixtureRoot, [string]$Case, [Collections.Generic.List[string]]$UnexpectedPasses)

    $result = Invoke-Verifier -FixtureRoot $FixtureRoot -Raw
    if ($result.exitCode -eq 0) {
        [void]$UnexpectedPasses.Add($Case)
        Write-Host "RED observed: $Case passed before verifier hardening."
    }
}

Assert-True (Test-Path -LiteralPath $verifierPath) 'verify-publication.ps1 is missing.'

$fixture = New-PublicationFixture
try {
    [void](Invoke-Verifier -FixtureRoot $fixture -ExpectSuccess)

    $privateIpv4 = '10.' + '20.30.40'
    Write-Utf8File (Join-Path $fixture 'docs/private-host.md') "Observed host $privateIpv4."
    & git -C $fixture add docs/private-host.md
    Assert-True ((@(& git -C $fixture ls-files) -contains 'docs/private-host.md')) 'Private IPv4 fixture file was not tracked.'
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'private IPv4')
    & git -C $fixture reset --quiet docs/private-host.md
    Remove-Item -LiteralPath (Join-Path $fixture 'docs/private-host.md') -Force

    $enterpriseName = 'GitHub ' + 'Enterprise'
    Write-Utf8File (Join-Path $fixture 'docs/enterprise.md') "$enterpriseName is not a public record."
    & git -C $fixture add docs/enterprise.md
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'enterprise name')
    & git -C $fixture reset --quiet docs/enterprise.md
    Remove-Item -LiteralPath (Join-Path $fixture 'docs/enterprise.md') -Force

    Write-Utf8File (Join-Path $fixture 'e2e/storage-state.json') '{"cookies":[],"origins":[]}'
    & git -C $fixture add e2e/storage-state.json
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'tracked storage state')
    & git -C $fixture reset --quiet e2e/storage-state.json
    Remove-Item -LiteralPath (Join-Path $fixture 'e2e/storage-state.json') -Force

    Write-Utf8File (Join-Path $fixture 'README.md') @'
# Fixture

## Measured Results

- A resume claim without evidence.
'@
    & git -C $fixture add README.md
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'unlinked result claim')

    Write-Utf8File (Join-Path $fixture 'README.md') @'
# Fixture

## Measured Results

- Qualified claim with [missing evidence](artifacts/missing.txt).
'@
    & git -C $fixture add README.md
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'broken evidence link')

    Write-Utf8File (Join-Path $fixture 'README.md') @'
# Fixture

## Measured Results

- Qualified claim with [evidence](artifacts/evidence.txt).
'@
    Write-Utf8File (Join-Path $fixture 'docs/synthetic-password.md') 'HaloQE!2026'
    & git -C $fixture add README.md docs/synthetic-password.md
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'forbidden synthetic password')
    & git -C $fixture reset --quiet docs/synthetic-password.md
    Remove-Item -LiteralPath (Join-Path $fixture 'docs/synthetic-password.md') -Force

    $tokenFixtureValue = 'ghp_' + 'abcdefghijklmnopqrstuvwxyz0123456789'
    Write-Utf8File (Join-Path $fixture 'secrets.md') $tokenFixtureValue
    & git -C $fixture add secrets.md
    [void](Invoke-Verifier -FixtureRoot $fixture -Case 'token pattern')
    & git -C $fixture reset --quiet secrets.md
    Remove-Item -LiteralPath (Join-Path $fixture 'secrets.md') -Force

    Write-Utf8File (Join-Path $fixture 'e2e/specs/fixture.ts') "const password = 'HaloQE!2026';`n"
    Write-Utf8File (Join-Path $fixture 'api-tests/bin/leak.txt') $tokenFixtureValue
    Write-ValidFixtureReadme (Join-Path $fixture 'README.md')
    & git -C $fixture add README.md e2e/specs/fixture.ts
    [void](Invoke-Verifier -FixtureRoot $fixture -ExpectSuccess)
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

# Round-one hardening cases: execute every missing control before failing the test run.
$hardeningFixture = New-PublicationFixture
try {
    $unexpectedPasses = [Collections.Generic.List[string]]::new()

    $hardeningReadmePath = Join-Path $hardeningFixture 'README.md'
    $mismatchedClaims = [IO.File]::ReadAllText($hardeningReadmePath).Replace('"averageDurationSeconds": 1', '"averageDurationSeconds": 999')
    [IO.File]::WriteAllText($hardeningReadmePath, $mismatchedClaims, [Text.UTF8Encoding]::new($false))
    & git -C $hardeningFixture add README.md
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'structured result claim mismatch' -UnexpectedPasses $unexpectedPasses
    Write-ValidFixtureReadme $hardeningReadmePath

    Write-Utf8File $hardeningReadmePath @'
# Fixture

## Measured Results

- Qualified claim with [evidence](artifacts/evidence.txt).

  Fabricated duration 999.999s and fabricated commit ffffffffffffffffffffffffffffffffffffffff.
'@
    & git -C $hardeningFixture add README.md
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'multiline result claim mismatch' -UnexpectedPasses $unexpectedPasses

    Write-Utf8File (Join-Path $hardeningFixture 'README.md') @'
# Fixture

## Measured Results

- Qualified claim with [evidence](artifacts/evidence.txt).
'@
    $ledgerPath = Join-Path $hardeningFixture 'docs/upstream-contributions.md'
    $ledgerText = [IO.File]::ReadAllText($ledgerPath).Replace('"lifecycleStatus": "SUBMITTED"', '"lifecycleStatus": "MERGED"')
    [IO.File]::WriteAllText($ledgerPath, $ledgerText, [Text.UTF8Encoding]::new($false))
    & git -C $hardeningFixture add README.md docs/upstream-contributions.md
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'open PR marked MERGED' -UnexpectedPasses $unexpectedPasses

    $ledgerText = [IO.File]::ReadAllText($ledgerPath).Replace('"lifecycleStatus": "MERGED"', '"lifecycleStatus": "SUBMITTED"')
    [IO.File]::WriteAllText($ledgerPath, ($ledgerText + "`nBroken public evidence: https://example.invalid/absent`n"), [Text.UTF8Encoding]::new($false))
    & git -C $hardeningFixture add docs/upstream-contributions.md
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'unrequested broken public URL' -UnexpectedPasses $unexpectedPasses

    [IO.File]::WriteAllText($ledgerPath, $ledgerText, [Text.UTF8Encoding]::new($false))
    $synthetic = 'HaloQE!' + '2026'
    Write-Utf8File (Join-Path $hardeningFixture 'e2e/reports/run.txt') $synthetic
    & git -C $hardeningFixture add docs/upstream-contributions.md e2e/reports/run.txt
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'fixture password in nested report' -UnexpectedPasses $unexpectedPasses

    & git -C $hardeningFixture reset --quiet e2e/reports/run.txt
    Remove-Item -LiteralPath (Join-Path $hardeningFixture 'e2e/reports/run.txt') -Force
    $authorizationHeader = 'Authorization' + ': Basic example-value'
    $cookieHeader = 'Cookie' + ': session=example-value'
    $privateHost = 'halo.' + 'internal'
    Write-Utf8File (Join-Path $hardeningFixture 'docs/leaks.txt') "$authorizationHeader`n$cookieHeader`npassword: example-value`n$privateHost`n"
    Write-Utf8File (Join-Path $hardeningFixture 'e2e/.auth/admin.json') '{"cookies":[{"name":"session","value":"example-value"}],"origins":[]}'
    & git -C $hardeningFixture add docs/leaks.txt e2e/.auth/admin.json
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'headers password private host and ordinary auth state' -UnexpectedPasses $unexpectedPasses

    & git -C $hardeningFixture reset --quiet docs/leaks.txt e2e/.auth/admin.json
    Remove-Item -LiteralPath (Join-Path $hardeningFixture 'docs/leaks.txt') -Force
    Remove-Item -LiteralPath (Join-Path $hardeningFixture 'e2e/.auth/admin.json') -Force
    $contributionWithoutHistory = @'
# Upstream Contributions

<!-- upstream-ledger-v1 -->
```json
{
  "schemaVersion": 1,
  "records": [
    {
      "kind": "ISSUE",
      "url": "https://github.com/halo-dev/halo/issues/1",
      "pageState": "OPEN",
      "lifecycleStatus": "REPORTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "0123456789012345678901234567890123456789",
      "evidence": "artifacts/evidence.txt"
    },
    {
      "kind": "PR",
      "url": "https://github.com/halo-dev/halo/pull/2",
      "pageState": "OPEN",
      "lifecycleStatus": "SUBMITTED",
      "haloVersion": "2.26.1",
      "sourceCommit": "0123456789012345678901234567890123456789",
      "headCommit": "fedcba9876543210fedcba9876543210fedcba98",
      "evidence": "artifacts/evidence.txt"
    }
  ]
}
```
'@
    Write-Utf8File $ledgerPath $contributionWithoutHistory
    & git -C $hardeningFixture add docs/upstream-contributions.md
    Assert-FailsOrRecordRed -FixtureRoot $hardeningFixture -Case 'missing contribution narrative and history' -UnexpectedPasses $unexpectedPasses

    if ($unexpectedPasses.Count -gt 0) {
        throw "Verifier hardening RED: missing failures for $($unexpectedPasses -join ', ')."
    }
} finally {
    Remove-Item -LiteralPath $hardeningFixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'verify-publication tests passed.'
