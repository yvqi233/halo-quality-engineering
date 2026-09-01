[CmdletBinding()]
param(
    [ValidateSet('L0', 'L1', 'L2', 'All')]
    [string]$Layer = 'All',
    [ValidateSet('MainChain', 'Nightly')]
    [string]$QuarantineMode = 'MainChain'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $repoRoot 'artifacts/quality-gate'
$summaryPath = Join-Path $artifactRoot 'summary.jsonl'
$baselinePath = Join-Path $repoRoot 'contracts/baseline/halo-2.26-openapi.json'
$captureScript = Join-Path $PSScriptRoot 'capture-openapi.ps1'
$collectorScript = Join-Path $PSScriptRoot 'collect-evidence.ps1'
$quarantineValidator = Join-Path $PSScriptRoot 'validate-quarantine.mjs'
$quarantinePath = Join-Path $repoRoot 'docs/quarantine.yaml'
$isWindowsPlatform = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [Runtime.InteropServices.OSPlatform]::Windows)
$gradleCommand = if ($isWindowsPlatform) {
    Join-Path $repoRoot 'gradlew.bat'
} else {
    Join-Path $repoRoot 'gradlew'
}
$playwrightCommand = if ($isWindowsPlatform) {
    Join-Path $repoRoot 'e2e/node_modules/.bin/playwright.cmd'
} else {
    Join-Path $repoRoot 'e2e/node_modules/.bin/playwright'
}

$ExpectedApiScenarioIds = @(
    'A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07', 'A08',
    'P01', 'P02', 'P03', 'P04', 'P05', 'P06', 'P07', 'P08', 'P09', 'P10', 'P11',
    'R01', 'R02', 'R03', 'R04', 'R05', 'R06', 'R07', 'R08', 'R09'
)
$ExpectedJourneyIds = @('E01', 'E02', 'E03', 'E04', 'E05', 'E06', 'E07', 'E08', 'E09', 'E10')
$ApiTestPatterns = [ordered]@{
    A01 = '*AuthenticationIT.adminValidCredentials'
    A02 = '*AuthenticationIT.wrongPasswordIsDenied'
    A03 = '*AuthenticationIT.missingAuthenticationIsDenied'
    A04 = '*AuthenticationIT.authorValidCredentials'
    A05 = '*AuthenticationIT.readonlyValidCredentials'
    A06 = '*AuthenticationIT.disabledAuthorIsDenied'
    A07 = '*AuthenticationIT.disabledAuthorCreatesNoPost'
    A08 = '*AuthenticationIT.reenabledAuthorAuthenticates'
    P01 = '*PostLifecycleIT.createDraft'
    P02 = '*PostLifecycleIT.draftIsNotPublic'
    P03 = '*PostLifecycleIT.publishReachesPublished'
    P04 = '*PostLifecycleIT.publicApiMatchesTitleAndSlug'
    P05 = '*PostLifecycleIT.permalinkServesTitle'
    P06 = '*PostLifecycleIT.unpublishClearsPublishFlag'
    P07 = '*PostLifecycleIT.unpublishedPostIsNotPublic'
    P08 = '*PostLifecycleIT.recycleRemovesPublicPost'
    P09 = '*PostLifecycleIT.publishUnknownNameIsDenied'
    P10 = '*PostLifecycleIT.repeatedPublishIsIdempotent'
    P11 = '*PostLifecycleIT.concurrentUpdatesPreserveCompletePair'
    R01 = '*PostPermissionIT.adminCreatesDraft'
    R02 = '*PostPermissionIT.contributorCreatesOwnDraft'
    R03 = '*PostPermissionIT.readonlyCreateIsDenied'
    R04 = '*PostPermissionIT.readonlyDenialLeavesNoResource'
    R05 = '*PostPermissionIT.contributorCannotPublish'
    R06 = '*PostPermissionIT.contributorPublishDenialPreservesDraft'
    R07 = '*PostPermissionIT.adminPublishesContributorPost'
    R08 = '*PostPermissionIT.contributorCannotUpdateAnotherOwnersPost'
    R09 = '*PostPermissionIT.unauthenticatedCreateIsDenied'
}

