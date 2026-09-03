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
. (Join-Path $PSScriptRoot 'junit-results.ps1')
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
    param([scriptblock]$Body, [string]$PhaseArtifactRoot, [object]$BodyContext)

    & $Body $PhaseArtifactRoot $BodyContext
}

function Set-GateFailureKind {
    param([ValidateSet('ENVIRONMENT', 'PRODUCT', 'CONTRACT', 'TEST_TOOL')][string]$Kind)

    $script:GateFailureKind = $Kind
}

function Get-JavaFailureKind {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        return 'TEST_TOOL'
    }
    try {
        $records = @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ConvertFrom-Json -InputObject $_ -ErrorAction Stop })
        if ($records.Count -eq 0) { throw 'No classification records were present.' }
        $expectedFields = @('failureKind', 'schemaVersion', 'testClass', 'testId', 'testMethod')
        $allowedKinds = @('ENVIRONMENT', 'PRODUCT', 'CONTRACT', 'TEST_TOOL')
        foreach ($record in $records) {
            $actualFields = @($record.PSObject.Properties.Name | Sort-Object)
            if ((Compare-Object $expectedFields $actualFields).Count -ne 0) {
                throw 'Classification record schema is invalid.'
            }
            if (($record.schemaVersion -isnot [int] -and $record.schemaVersion -isnot [long]) -or
                [long]$record.schemaVersion -ne 1) {
                throw 'Classification schemaVersion must be integer 1.'
            }
            foreach ($field in @('testId', 'testClass', 'testMethod', 'failureKind')) {
                if ($record.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($record.$field)) {
                    throw "Classification $field must be a non-empty string."
                }
            }
            if ($record.failureKind -notin $allowedKinds) {
                throw "Unsupported Java failure kind: $($record.failureKind)"
            }
        }
        $kinds = @($records.failureKind | Sort-Object -Unique)
        if ($kinds.Count -ne 1) { throw 'Java failure evidence contains mixed attribution.' }
        return $kinds[0]
    } catch {
        return 'TEST_TOOL'
    }
}

