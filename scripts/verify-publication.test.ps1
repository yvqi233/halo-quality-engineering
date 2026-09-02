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

function New-PublicationFixture {
    $path = Join-Path ([IO.Path]::GetTempPath()) "halo-publication-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    & git -C $path init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize publication fixture repository.' }

    Write-Utf8File (Join-Path $path 'artifacts/evidence.txt') "redacted evidence`n"
    Write-Utf8File (Join-Path $path 'README.md') @'
# Fixture

## Measured Results

- Qualified claim with [evidence](artifacts/evidence.txt).
'@
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
'@
    & git -C $path add README.md docs artifacts
    if ($LASTEXITCODE -ne 0) { throw 'Could not track publication fixture files.' }
    return $path
}

function Invoke-Verifier {
    param([string]$FixtureRoot, [switch]$ExpectSuccess, [string]$Case = 'fixture')

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierPath `
            -RepositoryRoot $FixtureRoot -SkipLiveChecks -Verbose 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($ExpectSuccess) {
        Assert-True ($exitCode -eq 0) "Expected verifier success, got exit ${exitCode}: $($output -join [Environment]::NewLine)"
    } else {
        Assert-True ($exitCode -ne 0) "Expected verifier failure for $Case, but it succeeded: $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine)
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

    Write-Utf8File (Join-Path $fixture 'e2e/fixture.ts') "const password = 'HaloQE!2026';`n"
    Write-Utf8File (Join-Path $fixture 'api-tests/bin/leak.txt') $tokenFixtureValue
    & git -C $fixture add e2e/fixture.ts
    [void](Invoke-Verifier -FixtureRoot $fixture -ExpectSuccess)
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'verify-publication tests passed.'
