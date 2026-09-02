[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runnerPath = Join-Path $PSScriptRoot 'stability.ps1'
$hostExecutable = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-stability-test-$([Guid]::NewGuid().ToString('N'))"
$fakeGatePath = Join-Path $testRoot 'fake-gate.ps1'
$counterPath = Join-Path $testRoot 'gate-invocations.txt'
$commit = $null
$image = 'halohub/halo@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

function Assert-True {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)

    Assert-True ([regex]::IsMatch($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::Multiline)) $Message
}

function Assert-Ordered {
    param([string]$Text, [string[]]$Tokens, [string]$Message)

    $position = -1
    foreach ($token in $Tokens) {
        $next = $Text.IndexOf($token, $position + 1, [StringComparison]::Ordinal)
        if ($next -lt 0) { throw "$Message Missing token: $token" }
        $position = $next
    }
}

function Invoke-TestRunner {
    param([int]$Runs, [string]$Mode)

    $env:HALO_STABILITY_FAKE_MODE = $Mode
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath,
        '-Runs', [string]$Runs, '-Layer', 'All',
        '-RepositoryRoot', $testRoot, '-GateScriptPath', $fakeGatePath
    )
    $output = @(& $hostExecutable @arguments)
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{ exitCode = $exitCode; output = @($output) }
}