function Invoke-LayerPhase {
    param(
        [string]$Name,
        [string]$SessionTimeout,
        [string]$PhaseArtifactRoot,
        [scriptblock]$Body,
        [object]$BodyContext
    )

    New-Item -ItemType Directory -Force -Path $PhaseArtifactRoot | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $primaryMessage = $null
    $primaryKind = 'NONE'
    Set-GateFailureKind 'ENVIRONMENT'
    $secondaryMessages = @()
    $previousTimeout = $env:HALO_SESSION_TIMEOUT

    try {
        $env:HALO_SESSION_TIMEOUT = $SessionTimeout
        try {
            Invoke-EnvironmentAction -Action Down
            Invoke-EnvironmentAction -Action Up
            Invoke-EnvironmentAction -Action Initialize
            Invoke-GateBody -Body $Body -PhaseArtifactRoot $PhaseArtifactRoot -BodyContext $BodyContext
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
                $secondaryMessages += $message
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
                $secondaryMessages += $message
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

    return [pscustomobject]@{
        result = if ($null -eq $primaryMessage) { 'PASS' } else { 'FAIL' }
        durationSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        failureKind = $primaryKind
        primaryMessage = $primaryMessage
        secondaryMessages = $secondaryMessages
    }
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

function Write-Counts {
    param([string]$Path, [Collections.Specialized.OrderedDictionary]$Counts)

    Write-Utf8File -Path $Path -Value ($Counts | ConvertTo-Json -Depth 8)
}

function New-PhaseLifecycle {
    return [ordered]@{
        environment = [ordered]@{ attempted = $false; completed = $false; result = 'NOT_RUN' }
        playwright = [ordered]@{ attempted = $false; completed = $false; result = 'NOT_RUN' }
    }
}

function Write-L2Lifecycle {
    param([string]$Path, [Collections.Specialized.OrderedDictionary]$Lifecycle)

    Write-Utf8File -Path $Path -Value ($Lifecycle | ConvertTo-Json -Depth 8)
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
    $bodyContext = [pscustomobject]@{
        repoRoot = $repoRoot
        gradleCommand = $gradleCommand
        layerRoot = $layerRoot
    }
    $body = {
        param($phaseRoot, $context)

        Set-GateFailureKind 'TEST_TOOL'
        Remove-SafeTree (Join-Path $context.repoRoot 'api-tests/build/classes/java/test')
        Remove-SafeTree (Join-Path $context.repoRoot 'api-tests/build/test-results/test')
        Remove-SafeTree (Join-Path $context.repoRoot 'api-tests/build/reports/tests/test')
        Invoke-NativeCommand -FilePath $context.gradleCommand -Arguments @(':api-tests:compileTestJava', ':api-tests:test') -Description 'L0 Java compile/unit'
        $unitCases = @(Get-JUnitCases (Join-Path $context.repoRoot 'api-tests/build/test-results/test'))
        Assert-AllCasesPassed -Cases $unitCases -Description 'L0 Java unit suite'
        $entries = @(Get-QuarantineEntries $context.layerRoot)
        Set-GateFailureKind 'CONTRACT'
        Invoke-OpenApiComparison $context.layerRoot
        Write-Counts -Path (Join-Path $context.layerRoot 'counts.json') -Counts ([ordered]@{
            unitTests = $unitCases.Count
            quarantinedCases = $entries.Count
            contractFindings = 0
        })
    }
    $phase = Invoke-LayerPhase -Name 'L0' -SessionTimeout 'PT30M' -PhaseArtifactRoot $layerRoot `
        -Body $body -BodyContext $bodyContext
    return Complete-Layer -Name 'L0' -ArtifactName 'contract' -Phases @($phase)
}

function Invoke-L1 {
    $layerRoot = Join-Path $artifactRoot 'L1'
    Remove-SafeTree $layerRoot
    New-Item -ItemType Directory -Force -Path $layerRoot | Out-Null
    $bodyContext = [pscustomobject]@{
        repoRoot = $repoRoot
        gradleCommand = $gradleCommand
        layerRoot = $layerRoot
        expectedApiScenarioIds = $ExpectedApiScenarioIds
        apiTestPatterns = $ApiTestPatterns
    }
    $body = {
        param($phaseRoot, $context)

        Set-GateFailureKind 'TEST_TOOL'
        $entries = @(Get-QuarantineEntries $context.layerRoot)
        $excluded = @(Get-ExcludedIds -Entries $entries -AllowedIds $context.expectedApiScenarioIds)
        $selectedIds = @($context.expectedApiScenarioIds | Where-Object { $_ -notin $excluded })
        Remove-SafeTree (Join-Path $context.repoRoot 'api-tests/build/evidence')
        $javaClassificationPath = Join-Path $context.repoRoot 'api-tests/build/failure-classification/integrationTest.jsonl'
        Remove-SafeTree $javaClassificationPath
        $arguments = @(':api-tests:integrationTest')
        if ($excluded.Count -gt 0) {
            $arguments += '--tests'
            $arguments += '*HaloApiContractIT'
            foreach ($id in $selectedIds) {
                $arguments += '--tests'
                $arguments += $context.apiTestPatterns[$id]
            }
        }
        try {
            Invoke-NativeCommand -FilePath $context.gradleCommand -Arguments $arguments -Description 'L1 API matrix'
        } catch {
            if (Test-Path -LiteralPath $javaClassificationPath -PathType Leaf) {
                Copy-Item -LiteralPath $javaClassificationPath `
                    -Destination (Join-Path $context.layerRoot 'failure-classification.jsonl') -Force
            }
            Set-GateFailureKind (Get-JavaFailureKind -Path $javaClassificationPath)
            throw
        }
        if (Test-Path -LiteralPath $javaClassificationPath -PathType Leaf) {
            Copy-Item -LiteralPath $javaClassificationPath `
                -Destination (Join-Path $context.layerRoot 'failure-classification.jsonl') -Force
            Set-GateFailureKind 'TEST_TOOL'
            throw 'Passing L1 Gradle execution produced failure-classification records.'
        }
        Set-GateFailureKind 'TEST_TOOL'
        $cases = @(Get-JUnitCases (Join-Path $context.repoRoot 'api-tests/build/test-results/integrationTest'))
        Assert-ExactIds -Cases $cases -ExpectedIds $selectedIds -PrefixPattern '[APR]\d{2}' -Description 'L1 API scenario'
        $infrastructure = @($cases | Where-Object { $_.name -notmatch '^[APR]\d{2}\s' })
        if ($infrastructure.Count -ne 1) { throw "L1 expected 1 infrastructure record, observed $($infrastructure.Count)." }
        Write-Counts -Path (Join-Path $context.layerRoot 'counts.json') -Counts ([ordered]@{
            apiScenarios = $selectedIds.Count
            infrastructure = $infrastructure.Count
            quarantinedExcluded = $excluded
        })
    }
    $phase = Invoke-LayerPhase -Name 'L1' -SessionTimeout 'PT30M' -PhaseArtifactRoot $layerRoot `
        -Body $body -BodyContext $bodyContext
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
    $lifecyclePath = Join-Path $layerRoot 'phases.json'
    $l2Lifecycle = [ordered]@{
        schemaVersion = 1
        ordinary = New-PhaseLifecycle
        expiry = New-PhaseLifecycle
    }
    Write-L2Lifecycle -Path $lifecyclePath -Lifecycle $l2Lifecycle
    $l2State = [pscustomobject]@{
        entries = @()
        excluded = @()
        ordinaryCount = 0
        infrastructureCount = 0
        expiryCount = 0
    }
    $bodyContext = [pscustomobject]@{
        layerRoot = $layerRoot
        lifecycle = $l2Lifecycle
        lifecyclePath = $lifecyclePath
        state = $l2State
        expectedJourneyIds = $ExpectedJourneyIds
    }

    $ordinaryBody = {
        param($phaseRoot, $context)

        Set-GateFailureKind 'TEST_TOOL'
        $context.state.entries = @(Get-QuarantineEntries $context.layerRoot)
        $context.state.excluded = @(Get-ExcludedIds -Entries $context.state.entries -AllowedIds $context.expectedJourneyIds)
        $selected = @($context.expectedJourneyIds[0..8] | Where-Object { $_ -notin $context.state.excluded })
        $context.state.ordinaryCount = $selected.Count
        $excludedPattern = @('@session-expiry') + @($context.state.excluded | Where-Object { $_ -ne 'E10' })
        Set-GateFailureKind 'PRODUCT'
        $context.lifecycle.ordinary.playwright.attempted = $true
        $context.lifecycle.ordinary.playwright.result = 'RUNNING'
        Write-L2Lifecycle -Path $context.lifecyclePath -Lifecycle $context.lifecycle
        try {
            Invoke-Playwright -ArtifactPath (Join-Path $context.layerRoot 'ordinary') `
                -Arguments @('test', '--project=chromium', '--grep-invert', ($excludedPattern -join '|')) `
                -Description 'L2 ordinary Chromium journeys'
            $context.lifecycle.ordinary.playwright.result = 'PASS'
        } catch {
            $context.lifecycle.ordinary.playwright.result = 'FAIL'
            throw
        } finally {
            $context.lifecycle.ordinary.playwright.completed = $true
            Write-L2Lifecycle -Path $context.lifecyclePath -Lifecycle $context.lifecycle
        }
        Set-GateFailureKind 'TEST_TOOL'
        $cases = @(Get-JUnitCases (Join-Path $context.layerRoot 'ordinary'))
        $expectedOrdinaryIds = @($selected) + @('I01', 'I02')
        Assert-ExactCaseInventory -Cases $cases -ExpectedIds $expectedOrdinaryIds `
            -PrefixPattern '(?:E|I)\d{2}' -Description 'L2 ordinary journey and infrastructure'
        $context.state.infrastructureCount = 2
    }

    $ordinaryPhase = $null
    $l2Lifecycle.ordinary.environment.attempted = $true
    $l2Lifecycle.ordinary.environment.result = 'RUNNING'
    Write-L2Lifecycle -Path $lifecyclePath -Lifecycle $l2Lifecycle
    try {
        $ordinaryPhase = Invoke-LayerPhase -Name 'L2-ordinary' -SessionTimeout 'PT30M' `
            -PhaseArtifactRoot (Join-Path $layerRoot 'ordinary-phase') -Body $ordinaryBody `
            -BodyContext $bodyContext
    } finally {
        $l2Lifecycle.ordinary.environment.completed = $null -ne $ordinaryPhase
        $l2Lifecycle.ordinary.environment.result = if ($null -eq $ordinaryPhase) { 'FAIL' } else { $ordinaryPhase.result }
        Write-L2Lifecycle -Path $lifecyclePath -Lifecycle $l2Lifecycle
    }
    $phases = @($ordinaryPhase)

    if ($ordinaryPhase.result -eq 'PASS' -and 'E10' -notin $l2State.excluded) {
        $expiryBody = {
            param($phaseRoot, $context)

            Set-GateFailureKind 'PRODUCT'
            $context.lifecycle.expiry.playwright.attempted = $true
            $context.lifecycle.expiry.playwright.result = 'RUNNING'
            Write-L2Lifecycle -Path $context.lifecyclePath -Lifecycle $context.lifecycle
            try {
                Invoke-Playwright -ArtifactPath (Join-Path $context.layerRoot 'expiry') `
                    -Arguments @('test', '--project=chromium', '--grep', '@session-expiry', '--no-deps') `
                    -Description 'L2 E10 Chromium journey'
                $context.lifecycle.expiry.playwright.result = 'PASS'
            } catch {
                $context.lifecycle.expiry.playwright.result = 'FAIL'
                throw
            } finally {
                $context.lifecycle.expiry.playwright.completed = $true
                Write-L2Lifecycle -Path $context.lifecyclePath -Lifecycle $context.lifecycle
            }
            Set-GateFailureKind 'TEST_TOOL'
            $cases = @(Get-JUnitCases (Join-Path $context.layerRoot 'expiry'))
            Assert-ExactCaseInventory -Cases $cases -ExpectedIds @('E10') `
                -PrefixPattern 'E\d{2}' -Description 'L2 expiry journey'
            $context.state.expiryCount = 1
        }
        $expiryPhase = $null
        $l2Lifecycle.expiry.environment.attempted = $true
        $l2Lifecycle.expiry.environment.result = 'RUNNING'
        Write-L2Lifecycle -Path $lifecyclePath -Lifecycle $l2Lifecycle
        try {
            $expiryPhase = Invoke-LayerPhase -Name 'L2-expiry' -SessionTimeout 'PT5S' `
                -PhaseArtifactRoot (Join-Path $layerRoot 'expiry-phase') -Body $expiryBody `
                -BodyContext $bodyContext
        } finally {
            $l2Lifecycle.expiry.environment.completed = $null -ne $expiryPhase
            $l2Lifecycle.expiry.environment.result = if ($null -eq $expiryPhase) { 'FAIL' } else { $expiryPhase.result }
            Write-L2Lifecycle -Path $lifecyclePath -Lifecycle $l2Lifecycle
        }
        $phases += $expiryPhase
    }

    Write-PlaywrightInventory $layerRoot
    Write-Counts -Path (Join-Path $layerRoot 'counts.json') -Counts ([ordered]@{
        ordinaryJourneys = $l2State.ordinaryCount
        expiryJourneys = $l2State.expiryCount
        totalJourneys = $l2State.ordinaryCount + $l2State.expiryCount
        infrastructure = $l2State.infrastructureCount
        quarantinedExcluded = $l2State.excluded
    })
    return Complete-Layer -Name 'L2' -ArtifactName 'chromium-e2e' -Phases $phases
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
    $results = @()

    foreach ($requested in $requestedLayers) {
        $result = switch ($requested) {
            'L0' { Invoke-L0 }
            'L1' { Invoke-L1 }
            'L2' { Invoke-L2 }
        }
        $results += $result
        if ($result.result -eq 'FAIL') { break }
    }

    return Get-GateOutcome -RequestedLayer $RequestedLayer -RequestedCount $requestedLayers.Count -Results $results
}

if ($MyInvocation.InvocationName -eq '.') { return }
$outcome = Invoke-QualityGate -RequestedLayer $Layer

if ($env:GITHUB_OUTPUT) {
    $output = "result=$($outcome.result)`ndurationSeconds=$($outcome.durationSeconds)`nfailureKind=$($outcome.failureKind)`nartifactName=$($outcome.artifactName)`n"
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT, $output, [Text.UTF8Encoding]::new($false))
}

exit $outcome.exitCode