function Write-Utf8File {
    param([string]$Path, [AllowEmptyString()][string]$Value)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Remove-SafeTree {
    param([string]$Path)

    $root = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath($Path)
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the repository: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

function Invoke-NativeCommand {
    param([string]$FilePath, [string[]]$Arguments, [string]$Description)

    $output = @(& $FilePath @Arguments)
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Description failed with exit code $exitCode." }
}

function Invoke-EnvironmentAction {
    param([ValidateSet('Up', 'Down', 'Initialize')][string]$Action)

    & (Join-Path $PSScriptRoot 'environment.ps1') -Action $Action | ForEach-Object { Write-Host $_ }
}

function Invoke-GateBody {
    param([scriptblock]$Body, [string]$PhaseArtifactRoot)

    & $Body $PhaseArtifactRoot
}

function Set-GateFailureKind {
    param([ValidateSet('ENVIRONMENT', 'PRODUCT', 'CONTRACT', 'TEST_TOOL')][string]$Kind)

    $script:GateFailureKind = $Kind
}

function Invoke-LayerPhase {
    param(
        [string]$Name,
        [string]$SessionTimeout,
        [string]$PhaseArtifactRoot,
        [scriptblock]$Body
    )

    New-Item -ItemType Directory -Force -Path $PhaseArtifactRoot | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $primaryMessage = $null
    $primaryKind = 'NONE'
    Set-GateFailureKind 'ENVIRONMENT'
    $secondaryMessages = [Collections.Generic.List[string]]::new()
    $previousTimeout = $env:HALO_SESSION_TIMEOUT

    try {
        $env:HALO_SESSION_TIMEOUT = $SessionTimeout
        try {
            Invoke-EnvironmentAction -Action Down
            Invoke-EnvironmentAction -Action Up
            Invoke-EnvironmentAction -Action Initialize
            Invoke-GateBody -Body $Body -PhaseArtifactRoot $PhaseArtifactRoot
        } catch {
            $primaryMessage = $_.Exception.Message
            $primaryKind = $script:GateFailureKind
        }

        try {
            & $collectorScript -ArtifactRoot (Join-Path $PhaseArtifactRoot 'environment') |
                ForEach-Object { Write-Host $_ }
        } catch {
            $message = "evidence collection: $($_.Exception.Message)"
            if ($null -eq $primaryMessage) {
                $primaryMessage = $message
                $primaryKind = 'TEST_TOOL'
            } else {
                [void]$secondaryMessages.Add($message)
            }
        }

        try {
            & (Join-Path $PSScriptRoot 'environment.ps1') -Action Down |
                ForEach-Object { Write-Host $_ }
        } catch {
            $message = "environment teardown: $($_.Exception.Message)"
            if ($null -eq $primaryMessage) {
                $primaryMessage = $message
                $primaryKind = 'ENVIRONMENT'
            } else {
                [void]$secondaryMessages.Add($message)
            }
        }
    } finally {
        if ($null -eq $previousTimeout) {
            Remove-Item Env:HALO_SESSION_TIMEOUT -ErrorAction SilentlyContinue
        } else {
            $env:HALO_SESSION_TIMEOUT = $previousTimeout
        }
        $watch.Stop()
    }

    if ($null -ne $primaryMessage) {
        [Console]::Error.WriteLine("$Name failed [$primaryKind]: $primaryMessage")
        foreach ($secondary in $secondaryMessages) {
            [Console]::Error.WriteLine("$Name additional failure: $secondary")
        }
    }

    Write-Output -NoEnumerate ([pscustomobject]@{
        result = if ($null -eq $primaryMessage) { 'PASS' } else { 'FAIL' }
        durationSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        failureKind = $primaryKind
        primaryMessage = $primaryMessage
        secondaryMessages = @($secondaryMessages)
    })
}

function Get-QuarantineEntries {
    param([string]$LayerArtifactRoot)

    $jsonLines = @(& node $quarantineValidator --file $quarantinePath --format json)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "Quarantine validation failed with exit code $exitCode." }
    $json = $jsonLines -join [Environment]::NewLine
    Write-Utf8File -Path (Join-Path $LayerArtifactRoot 'quarantine.json') -Value $json
    Copy-Item -LiteralPath $quarantinePath -Destination (Join-Path $LayerArtifactRoot 'quarantine.yaml') -Force
    $parsed = ConvertFrom-Json -InputObject $json
    $entries = @($parsed)
    $knownIds = @($ExpectedApiScenarioIds + $ExpectedJourneyIds)
    $unknown = @($entries | ForEach-Object { $_.testId } | Where-Object { $_ -notin $knownIds })
    if ($unknown.Count -gt 0) {
        throw "Unsupported quarantine testId(s): $($unknown -join ', ')"
    }
    return $entries
}

function Get-ExcludedIds {
    param([object[]]$Entries, [string[]]$AllowedIds)

    if ($QuarantineMode -eq 'Nightly') { return @() }
    return @($Entries | ForEach-Object { $_.testId } | Where-Object { $_ -in $AllowedIds } | Sort-Object -Unique)
}

function Get-JUnitCases {
    param([string]$Path)

    $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { throw "No JUnit XML files found at $Path." }
    $cases = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        [xml]$document = Get-Content -Raw -LiteralPath $file.FullName
        foreach ($testcase in @($document.SelectNodes('//testcase'))) {
            [void]$cases.Add([pscustomobject]@{ name = [string]$testcase.name; classname = [string]$testcase.classname })
        }
    }
    return @($cases)
}