function Invoke-TestGit {
    param([string[]]$Arguments)

    $output = @(& git -C $testRoot @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Test Git command failed: git -C $testRoot $($Arguments -join ' ')" }
    return ($output -join '').Trim()
}

function Reset-Fixture {
    $artifactRoot = Join-Path $testRoot 'artifacts'
    if (Test-Path -LiteralPath $artifactRoot) {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $counterPath) {
        Remove-Item -LiteralPath $counterPath -Force
    }
}

function Assert-RejectedSummary {
    param([string]$Mode)

    Reset-Fixture
    $summaryRun = Invoke-TestRunner -Runs 3 -Mode $Mode
    Assert-True ($summaryRun.exitCode -eq 1) "$Mode gate summary must fail the stability process."
    Assert-True ((Get-Content -Raw $counterPath) -eq '1') `
        "$Mode summary rejection must stop after the first gate invocation."
    $summaryRecords = @(Get-Content (Join-Path $testRoot 'artifacts/stability/runs.jsonl') |
        ForEach-Object { ConvertFrom-Json -InputObject $_ })
    Assert-True ($summaryRecords.Count -eq 1) "$Mode summary rejection must write one factual failure record."
    Assert-True ($summaryRecords[0].result -eq 'FAIL' -and $summaryRecords[0].failureKind -eq 'TEST_TOOL') `
        "$Mode exit-0 summary must be rejected as TEST_TOOL."
}

try {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "stability.ps1 has parse errors: $($parseErrors.Message -join '; ')"
    $runner = Get-Content -Raw $runnerPath
    Assert-Match $runner '\$repoRoot = if \(\$RepositoryRoot\).*else \{ Split-Path -Parent \$PSScriptRoot \}' `
        'The default repository root must remain the parent of the script directory.'
    Assert-Match $runner '\$gateScript = if \(\$GateScriptPath\).*else \{ Join-Path \$PSScriptRoot ''quality-gate\.ps1'' \}' `
        'The default gate path must remain scripts/quality-gate.ps1.'
    Assert-Match $runner "@\('-File', \`$gateScript, '-Layer', \`$Layer, '-QuarantineMode', 'MainChain'\)" `
        'The production quality-gate invocation contract changed.'
    Assert-Ordered $runner @('$gateOutput = @(& $hostExecutable @arguments)', '$gateExitCode = $LASTEXITCODE', '$gateOutput | ForEach-Object') `
        'The child exit code must be captured before gate output is rendered.'
    Assert-True (-not [regex]::IsMatch($runner, '(?i)\b(?:retry|rerun)\b')) `
        'The stability runner must not retry or rerun a failed sequence.'

    New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'environment') | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $testRoot 'environment/image-lock.env'),
        "HALO_IMAGE=$image`n",
        [Text.UTF8Encoding]::new($false))
    $fakeGate = @'
param(
    [string]$Layer,
    [string]$QuarantineMode
)

$ErrorActionPreference = 'Stop'
if ($Layer -ne 'All' -or $QuarantineMode -ne 'MainChain') {
    throw 'The stability runner changed the production gate arguments.'
}
$testRoot = $PSScriptRoot
$counterPath = Join-Path $testRoot 'gate-invocations.txt'
$count = if (Test-Path -LiteralPath $counterPath) { [int](Get-Content -Raw $counterPath) } else { 0 }
$count++
[IO.File]::WriteAllText($counterPath, [string]$count, [Text.UTF8Encoding]::new($false))
$qualityRoot = Join-Path $testRoot 'artifacts/quality-gate'
New-Item -ItemType Directory -Force -Path $qualityRoot | Out-Null
[IO.File]::WriteAllText(
    (Join-Path $qualityRoot 'evidence.txt'),
    "evidence-$count",
    [Text.UTF8Encoding]::new($false))
$summaryPath = Join-Path $qualityRoot 'summary.jsonl'

if ($env:HALO_STABILITY_FAKE_MODE -eq 'MissingSummary') {
    exit 0
}

if ($env:HALO_STABILITY_FAKE_MODE -eq 'MalformedSummary') {
    [IO.File]::WriteAllText($summaryPath, '{not-json', [Text.UTF8Encoding]::new($false))
    exit 0
}

if ($env:HALO_STABILITY_FAKE_MODE -eq 'IncompleteSummary') {
    $lines = @(
        '{"layer":"L0","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"contract"}',
        '{"layer":"L1","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"api-smoke"}'
    )
    [IO.File]::WriteAllLines($summaryPath, $lines, [Text.UTF8Encoding]::new($false))
    exit 0
}

if ($count -eq 1) {
    $lines = @(
        '{"layer":"L0","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"contract"}',
        '{"layer":"L1","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"api-smoke"}',
        '{"layer":"L2","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"chromium-e2e"}'
    )
    [IO.File]::WriteAllLines($summaryPath, $lines, [Text.UTF8Encoding]::new($false))
    exit 0
}

$lines = @(
    '{"layer":"L0","result":"PASS","durationSeconds":1,"failureKind":"NONE","artifactName":"contract"}',
    '{"layer":"L1","result":"FAIL","durationSeconds":1,"failureKind":"PRODUCT","artifactName":"api-smoke"}'
)
[IO.File]::WriteAllLines($summaryPath, $lines, [Text.UTF8Encoding]::new($false))
exit 1
'@
    [IO.File]::WriteAllText($fakeGatePath, $fakeGate, [Text.UTF8Encoding]::new($false))
    [void](Invoke-TestGit -Arguments @('init', '--quiet'))
    [void](Invoke-TestGit -Arguments @(
        '-c', 'user.name=Halo Stability Test',
        '-c', 'user.email=halo-stability@example.invalid',
        'commit', '--allow-empty', '--quiet', '-m', 'initialize stability fixture'))
    $commit = Invoke-TestGit -Arguments @('rev-parse', 'HEAD')

    $failureRun = Invoke-TestRunner -Runs 5 -Mode 'FailSecond'
    Assert-True ($failureRun.exitCode -eq 1) 'A failed gate must fail the stability process.'
    Assert-True ((Get-Content -Raw $counterPath) -eq '2') `
        'The runner must invoke the gate once per completed sequence and stop immediately after failure.'
    $records = @(Get-Content (Join-Path $testRoot 'artifacts/stability/runs.jsonl') |
        ForEach-Object { ConvertFrom-Json -InputObject $_ })
    Assert-True ($records.Count -eq 2) 'The runner must write exactly one record per gate invocation.'
    $expectedFields = @('sequence', 'startedAt', 'commit', 'haloImage', 'result', 'durationSeconds', 'failureKind')
    Assert-True ((Compare-Object $expectedFields @($records[0].PSObject.Properties.Name)).Count -eq 0) `
        'Runner records must contain exactly the seven-field interface.'
    Assert-True ($records[0].result -eq 'PASS' -and $records[1].result -eq 'FAIL') `
        'The runner must retain the PASS then record the first failure.'
    Assert-True ($records[0].commit -eq $commit -and $records[1].commit -eq $commit) `
        'Runner records must use the real revision resolved from the fixture repository.'
    Assert-True ($records[1].failureKind -eq 'PRODUCT') 'The gate failure kind must be retained.'
    $failureRoots = @(Get-ChildItem (Join-Path $testRoot 'artifacts/stability/failures') -Directory)
    Assert-True ($failureRoots.Count -eq 1) 'Exactly one failed-attempt evidence directory is required.'
    Assert-True (Test-Path (Join-Path $failureRoots[0].FullName 'quality-gate/evidence.txt')) `
        'Failed quality-gate evidence must be preserved.'
    Assert-True (Test-Path (Join-Path $failureRoots[0].FullName 'runs.jsonl')) `
        'The failed run record must be preserved with its evidence.'

    foreach ($mode in @('IncompleteSummary', 'MissingSummary', 'MalformedSummary')) {
        Assert-RejectedSummary -Mode $mode
    }

    Write-Output 'stability runner hermetic tests passed'
} finally {
    Remove-Item Env:HALO_STABILITY_FAKE_MODE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
