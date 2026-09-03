[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$GitHubApiBaseUri = 'https://api.github.com',
    [switch]$SkipLiveChecks,
    [switch]$CheckPublicUrls
)

$ErrorActionPreference = 'Stop'
$repoRoot = if ($RepositoryRoot) {
    [IO.Path]::GetFullPath($RepositoryRoot)
} else {
    Split-Path -Parent $PSScriptRoot
}
$errors = [Collections.Generic.List[string]]::new()
$syntheticPassword = 'HaloQE!' + '2026'
. (Join-Path $PSScriptRoot 'verify-publication.github.ps1')

function Add-PublicationError {
    param([string]$Message)

    [void]$errors.Add($Message)
}

function Get-TrackedPaths {
    $paths = @(& git -C $repoRoot ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate tracked files with git ls-files.' }
    return @($paths | Where-Object { $_ -and -not $_.EndsWith('/') } | ForEach-Object { $_.Replace('\', '/') })
}

function Get-TextFiles {
    param([string[]]$Paths)

    $extensions = @('.env', '.gradle', '.html', '.java', '.json', '.kts', '.md', '.mjs', '.ps1', '.properties', '.ts', '.txt', '.xml', '.yaml', '.yml')
    foreach ($relativePath in $Paths) {
        if ($extensions -notcontains [IO.Path]::GetExtension($relativePath).ToLowerInvariant()) { continue }
        $fullPath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        [pscustomobject]@{ path = $relativePath; text = [IO.File]::ReadAllText($fullPath) }
    }
}

function Get-PublicationPaths {
    param([string[]]$Paths)

    return @($Paths | Where-Object { $_ -notmatch '^(?:\.superpowers|docs/superpowers)/' })
}

function Test-AllowedIpv4 {
    param([string]$Address)

    return $Address.StartsWith('127.') -or $Address.StartsWith('0.') -or
        $Address.StartsWith('192.0.2.') -or $Address.StartsWith('198.51.100.') -or $Address.StartsWith('203.0.113.')
}

function Test-SyntheticPasswordPath {
    param([string]$Path)

    return $Path -match '^environment/(?:docker-compose\.ya?ml|halo-config/.+\.(?:ya?ml|properties))$' -or
        $Path -match '^scripts/(?:environment|collect-evidence(?:\.test)?|verify-publication(?:\.test)?)\.ps1$' -or
        $Path -match '^api-tests/src/test/.+\.(?:java|kt)$' -or
        $Path -match '^e2e/(?:fixtures|pages|specs|unit|probes|reporters)/.+\.ts$'
}

function Test-AllowedSecretSourcePath {
    param([string]$Path)

    return (Test-SyntheticPasswordPath -Path $Path) -or
        $Path -match '^(?:scripts/(?:collect-evidence|verify-publication)\.ps1|scripts/.+\.test\.ps1|contracts/)'
}

function Get-MarkedJson {
    param([string]$Text, [string]$Marker, [string]$Description)

    $pattern = '(?s)<!--\s*' + [regex]::Escape($Marker) + '\s*-->\s*```json\s*(.*?)\s*```'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "$Description is missing its $Marker JSON block." }
    try {
        return ($match.Groups[1].Value | ConvertFrom-Json)
    } catch {
        throw "$Description has invalid $Marker JSON: $($_.Exception.Message)"
    }
}

function Test-JsonValueEqual {
    param($Left, $Right)

    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    $leftObject = $Left -is [Management.Automation.PSCustomObject] -or $Left -is [Collections.IDictionary]
    $rightObject = $Right -is [Management.Automation.PSCustomObject] -or $Right -is [Collections.IDictionary]
    if ($leftObject -or $rightObject) {
        if (-not ($leftObject -and $rightObject)) { return $false }
        $leftNames = @($Left.PSObject.Properties.Name | Sort-Object)
        $rightNames = @($Right.PSObject.Properties.Name | Sort-Object)
        if (($leftNames -join '|') -cne ($rightNames -join '|')) { return $false }
        foreach ($name in $leftNames) {
            if (-not (Test-JsonValueEqual $Left.$name $Right.$name)) { return $false }
        }
        return $true
    }
    $leftArray = $Left -is [Collections.IEnumerable] -and -not ($Left -is [string])
    $rightArray = $Right -is [Collections.IEnumerable] -and -not ($Right -is [string])
    if ($leftArray -or $rightArray) {
        if (-not ($leftArray -and $rightArray)) { return $false }
        $leftItems = @($Left)
        $rightItems = @($Right)
        if ($leftItems.Count -ne $rightItems.Count) { return $false }
        for ($index = 0; $index -lt $leftItems.Count; $index++) {
            if (-not (Test-JsonValueEqual $leftItems[$index] $rightItems[$index])) { return $false }
        }
        return $true
    }
    $numericTypes = [Type[]]@(
        [System.Byte], [System.SByte], [System.Int16], [System.UInt16], [System.Int32], [System.UInt32],
        [System.Int64], [System.UInt64], [System.Single], [System.Double], [System.Decimal]
    )
    $leftKind = if ($Left -is [string]) {
        'STRING'
    } elseif ($Left -is [bool]) {
        'BOOLEAN'
    } elseif (@($numericTypes | Where-Object { $_.IsInstanceOfType($Left) }).Count -gt 0) {
        'NUMBER'
    } else {
        $Left.GetType().FullName
    }
    $rightKind = if ($Right -is [string]) {
        'STRING'
    } elseif ($Right -is [bool]) {
        'BOOLEAN'
    } elseif (@($numericTypes | Where-Object { $_.IsInstanceOfType($Right) }).Count -gt 0) {
        'NUMBER'
    } else {
        $Right.GetType().FullName
    }
    if ($leftKind -cne $rightKind) { return $false }
    if ($leftKind -eq 'NUMBER') { return [double]$Left -eq [double]$Right }
    if ($leftKind -eq 'STRING') { return [string]$Left -ceq [string]$Right }
    return $Left -eq $Right
}

function Test-QualificationFacts {
    param($Facts, [string]$Description)

    if ($null -eq $Facts) { Add-PublicationError "$Description is missing facts."; return }
    foreach ($field in @('stability', 'fullGate', 'firefox')) {
        if (-not $Facts.PSObject.Properties.Name.Contains($field)) { Add-PublicationError "$Description facts are missing $field." }
    }
    if ($Facts.stability.consecutivePassNoneRuns -ne 20 -or $Facts.stability.minimumDurationSeconds -gt $Facts.stability.maximumDurationSeconds) {
        Add-PublicationError "$Description stability facts are invalid."
    }
    $layers = @($Facts.fullGate.layers)
    if ($layers.Count -ne 3 -or (@($layers.layer) -join '|') -ne 'L0|L1|L2' -or @($layers | Where-Object { $_.result -ne 'PASS' -or $_.durationSeconds -lt 0 }).Count -gt 0) {
        Add-PublicationError "$Description full-gate layer facts are invalid."
    }
    if ($Facts.firefox.ordinaryPassed -ne $Facts.firefox.ordinaryExpected -or
        $Facts.firefox.isolatedExpiryPassed -ne $Facts.firefox.isolatedExpiryExpected) {
        Add-PublicationError "$Description Firefox or evidence facts are invalid."
    }
}

function Test-ResultNarrative {
    param([string]$Readme)

    $section = [regex]::Match($Readme, '(?s)^##\s+Measured Results\s*$\r?\n(.*?)(?=^##\s+|\z)', [Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $section.Success) { Add-PublicationError 'README.md is missing the Measured Results section.'; return }
    $narrative = [regex]::Replace($section.Groups[1].Value, '(?s)<!--\s*qualification-claims-v1\s*-->\s*```json\s*.*?\s*```', '')
    Write-Verbose "Measured-result narrative [$($narrative.Trim())]"
    $allowed = '(?s)^The machine-checked claim below is compared exactly with the authoritative tracked \[raw qualification artifact\]\(evidence/qualification-v1\.json\)\. The structured record is the only location for qualification values in this section\.$'
    if ($narrative.Trim() -notmatch $allowed) {
        Add-PublicationError 'README measured-result narrative must contain only the documented boilerplate and artifact link.'
    }
}

function Get-DerivedQualificationFacts {
    param([object]$Provenance, [hashtable]$Tracked)

    foreach ($field in @('stabilityRecord', 'gateSummary', 'journeyCounts', 'gatePhases', 'firefoxOrdinaryJunit', 'firefoxExpiryJunit')) {
        if (-not $Provenance.PSObject.Properties.Name.Contains($field)) { throw "Qualification provenance is missing $field." }
    }
    $rootWithSeparator = $repoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $paths = @{}
    foreach ($field in @('stabilityRecord', 'gateSummary', 'journeyCounts', 'gatePhases', 'firefoxOrdinaryJunit', 'firefoxExpiryJunit')) {
        $relative = [string]$Provenance.$field
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
            throw "Qualification provenance path is invalid or outside repository root: $relative"
        }
        if (@($relative -split '[\\/]' | Where-Object { $_ -eq '..' }).Count -gt 0) {
            throw "Qualification provenance path contains traversal: $relative"
        }
        $full = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
        if (-not $full.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Qualification provenance path is outside repository root: $relative"
        }
        $normalized = $full.Substring($rootWithSeparator.Length).Replace('\', '/')
        if (-not $Tracked.ContainsKey($normalized)) {
            throw "Qualification provenance path is not tracked: $relative"
        }
        $paths[$field] = $full
    }
    $stability = @(Get-Content -LiteralPath $paths.stabilityRecord | ForEach-Object { $_ | ConvertFrom-Json })
    $gate = @(Get-Content -LiteralPath $paths.gateSummary | ForEach-Object { $_ | ConvertFrom-Json })
    $journeyCounts = Get-Content -Raw -LiteralPath $paths.journeyCounts | ConvertFrom-Json
    $phases = Get-Content -Raw -LiteralPath $paths.gatePhases | ConvertFrom-Json
    [xml]$ordinary = Get-Content -Raw -LiteralPath $paths.firefoxOrdinaryJunit
    [xml]$expiry = Get-Content -Raw -LiteralPath $paths.firefoxExpiryJunit
    if ($stability.Count -ne 20) {
        throw "Qualification raw stability records must contain exactly sequences 1 through 20; found $($stability.Count) rows."
    }
    $stabilityFields = @('commit', 'durationSeconds', 'failureKind', 'haloImage', 'result', 'sequence', 'startedAt')
    $expectedCommit = [string]$stability[0].commit
    $expectedImage = [string]$stability[0].haloImage
    $durations = [Collections.Generic.List[double]]::new()
    for ($index = 0; $index -lt $stability.Count; $index++) {
        $record = $stability[$index]
        if ((Compare-Object $stabilityFields @($record.PSObject.Properties.Name | Sort-Object)).Count -ne 0) {
            throw 'Qualification raw stability records must use the exact seven-field schema.'
        }
        if ($record.sequence -isnot [int] -or $record.sequence -ne ($index + 1)) {
            throw "Qualification raw stability records must contain exactly sequences 1 through 20; position $($index + 1) contains '$($record.sequence)'."
        }
        $parsedStartedAt = [DateTimeOffset]::MinValue
        if ($record.startedAt -isnot [string] -or -not [DateTimeOffset]::TryParse($record.startedAt, [ref]$parsedStartedAt)) {
            throw 'Qualification raw stability startedAt values must be ISO-8601 timestamps.'
        }
        if ($record.commit -isnot [string] -or $record.commit -notmatch '^[0-9a-f]{40}$' -or
            $record.haloImage -isnot [string] -or $record.haloImage -notmatch '.+@sha256:[0-9a-f]{64}$') {
            throw 'Qualification raw stability commit or image identity is invalid.'
        }
        if ($record.commit -cne $expectedCommit -or $record.haloImage -cne $expectedImage) {
            throw 'Qualification raw stability records must identify one commit and one image.'
        }
        if ($record.result -isnot [string] -or $record.failureKind -isnot [string]) {
            throw 'Qualification raw stability result and failureKind must be strings.'
        }
        if ($record.result -cne 'PASS' -or $record.failureKind -cne 'NONE') {
            throw 'Qualification raw stability records are incomplete or contain a non-passing run.'
        }
        if ($record.durationSeconds -isnot [ValueType] -or $record.durationSeconds -is [bool] -or
            [double]::IsNaN([double]$record.durationSeconds) -or
            [double]::IsInfinity([double]$record.durationSeconds) -or [double]$record.durationSeconds -lt 0) {
            throw 'Qualification raw stability duration is invalid.'
        }
        [void]$durations.Add([double]$record.durationSeconds)
    }
    $gateFields = @('artifactName', 'durationSeconds', 'failureKind', 'layer', 'result')
    $gateLayers = @('L0', 'L1', 'L2')
    $gateArtifacts = @('contract', 'api-smoke', 'chromium-e2e')
    if ($gate.Count -ne 3) {
        throw 'Qualification raw gate summary must contain passing L0, L1, and L2 results.'
    }
    for ($index = 0; $index -lt $gate.Count; $index++) {
        $record = $gate[$index]
        if ((Compare-Object $gateFields @($record.PSObject.Properties.Name | Sort-Object)).Count -ne 0 -or
            $record.layer -isnot [string] -or $record.artifactName -isnot [string] -or
            $record.result -isnot [string] -or $record.failureKind -isnot [string] -or
            $record.layer -cne $gateLayers[$index] -or $record.artifactName -cne $gateArtifacts[$index] -or
            $record.result -cne 'PASS' -or $record.failureKind -cne 'NONE' -or
            $record.durationSeconds -isnot [ValueType] -or $record.durationSeconds -is [bool] -or
            [double]::IsNaN([double]$record.durationSeconds) -or
            [double]::IsInfinity([double]$record.durationSeconds) -or [double]$record.durationSeconds -lt 0) {
            throw 'Qualification raw gate summary must use the exact schema and passing L0, L1, and L2 outcomes.'
        }
    }
    if ($phases.schemaVersion -ne 1) { throw 'Qualification raw gate phases must use schemaVersion 1.' }
    foreach ($phaseName in @('ordinary', 'expiry')) {
        if (-not $phases.PSObject.Properties.Name.Contains($phaseName)) { throw "Qualification raw gate phase '$phaseName' is missing." }
        foreach ($stepName in @('environment', 'playwright')) {
            $step = $phases.$phaseName.$stepName
            if ($null -eq $step -or -not [bool]$step.attempted -or -not [bool]$step.completed -or $step.result -ne 'PASS') {
                throw "Qualification raw gate phase '$phaseName/$stepName' is incomplete or failed."
            }
        }
    }
    if ($journeyCounts.totalJourneys -lt 1 -or $journeyCounts.ordinaryJourneys -lt 0 -or $journeyCounts.expiryJourneys -lt 0 -or
        ($journeyCounts.ordinaryJourneys + $journeyCounts.expiryJourneys) -ne $journeyCounts.totalJourneys) {
        throw 'Qualification raw journey counts are incomplete.'
    }
    function Get-JunitOutcome {
        param([xml]$Document, [string]$Description)

        $root = if ($null -ne $Document.testsuites) { $Document.testsuites } elseif ($null -ne $Document.testsuite) { $Document.testsuite } else { $null }
        if ($null -eq $root) { throw "$Description is missing a testsuites or testsuite root." }
        $counts = @{}
        foreach ($attribute in @('tests', 'failures', 'errors', 'skipped')) {
            if (-not $root.HasAttribute($attribute)) { throw "$Description is missing the $attribute count." }
            $value = 0
            if (-not [int]::TryParse($root.GetAttribute($attribute), [ref]$value) -or $value -lt 0) { throw "$Description has an invalid $attribute count." }
            $counts[$attribute] = $value
        }
        $notPassed = $counts.failures + $counts.errors + $counts.skipped
        if ($notPassed -gt $counts.tests) { throw "$Description has inconsistent outcome counts." }
        if ($notPassed -ne 0) { throw "$Description must be completely green; failures=$($counts.failures), errors=$($counts.errors), skipped=$($counts.skipped)." }
        return [pscustomobject]@{ expected = $counts.tests; passed = $counts.tests - $notPassed }
    }
    $ordinaryOutcome = Get-JunitOutcome -Document $ordinary -Description 'Qualification raw ordinary Firefox JUnit'
    $expiryOutcome = Get-JunitOutcome -Document $expiry -Description 'Qualification raw expiry Firefox JUnit'
    return [pscustomobject]@{
        stability = [pscustomobject]@{ testedCommit = $expectedCommit; consecutivePassNoneRuns = $stability.Count; minimumDurationSeconds = [Math]::Round(($durations | Measure-Object -Minimum).Minimum, 3); maximumDurationSeconds = [Math]::Round(($durations | Measure-Object -Maximum).Maximum, 3); averageDurationSeconds = [Math]::Round(($durations | Measure-Object -Average).Average, 3) }
        fullGate = [pscustomobject]@{ layers = @($gate | ForEach-Object { [pscustomobject]@{ layer = $_.layer; result = $_.result; durationSeconds = $_.durationSeconds } }) }
        firefox = [pscustomobject]@{ ordinaryPassed = $ordinaryOutcome.passed; ordinaryExpected = $ordinaryOutcome.expected; isolatedExpiryPassed = $expiryOutcome.passed; isolatedExpiryExpected = $expiryOutcome.expected; userJourneys = [int]$journeyCounts.totalJourneys }
    }
}

function Test-TrackedEvidenceLink {
    param([string]$RelativePath, [string]$LinkTarget, [hashtable]$Tracked)

    if ($LinkTarget -match '^https?://') { return $true }
    $target = $LinkTarget.Split('#')[0].Split('?')[0]
    if ([string]::IsNullOrWhiteSpace($target)) { return $false }
    $base = Split-Path -Parent $RelativePath
    $combined = if ($base) { Join-Path $base $target } else { $target }
    $normalized = [IO.Path]::GetFullPath((Join-Path $repoRoot $combined))
    $rootWithSeparator = $repoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $normalized.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $repoRelative = $normalized.Substring($rootWithSeparator.Length).Replace('\', '/')
    return $Tracked.ContainsKey($repoRelative)
}

function Get-UpstreamLedger {
    param([string]$LedgerPath)

    $text = [IO.File]::ReadAllText($LedgerPath)
    return Get-MarkedJson -Text $text -Marker 'upstream-ledger-v1' -Description 'docs/upstream-contributions.md'
}

function Test-LedgerRecord {
    param([object]$Record, [hashtable]$Tracked)

    foreach ($field in @('kind', 'url', 'pageState', 'lifecycleStatus', 'haloVersion', 'sourceCommit', 'evidence')) {
        if (-not $Record.PSObject.Properties.Name.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$Record.$field)) {
            Add-PublicationError "Ledger record is missing required field '$field'."
        }
    }
    if ($Record.kind -notin @('ISSUE', 'PR')) { Add-PublicationError "Ledger kind must be ISSUE or PR, observed '$($Record.kind)'." }
    if ($Record.pageState -notin @('OPEN', 'CLOSED', 'MERGED', 'DRAFT')) { Add-PublicationError "Ledger pageState is invalid for $($Record.url)." }
    $allowedLifecycle = if ($Record.kind -eq 'ISSUE') { @('REPORTED', 'RESOLVED') } else { @('SUBMITTED', 'CLOSED', 'MERGED') }
    if ($Record.lifecycleStatus -notin $allowedLifecycle) { Add-PublicationError "Ledger lifecycleStatus is invalid for $($Record.url)." }
    if ($Record.kind -eq 'PR') {
        $expectedLifecycle = switch ($Record.pageState) {
            'OPEN' { 'SUBMITTED' }
            'DRAFT' { 'SUBMITTED' }
            'CLOSED' { 'CLOSED' }
            'MERGED' { 'MERGED' }
        }
        if ($Record.lifecycleStatus -ne $expectedLifecycle) {
            Add-PublicationError "PR lifecycleStatus must be $expectedLifecycle when pageState is $($Record.pageState) for $($Record.url)."
        }
    }
    if ([string]$Record.sourceCommit -notmatch '^[0-9a-f]{40}$') { Add-PublicationError "Ledger sourceCommit must be a full lowercase SHA for $($Record.url)." }
    if ($Record.kind -eq 'PR' -and (-not $Record.PSObject.Properties.Name.Contains('headCommit') -or [string]$Record.headCommit -notmatch '^[0-9a-f]{40}$')) {
        Add-PublicationError "PR ledger record must contain a full lowercase headCommit for $($Record.url)."
    }
    $evidenceIsTracked = ([string]$Record.evidence -match '^https?://') -or $Tracked.ContainsKey([string]$Record.evidence)
    if (-not $evidenceIsTracked) {
        Add-PublicationError "Ledger evidence is not a tracked file or URL for $($Record.url): $($Record.evidence)"
    }
}

function Get-PublicationUrls {
    param([string]$Text)

    return @([regex]::Matches($Text, 'https?://[^\s)"''<>]+') | ForEach-Object { $_.Value.TrimEnd('.', ',', ';', ':') } | Sort-Object -Unique)
}

function Test-PublicUrl {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -MaximumRedirection 5 -Headers @{ 'User-Agent' = 'halo-quality-engineering-publication-verifier' }
    } catch {
        Add-PublicationError "Public URL check failed for ${Url}: $($_.Exception.Message)"
        return
    }
    if ($response.StatusCode -notin @(200, 301, 302)) { Add-PublicationError "Public URL returned HTTP $($response.StatusCode): $Url" }
}

function Test-ContributionNarrative {
    param([string]$Text)

    foreach ($heading in @(
        'Contribution Purpose', 'Reproduction', 'Expected And Actual', 'Duplicate Search',
        'PR Change And Validation', 'AI Disclosure', 'Review And Status', 'Modification History'
    )) {
        if ($Text -notmatch ('(?m)^##\s+' + [regex]::Escape($heading) + '\s*$')) {
            Add-PublicationError "docs/upstream-contributions.md is missing the '$heading' section."
        }
    }
    try {
        $detail = Get-MarkedJson -Text $Text -Marker 'upstream-contribution-detail-v1' -Description 'docs/upstream-contributions.md'
        foreach ($field in @('purpose', 'reproductionEvidence', 'expectedActual', 'duplicateSearch', 'prChangeHead', 'validation', 'aiDisclosure', 'modificationHistory')) {
            if (-not $detail.PSObject.Properties.Name.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$detail.$field)) {
                Add-PublicationError "Upstream contribution detail is missing $field."
            }
        }
        if (@($detail.modificationHistory).Count -eq 0) { Add-PublicationError 'Upstream contribution detail has empty modificationHistory.' }
        if ($detail.PSObject.Properties.Name.Contains('reviewFeedback')) {
            Add-PublicationError 'Upstream contribution detail must not infer human feedback from GitHub actor type; record exact publicReviewFacts instead.'
        }
        if (-not $detail.PSObject.Properties.Name.Contains('publicReviewFacts') -or $detail.publicReviewFacts -isnot [psobject] -or $detail.publicReviewFacts -is [string]) {
            Add-PublicationError 'Upstream contribution detail requires structured publicReviewFacts.'
        } else {
            $facts = $detail.publicReviewFacts
            foreach ($field in @('checkedAt', 'issueCommentCount', 'reviewCount', 'issueComments', 'reviews')) {
                if (-not $facts.PSObject.Properties.Name.Contains($field)) { Add-PublicationError "Upstream contribution publicReviewFacts is missing $field." }
            }
            $unsupportedFields = @($facts.PSObject.Properties.Name | Where-Object { $_ -notin @('checkedAt', 'issueCommentCount', 'reviewCount', 'issueComments', 'reviews') })
            if ($unsupportedFields.Count -gt 0) {
                Add-PublicationError "Upstream contribution publicReviewFacts contains unsupported fields: $($unsupportedFields -join ', ')."
            }
            $checkedAt = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact([string]$facts.checkedAt, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$checkedAt) -or $checkedAt.Date -gt [DateTime]::UtcNow.Date) {
                Add-PublicationError 'Upstream contribution publicReviewFacts checkedAt must be a non-future ISO date.'
            }
            foreach ($field in @('issueCommentCount', 'reviewCount')) {
                $count = -1
                if (-not [int]::TryParse([string]$facts.$field, [ref]$count) -or $count -lt 0) { Add-PublicationError "Upstream contribution publicReviewFacts $field must be a non-negative integer." }
            }
            $comments = @($facts.issueComments)
            $reviews = @($facts.reviews)
            if ([int]$facts.issueCommentCount -ne $comments.Count -or [int]$facts.reviewCount -ne $reviews.Count) {
                Add-PublicationError 'Upstream contribution publicReviewFacts counts do not match the recorded fact arrays.'
            }
            foreach ($comment in $comments) {
                if ([string]::IsNullOrWhiteSpace([string]$comment.actor) -or [string]::IsNullOrWhiteSpace([string]$comment.actorType)) {
                    Add-PublicationError 'Upstream contribution publicReviewFacts issue comments require actor and actorType.'
                }
            }
            foreach ($review in $reviews) {
                if ([string]::IsNullOrWhiteSpace([string]$review.actor) -or [string]::IsNullOrWhiteSpace([string]$review.actorType) -or [string]::IsNullOrWhiteSpace([string]$review.state)) {
                    Add-PublicationError 'Upstream contribution publicReviewFacts reviews require actor, actorType, and state.'
                }
            }
        }
        return $detail
    } catch { Add-PublicationError $_.Exception.Message; return $null }
}

function Get-GitHubRecordState {
    param([object]$Record)

    $match = [regex]::Match([string]$Record.url, '^https://github\.com/halo-dev/halo/(issues|pull)/(\d+)$')
    if (-not $match.Success) { throw "Unsupported upstream URL: $($Record.url)" }
    $endpoint = if ($Record.kind -eq 'PR') { 'pulls' } else { 'issues' }
    if (($Record.kind -eq 'PR' -and $match.Groups[1].Value -ne 'pull') -or ($Record.kind -eq 'ISSUE' -and $match.Groups[1].Value -ne 'issues')) {
        throw "Ledger kind does not match URL: $($Record.url)"
    }
    $uri = $GitHubApiBaseUri.TrimEnd('/') + "/repos/halo-dev/halo/$endpoint/$($match.Groups[2].Value)"
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{ 'User-Agent' = 'halo-quality-engineering-publication-verifier' }
    } catch {
        throw "Public GitHub API check failed for $($Record.url): $($_.Exception.Message)"
    }
    if ($response.StatusCode -notin @(200, 301, 302)) { throw "Public GitHub API returned HTTP $($response.StatusCode) for $($Record.url)." }
    try {
        $body = $response.Content | ConvertFrom-Json
    } catch {
        throw "Public GitHub API returned invalid JSON for $($Record.url)."
    }
    $state = if ($Record.kind -eq 'PR' -and [bool]$body.merged) {
        'MERGED'
    } elseif ($Record.kind -eq 'PR' -and [bool]$body.draft) {
        'DRAFT'
    } else {
        ([string]$body.state).ToUpperInvariant()
    }
    return [pscustomobject]@{ state = $state; body = $body }
}

