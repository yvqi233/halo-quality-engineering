[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Runs = 20,
    [ValidateSet('L0', 'L1', 'L2', 'All')]
    [string]$Layer = 'All',
    [string]$RepositoryRoot,
    [string]$GateScriptPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = if ($RepositoryRoot) { [IO.Path]::GetFullPath($RepositoryRoot) } else { Split-Path -Parent $PSScriptRoot }
$gateScript = if ($GateScriptPath) { [IO.Path]::GetFullPath($GateScriptPath) } else { Join-Path $PSScriptRoot 'quality-gate.ps1' }
$gateSummaryPath = Join-Path $repoRoot 'artifacts/quality-gate/summary.jsonl'
$stabilityRoot = Join-Path $repoRoot 'artifacts/stability'
$recordPath = Join-Path $stabilityRoot 'runs.jsonl'
$lockPath = Join-Path $repoRoot 'environment/image-lock.env'
$expectedLayerCount = if ($Layer -eq 'All') { 3 } else { 1 }

function Invoke-CheckedNative {
    param([string]$FilePath, [string[]]$Arguments, [string]$Description)

    $output = @(& $FilePath @Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
    return ($output -join '').Trim()
}

function Get-HaloImage {
    $line = Get-Content -LiteralPath $lockPath | Where-Object { $_ -match '^HALO_IMAGE=' } | Select-Object -First 1
    if ($null -eq $line) { throw 'HALO_IMAGE is missing from environment/image-lock.env.' }
    $image = $line.Substring('HALO_IMAGE='.Length).Trim()
    if ($image -notmatch '@sha256:[0-9a-f]{64}$') { throw 'HALO_IMAGE must be digest-pinned.' }
    return $image
}

function Get-GateResult {
    param([int]$ExitCode)

    if (-not (Test-Path -LiteralPath $gateSummaryPath -PathType Leaf)) {
        return [pscustomobject]@{ result = 'FAIL'; failureKind = 'TEST_TOOL' }
    }

    try {
        $records = @(Get-Content -LiteralPath $gateSummaryPath | ForEach-Object { ConvertFrom-Json -InputObject $_ })
    } catch {
        return [pscustomobject]@{ result = 'FAIL'; failureKind = 'TEST_TOOL' }
    }
    $failures = @($records | Where-Object { $_.result -eq 'FAIL' })
    $complete = $records.Count -eq $expectedLayerCount -and $failures.Count -eq 0
    if ($ExitCode -eq 0 -and $complete) {
        return [pscustomobject]@{ result = 'PASS'; failureKind = 'NONE' }
    }
    $kind = if ($failures.Count -gt 0 -and $failures[0].failureKind) {
        [string]$failures[0].failureKind
    } else {
        'TEST_TOOL'
    }
    return [pscustomobject]@{ result = 'FAIL'; failureKind = $kind }
}

function Preserve-FailureEvidence {
    param([int]$Sequence, [string]$StartedAt)

    $safeTimestamp = $StartedAt -replace '[:.]', '-'
    $failureRoot = Join-Path $stabilityRoot "failures/sequence-$Sequence-$safeTimestamp"
    New-Item -ItemType Directory -Force -Path $failureRoot | Out-Null
    $qualityGateRoot = Join-Path $repoRoot 'artifacts/quality-gate'
    if (Test-Path -LiteralPath $qualityGateRoot) {
        Copy-Item -LiteralPath $qualityGateRoot -Destination (Join-Path $failureRoot 'quality-gate') -Recurse -Force
    }
    Copy-Item -LiteralPath $recordPath -Destination (Join-Path $failureRoot 'runs.jsonl') -Force
    Write-Host "Failure evidence preserved at $failureRoot"
}

if (-not (Test-Path -LiteralPath $gateScript -PathType Leaf)) { throw 'scripts/quality-gate.ps1 is missing.' }
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw 'environment/image-lock.env is missing.' }

$commit = Invoke-CheckedNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Description 'Git revision lookup'
if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Git revision lookup did not return a full lowercase SHA.' }
$haloImage = Get-HaloImage
$hostExecutable = (Get-Process -Id $PID).Path
if (-not $hostExecutable) { throw 'Unable to resolve the current PowerShell executable.' }

New-Item -ItemType Directory -Force -Path $stabilityRoot | Out-Null
if (Test-Path -LiteralPath $recordPath) { Remove-Item -LiteralPath $recordPath -Force }

for ($sequence = 1; $sequence -le $Runs; $sequence++) {
    $startedAt = [DateTimeOffset]::UtcNow.ToString('O')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "Starting stability run $sequence of $Runs for layer $Layer."

    $arguments = @('-NoProfile')
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        $arguments += @('-ExecutionPolicy', 'Bypass')
    }
    $arguments += @('-File', $gateScript, '-Layer', $Layer, '-QuarantineMode', 'MainChain')
    $gateOutput = @(& $hostExecutable @arguments)
    $gateExitCode = $LASTEXITCODE
    $gateOutput | ForEach-Object { Write-Host $_ }
    $watch.Stop()

    $outcome = Get-GateResult -ExitCode $gateExitCode
    $record = [ordered]@{
        sequence = $sequence
        startedAt = $startedAt
        commit = $commit
        haloImage = $haloImage
        result = $outcome.result
        durationSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        failureKind = $outcome.failureKind
    }
    $json = $record | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($recordPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host $json

    if ($outcome.result -ne 'PASS') {
        Preserve-FailureEvidence -Sequence $sequence -StartedAt $startedAt
        exit 1
    }
}

exit 0