function Assert-ExactIds {
    param([object[]]$Cases, [string[]]$ExpectedIds, [string]$PrefixPattern, [string]$Description)

    $actualIds = @($Cases | ForEach-Object {
        $match = [regex]::Match($_.name, "^($PrefixPattern)\s")
        if ($match.Success) { $match.Groups[1].Value }
    })
    $difference = if ($ExpectedIds.Count -eq 0 -and $actualIds.Count -eq 0) {
        @()
    } else {
        @(Compare-Object @($ExpectedIds | Sort-Object) @($actualIds | Sort-Object))
    }
    if ($difference.Count -gt 0 -or $actualIds.Count -ne $ExpectedIds.Count) {
        throw "$Description inventory mismatch. Expected $($ExpectedIds.Count), observed $($actualIds.Count)."
    }
}

function Assert-ExactCaseInventory {
    param([object[]]$Cases, [string[]]$ExpectedIds, [string]$PrefixPattern, [string]$Description)

    $actualIds = [Collections.Generic.List[string]]::new()
    $unclassified = [Collections.Generic.List[string]]::new()
    foreach ($case in $Cases) {
        $match = [regex]::Match($case.name, "^($PrefixPattern)\s")
        if ($match.Success) {
            [void]$actualIds.Add($match.Groups[1].Value)
        } else {
            [void]$unclassified.Add($case.name)
        }
    }
    $difference = if ($ExpectedIds.Count -eq 0 -and $actualIds.Count -eq 0) {
        @()
    } else {
        @(Compare-Object @($ExpectedIds | Sort-Object) @($actualIds | Sort-Object))
    }
    if ($unclassified.Count -gt 0 -or $difference.Count -gt 0 -or $Cases.Count -ne $ExpectedIds.Count) {
        $unclassifiedText = if ($unclassified.Count -eq 0) { 'none' } else { $unclassified -join ', ' }
        throw "$Description inventory mismatch. Expected $($ExpectedIds.Count) exact records, observed $($Cases.Count); unclassified: $unclassifiedText."
    }
}

function Write-Counts {
    param([string]$Path, [Collections.Specialized.OrderedDictionary]$Counts)

    Write-Utf8File -Path $Path -Value ($Counts | ConvertTo-Json -Depth 8)
}

function Invoke-OpenApiComparison {
    param([string]$LayerArtifactRoot)

    $candidatePath = Join-Path $LayerArtifactRoot 'live-openapi.json'
    & $captureScript -BaselinePath $candidatePath | ForEach-Object { Write-Host $_ }
    $findings = @(& node (Join-Path $repoRoot 'contracts/openapi-check/check.mjs') $baselinePath $candidatePath)
    $exitCode = $LASTEXITCODE
    Write-Utf8File -Path (Join-Path $LayerArtifactRoot 'openapi-findings.json') -Value ($findings -join [Environment]::NewLine)
    $findings | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "Live OpenAPI comparison failed with exit code $exitCode." }
}

