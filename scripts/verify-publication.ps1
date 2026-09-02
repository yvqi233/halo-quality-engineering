[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$GitHubApiBaseUri = 'https://api.github.com',
    [switch]$SkipLiveChecks
)

$ErrorActionPreference = 'Stop'
$repoRoot = if ($RepositoryRoot) {
    [IO.Path]::GetFullPath($RepositoryRoot)
} else {
    Split-Path -Parent $PSScriptRoot
}
$errors = [Collections.Generic.List[string]]::new()
$syntheticPassword = 'HaloQE!' + '2026'

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

    return $Path -match '^(?:environment|api-tests|e2e)/' -or
        $Path -match '^scripts/(?:environment|collect-evidence|.+\.test)\.ps1$'
}

function Get-ReadmeResultBullets {
    param([string]$Readme)

    $inResults = $false
    foreach ($line in ($Readme -split "`r?`n")) {
        if ($line -match '^##\s+Measured Results\s*$') { $inResults = $true; continue }
        if ($inResults -and $line -match '^##\s+') { break }
        if ($inResults -and $line -match '^\s*-\s+') { $line }
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
    $match = [regex]::Match($text, '(?s)<!--\s*upstream-ledger-v1\s*-->\s*```json\s*(.*?)\s*```')
    if (-not $match.Success) { throw 'docs/upstream-contributions.md is missing its upstream-ledger-v1 JSON block.' }
    try {
        return ($match.Groups[1].Value | ConvertFrom-Json)
    } catch {
        throw "docs/upstream-contributions.md has invalid ledger JSON: $($_.Exception.Message)"
    }
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
    if ([string]$Record.sourceCommit -notmatch '^[0-9a-f]{40}$') { Add-PublicationError "Ledger sourceCommit must be a full lowercase SHA for $($Record.url)." }
    if ($Record.kind -eq 'PR' -and (-not $Record.PSObject.Properties.Name.Contains('headCommit') -or [string]$Record.headCommit -notmatch '^[0-9a-f]{40}$')) {
        Add-PublicationError "PR ledger record must contain a full lowercase headCommit for $($Record.url)."
    }
    $evidenceIsTracked = ([string]$Record.evidence -match '^https?://') -or $Tracked.ContainsKey([string]$Record.evidence)
    if (-not $evidenceIsTracked) {
        Add-PublicationError "Ledger evidence is not a tracked file or URL for $($Record.url): $($Record.evidence)"
    }
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
    if ([regex]::IsMatch($file.text, '(?i)\b(?:github[ -]?enterprise|github\.[a-z0-9-]+\.(?:com|net|org)|git(?:hub|lab)?\.(?:corp|internal|local))\b')) {
        Add-PublicationError "$($file.path) contains an enterprise or private-host name."
    }
    if ($file.text.Contains($syntheticPassword) -and -not (Test-SyntheticPasswordPath -Path $file.path)) {
        Add-PublicationError "$($file.path) contains the declared synthetic password outside approved environment or test source."
    }
}

foreach ($path in $trackedPaths) {
    if ($path -match '(?i)(?:^|/)(?:storage[-_]?state|.*\.storage[-_]?state)\.(?:json|js|ts)$') {
        Add-PublicationError "Tracked storageState file is forbidden: $path"
    }
}

$readmePath = Join-Path $repoRoot 'README.md'
if (-not $tracked.ContainsKey('README.md')) {
    Add-PublicationError 'README.md must be tracked.'
} else {
    $readme = [IO.File]::ReadAllText($readmePath)
    $resultBullets = @(Get-ReadmeResultBullets -Readme $readme)
    if ($resultBullets.Count -eq 0) { Add-PublicationError 'README.md must contain a Measured Results bullet linked to evidence.' }
    foreach ($bullet in $resultBullets) {
        $links = @([regex]::Matches($bullet, '\[[^\]]+\]\(([^)]+)\)'))
        if ($links.Count -eq 0) { Add-PublicationError "README measured-result claim lacks an evidence link: $bullet"; continue }
        foreach ($link in $links) {
            if (-not (Test-TrackedEvidenceLink -RelativePath 'README.md' -LinkTarget $link.Groups[1].Value -Tracked $tracked)) {
                Add-PublicationError "README evidence link is not tracked or public: $($link.Groups[1].Value)"
            }
        }
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
        $ledger = Get-UpstreamLedger -LedgerPath (Join-Path $repoRoot $ledgerRelativePath)
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
                } catch {
                    Add-PublicationError $_.Exception.Message
                }
            }
        }
    } catch {
        Add-PublicationError $_.Exception.Message
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Publication verification passed.'
exit 0
