function Get-PublicGitHubCollection {
    param([string]$Path, [string]$Description, [string]$ApiBaseUri)

    $items = @()
    for ($page = 1; $page -le 100; $page++) {
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $uri = $ApiBaseUri.TrimEnd('/') + $Path + $separator + "per_page=100&page=$page"
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{ 'User-Agent' = 'halo-quality-engineering-publication-verifier' }
            if ($response.StatusCode -notin @(200, 301, 302)) { throw "HTTP $($response.StatusCode)" }
            $parsed = $response.Content | ConvertFrom-Json
            $pageItems = if ($null -eq $parsed) {
                @()
            } elseif ($parsed -is [Array]) {
                @($parsed | ForEach-Object { $_ })
            } else {
                @($parsed)
            }
        } catch {
            throw "Public GitHub API check failed for ${Description}: $($_.Exception.Message)"
        }
        $items += $pageItems
        if ($pageItems.Count -lt 100) { return $items }
    }
    throw "Public GitHub API pagination exceeded 100 pages for $Description."
}

function Test-PublicPrFacts {
    param([object]$Record, [object]$Facts, [string]$ApiBaseUri)

    $match = [regex]::Match([string]$Record.url, '^https://github\.com/halo-dev/halo/pull/(\d+)$')
    if (-not $match.Success) { throw "Unsupported upstream PR URL: $($Record.url)" }
    $number = $match.Groups[1].Value
    $issueComments = @(Get-PublicGitHubCollection -Path "/repos/halo-dev/halo/issues/$number/comments" -Description "PR issue comments for $($Record.url)" -ApiBaseUri $ApiBaseUri)
    $reviews = @(Get-PublicGitHubCollection -Path "/repos/halo-dev/halo/pulls/$number/reviews" -Description "PR reviews for $($Record.url)" -ApiBaseUri $ApiBaseUri)
    $actual = [pscustomobject]@{
        issueCommentCount = $issueComments.Count
        reviewCount = $reviews.Count
        issueComments = @($issueComments | ForEach-Object { [pscustomobject]@{ actor = [string]$_.user.login; actorType = [string]$_.user.type } })
        reviews = @($reviews | ForEach-Object { [pscustomobject]@{ actor = [string]$_.user.login; actorType = [string]$_.user.type; state = [string]$_.state } })
    }
    foreach ($field in @('issueCommentCount', 'reviewCount')) {
        if ([int]$Facts.$field -ne [int]$actual.$field) { throw "Public PR facts mismatch for $($Record.url): $field ledger=$($Facts.$field), live=$($actual.$field)." }
    }
    $recordedComments = @($Facts.issueComments | ForEach-Object { "$($_.actor)`t$($_.actorType)" } | Sort-Object)
    $liveComments = @($actual.issueComments | ForEach-Object { "$($_.actor)`t$($_.actorType)" } | Sort-Object)
    if (($recordedComments -join "`n") -ne ($liveComments -join "`n")) {
        throw "Public PR facts mismatch for $($Record.url): issue comment actor/type facts differ."
    }
    $recordedReviews = @($Facts.reviews | ForEach-Object { "$($_.actor)`t$($_.actorType)`t$($_.state)" } | Sort-Object)
    $liveReviews = @($actual.reviews | ForEach-Object { "$($_.actor)`t$($_.actorType)`t$($_.state)" } | Sort-Object)
    if (($recordedReviews -join "`n") -ne ($liveReviews -join "`n")) {
        throw "Public PR facts mismatch for $($Record.url): review actor/type/state facts differ."
    }
}