function Complete-Layer {
    param([string]$Name, [string]$ArtifactName, [object[]]$Phases)

    $failed = @($Phases | Where-Object { $_.result -eq 'FAIL' })
    $duration = ($Phases | Measure-Object -Property durationSeconds -Sum).Sum
    $record = [ordered]@{
        layer = $Name
        result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
        durationSeconds = [Math]::Round([double]$duration, 3)
        failureKind = if ($failed.Count -eq 0) { 'NONE' } else { $failed[0].failureKind }
        artifactName = $ArtifactName
    }
    [IO.File]::AppendAllText($summaryPath, (($record | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Write-Host ($record | ConvertTo-Json -Compress)
    return [pscustomobject]$record
}

function Invoke-L0 {
    $layerRoot = Join-Path $artifactRoot 'L0'
    Remove-SafeTree $layerRoot
    New-Item -ItemType Directory -Force -Path $layerRoot | Out-Null
    $body = {
        param($phaseRoot)

        Set-GateFailureKind 'TEST_TOOL'
        Remove-SafeTree (Join-Path $repoRoot 'api-tests/build/classes/java/test')
        Remove-SafeTree (Join-Path $repoRoot 'api-tests/build/test-results/test')
        Remove-SafeTree (Join-Path $repoRoot 'api-tests/build/reports/tests/test')
        Invoke-NativeCommand -FilePath $gradleCommand -Arguments @(':api-tests:compileTestJava', ':api-tests:test') -Description 'L0 Java compile/unit'
        $unitCases = @(Get-JUnitCases (Join-Path $repoRoot 'api-tests/build/test-results/test'))
        $entries = @(Get-QuarantineEntries $layerRoot)
        Set-GateFailureKind 'CONTRACT'
        Invoke-OpenApiComparison $layerRoot
        Write-Counts -Path (Join-Path $layerRoot 'counts.json') -Counts ([ordered]@{
            unitTests = $unitCases.Count
            quarantinedCases = $entries.Count
            contractFindings = 0
        })
    }.GetNewClosure()
    $phase = Invoke-LayerPhase -Name 'L0' -SessionTimeout 'PT30M' -PhaseArtifactRoot $layerRoot -Body $body
    return Complete-Layer -Name 'L0' -ArtifactName 'contract' -Phases @($phase)
}

function Invoke-L1 {
    $layerRoot = Join-Path $artifactRoot 'L1'
    Remove-SafeTree $layerRoot
    New-Item -ItemType Directory -Force -Path $layerRoot | Out-Null
    $body = {
        param($phaseRoot)

        Set-GateFailureKind 'TEST_TOOL'
        $entries = @(Get-QuarantineEntries $layerRoot)
        $excluded = @(Get-ExcludedIds -Entries $entries -AllowedIds $ExpectedApiScenarioIds)
        $selectedIds = @($ExpectedApiScenarioIds | Where-Object { $_ -notin $excluded })
        Remove-SafeTree (Join-Path $repoRoot 'api-tests/build/evidence')
        $arguments = [Collections.Generic.List[string]]::new()
        [void]$arguments.Add(':api-tests:integrationTest')
        if ($excluded.Count -gt 0) {
            [void]$arguments.Add('--tests')
            [void]$arguments.Add('*HaloApiContractIT')
            foreach ($id in $selectedIds) {
                [void]$arguments.Add('--tests')
                [void]$arguments.Add($ApiTestPatterns[$id])
            }
        }
        Set-GateFailureKind 'PRODUCT'
        Invoke-NativeCommand -FilePath $gradleCommand -Arguments @($arguments) -Description 'L1 API matrix'
        Set-GateFailureKind 'TEST_TOOL'
        $cases = @(Get-JUnitCases (Join-Path $repoRoot 'api-tests/build/test-results/integrationTest'))
        Assert-ExactIds -Cases $cases -ExpectedIds $selectedIds -PrefixPattern '[APR]\d{2}' -Description 'L1 API scenario'
        $infrastructure = @($cases | Where-Object { $_.name -notmatch '^[APR]\d{2}\s' })
        if ($infrastructure.Count -ne 1) { throw "L1 expected 1 infrastructure record, observed $($infrastructure.Count)." }
        Write-Counts -Path (Join-Path $layerRoot 'counts.json') -Counts ([ordered]@{
            apiScenarios = $selectedIds.Count
            infrastructure = $infrastructure.Count
            quarantinedExcluded = $excluded
        })
    }.GetNewClosure()
    $phase = Invoke-LayerPhase -Name 'L1' -SessionTimeout 'PT30M' -PhaseArtifactRoot $layerRoot -Body $body
    return Complete-Layer -Name 'L1' -ArtifactName 'api-smoke' -Phases @($phase)
}

function Test-PlaywrightToolFailureArtifact {
    param([string]$ArtifactPath)

    if (Test-Path -LiteralPath (Join-Path $ArtifactPath 'SANITIZATION_FAILED.txt')) {
        return $true
    }
    $junitPath = Join-Path $ArtifactPath 'junit.xml'
    return (Test-Path -LiteralPath $junitPath) -and
        (Get-Content -Raw -LiteralPath $junitPath) -match 'cleanup failed:|Credential-safe artifact publishing blocked'
}

function Invoke-Playwright {
    param([string]$ArtifactPath, [string[]]$Arguments, [string]$Description)

    if (-not (Test-Path -LiteralPath $playwrightCommand)) {
        throw 'Playwright is unavailable. Run pnpm install --frozen-lockfile in e2e first.'
    }
    $previousArtifactPath = $env:PW_ARTIFACT_DIR
    $previousInvocationId = $env:HALO_QE_INVOCATION_ID
    $previousRunId = $env:QE_RUN_ID
    $env:PW_ARTIFACT_DIR = $ArtifactPath
    $env:HALO_QE_INVOCATION_ID = "gate-$([Guid]::NewGuid().ToString('N'))"
    $env:QE_RUN_ID = "gate-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
    Push-Location (Join-Path $repoRoot 'e2e')
    try {
        try {
            Invoke-NativeCommand -FilePath $playwrightCommand -Arguments $Arguments -Description $Description
        } catch {
            if (Test-PlaywrightToolFailureArtifact -ArtifactPath $ArtifactPath) {
                Set-GateFailureKind 'TEST_TOOL'
            }
            throw
        }
    } finally {
        Pop-Location
        foreach ($item in @(
            @{ Name = 'PW_ARTIFACT_DIR'; Value = $previousArtifactPath },
            @{ Name = 'HALO_QE_INVOCATION_ID'; Value = $previousInvocationId },
            @{ Name = 'QE_RUN_ID'; Value = $previousRunId }
        )) {
            if ($null -eq $item.Value) {
                Remove-Item "Env:$($item.Name)" -ErrorAction SilentlyContinue
            } else {
                Set-Item "Env:$($item.Name)" $item.Value
            }
        }
    }
}

function Write-PlaywrightInventory {
    param([string]$LayerRoot)

    $manifestRoot = Join-Path $LayerRoot 'manifests'
    New-Item -ItemType Directory -Force -Path $manifestRoot | Out-Null
    $allFiles = @(Get-ChildItem -LiteralPath $LayerRoot -Recurse -File -ErrorAction SilentlyContinue)
    $groups = [ordered]@{
        'report-files.txt' = @($allFiles | Where-Object { $_.Name -eq 'junit.xml' -or $_.FullName -match '[\\/]html-report[\\/]' })
        'trace-files.txt' = @($allFiles | Where-Object { $_.Name -eq 'trace.zip' })
        'video-files.txt' = @($allFiles | Where-Object { $_.Extension -eq '.webm' })
    }
    foreach ($entry in $groups.GetEnumerator()) {
        $paths = @($entry.Value | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/') })
        $value = if ($paths.Count -eq 0) { 'NONE_RETAINED' } else { $paths -join [Environment]::NewLine }
        Write-Utf8File -Path (Join-Path $manifestRoot $entry.Key) -Value ($value + [Environment]::NewLine)
    }
}

function Invoke-L2 {
    $layerRoot = Join-Path $artifactRoot 'L2'
    Remove-SafeTree $layerRoot
    New-Item -ItemType Directory -Force -Path $layerRoot | Out-Null
    Write-PlaywrightInventory $layerRoot
    $l2State = [pscustomobject]@{
        entries = @()
        excluded = @()
        ordinaryCount = 0
        infrastructureCount = 0
        expiryCount = 0
    }

    $ordinaryBody = {
        param($phaseRoot)

        Set-GateFailureKind 'TEST_TOOL'
        $l2State.entries = @(Get-QuarantineEntries $layerRoot)
        $l2State.excluded = @(Get-ExcludedIds -Entries $l2State.entries -AllowedIds $ExpectedJourneyIds)
        $selected = @($ExpectedJourneyIds[0..8] | Where-Object { $_ -notin $l2State.excluded })
        $l2State.ordinaryCount = $selected.Count
        $excludedPattern = @('@session-expiry') + @($l2State.excluded | Where-Object { $_ -ne 'E10' })
        Set-GateFailureKind 'PRODUCT'
        Invoke-Playwright -ArtifactPath (Join-Path $layerRoot 'ordinary') `
            -Arguments @('test', '--project=chromium', '--grep-invert', ($excludedPattern -join '|')) `
            -Description 'L2 ordinary Chromium journeys'
        Set-GateFailureKind 'TEST_TOOL'
        $cases = @(Get-JUnitCases (Join-Path $layerRoot 'ordinary'))
        $expectedOrdinaryIds = @($selected) + @('I01', 'I02')
        Assert-ExactCaseInventory -Cases $cases -ExpectedIds $expectedOrdinaryIds `
            -PrefixPattern '(?:E|I)\d{2}' -Description 'L2 ordinary journey and infrastructure'
        $l2State.infrastructureCount = 2
    }.GetNewClosure()

    $ordinaryPhase = Invoke-LayerPhase -Name 'L2-ordinary' -SessionTimeout 'PT30M' `
        -PhaseArtifactRoot (Join-Path $layerRoot 'ordinary-phase') -Body $ordinaryBody
    $phases = [Collections.Generic.List[object]]::new()
    [void]$phases.Add($ordinaryPhase)

    if ($ordinaryPhase.result -eq 'PASS' -and 'E10' -notin $l2State.excluded) {
        $expiryBody = {
            param($phaseRoot)

            Set-GateFailureKind 'PRODUCT'
            Invoke-Playwright -ArtifactPath (Join-Path $layerRoot 'expiry') `
                -Arguments @('test', '--project=chromium', '--grep', '@session-expiry', '--no-deps') `
                -Description 'L2 E10 Chromium journey'
            Set-GateFailureKind 'TEST_TOOL'
            $cases = @(Get-JUnitCases (Join-Path $layerRoot 'expiry'))
            Assert-ExactCaseInventory -Cases $cases -ExpectedIds @('E10') `
                -PrefixPattern 'E\d{2}' -Description 'L2 expiry journey'
            $l2State.expiryCount = 1
        }.GetNewClosure()
        $expiryPhase = Invoke-LayerPhase -Name 'L2-expiry' -SessionTimeout 'PT5S' `
            -PhaseArtifactRoot (Join-Path $layerRoot 'expiry-phase') -Body $expiryBody
        [void]$phases.Add($expiryPhase)
    }

    Write-PlaywrightInventory $layerRoot
    Write-Counts -Path (Join-Path $layerRoot 'counts.json') -Counts ([ordered]@{
        ordinaryJourneys = $l2State.ordinaryCount
        expiryJourneys = $l2State.expiryCount
        totalJourneys = $l2State.ordinaryCount + $l2State.expiryCount
        infrastructure = $l2State.infrastructureCount
        quarantinedExcluded = $l2State.excluded
    })
    return Complete-Layer -Name 'L2' -ArtifactName 'chromium-e2e' -Phases @($phases)
}

function Get-GateOutcome {
    param([string]$RequestedLayer, [int]$RequestedCount, [object[]]$Results)

    $failedResults = @($Results | Where-Object { $_.result -eq 'FAIL' })
    $result = if ($failedResults.Count -eq 0 -and $Results.Count -eq $RequestedCount) { 'PASS' } else { 'FAIL' }
    return [pscustomobject]@{
        result = $result
        durationSeconds = [Math]::Round([double](($Results | Measure-Object -Property durationSeconds -Sum).Sum), 3)
        failureKind = if ($failedResults.Count -eq 0) { 'NONE' } else { $failedResults[0].failureKind }
        artifactName = if ($RequestedLayer -eq 'All') { 'nightly-regression' } else { $Results[0].artifactName }
        exitCode = if ($result -eq 'PASS') { 0 } else { 1 }
    }
}

function Invoke-QualityGate {
    param([string]$RequestedLayer)

    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    if (Test-Path -LiteralPath $summaryPath) { Remove-Item -LiteralPath $summaryPath -Force }
    $requestedLayers = if ($RequestedLayer -eq 'All') { @('L0', 'L1', 'L2') } else { @($RequestedLayer) }
    $results = [Collections.Generic.List[object]]::new()

    foreach ($requested in $requestedLayers) {
        $result = switch ($requested) {
            'L0' { Invoke-L0 }
            'L1' { Invoke-L1 }
            'L2' { Invoke-L2 }
        }
        [void]$results.Add($result)
        if ($result.result -eq 'FAIL') { break }
    }

    return Get-GateOutcome -RequestedLayer $RequestedLayer -RequestedCount $requestedLayers.Count -Results @($results)
}

if ($MyInvocation.InvocationName -eq '.') { return }
$outcome = Invoke-QualityGate -RequestedLayer $Layer

if ($env:GITHUB_OUTPUT) {
    $output = "result=$($outcome.result)`ndurationSeconds=$($outcome.durationSeconds)`nfailureKind=$($outcome.failureKind)`nartifactName=$($outcome.artifactName)`n"
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT, $output, [Text.UTF8Encoding]::new($false))
}

exit $outcome.exitCode
