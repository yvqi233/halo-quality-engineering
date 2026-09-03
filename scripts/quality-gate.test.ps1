[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $PSScriptRoot 'quality-gate.ps1'
$preflightPath = Join-Path $PSScriptRoot 'quality-gate-preflight.ps1'
$prWorkflowPath = Join-Path $repoRoot '.github/workflows/quality-gate.yml'
$nightlyWorkflowPath = Join-Path $repoRoot '.github/workflows/nightly.yml'

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

function Assert-Throws {
    param([scriptblock]$Body, [string]$Pattern, [string]$Message)

    $failure = $null
    try {
        & $Body
    } catch {
        $failure = $_.Exception.Message
    }
    Assert-True ($null -ne $failure) "$Message Expected an exception."
    Assert-Match $failure $Pattern $Message
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "quality-gate.ps1 has parse errors: $($parseErrors.Message -join '; ')"

$runner = Get-Content -Raw $runnerPath
Assert-Match $runner "ValidateSet\('L0', 'L1', 'L2', 'All'\)" 'Runner layer contract changed.'
Assert-Match $runner "ValidateSet\('MainChain', 'Nightly'\)" 'Runner must distinguish PR and nightly quarantine semantics.'
Assert-True (-not $runner.Contains('contracts/openapi-check/fixtures')) 'The known-removal RED probe must not remain in the final runner.'
Assert-Match $runner 'exit \$outcome\.exitCode\s*$' 'The final process result must come only from formal layer outcomes.'
Assert-Match $runner 'RuntimeInformation.*IsOSPlatform' 'Command selection must not depend on an optional OS environment variable.'
Assert-Match $runner "gradlew\.bat" 'Windows must use the Gradle batch launcher.'
Assert-Match $runner "playwright\.cmd" 'Windows must use the Playwright command launcher.'
Assert-Ordered $runner @('$output = @(& $FilePath @Arguments)', '$exitCode = $LASTEXITCODE', '$output | ForEach-Object') 'Native commands must execute outside the output pipeline.'
$isWindowsPlatform = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [Runtime.InteropServices.OSPlatform]::Windows)
Assert-True $isWindowsPlatform 'This Windows hermetic check did not detect the host platform.'
$selectedGradle = if ($isWindowsPlatform) { 'gradlew.bat' } else { 'gradlew' }
$selectedPlaywright = if ($isWindowsPlatform) { 'playwright.cmd' } else { 'playwright' }
Assert-True ($selectedGradle -eq 'gradlew.bat' -and $selectedPlaywright -eq 'playwright.cmd') 'Windows launcher regression.'
. $runnerPath
$greenLayers = @(
    [pscustomobject]@{ result = 'PASS'; durationSeconds = 1.1; failureKind = 'NONE'; artifactName = 'contract' },
    [pscustomobject]@{ result = 'PASS'; durationSeconds = 2.2; failureKind = 'NONE'; artifactName = 'api-smoke' },
    [pscustomobject]@{ result = 'PASS'; durationSeconds = 3.3; failureKind = 'NONE'; artifactName = 'chromium-e2e' }
)
$greenOutcome = Get-GateOutcome -RequestedLayer All -RequestedCount 3 -Results $greenLayers
Assert-True ($greenOutcome.result -eq 'PASS' -and $greenOutcome.exitCode -eq 0) 'Three formal green layers must return exit 0.'
Assert-True ($greenOutcome.durationSeconds -eq 6.6) 'Formal All duration must be the measured layer sum.'
$orchestrationRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-orchestration-$([Guid]::NewGuid().ToString('N'))"
$orchestrationFunctionNames = @(
    'Invoke-LayerPhase', 'Remove-SafeTree', 'Invoke-NativeCommand', 'Get-JUnitCases',
    'Get-QuarantineEntries', 'Invoke-OpenApiComparison', 'Write-Counts', 'Invoke-Playwright',
    'Write-PlaywrightInventory', 'Write-L2Lifecycle'
)
$originalOrchestrationFunctions = @{}
foreach ($functionName in $orchestrationFunctionNames) {
    $originalOrchestrationFunctions[$functionName] = (Get-Item "Function:$functionName").ScriptBlock
}
$originalArtifactRoot = $artifactRoot
$originalSummaryPath = $summaryPath
try {
    New-Item -ItemType Directory -Force -Path $orchestrationRoot | Out-Null
    $script:artifactRoot = Join-Path $orchestrationRoot 'artifacts/quality-gate'
    $script:summaryPath = Join-Path $artifactRoot 'summary.jsonl'
    function Invoke-LayerPhase {
        param(
            [string]$Name,
            [string]$SessionTimeout,
            [string]$PhaseArtifactRoot,
            [scriptblock]$Body,
            [object]$BodyContext
        )

        & $Body $PhaseArtifactRoot $BodyContext
        return [pscustomobject]@{
            result = 'PASS'
            durationSeconds = 0.1
            failureKind = 'NONE'
            primaryMessage = $null
            secondaryMessages = @()
        }
    }
    function Remove-SafeTree { param([string]$Path) }
    function Invoke-NativeCommand {
        param([string]$FilePath, [string[]]$Arguments, [string]$Description)
    }
    function Get-JUnitCases {
        param([string]$Path)

        if ($Path -match 'integrationTest') {
            $ExpectedApiScenarioIds | ForEach-Object {
                [pscustomobject]@{ name = "$_ scenario"; classname = 'fixture'; outcome = 'PASS' }
            }
            return [pscustomobject]@{ name = 'environment fixture'; classname = 'fixture'; outcome = 'PASS' }
        }
        if ($Path -match '[\\/]expiry$') {
            return [pscustomobject]@{ name = 'E10 expiry'; classname = 'fixture'; outcome = 'PASS' }
        }
        if ($Path -match '[\\/]ordinary$') {
            @($ExpectedJourneyIds[0..8]) + @('I01', 'I02') | ForEach-Object {
                [pscustomobject]@{ name = "$_ journey"; classname = 'fixture'; outcome = 'PASS' }
            }
            return
        }
        return [pscustomobject]@{ name = 'unit fixture'; classname = 'fixture'; outcome = 'PASS' }
    }
    function Get-QuarantineEntries { param([string]$LayerArtifactRoot) }
    function Invoke-OpenApiComparison { param([string]$LayerArtifactRoot) }
    function Write-Counts {
        param([string]$Path, [Collections.Specialized.OrderedDictionary]$Counts)
    }
    function Invoke-Playwright {
        param([string]$ArtifactPath, [string[]]$Arguments, [string]$Description)
    }
    function Write-PlaywrightInventory { param([string]$LayerRoot) }
    function Write-L2Lifecycle {
        param([string]$Path, [Collections.Specialized.OrderedDictionary]$Lifecycle)
    }

    $orchestrationFailures = @()
    foreach ($layerName in @('L0', 'L1', 'L2')) {
        try {
            $layerResult = & "Invoke-$layerName"
            if ($layerResult.result -ne 'PASS') {
                $orchestrationFailures += "$layerName returned $($layerResult.result)."
            }
        } catch {
            $orchestrationFailures += "$layerName orchestration: $($_.Exception.Message)"
        }
    }
    try {
        $singleLayerOutcome = Invoke-QualityGate -RequestedLayer L0
        if ($singleLayerOutcome.result -ne 'PASS' -or $singleLayerOutcome.exitCode -ne 0) {
            $orchestrationFailures += 'Single-layer gate aggregation did not return PASS/0.'
        }
    } catch {
        $orchestrationFailures += "Single-layer gate aggregation: $($_.Exception.Message)"
    }
    Assert-True ($orchestrationFailures.Count -eq 0) `
        "Layer bodies and result aggregation must execute in PowerShell 7: $($orchestrationFailures -join '; ')"
} finally {
    foreach ($functionName in $orchestrationFunctionNames) {
        Set-Item "Function:$functionName" -Value $originalOrchestrationFunctions[$functionName]
    }
    $script:artifactRoot = $originalArtifactRoot
    $script:summaryPath = $originalSummaryPath
    Remove-Item -LiteralPath $orchestrationRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$junitOutcomeRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-junit-outcomes-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path $junitOutcomeRoot | Out-Null
    @'
<testsuite tests="4" failures="1" errors="1" skipped="1">
  <testcase name="E01 passing" classname="fixture" />
  <testcase name="E02 skipped" classname="fixture"><skipped message="disabled" /></testcase>
  <testcase name="I01 failed" classname="fixture"><failure message="assertion" /></testcase>
  <testcase name="I02 errored" classname="fixture"><error message="setup" /></testcase>
</testsuite>
'@ | Set-Content -LiteralPath (Join-Path $junitOutcomeRoot 'outcomes.xml') -Encoding utf8
    $outcomeCases = @(Get-JUnitCases -Path $junitOutcomeRoot)
    Assert-True ((@($outcomeCases.outcome) -join '|') -eq 'PASS|SKIPPED|FAILURE|ERROR') `
        'JUnit testcase outcomes must be parsed from skipped/failure/error child elements.'
    foreach ($outcome in @('SKIPPED', 'FAILURE', 'ERROR')) {
        $nonPassing = @($outcomeCases | Where-Object { $_.outcome -eq $outcome })
        Assert-Throws {
            Assert-AllCasesPassed -Cases $nonPassing -Description "$outcome fixture"
        } 'non-passing' "$outcome testcase must fail gate validation."
    }
} finally {
    Remove-Item -LiteralPath $junitOutcomeRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$validOrdinaryCases = @('E01', 'E02', 'I01', 'I02') | ForEach-Object {
    [pscustomobject]@{ name = "$_ case"; classname = 'fixture'; outcome = 'PASS' }
}
Assert-ExactCaseInventory -Cases $validOrdinaryCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
    -PrefixPattern '(?:E|I)\d{2}' -Description 'valid L2 ordinary fixture'
$wrongInfrastructureCases = @('E01', 'E02', 'I03', 'I04') | ForEach-Object {
    [pscustomobject]@{ name = "$_ case"; classname = 'fixture'; outcome = 'PASS' }
}
Assert-Throws {
    Assert-ExactCaseInventory -Cases $wrongInfrastructureCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
        -PrefixPattern '(?:E|I)\d{2}' -Description 'wrong L2 infrastructure fixture'
} 'inventory mismatch' 'I03/I04 must not satisfy the I01/I02 infrastructure contract.'
$extraOrdinaryCases = @($validOrdinaryCases) + @([pscustomobject]@{ name = 'unexpected helper'; classname = 'fixture'; outcome = 'PASS' })
Assert-Throws {
    Assert-ExactCaseInventory -Cases $extraOrdinaryCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
        -PrefixPattern '(?:E|I)\d{2}' -Description 'extra L2 ordinary fixture'
} 'unclassified' 'Unclassified ordinary records must fail the exact inventory.'
$extraExpiryCases = @(
    [pscustomobject]@{ name = 'E10 case'; classname = 'fixture'; outcome = 'PASS' },
    [pscustomobject]@{ name = 'unexpected expiry helper'; classname = 'fixture'; outcome = 'PASS' }
)
Assert-Throws {
    Assert-ExactCaseInventory -Cases $extraExpiryCases -ExpectedIds @('E10') `
        -PrefixPattern 'E\d{2}' -Description 'extra L2 expiry fixture'
} 'unclassified' 'Expiry must contain only E10.'
$allOrdinaryQuarantined = @($ExpectedJourneyIds[0..8] | ForEach-Object { [pscustomobject]@{ testId = $_ } })
$allOrdinaryExcluded = @(Get-ExcludedIds -Entries $allOrdinaryQuarantined -AllowedIds $ExpectedJourneyIds)
$noSelectedOrdinary = @($ExpectedJourneyIds[0..8] | Where-Object { $_ -notin $allOrdinaryExcluded })
Assert-True ($noSelectedOrdinary.Count -eq 0) 'All ordinary journeys fixture must select zero E journeys.'
Assert-True (-not [regex]::IsMatch($runner, 'if\s*\(\$selected\.Count\s*-eq\s*0\)\s*\{\s*return')) `
    'I01/I02 must still execute when every ordinary E journey is quarantined.'
$markerRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-marker-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path $markerRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $markerRoot 'SANITIZATION_FAILED.txt') -Value 'blocked'
    Assert-True (Test-PlaywrightToolFailureArtifact -ArtifactPath $markerRoot) `
        'A standalone sanitizer marker must classify the Playwright failure as TEST_TOOL.'
} finally {
    Remove-Item -LiteralPath $markerRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$classificationRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-java-classification-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path $classificationRoot | Out-Null
    foreach ($kind in @('ENVIRONMENT', 'PRODUCT', 'CONTRACT', 'TEST_TOOL')) {
        $path = Join-Path $classificationRoot "$kind.jsonl"
        "{`"schemaVersion`":1,`"testId`":`"R01`",`"testClass`":`"fixture.Case`",`"testMethod`":`"fails`",`"failureKind`":`"$kind`"}" |
            Set-Content -LiteralPath $path -Encoding utf8
        Assert-True ((Get-JavaFailureKind -Path $path) -eq $kind) `
            "Machine-readable Java evidence must retain $kind attribution."
    }
    Assert-True ((Get-JavaFailureKind -Path (Join-Path $classificationRoot 'missing.jsonl')) -eq 'TEST_TOOL') `
        'Absent Java failure evidence must fail closed as TEST_TOOL.'
    $malformed = Join-Path $classificationRoot 'malformed.jsonl'
    Set-Content -LiteralPath $malformed -Value '{not-json' -Encoding utf8
    Assert-True ((Get-JavaFailureKind -Path $malformed) -eq 'TEST_TOOL') `
        'Malformed Java failure evidence must fail closed as TEST_TOOL.'
    $unsupported = Join-Path $classificationRoot 'unsupported.jsonl'
    Set-Content -LiteralPath $unsupported `
        -Value '{"schemaVersion":1,"testId":"R01","testClass":"fixture.Case","testMethod":"fails","failureKind":"FLAKY_CANDIDATE"}' -Encoding utf8
    Assert-True ((Get-JavaFailureKind -Path $unsupported) -eq 'TEST_TOOL') `
        'A single Java failure must never be accepted as FLAKY_CANDIDATE.'
    $mixed = Join-Path $classificationRoot 'mixed.jsonl'
    @(
        '{"schemaVersion":1,"testId":"R01","testClass":"fixture.One","testMethod":"fails","failureKind":"PRODUCT"}',
        '{"schemaVersion":1,"testId":"R02","testClass":"fixture.Two","testMethod":"fails","failureKind":"ENVIRONMENT"}'
    ) | Set-Content -LiteralPath $mixed -Encoding utf8
    Assert-True ((Get-JavaFailureKind -Path $mixed) -eq 'TEST_TOOL') `
        'Mixed Java failure attribution must fail closed as TEST_TOOL.'
} finally {
    Remove-Item -LiteralPath $classificationRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-Match $runner 'validate-quarantine\.mjs' 'L0 must validate quarantine policy.'
Assert-Match $runner 'capture-openapi\.ps1' 'L0 must consume the reviewed live OpenAPI capture interface.'
Assert-Match $runner 'halo-2\.26-openapi\.json' 'L0 must compare against the committed baseline.'
Assert-Match $runner ':api-tests:compileTestJava' 'L0 must compile Java test code.'
Assert-Match $runner ':api-tests:test' 'L0 must run Java unit tests.'
Assert-Ordered $runner @("api-tests/build/classes/java/test'", "api-tests/build/test-results/test'", "api-tests/build/reports/tests/test'", "@(':api-tests:compileTestJava', ':api-tests:test')") 'L0 must invalidate generated compile/test outputs before its single Gradle invocation.'
Assert-Match $runner ':api-tests:integrationTest' 'L1 must use the existing integration task.'
Assert-Match $runner 'failure-classification[\\/]integrationTest\.jsonl' 'L1 must consume the JUnit-emitted classification artifact.'
Assert-Match $runner 'Get-JavaFailureKind' 'L1 Gradle failures must be attributed from machine-readable Java evidence.'
Assert-True (-not [regex]::IsMatch($runner, 'Set-GateFailureKind ''PRODUCT''\s*\r?\n\s*Invoke-NativeCommand -FilePath \$gradleCommand')) `
    'L1 must not default every Gradle failure to PRODUCT.'
Assert-Match $runner 'ExpectedApiScenarioIds' 'L1 must enforce the exact API scenario inventory.'
Assert-Match $runner "@\('E01'.*'E10'\)" 'L2 must enforce E01-E10.'
Assert-Match $runner 'Assert-ExactCaseInventory' 'L2 must reject extra or misidentified test records.'
Assert-Match $runner '--grep-invert' 'Ordinary journeys must exclude E10.'
Assert-Match $runner '--no-deps' 'E10 must not reuse ordinary setup dependencies.'
Assert-Match $runner 'PT30M' 'Ordinary journeys need the normal session timeout.'
Assert-Match $runner 'PT5S' 'E10 needs its own short-lived environment.'
Assert-Match $runner 'collect-evidence\.ps1' 'Layer failures must collect redacted evidence.'
Assert-Match $runner 'cleanup failed:[\s\S]*?Set-GateFailureKind ''TEST_TOOL''' 'Playwright cleanup failures must be classified as test-tool failures.'
Assert-Match $runner 'SANITIZATION_FAILED\.txt' 'Playwright sanitizer marker classification is missing.'
Assert-Match $runner 'phases\.json' 'L2 must persist phase lifecycle facts independently of successful counts.'
Assert-Match $runner "environment\.ps1.*-Action Down" 'Every layer phase must tear down.'
Assert-Ordered $runner @('Invoke-GateBody', '& $collectorScript', '-Action Down') 'Evidence must run after the test body and before final teardown.'
Assert-Match $runner "\[ordered\]@\{\s*layer\s*=.*\s*result\s*=.*\s*durationSeconds\s*=.*\s*failureKind\s*=.*\s*artifactName\s*=" 'Summary schema is incomplete or reordered.'
Assert-True (-not [regex]::IsMatch($runner, '(?i)\b(?:retry|rerun|Start-Sleep|WaitForTimeout)\b')) 'Runner must not retry, rerun, or use fixed sleeps.'

foreach ($workflowPath in @($prWorkflowPath, $nightlyWorkflowPath)) {
    Assert-True (Test-Path -LiteralPath $workflowPath) "Missing workflow: $workflowPath"
    $workflow = Get-Content -Raw $workflowPath
    Assert-True (-not $workflow.Contains("`t")) "$workflowPath contains YAML tabs."
    Assert-Match $workflow '^name:\s+\S+' "$workflowPath is missing a workflow name."
    Assert-Match $workflow '^on:' "$workflowPath is missing triggers."
    Assert-Match $workflow '^jobs:' "$workflowPath is missing jobs."
    Assert-Match $workflow 'actions/checkout@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+' "$workflowPath must use immutable checkout."
    Assert-Match $workflow 'actions/setup-java@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+' "$workflowPath must provision Java from an immutable action."
    Assert-Match $workflow 'java-version:\s*[''"]?21' "$workflowPath must use Java 21."
    Assert-True (-not [regex]::IsMatch($workflow, '(?i)\b(?:retry|rerun|Start-Sleep|WaitForTimeout)\b')) "$workflowPath enables retry or fixed sleep."
    $externalUses = @($workflow -split "`r?`n" | Where-Object { $_ -match '^\s*uses:\s+(?!\./)' })
    Assert-True ($externalUses.Count -gt 0) "$workflowPath has no external actions."
    foreach ($usesLine in $externalUses) {
        Assert-Match $usesLine '^\s*uses:\s+[^@\s]+@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+\s*$' `
            "$workflowPath contains a mutable or uncommented external action: $usesLine"
    }
    $uploads = @([regex]::Matches($workflow, '(?ms)^\s{6}- name: Upload.*?(?=^\s{6}- name:|\z)') |
        Where-Object { $_.Value -match 'uses:\s+actions/upload-artifact@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+' })
    Assert-True ($uploads.Count -gt 0) "$workflowPath has no artifact uploads."
    foreach ($upload in $uploads) {
        $body = $upload.Value
        Assert-Match $body 'if:\s+always\(\)' "$workflowPath upload is not unconditional."
        Assert-Match $body 'continue-on-error:\s+false' "$workflowPath upload can hide failure."
        Assert-Match $body 'if-no-files-found:\s+error' "$workflowPath upload does not fail on missing evidence."
    }
}

$prWorkflow = Get-Content -Raw $prWorkflowPath
Assert-Match $prWorkflow 'contract:[\s\S]*?timeout-minutes:\s+10' 'L0 timeout must be 10 minutes.'
Assert-Match $prWorkflow 'api-smoke:[\s\S]*?needs:\s+contract[\s\S]*?timeout-minutes:\s+10' 'L1 must follow L0 with a 10-minute timeout.'
Assert-Match $prWorkflow 'chromium-e2e:[\s\S]*?needs:\s+api-smoke[\s\S]*?timeout-minutes:\s+15' 'L2 must follow L1 with a 15-minute timeout.'
Assert-Match $prWorkflow 'pnpm/action-setup@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+' 'L2 must install immutable pnpm setup.'
Assert-Match $prWorkflow 'actions/setup-node@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+' 'L2 must provision Node from an immutable action.'
Assert-Match $prWorkflow 'node-version:\s*[''"]?22' 'L2 must use Node 22.'
Assert-Match $prWorkflow 'playwright install --with-deps chromium' 'PR gate must install Chromium.'
Assert-Match $prWorkflow '-QuarantineMode MainChain' 'PR jobs must exclude valid quarantine records from main-chain results.'
Assert-True (-not [regex]::IsMatch($prWorkflow, '(?i)firefox|stability')) 'PR gate must remain Chromium-only.'
Assert-Match $prWorkflow 'l0-junit-xml' 'L0 JUnit artifact name is missing.'
Assert-Match $prWorkflow 'l1-api-evidence' 'L1 API evidence artifact name is missing.'
Assert-Match $prWorkflow 'l2-playwright-report' 'L2 report artifact name is missing.'
Assert-Match $prWorkflow 'l2-playwright-traces' 'L2 trace artifact name is missing.'
Assert-Match $prWorkflow 'l2-playwright-videos' 'L2 video artifact name is missing.'
Assert-Match $prWorkflow 'artifacts/quality-gate/L2/phases\.json' 'L2 lifecycle metadata must be uploaded.'
Assert-Match $prWorkflow 'evidence-upload' 'Test and evidence-upload summary rows must be separate.'
foreach ($layerName in @('L0', 'L1', 'L2')) {
    Assert-Match $prWorkflow "Validate $layerName artifact completeness[\s\S]*?if:\s+always\(\)[\s\S]*?continue-on-error:\s+true[\s\S]*?quality-gate-preflight\.ps1 -Layer $layerName" `
        "$layerName must run a non-blocking completeness preflight before unconditional uploads."
    Assert-Match $prWorkflow "$layerName-evidence-preflight" "$layerName preflight needs its own Summary row."
}

$nightlyWorkflow = Get-Content -Raw $nightlyWorkflowPath
Assert-Match $nightlyWorkflow 'schedule:' 'Nightly workflow must have a schedule.'
Assert-Match $nightlyWorkflow 'nightly-regression:' 'Nightly workflow must expose the L3 job name.'
Assert-Match $nightlyWorkflow 'timeout-minutes:\s+30' 'Nightly timeout must be 30 minutes.'
Assert-Match $nightlyWorkflow '-QuarantineMode Nightly' 'Nightly must execute quarantined cases visibly.'
Assert-Match $nightlyWorkflow 'Validate nightly artifact completeness[\s\S]*?if:\s+always\(\)[\s\S]*?continue-on-error:\s+true[\s\S]*?quality-gate-preflight\.ps1 -Layer All' `
    'Nightly must run a non-blocking completeness preflight before unconditional uploads.'
Assert-Match $nightlyWorkflow 'L3-evidence-preflight' 'Nightly preflight needs its own Summary row.'
Assert-Match $nightlyWorkflow 'artifacts/quality-gate/L2/phases\.json' 'Nightly lifecycle metadata must be uploaded.'
Assert-Match $nightlyWorkflow 'artifacts/quality-gate/L0/quarantine\.yaml' 'Nightly summary must use generated validated quarantine evidence.'
Assert-Match $nightlyWorkflow 'validation unavailable' 'Nightly summary must identify unavailable validation.'
Assert-True (-not $nightlyWorkflow.Contains('Get-Content -Raw docs/quarantine.yaml')) `
    'Nightly must not label the unvalidated source quarantine file as validated.'
Assert-Match $nightlyWorkflow 'playwright install --with-deps chromium firefox' 'Nightly must install both required browsers.'
Assert-Match $nightlyWorkflow "--project=firefox[\s\S]*?--grep-invert[\s\S]*?--project=firefox[\s\S]*?--grep[\s\S]*?--no-deps" 'Nightly must run ordinary Firefox journeys and isolated E10 exactly once.'
Assert-Match $nightlyWorkflow 'junit-results\.ps1' 'Nightly Firefox must use the shared JUnit outcome validator.'
Assert-Match $nightlyWorkflow 'Assert-AllCasesPassed[\s\S]*?nightly Firefox' 'Nightly Firefox must reject skipped, failed, or errored testcase records.'
Assert-True (-not [regex]::IsMatch($nightlyWorkflow, '(?i)20-run|stability\.ps1')) 'Nightly must not claim the separately executed 20-run qualification.'

Assert-True (Test-Path -LiteralPath $preflightPath) 'Missing quality-gate artifact preflight script.'
$preflightTokens = $null
$preflightParseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($preflightPath, [ref]$preflightTokens, [ref]$preflightParseErrors)
Assert-True ($preflightParseErrors.Count -eq 0) "quality-gate-preflight.ps1 has parse errors: $($preflightParseErrors.Message -join '; ')"
. $preflightPath
$summaryOnlyRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-preflight-$([Guid]::NewGuid().ToString('N'))"
try {
    $summaryParent = Join-Path $summaryOnlyRoot 'artifacts/quality-gate'
    New-Item -ItemType Directory -Force -Path $summaryParent | Out-Null
    Set-Content -LiteralPath (Join-Path $summaryParent 'summary.jsonl') -Value '{}'
    $missingWithSummary = @(Get-MissingQualityGateArtifacts -RequestedLayer L0 -RepositoryRoot $summaryOnlyRoot)
    Assert-True ($missingWithSummary -contains 'api-tests/build/test-results/test/*.xml') `
        'A summary file must not mask missing L0 JUnit XML.'
    Assert-True ($missingWithSummary -contains 'artifacts/quality-gate/L0/live-openapi.json') `
        'A summary file must not mask missing L0 OpenAPI evidence.'
} finally {
    Remove-Item -LiteralPath $summaryOnlyRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$collectionMarkerRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-collection-marker-$([Guid]::NewGuid().ToString('N'))"
try {
    foreach ($relativePath in @(
            'api-tests/build/test-results/test/result.xml',
            'artifacts/quality-gate/L0/live-openapi.json',
            'artifacts/quality-gate/L0/openapi-findings.json',
            'artifacts/quality-gate/L0/counts.json',
            'artifacts/quality-gate/L0/quarantine.json',
            'artifacts/quality-gate/L0/quarantine.yaml',
            'artifacts/quality-gate/summary.jsonl',
            'artifacts/quality-gate/L0/environment/docker-ps.txt',
            'artifacts/quality-gate/L0/environment/halo.log',
            'artifacts/quality-gate/L0/environment/postgres.log',
            'artifacts/quality-gate/L0/environment/health.json')) {
        $path = Join-Path $collectionMarkerRoot $relativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        Set-Content -LiteralPath $path -Value 'valid'
    }
    $completeL0 = @(Get-MissingQualityGateArtifacts -RequestedLayer L0 -RepositoryRoot $collectionMarkerRoot)
    Assert-True ($completeL0.Count -eq 0) "Complete L0 fixture was unexpectedly rejected: $($completeL0 -join ', ')"
    $markerRelativePath = 'artifacts/quality-gate/L0/environment/COLLECTION_FAILED.txt'
    Set-Content -LiteralPath (Join-Path $collectionMarkerRoot $markerRelativePath) -Value ''
    $blockedL0 = @(Get-MissingQualityGateArtifacts -RequestedLayer L0 -RepositoryRoot $collectionMarkerRoot)
    Assert-True ($blockedL0 -contains "$markerRelativePath (evidence collection failed)") `
        'Preflight must reject an evidence-collection marker even when it is empty and all positive artifacts exist.'
} finally {
    Remove-Item -LiteralPath $collectionMarkerRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$failedL2Root = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-failed-l2-$([Guid]::NewGuid().ToString('N'))"
try {
    $l2Root = Join-Path $failedL2Root 'artifacts/quality-gate/L2'
    $manifestRoot = Join-Path $l2Root 'manifests'
    New-Item -ItemType Directory -Force -Path $manifestRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $l2Root 'counts.json') -Value '{"ordinaryJourneys":0,"expiryJourneys":0}'
    Set-Content -LiteralPath (Join-Path $manifestRoot 'report-files.txt') -Value 'NONE_RETAINED'
    Set-Content -LiteralPath (Join-Path $manifestRoot 'trace-files.txt') -Value 'NONE_RETAINED'
    Set-Content -LiteralPath (Join-Path $manifestRoot 'video-files.txt') -Value 'NONE_RETAINED'

    $notRun = [ordered]@{
        environment = [ordered]@{ attempted = $false; completed = $false; result = 'NOT_RUN' }
        playwright = [ordered]@{ attempted = $false; completed = $false; result = 'NOT_RUN' }
    }
    $failed = [ordered]@{
        environment = [ordered]@{ attempted = $true; completed = $true; result = 'FAIL' }
        playwright = [ordered]@{ attempted = $true; completed = $true; result = 'FAIL' }
    }
    $expiryFailedLifecycle = [ordered]@{ schemaVersion = 1; ordinary = $notRun; expiry = $failed }
    Set-Content -LiteralPath (Join-Path $l2Root 'phases.json') `
        -Value ($expiryFailedLifecycle | ConvertTo-Json -Depth 8)
    $expiryFailedMissing = @(Get-MissingQualityGateArtifacts -RequestedLayer L2 -RepositoryRoot $failedL2Root)
    Assert-True ($expiryFailedMissing -contains 'artifacts/quality-gate/L2/expiry/junit.xml') `
        'Attempted failed expiry must require JUnit even when expiryJourneys remains zero.'
    Assert-True ($expiryFailedMissing -contains 'artifacts/quality-gate/L2/expiry/html-report/index.html') `
        'Attempted failed expiry must require its HTML report.'
    Assert-True ($expiryFailedMissing -contains 'artifacts/quality-gate/L2/expiry-phase/environment/docker-ps.txt') `
        'Attempted expiry environment must require environment evidence.'
    Assert-True ($expiryFailedMissing -contains 'artifacts/quality-gate/L2/manifests/trace-files.txt (retained expiry failure evidence)') `
        'NONE_RETAINED must not satisfy failed expiry trace evidence.'
    Assert-True ($expiryFailedMissing -contains 'artifacts/quality-gate/L2/manifests/video-files.txt (retained expiry failure evidence)') `
        'NONE_RETAINED must not satisfy failed expiry video evidence.'

    $ordinaryFailedLifecycle = [ordered]@{ schemaVersion = 1; ordinary = $failed; expiry = $notRun }
    Set-Content -LiteralPath (Join-Path $l2Root 'phases.json') `
        -Value ($ordinaryFailedLifecycle | ConvertTo-Json -Depth 8)
    $ordinaryFailedMissing = @(Get-MissingQualityGateArtifacts -RequestedLayer L2 -RepositoryRoot $failedL2Root)
    Assert-True ($ordinaryFailedMissing -contains 'artifacts/quality-gate/L2/manifests/trace-files.txt (retained ordinary failure evidence)') `
        'NONE_RETAINED must not satisfy failed ordinary trace evidence.'
    Assert-True ($ordinaryFailedMissing -contains 'artifacts/quality-gate/L2/manifests/video-files.txt (retained ordinary failure evidence)') `
        'NONE_RETAINED must not satisfy failed ordinary video evidence.'

    Set-Content -LiteralPath (Join-Path $l2Root 'phases.json') `
        -Value ($expiryFailedLifecycle | ConvertTo-Json -Depth 8)
    $expiryArtifactRoot = Join-Path $l2Root 'expiry'
    New-Item -ItemType Directory -Force -Path $expiryArtifactRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $expiryArtifactRoot 'SANITIZATION_FAILED.txt') -Value 'blocked'
    $sanitizerBlockedMissing = @(Get-MissingQualityGateArtifacts -RequestedLayer L2 -RepositoryRoot $failedL2Root)
    Assert-True ($sanitizerBlockedMissing -notcontains 'artifacts/quality-gate/L2/expiry/junit.xml') `
        'A fail-closed sanitizer marker must replace unavailable expiry Playwright publications.'
    Assert-True ($sanitizerBlockedMissing -notcontains 'artifacts/quality-gate/L2/manifests/trace-files.txt (retained expiry failure evidence)') `
        'A fail-closed sanitizer marker must replace unavailable expiry media publications.'
} finally {
    Remove-Item -LiteralPath $failedL2Root -Recurse -Force -ErrorAction SilentlyContinue
}

$artifactNames = [regex]::Matches("$prWorkflow`n$nightlyWorkflow", '(?m)^\s+name:\s+((?:l[0-3]|nightly)-[a-z0-9-]+)\s*$') |
    ForEach-Object { $_.Groups[1].Value }
Assert-True ($artifactNames.Count -eq (@($artifactNames | Sort-Object -Unique).Count)) 'Workflow artifact names must be globally distinct.'

$phaseRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-phase-$([Guid]::NewGuid().ToString('N'))"
$originalPhaseCounter = $env:HALO_QE_TEST_DOWN_COUNT
try {
    $phaseScripts = Join-Path $phaseRoot 'scripts'
    New-Item -ItemType Directory -Force -Path $phaseScripts | Out-Null
    Copy-Item -LiteralPath $runnerPath -Destination (Join-Path $phaseScripts 'quality-gate.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'junit-results.ps1') -Destination $phaseScripts
    Set-Content -LiteralPath (Join-Path $phaseScripts 'environment.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$Action)
if ($Action -eq 'Down') {
    $count = if ($env:HALO_QE_TEST_DOWN_COUNT) { [int]$env:HALO_QE_TEST_DOWN_COUNT } else { 0 }
    $env:HALO_QE_TEST_DOWN_COUNT = [string]($count + 1)
    if ($count -ge 1) { throw 'teardown sentinel' }
}
'@
    Set-Content -LiteralPath (Join-Path $phaseScripts 'collect-evidence.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$ArtifactRoot)
throw 'collector sentinel'
'@
    Remove-Item Env:HALO_QE_TEST_DOWN_COUNT -ErrorAction SilentlyContinue
    . (Join-Path $phaseScripts 'quality-gate.ps1')
    $phaseFailure = $null
    try {
        $phaseResult = Invoke-LayerPhase -Name 'compatibility' -SessionTimeout 'PT1M' `
            -PhaseArtifactRoot (Join-Path $phaseRoot 'artifacts') -Body {
                param($currentPhaseRoot, $context)
                Set-GateFailureKind 'PRODUCT'
                throw 'primary sentinel'
            }
    } catch {
        $phaseFailure = $_.Exception.Message
    }
    Assert-True ($null -eq $phaseFailure) `
        "Layer failure aggregation must not throw in PowerShell 7: $phaseFailure"
    Assert-True ($phaseResult.result -eq 'FAIL' -and $phaseResult.failureKind -eq 'PRODUCT') `
        'Layer failure aggregation must preserve the primary result and attribution.'
    Assert-True ($phaseResult.secondaryMessages.Count -eq 2) `
        'Layer failure aggregation must retain collector and teardown failures as secondary evidence.'
} finally {
    if ($null -eq $originalPhaseCounter) {
        Remove-Item Env:HALO_QE_TEST_DOWN_COUNT -ErrorAction SilentlyContinue
    } else {
        $env:HALO_QE_TEST_DOWN_COUNT = $originalPhaseCounter
    }
    Remove-Item -LiteralPath $phaseRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'quality-gate hermetic/static tests passed'
