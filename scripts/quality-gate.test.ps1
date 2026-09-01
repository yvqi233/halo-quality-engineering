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
$validOrdinaryCases = @('E01', 'E02', 'I01', 'I02') | ForEach-Object {
    [pscustomobject]@{ name = "$_ case"; classname = 'fixture' }
}
Assert-ExactCaseInventory -Cases $validOrdinaryCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
    -PrefixPattern '(?:E|I)\d{2}' -Description 'valid L2 ordinary fixture'
$wrongInfrastructureCases = @('E01', 'E02', 'I03', 'I04') | ForEach-Object {
    [pscustomobject]@{ name = "$_ case"; classname = 'fixture' }
}
Assert-Throws {
    Assert-ExactCaseInventory -Cases $wrongInfrastructureCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
        -PrefixPattern '(?:E|I)\d{2}' -Description 'wrong L2 infrastructure fixture'
} 'inventory mismatch' 'I03/I04 must not satisfy the I01/I02 infrastructure contract.'
$extraOrdinaryCases = @($validOrdinaryCases) + @([pscustomobject]@{ name = 'unexpected helper'; classname = 'fixture' })
Assert-Throws {
    Assert-ExactCaseInventory -Cases $extraOrdinaryCases -ExpectedIds @('E01', 'E02', 'I01', 'I02') `
        -PrefixPattern '(?:E|I)\d{2}' -Description 'extra L2 ordinary fixture'
} 'unclassified' 'Unclassified ordinary records must fail the exact inventory.'
$extraExpiryCases = @(
    [pscustomobject]@{ name = 'E10 case'; classname = 'fixture' },
    [pscustomobject]@{ name = 'unexpected expiry helper'; classname = 'fixture' }
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
Assert-Match $runner 'validate-quarantine\.mjs' 'L0 must validate quarantine policy.'
Assert-Match $runner 'capture-openapi\.ps1' 'L0 must consume the reviewed live OpenAPI capture interface.'
Assert-Match $runner 'halo-2\.26-openapi\.json' 'L0 must compare against the committed baseline.'
Assert-Match $runner ':api-tests:compileTestJava' 'L0 must compile Java test code.'
Assert-Match $runner ':api-tests:test' 'L0 must run Java unit tests.'
Assert-Ordered $runner @("api-tests/build/classes/java/test'", "api-tests/build/test-results/test'", "api-tests/build/reports/tests/test'", "@(':api-tests:compileTestJava', ':api-tests:test')") 'L0 must invalidate generated compile/test outputs before its single Gradle invocation.'
Assert-Match $runner ':api-tests:integrationTest' 'L1 must use the existing integration task.'
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
    Assert-Match $workflow 'actions/checkout@v4' "$workflowPath must use checkout."
    Assert-Match $workflow 'actions/setup-java@v4' "$workflowPath must provision Java."
    Assert-Match $workflow 'java-version:\s*[''"]?21' "$workflowPath must use Java 21."
    Assert-True (-not [regex]::IsMatch($workflow, '(?i)\b(?:retry|rerun|Start-Sleep|WaitForTimeout)\b')) "$workflowPath enables retry or fixed sleep."
    $uploads = @([regex]::Matches($workflow, '(?ms)^\s{6}- name: Upload.*?(?=^\s{6}- name:|\z)') |
        Where-Object { $_.Value -match 'uses:\s+actions/upload-artifact@v4' })
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
Assert-Match $prWorkflow 'pnpm/action-setup@v4' 'L2 must install pinned pnpm.'
Assert-Match $prWorkflow 'actions/setup-node@v4' 'L2 must provision Node.'
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
Assert-True (-not [regex]::IsMatch($nightlyWorkflow, '(?i)firefox|20-run|stability\.ps1')) 'Task 9 must not claim Task 10 Firefox or stability results.'

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

Write-Output 'quality-gate hermetic/static tests passed'