if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) { throw "Repository root does not exist: $repoRoot" }
$trackedPaths = @(Get-PublicationPaths -Paths @(Get-TrackedPaths))
$tracked = @{}
foreach ($path in $trackedPaths) { $tracked[$path] = $true }
$textFiles = @(Get-TextFiles -Paths $trackedPaths)

foreach ($file in $textFiles) {
    Write-Verbose "Scanning publication file $($file.path)"
    foreach ($match in [regex]::Matches($file.text, '\b(?:\d{1,3}\.){3}\d{1,3}\b')) {
        if (-not (Test-AllowedIpv4 -Address $match.Value)) { Add-PublicationError "$($file.path) contains disallowed IPv4 address $($match.Value)." }
    }
    if ([regex]::IsMatch($file.text, '(?i)\b(?:ghp|github_pat|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b|\bBearer\s+[A-Za-z0-9._~+/-]{20,}\b')) {
        Add-PublicationError "$($file.path) contains a credential or token pattern."
    }
    if (-not (Test-AllowedSecretSourcePath -Path $file.path) -and
        [regex]::IsMatch($file.text, '(?im)^\s*(?:authorization|cookie|set-cookie)\s*:\s*(?!\s*(?:\[?redacted\]?|<redacted>)\s*$).+$|(?:["'']?(?:password|authorization|cookie|set-cookie|token|access_token|refresh_token)["'']?\s*[:=]\s*)(?!\s*(?:\[?redacted\]?|<redacted>)\s*$)(?:["'']?)[^\s"'']+')) {
        Add-PublicationError "$($file.path) contains an unredacted authentication or password field."
    }
    if ([regex]::IsMatch($file.text, '(?i)\b(?:github[ -]?enterprise|github\.[a-z0-9-]+\.(?:com|net|org)|git(?:hub|lab)?\.(?:corp|internal|local)|[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:internal|local|corp|lan|home|private))\b')) {
        Add-PublicationError "$($file.path) contains an enterprise or private-host name."
    }
    if ($file.text.Contains($syntheticPassword) -and -not (Test-SyntheticPasswordPath -Path $file.path)) {
        Add-PublicationError "$($file.path) contains the declared synthetic password outside approved environment or test source."
    }
}

