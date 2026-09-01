[CmdletBinding()]
param(
    [ValidateSet('L0', 'L1', 'L2', 'All')]
    [string]$Layer = 'All'
)

$ErrorActionPreference = 'Stop'
$defaultRepositoryRoot = Split-Path -Parent $PSScriptRoot

function Add-ArtifactRequirement {
    param(
        [Collections.Generic.List[object]]$Requirements,
        [ValidateSet('File', 'Glob', 'Tree')][string]$Type,
        [string]$Path
    )

    [void]$Requirements.Add([pscustomobject]@{ Type = $Type; Path = $Path })
}

function Add-EnvironmentRequirements {
    param([Collections.Generic.List[object]]$Requirements, [string]$RelativeRoot)

    foreach ($name in @('docker-ps.txt', 'halo.log', 'postgres.log', 'health.json')) {
        Add-ArtifactRequirement -Requirements $Requirements -Type File -Path "$RelativeRoot/$name"
    }
}

function Add-L0Requirements {
    param([Collections.Generic.List[object]]$Requirements)

    Add-ArtifactRequirement $Requirements Glob 'api-tests/build/test-results/test/*.xml'
    foreach ($path in @(
        'artifacts/quality-gate/L0/live-openapi.json',
        'artifacts/quality-gate/L0/openapi-findings.json',
        'artifacts/quality-gate/L0/counts.json',
        'artifacts/quality-gate/L0/quarantine.json',
        'artifacts/quality-gate/L0/quarantine.yaml',
        'artifacts/quality-gate/summary.jsonl'
    )) {
        Add-ArtifactRequirement $Requirements File $path
    }
    Add-EnvironmentRequirements $Requirements 'artifacts/quality-gate/L0/environment'
}

function Add-L1Requirements {
    param([Collections.Generic.List[object]]$Requirements)

    Add-ArtifactRequirement $Requirements Glob 'api-tests/build/test-results/integrationTest/*.xml'
    Add-ArtifactRequirement $Requirements Tree 'api-tests/build/evidence'
    foreach ($path in @(
        'artifacts/quality-gate/L1/counts.json',
        'artifacts/quality-gate/L1/quarantine.json',
        'artifacts/quality-gate/L1/quarantine.yaml',
        'artifacts/quality-gate/summary.jsonl'
    )) {
        Add-ArtifactRequirement $Requirements File $path
    }
    Add-EnvironmentRequirements $Requirements 'artifacts/quality-gate/L1/environment'
}

function Add-L2Requirements {
    param(
        [Collections.Generic.List[object]]$Requirements,
        [string]$RepositoryRoot,
        [Collections.Generic.List[string]]$ContractFailures
    )

    foreach ($path in @(
        'artifacts/quality-gate/L2/counts.json',
        'artifacts/quality-gate/L2/quarantine.json',
        'artifacts/quality-gate/L2/quarantine.yaml',
        'artifacts/quality-gate/L2/manifests/report-files.txt',
        'artifacts/quality-gate/L2/manifests/trace-files.txt',
        'artifacts/quality-gate/L2/manifests/video-files.txt',
        'artifacts/quality-gate/L2/ordinary/junit.xml',
        'artifacts/quality-gate/L2/ordinary/html-report/index.html',
        'artifacts/quality-gate/summary.jsonl'
    )) {
        Add-ArtifactRequirement $Requirements File $path
    }
    Add-EnvironmentRequirements $Requirements 'artifacts/quality-gate/L2/ordinary-phase/environment'

    $countsRelativePath = 'artifacts/quality-gate/L2/counts.json'
    $countsPath = Join-Path $RepositoryRoot $countsRelativePath
    if (Test-Path -LiteralPath $countsPath -PathType Leaf) {
        try {
            $counts = Get-Content -Raw -LiteralPath $countsPath | ConvertFrom-Json
            if ($counts.ordinaryJourneys -lt 0 -or $counts.ordinaryJourneys -gt 9 -or
                $counts.expiryJourneys -notin 0, 1) {
                throw 'count values are outside the L2 contract'
            }
            if ($counts.expiryJourneys -eq 1) {
                foreach ($path in @(
                    'artifacts/quality-gate/L2/expiry/junit.xml',
                    'artifacts/quality-gate/L2/expiry/html-report/index.html'
                )) {
                    Add-ArtifactRequirement $Requirements File $path
                }
                Add-EnvironmentRequirements $Requirements 'artifacts/quality-gate/L2/expiry-phase/environment'
            }
        } catch {
            [void]$ContractFailures.Add("$countsRelativePath (valid L2 count contract)")
        }
    }
}

function Get-MissingQualityGateArtifacts {
    param(
        [ValidateSet('L0', 'L1', 'L2', 'All')][string]$RequestedLayer,
        [string]$RepositoryRoot = $defaultRepositoryRoot
    )

    $requirements = [Collections.Generic.List[object]]::new()
    $contractFailures = [Collections.Generic.List[string]]::new()
    $requested = if ($RequestedLayer -eq 'All') { @('L0', 'L1', 'L2') } else { @($RequestedLayer) }
    foreach ($item in $requested) {
        switch ($item) {
            'L0' { Add-L0Requirements $requirements }
            'L1' { Add-L1Requirements $requirements }
            'L2' { Add-L2Requirements $requirements $RepositoryRoot $contractFailures }
        }
    }

    $missing = [Collections.Generic.List[string]]::new()
    foreach ($requirement in $requirements) {
        $resolved = Join-Path $RepositoryRoot $requirement.Path
        $present = switch ($requirement.Type) {
            'File' {
                (Test-Path -LiteralPath $resolved -PathType Leaf) -and (Get-Item -LiteralPath $resolved).Length -gt 0
            }
            'Glob' {
                @(Get-ChildItem -Path $resolved -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 0 }).Count -gt 0
            }
            'Tree' {
                (Test-Path -LiteralPath $resolved -PathType Container) -and
                    @(Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Length -gt 0 }).Count -gt 0
            }
        }
        if (-not $present) { [void]$missing.Add($requirement.Path) }
    }
    foreach ($failure in $contractFailures) { [void]$missing.Add($failure) }
    return @($missing | Sort-Object -Unique)
}

if ($MyInvocation.InvocationName -eq '.') { return }

$watch = [Diagnostics.Stopwatch]::StartNew()
$missingArtifacts = @(Get-MissingQualityGateArtifacts -RequestedLayer $Layer)
$watch.Stop()
$result = if ($missingArtifacts.Count -eq 0) { 'PASS' } else { 'FAIL' }
$failureKind = if ($result -eq 'PASS') { 'NONE' } else { 'TEST_TOOL' }
$duration = [Math]::Round($watch.Elapsed.TotalSeconds, 3)

if ($env:GITHUB_OUTPUT) {
    $output = "result=$result`ndurationSeconds=$duration`nfailureKind=$failureKind`nmissingCount=$($missingArtifacts.Count)`n"
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT, $output, [Text.UTF8Encoding]::new($false))
}

Write-Host "Artifact completeness $result for $Layer ($($missingArtifacts.Count) missing)."
foreach ($missing in $missingArtifacts) {
    [Console]::Error.WriteLine("Missing required artifact: $missing")
}
if ($missingArtifacts.Count -gt 0) { exit 1 }
