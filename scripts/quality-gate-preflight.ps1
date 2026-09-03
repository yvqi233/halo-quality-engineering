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
        [ValidateSet('File', 'Glob', 'Tree', 'ForbiddenFile')][string]$Type,
        [string]$Path
    )

    [void]$Requirements.Add([pscustomobject]@{ Type = $Type; Path = $Path })
}

function Add-EnvironmentRequirements {
    param([Collections.Generic.List[object]]$Requirements, [string]$RelativeRoot)

    foreach ($name in @('docker-ps.txt', 'halo.log', 'postgres.log', 'health.json')) {
        Add-ArtifactRequirement -Requirements $Requirements -Type File -Path "$RelativeRoot/$name"
    }
    Add-ArtifactRequirement -Requirements $Requirements -Type ForbiddenFile -Path "$RelativeRoot/COLLECTION_FAILED.txt"
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

function Test-NonEmptyArtifactFile {
    param([string]$Path)

    return (Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-Item -LiteralPath $Path).Length -gt 0
}

function Test-LifecycleStage {
    param([object]$Stage)

    if ($null -eq $Stage -or $Stage.attempted -isnot [bool] -or $Stage.completed -isnot [bool]) {
        return $false
    }
    if (-not $Stage.attempted) {
        return -not $Stage.completed -and $Stage.result -eq 'NOT_RUN'
    }
    return $Stage.completed -and $Stage.result -in 'PASS', 'FAIL'
}

function Test-RetainedPhaseMedia {
    param([string]$RepositoryRoot, [string]$ManifestRelativePath, [string]$Phase)

    $manifestPath = Join-Path $RepositoryRoot $ManifestRelativePath
    if (-not (Test-NonEmptyArtifactFile $manifestPath)) { return $false }
    $phasePrefix = "artifacts/quality-gate/L2/$Phase/"
    $entries = @(Get-Content -LiteralPath $manifestPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -ne 'NONE_RETAINED' -and $_.StartsWith($phasePrefix, [StringComparison]::OrdinalIgnoreCase) })
    if ($entries.Count -eq 0) { return $false }

    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    foreach ($entry in $entries) {
        $resolved = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $entry))
        if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-NonEmptyArtifactFile $resolved)) {
            return $false
        }
    }
    return $true
}

function Add-L2PhaseRequirements {
    param(
        [Collections.Generic.List[object]]$Requirements,
        [Collections.Generic.List[string]]$ContractFailures,
        [string]$RepositoryRoot,
        [ValidateSet('ordinary', 'expiry')][string]$Phase,
        [object]$Lifecycle
    )

    $environmentValid = Test-LifecycleStage $Lifecycle.environment
    $playwrightValid = Test-LifecycleStage $Lifecycle.playwright
    if (-not $environmentValid -or -not $playwrightValid -or
        ($Lifecycle.playwright.attempted -and -not $Lifecycle.environment.attempted)) {
        [void]$ContractFailures.Add("artifacts/quality-gate/L2/phases.json (valid $Phase lifecycle)")
    }
    if ($Lifecycle.environment.attempted) {
        Add-EnvironmentRequirements $Requirements "artifacts/quality-gate/L2/$Phase-phase/environment"
    }
    if (-not $Lifecycle.playwright.attempted) { return }

    $artifactRoot = "artifacts/quality-gate/L2/$Phase"
    $markerRelativePath = "$artifactRoot/SANITIZATION_FAILED.txt"
    $markerPath = Join-Path $RepositoryRoot $markerRelativePath
    $sanitizerBlocked = Test-NonEmptyArtifactFile $markerPath
    if ($sanitizerBlocked) {
        Add-ArtifactRequirement $Requirements File $markerRelativePath
        if ($Lifecycle.playwright.result -ne 'FAIL') {
            [void]$ContractFailures.Add("$markerRelativePath (failed Playwright publication)")
        }
        return
    }

    Add-ArtifactRequirement $Requirements File "$artifactRoot/junit.xml"
    Add-ArtifactRequirement $Requirements File "$artifactRoot/html-report/index.html"
    if ($Lifecycle.playwright.result -eq 'PASS') { return }

    foreach ($kind in @('trace', 'video')) {
        $manifest = "artifacts/quality-gate/L2/manifests/$kind-files.txt"
        if (-not (Test-RetainedPhaseMedia -RepositoryRoot $RepositoryRoot `
                -ManifestRelativePath $manifest -Phase $Phase)) {
            [void]$ContractFailures.Add("$manifest (retained $Phase failure evidence)")
        }
    }
}

function Add-L2Requirements {
    param(
        [Collections.Generic.List[object]]$Requirements,
        [string]$RepositoryRoot,
        [Collections.Generic.List[string]]$ContractFailures
    )

    foreach ($path in @(
        'artifacts/quality-gate/L2/counts.json',
        'artifacts/quality-gate/L2/phases.json',
        'artifacts/quality-gate/L2/quarantine.json',
        'artifacts/quality-gate/L2/quarantine.yaml',
        'artifacts/quality-gate/L2/manifests/report-files.txt',
        'artifacts/quality-gate/L2/manifests/trace-files.txt',
        'artifacts/quality-gate/L2/manifests/video-files.txt',
        'artifacts/quality-gate/summary.jsonl'
    )) {
        Add-ArtifactRequirement $Requirements File $path
    }
    $countsRelativePath = 'artifacts/quality-gate/L2/counts.json'
    $countsPath = Join-Path $RepositoryRoot $countsRelativePath
    if (Test-Path -LiteralPath $countsPath -PathType Leaf) {
        try {
            $counts = Get-Content -Raw -LiteralPath $countsPath | ConvertFrom-Json
            if ($counts.ordinaryJourneys -lt 0 -or $counts.ordinaryJourneys -gt 9 -or
                $counts.expiryJourneys -notin 0, 1) {
                throw 'count values are outside the L2 contract'
            }
        } catch {
            [void]$ContractFailures.Add("$countsRelativePath (valid L2 count contract)")
        }
    }

    $lifecycleRelativePath = 'artifacts/quality-gate/L2/phases.json'
    $lifecyclePath = Join-Path $RepositoryRoot $lifecycleRelativePath
    if (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) {
        try {
            $lifecycle = Get-Content -Raw -LiteralPath $lifecyclePath | ConvertFrom-Json
            if ($lifecycle.schemaVersion -ne 1 -or $null -eq $lifecycle.ordinary -or $null -eq $lifecycle.expiry) {
                throw 'unsupported lifecycle document'
            }
            Add-L2PhaseRequirements $Requirements $ContractFailures $RepositoryRoot ordinary $lifecycle.ordinary
            Add-L2PhaseRequirements $Requirements $ContractFailures $RepositoryRoot expiry $lifecycle.expiry
        } catch {
            [void]$ContractFailures.Add("$lifecycleRelativePath (valid lifecycle document)")
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
                Test-NonEmptyArtifactFile $resolved
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
            'ForbiddenFile' {
                -not (Test-Path -LiteralPath $resolved)
            }
        }
        if (-not $present) {
            $description = if ($requirement.Type -eq 'ForbiddenFile') {
                "$($requirement.Path) (evidence collection failed)"
            } else {
                $requirement.Path
            }
            [void]$missing.Add($description)
        }
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