foreach ($path in $trackedPaths) {
    if ($path -match '(?i)(?:^|/)(?:\.auth(?:/|$)|[^/]*storage[-_]?state[^/]*\.(?:json|js|ts)$)') {
        Add-PublicationError "Tracked storageState file is forbidden: $path"
    }
}

$readmePath = Join-Path $repoRoot 'README.md'
if (-not $tracked.ContainsKey('README.md')) {
    Add-PublicationError 'README.md must be tracked.'
} else {
    $readme = [IO.File]::ReadAllText($readmePath)
    Test-ResultNarrative -Readme $readme
    try {
        $claims = Get-MarkedJson -Text $readme -Marker 'qualification-claims-v1' -Description 'README.md'
        if ($claims.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$claims.evidence)) {
            Add-PublicationError 'README qualification claims require schemaVersion 1 and an evidence path.'
        } elseif (-not $tracked.ContainsKey([string]$claims.evidence)) {
            Add-PublicationError "README qualification evidence is not a tracked file: $($claims.evidence)"
        } else {
            try {
                $evidence = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $claims.evidence) | ConvertFrom-Json
                if ($evidence.schemaVersion -ne 1) { Add-PublicationError 'Qualification evidence must use schemaVersion 1.' }
                Test-QualificationFacts -Facts $evidence.facts -Description 'Qualification evidence'
                Test-QualificationFacts -Facts $claims.facts -Description 'README qualification claims'
                $derivedFacts = Get-DerivedQualificationFacts -Provenance $evidence.provenance -Tracked $tracked
                if (($evidence.facts | ConvertTo-Json -Depth 8 -Compress) -ne ($derivedFacts | ConvertTo-Json -Depth 8 -Compress)) {
                    Add-PublicationError "Qualification evidence facts do not exactly match derived tracked raw artifacts. expected=$($evidence.facts | ConvertTo-Json -Depth 8 -Compress) actual=$($derivedFacts | ConvertTo-Json -Depth 8 -Compress)"
                }
                if (-not (Test-JsonValueEqual $claims.facts $evidence.facts)) {
                    Add-PublicationError 'README qualification claims do not exactly match the authoritative evidence facts.'
                }
            } catch {
                Add-PublicationError "README qualification evidence cannot be parsed: $($_.Exception.Message)"
            }
        }
    } catch {
        Add-PublicationError $_.Exception.Message
    }
    foreach ($line in ($readme -split "`r?`n")) {
        if ($line -match '(?i)\b(?:resume|curriculum vitae|\bcv\b)\b' -and $line -notmatch '\[[^\]]+\]\([^)]+\)') {
            Add-PublicationError "Resume claim lacks an evidence link: $line"
        }
    }
}

$ledgerRelativePath = 'docs/upstream-contributions.md'
if (-not $tracked.ContainsKey($ledgerRelativePath)) {
    Add-PublicationError "$ledgerRelativePath must be tracked."
} else {
    try {
        $ledgerPath = Join-Path $repoRoot $ledgerRelativePath
        $ledgerText = [IO.File]::ReadAllText($ledgerPath)
        $contributionDetail = Test-ContributionNarrative -Text $ledgerText
        $ledger = Get-UpstreamLedger -LedgerPath $ledgerPath
        if ($ledger.schemaVersion -ne 1 -or $null -eq $ledger.records) { Add-PublicationError 'Upstream ledger must use schemaVersion 1 with records.' }
        $records = @($ledger.records)
        if (@($records | Where-Object { $_.kind -eq 'ISSUE' }).Count -lt 1) { Add-PublicationError 'Upstream ledger requires at least one Issue.' }
        if (@($records | Where-Object { $_.kind -eq 'PR' }).Count -lt 1) { Add-PublicationError 'Upstream ledger requires at least one PR.' }
        foreach ($record in $records) {
            Test-LedgerRecord -Record $record -Tracked $tracked
            if (-not $SkipLiveChecks -and $record.kind -in @('ISSUE', 'PR')) {
                try {
                    $live = Get-GitHubRecordState -Record $record
                    if ($live.state -ne $record.pageState) { Add-PublicationError "Public state mismatch for $($record.url): ledger=$($record.pageState), live=$($live.state)." }
                    if ($record.kind -eq 'PR' -and [string]$live.body.head.sha -ne [string]$record.headCommit) {
                        Add-PublicationError "Public PR head commit mismatch for $($record.url)."
                    }
                    if ($record.kind -eq 'PR' -and $null -ne $contributionDetail -and $null -ne $contributionDetail.publicReviewFacts) {
                        Test-PublicPrFacts -Record $record -Facts $contributionDetail.publicReviewFacts -ApiBaseUri $GitHubApiBaseUri
                    }
                } catch {
                    Add-PublicationError $_.Exception.Message
                }
            }
        }
        if (-not $SkipLiveChecks -or $CheckPublicUrls) {
            foreach ($url in @(Get-PublicationUrls -Text $ledgerText) + @(Get-PublicationUrls -Text $readme)) {
                Test-PublicUrl -Url $url
            }
        }
    } catch {
        Add-PublicationError $_.Exception.Message
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host 'Publication verification passed.'
exit 0
