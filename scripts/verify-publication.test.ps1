[CmdletBinding()]
param(
    [ValidateSet('', 'partial-junit', 'untracked-provenance', 'root-array', 'unsupported-human-inference')]
    [string]$Regression = ''
)

$ErrorActionPreference = 'Stop'
$verifier = Join-Path $PSScriptRoot 'verify-publication.ps1'
$githubHelper = Join-Path $PSScriptRoot 'verify-publication.github.ps1'

function Assert-True { param([bool]$Value, [string]$Message) if (-not $Value) { throw $Message } }
function Write-Text { param([string]$Path, [string]$Text) New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null; [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) "publication-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $root | Out-Null
    & git -C $root init --quiet
    & git -C $root config core.autocrlf false
    $excludeFile = Join-Path $root '.git/info/fixture-excludes'
    Write-Text $excludeFile ''
    & git -C $root config core.excludesFile $excludeFile
    $sha = '0123456789012345678901234567890123456789'; $digest = 'halohub/halo@sha256:0123456789012345678901234567890123456789012345678901234567890123'
    $stabilityLines = @(1..20 | ForEach-Object {
        "{`"sequence`":$_,`"startedAt`":`"2026-09-01T00:00:$($_.ToString('00'))Z`",`"commit`":`"$sha`",`"haloImage`":`"$digest`",`"result`":`"PASS`",`"durationSeconds`":1,`"failureKind`":`"NONE`"}"
    })
    Write-Text "$root/artifacts/stability/runs.jsonl" (($stabilityLines -join "`n") + "`n")
    Write-Text "$root/evidence/raw/quality-gate/summary.jsonl" "{`"layer`":`"L0`",`"result`":`"PASS`",`"durationSeconds`":1,`"failureKind`":`"NONE`",`"artifactName`":`"contract`"}`n{`"layer`":`"L1`",`"result`":`"PASS`",`"durationSeconds`":1,`"failureKind`":`"NONE`",`"artifactName`":`"api-smoke`"}`n{`"layer`":`"L2`",`"result`":`"PASS`",`"durationSeconds`":1,`"failureKind`":`"NONE`",`"artifactName`":`"chromium-e2e`"}`n"
    Write-Text "$root/evidence/raw/quality-gate/L0-counts.json" '{}'; Write-Text "$root/evidence/raw/quality-gate/L1-counts.json" '{}'; Write-Text "$root/evidence/raw/quality-gate/L2-counts.json" '{"ordinaryJourneys":0,"expiryJourneys":1,"totalJourneys":1}'
    Write-Text "$root/evidence/raw/quality-gate/L2-phases.json" '{"schemaVersion":1,"ordinary":{"environment":{"attempted":true,"completed":true,"result":"PASS"},"playwright":{"attempted":true,"completed":true,"result":"PASS"}},"expiry":{"environment":{"attempted":true,"completed":true,"result":"PASS"},"playwright":{"attempted":true,"completed":true,"result":"PASS"}}}'
    Write-Text "$root/evidence/raw/firefox/ordinary.xml" '<testsuites tests="11" failures="0" errors="0" skipped="0" />'; Write-Text "$root/evidence/raw/firefox/expiry.xml" '<testsuites tests="1" failures="0" errors="0" skipped="0" />'
    $facts = "{`"stability`":{`"testedCommit`":`"$sha`",`"consecutivePassNoneRuns`":20,`"minimumDurationSeconds`":1,`"maximumDurationSeconds`":1,`"averageDurationSeconds`":1},`"fullGate`":{`"layers`": [{`"layer`":`"L0`",`"result`":`"PASS`",`"durationSeconds`":1},{`"layer`":`"L1`",`"result`":`"PASS`",`"durationSeconds`":1},{`"layer`":`"L2`",`"result`":`"PASS`",`"durationSeconds`":1}]},`"firefox`":{`"ordinaryPassed`":11,`"ordinaryExpected`":11,`"isolatedExpiryPassed`":1,`"isolatedExpiryExpected`":1,`"userJourneys`":1}}"
    $prov = '{"stabilityRecord":"artifacts/stability/runs.jsonl","gateSummary":"evidence/raw/quality-gate/summary.jsonl","journeyCounts":"evidence/raw/quality-gate/L2-counts.json","gatePhases":"evidence/raw/quality-gate/L2-phases.json","firefoxOrdinaryJunit":"evidence/raw/firefox/ordinary.xml","firefoxExpiryJunit":"evidence/raw/firefox/expiry.xml"}'
    Write-Text "$root/evidence/qualification-v1.json" "{`"schemaVersion`":1,`"facts`":$facts,`"provenance`":$prov}"
    $readme = @(
        '# Fixture', '', '## Measured Results', '',
        'The machine-checked claim below is compared exactly with the authoritative tracked [raw qualification artifact](evidence/qualification-v1.json). The structured record is the only location for qualification values in this section.', '',
        '<!-- qualification-claims-v1 -->', '```json',
        ('{"schemaVersion":1,"evidence":"evidence/qualification-v1.json","facts":' + $facts + '}'), '```'
    ) -join "`n"
    Write-Text "$root/README.md" $readme
    $detail = '{"schemaVersion":1,"purpose":"x","reproductionEvidence":"evidence/qualification-v1.json","expectedActual":"x","duplicateSearch":"x","prChangeHead":"x","validation":"x","aiDisclosure":"x","publicReviewFacts":{"checkedAt":"2026-09-02","issueCommentCount":0,"reviewCount":0,"issueComments":[],"reviews":[]},"modificationHistory":["x"]}'
    $ledger = @(
        '# Upstream', '', '## Contribution Purpose', 'x', '## Reproduction', 'x', '## Expected And Actual', 'x',
        '## Duplicate Search', 'x', '## PR Change And Validation', 'x', '## AI Disclosure', 'x',
        '## Review And Status', 'x', '## Modification History', 'x',
        '<!-- upstream-contribution-detail-v1 -->', '```json', $detail, '```',
        '<!-- upstream-ledger-v1 -->', '```json',
        ('{"schemaVersion":1,"records":[{"kind":"ISSUE","url":"https://github.com/halo-dev/halo/issues/1","pageState":"OPEN","lifecycleStatus":"REPORTED","haloVersion":"2.26.1","sourceCommit":"' + $sha + '","evidence":"evidence/qualification-v1.json"},{"kind":"PR","url":"https://github.com/halo-dev/halo/pull/2","pageState":"OPEN","lifecycleStatus":"SUBMITTED","haloVersion":"2.26.1","sourceCommit":"' + $sha + '","headCommit":"fedcba9876543210fedcba9876543210fedcba98","evidence":"evidence/qualification-v1.json"}]}'), '```'
    ) -join "`n"
    Write-Text "$root/docs/upstream-contributions.md" $ledger
    & git -C $root add .; return $root
}
function Invoke-Verifier { param([string]$Root,[string[]]$AdditionalVerifierArguments = @())
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifier,'-RepositoryRoot',$Root,'-SkipLiveChecks') + $AdditionalVerifierArguments
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output=@(& powershell.exe @arguments 2>&1); $exitCode=$LASTEXITCODE } finally { $ErrorActionPreference = $savedErrorActionPreference }
    return [pscustomobject]@{ exitCode = $exitCode; output = $output }
}
function Invoke-Case { param([string]$Name,[string]$Expected,[scriptblock]$Mutate,[string[]]$AdditionalVerifierArguments = @())
    $root=New-Fixture; try { & $Mutate $root; & git -C $root add .; $result=Invoke-Verifier -Root $root -AdditionalVerifierArguments $AdditionalVerifierArguments; Assert-True ($result.exitCode -ne 0) "$Name unexpectedly passed"; $normalizedOutput = ($result.output -join "`n") -replace '\s', ''; $normalizedExpected = $Expected -replace '\s', ''; Assert-True ($normalizedOutput -match [regex]::Escape($normalizedExpected)) "$Name missing diagnostic $Expected; output=$($result.output -join ' | ')" } finally { Remove-Item $root -Recurse -Force }
}

function Test-PartialJunitRegression {
    Invoke-Case 'partial junit with matching claims' 'Qualification raw ordinary Firefox JUnit must be completely green' {
        param($r)
        (Get-Content -Raw "$r/evidence/raw/firefox/ordinary.xml").Replace('failures="0"','failures="1"') | Set-Content "$r/evidence/raw/firefox/ordinary.xml"
        (Get-Content -Raw "$r/evidence/qualification-v1.json").Replace('"ordinaryPassed":11','"ordinaryPassed":10') | Set-Content "$r/evidence/qualification-v1.json"
        (Get-Content -Raw "$r/README.md").Replace('"ordinaryPassed":11','"ordinaryPassed":10') | Set-Content "$r/README.md"
    }
}

function Test-UntrackedProvenanceRegression {
    $root=New-Fixture
    try {
        & git -C $root rm --cached --quiet evidence/raw/firefox/ordinary.xml
        $result=Invoke-Verifier -Root $root
        Assert-True ($result.exitCode -ne 0) 'untracked provenance unexpectedly passed'
        Assert-True (($result.output -join "`n") -match [regex]::Escape('Qualification provenance path is not tracked')) 'untracked provenance missing its own diagnostic'
    } finally { Remove-Item $root -Recurse -Force }
}

function Test-ProvenancePathRegressions {
    Invoke-Case 'traversing provenance' 'Qualification provenance path contains traversal' {
        param($r)
        (Get-Content -Raw "$r/evidence/qualification-v1.json").Replace('evidence/raw/firefox/ordinary.xml','evidence/raw/firefox/../firefox/ordinary.xml') | Set-Content "$r/evidence/qualification-v1.json"
    }
    Invoke-Case 'outside provenance' 'Qualification provenance path is invalid or outside repository root' {
        param($r)
        (Get-Content -Raw "$r/evidence/qualification-v1.json").Replace('evidence/raw/firefox/ordinary.xml','C:/outside.xml') | Set-Content "$r/evidence/qualification-v1.json"
    }
}

function Test-RootArrayRegression {
    $root=New-Fixture
    $tcp = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $tcp.Start(); $port = ([Net.IPEndPoint]$tcp.LocalEndpoint).Port; $tcp.Stop()
    $apiJob = Start-Job -ArgumentList $port -ScriptBlock {
        param($listenerPort)
        $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $listenerPort); $listener.Start()
        try {
            $requestCount=0; $deadline=[DateTime]::UtcNow.AddSeconds(20)
            while ($requestCount -lt 4 -and [DateTime]::UtcNow -lt $deadline) {
                if (-not $listener.Pending()) { Start-Sleep -Milliseconds 20; continue }
                $client=$listener.AcceptTcpClient(); $stream=$client.GetStream()
                $reader=[IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
                $requestLine=$reader.ReadLine(); while ($reader.ReadLine()) {}
                $path=($requestLine -split ' ')[1].Split('?')[0]
                $body = switch ($path) {
                    '/repos/halo-dev/halo/issues/10283/comments' { '[{"user":{"login":"CLAassistant","type":"User"}},{"user":{"login":"sonarqubecloud[bot]","type":"Bot"}}]' }
                    '/repos/halo-dev/halo/pulls/10283/reviews' { '[]' }
                    default { '{"message":"not found"}' }
                }
                $bytes=[Text.Encoding]::UTF8.GetBytes($body)
                $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
                $stream.Write($header,0,$header.Length); $stream.Write($bytes,0,$bytes.Length); $stream.Flush(); $client.Close()
                $requestCount++
            }
            if ($requestCount -ne 4) { throw "Fake GitHub API received $requestCount of 4 expected requests." }
        } finally { $listener.Stop() }
    }
    try {
        $runner = @'
param([string]$HelperPath, [string]$ApiBaseUri)
$ErrorActionPreference = 'Stop'
. $HelperPath
$record = [pscustomobject]@{ url = 'https://github.com/halo-dev/halo/pull/10283' }
$facts = '{"issueCommentCount":2,"reviewCount":0,"issueComments":[{"actor":"CLAassistant","actorType":"User"},{"actor":"sonarqubecloud[bot]","actorType":"Bot"}],"reviews":[]}' | ConvertFrom-Json
Test-PublicPrFacts -Record $record -Facts $facts -ApiBaseUri $ApiBaseUri
$facts.issueComments[0].actor = 'different-status-service'
try {
    Test-PublicPrFacts -Record $record -Facts $facts -ApiBaseUri $ApiBaseUri
    throw 'fake GitHub actor/type mismatch unexpectedly passed'
} catch {
    if ($_.Exception.Message -notmatch 'issue comment actor/type facts differ') { throw }
}
Write-Host 'fake GitHub collection and fact comparison passed.'
'@
        $runnerPath=Join-Path $root 'github-helper-regression.ps1'; Write-Text $runnerPath $runner
        Start-Sleep -Milliseconds 1000
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerPath,'-HelperPath',$githubHelper,'-ApiBaseUri',"http://127.0.0.1:$port")
        $stdout=Join-Path $root 'github-helper.stdout.txt'; $stderr=Join-Path $root 'github-helper.stderr.txt'
        $child=Start-Process -FilePath powershell.exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $child.WaitForExit(15000)) {
            $child.Kill()
            throw 'fake GitHub helper child exceeded its 15-second deadline'
        }
        $child.WaitForExit(); $child.Refresh(); $exitCode=[int]$child.ExitCode
        $output=@(Get-Content $stdout -ErrorAction SilentlyContinue) + @(Get-Content $stderr -ErrorAction SilentlyContinue)
        Assert-True ($exitCode -eq 0) "fake GitHub root arrays were not normalized as 2 comments and 0 reviews (exit=$exitCode): $($output -join ' | ')"
        [void](Wait-Job $apiJob -Timeout 5)
        Assert-True ($apiJob.State -eq 'Completed') "fake GitHub API job did not complete: $($apiJob.State)"
        Receive-Job $apiJob -ErrorAction Stop | Out-Null
    } finally {
        Stop-Job $apiJob -ErrorAction SilentlyContinue
        Remove-Job $apiJob -Force -ErrorAction SilentlyContinue
        Remove-Item $root -Recurse -Force
    }
}

function Test-UnsupportedHumanInferenceRegression {
    Invoke-Case 'unsupported human inference' 'infer human feedback from GitHub actor type' {
        param($r)
        (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace('"publicReviewFacts":{"checkedAt":"2026-09-02","issueCommentCount":0,"reviewCount":0,"issueComments":[],"reviews":[]}', '"reviewFeedback":{"checkedAt":"2026-09-02","issueCommentCount":0,"reviewCount":0,"humanIssueCommentCount":0,"humanReviewCount":0,"noHumanFeedback":true}') | Set-Content "$r/docs/upstream-contributions.md"
    }
}

if ($Regression) {
    switch ($Regression) {
        'partial-junit' { Test-PartialJunitRegression }
        'untracked-provenance' { Test-UntrackedProvenanceRegression }
        'root-array' { Test-RootArrayRegression }
        'unsupported-human-inference' { Test-UnsupportedHumanInferenceRegression }
    }
    Write-Host "verify-publication regression passed: $Regression"
    exit 0
}

Assert-True (Test-Path $verifier) 'verifier missing'
$root=New-Fixture; try { $result=Invoke-Verifier -Root $root; Assert-True ($result.exitCode -eq 0) "valid fixture failed: $($result.output -join ' | ')"; Write-Text "$root/api-tests/bin/leak.txt" ('ghp_'+'abcdefghijklmnopqrstuvwxyz0123456789'); $result=Invoke-Verifier -Root $root; Assert-True ($result.exitCode -eq 0) "untracked bin contaminated verifier: $($result.output -join ' | ')" } finally { Remove-Item $root -Recurse -Force }
Invoke-Case 'ipv4' 'disallowed IPv4' { param($r) Write-Text "$r/docs/x.md" ('10.' + '20.30.40') }
Invoke-Case 'host' 'private-host name' { param($r) Write-Text "$r/docs/x.md" ('halo.'+'internal') }
Invoke-Case 'auth state' 'Tracked storageState' { param($r) Write-Text "$r/e2e/.auth/admin.json" '{}' }
Invoke-Case 'claim' 'README qualification claims' { param($r) (Get-Content -Raw "$r/README.md").Replace('"averageDurationSeconds":1','"averageDurationSeconds":9') | Set-Content "$r/README.md" }
Invoke-Case 'typed scalar claim' 'README qualification claims do not exactly match' {
    param($r)
    (Get-Content -Raw "$r/README.md").Replace('"consecutivePassNoneRuns":20','"consecutivePassNoneRuns":"20"') |
        Set-Content "$r/README.md"
}
Invoke-Case 'boolean stability duration' 'stability duration is invalid' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    Write-Text $path ((Get-Content -Raw $path).Replace('"durationSeconds":1', '"durationSeconds":true'))
}
Invoke-Case 'boolean stability outcomes' 'stability result and failureKind must be strings' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    Write-Text $path ((Get-Content -Raw $path).
        Replace('"result":"PASS","durationSeconds":1,"failureKind":"NONE"', '"result":true,"durationSeconds":1,"failureKind":true'))
}
Invoke-Case 'boolean gate duration' 'gate summary must use the exact schema' {
    param($r)
    $gatePath = "$r/evidence/raw/quality-gate/summary.jsonl"
    Write-Text $gatePath ((Get-Content -Raw $gatePath).Replace('"durationSeconds":1', '"durationSeconds":true'))
    foreach ($factsPath in @("$r/evidence/qualification-v1.json", "$r/README.md")) {
        (Get-Content -Raw $factsPath).Replace('"durationSeconds":1', '"durationSeconds":true') |
            Set-Content $factsPath
    }
}
Invoke-Case 'boolean gate outcomes' 'gate summary must use the exact schema' {
    param($r)
    $gatePath = "$r/evidence/raw/quality-gate/summary.jsonl"
    Write-Text $gatePath ((Get-Content -Raw $gatePath).Replace('"result":"PASS"', '"result":true'))
    foreach ($factsPath in @("$r/evidence/qualification-v1.json", "$r/README.md")) {
        (Get-Content -Raw $factsPath).Replace('"result":"PASS"', '"result":true') |
            Set-Content $factsPath
    }
}
Invoke-Case 'nineteen stability rows' 'exactly sequences 1 through 20' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    [IO.File]::WriteAllLines($path, @((Get-Content $path) | Select-Object -First 19), [Text.UTF8Encoding]::new($false))
    foreach ($factsPath in @("$r/evidence/qualification-v1.json", "$r/README.md")) {
        (Get-Content -Raw $factsPath).Replace('"consecutivePassNoneRuns":20','"consecutivePassNoneRuns":19') |
            Set-Content $factsPath
    }
}
Invoke-Case 'stability sequence gap' 'exactly sequences 1 through 20' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    Write-Text $path ((Get-Content -Raw $path).Replace('"sequence":10,','"sequence":99,'))
}
Invoke-Case 'mixed stability commit' 'one commit and one image' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    $lines = @(Get-Content $path)
    $lines[9] = $lines[9].Replace('0123456789012345678901234567890123456789','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
}
Invoke-Case 'mixed stability image' 'one commit and one image' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    $lines = @(Get-Content $path)
    $lines[9] = $lines[9].Replace(('sha256:' + ('0123456789' * 6) + '0123'), ('sha256:' + ('b' * 64)))
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
}
Invoke-Case 'stability schema drift' 'exact seven-field schema' {
    param($r)
    $path = "$r/artifacts/stability/runs.jsonl"
    Write-Text $path ((Get-Content -Raw $path).Replace('"failureKind":"NONE"}', '"failureKind":"NONE","attempt":1}'))
}
Invoke-Case 'prose' 'documented boilerplate' { param($r) Add-Content "$r/README.md" 'the suite completed successfully after twelve runs' }
Invoke-Case 'local link' 'README qualification evidence' { param($r) (Get-Content -Raw "$r/README.md").Replace('evidence/qualification-v1.json","facts','evidence/missing.json","facts') | Set-Content "$r/README.md" }
Invoke-Case 'lifecycle' 'lifecycleStatus must be SUBMITTED' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace('"lifecycleStatus":"SUBMITTED"','"lifecycleStatus":"MERGED"') | Set-Content "$r/docs/upstream-contributions.md" }
Invoke-Case 'ordinary junit failure' 'Firefox JUnit must be completely green' { param($r) (Get-Content -Raw "$r/evidence/raw/firefox/ordinary.xml").Replace('failures="0"','failures="1"') | Set-Content "$r/evidence/raw/firefox/ordinary.xml" }
Invoke-Case 'ordinary junit error' 'Firefox JUnit must be completely green' { param($r) (Get-Content -Raw "$r/evidence/raw/firefox/ordinary.xml").Replace('errors="0"','errors="1"') | Set-Content "$r/evidence/raw/firefox/ordinary.xml" }
Invoke-Case 'expiry junit skipped' 'Firefox JUnit must be completely green' { param($r) (Get-Content -Raw "$r/evidence/raw/firefox/expiry.xml").Replace('skipped="0"','skipped="1"') | Set-Content "$r/evidence/raw/firefox/expiry.xml" }
Invoke-Case 'failed phase' 'Qualification raw gate phase' { param($r) (Get-Content -Raw "$r/evidence/raw/quality-gate/L2-phases.json").Replace('"result":"PASS"','"result":"FAIL"') | Set-Content "$r/evidence/raw/quality-gate/L2-phases.json" }
Invoke-Case 'incomplete phase' 'Qualification raw gate phase' { param($r) (Get-Content -Raw "$r/evidence/raw/quality-gate/L2-phases.json").Replace('"completed":true','"completed":false') | Set-Content "$r/evidence/raw/quality-gate/L2-phases.json" }
$tcp = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $tcp.Start(); $port = ([Net.IPEndPoint]$tcp.LocalEndpoint).Port; $tcp.Stop()
$urlJob = Start-Job -ArgumentList $port -ScriptBlock { param($listenerPort) $listener=[Net.HttpListener]::new(); $listener.Prefixes.Add("http://127.0.0.1:$listenerPort/"); $listener.Start(); try { for ($index=0; $index -lt 2; $index++) { $context=$listener.GetContext(); $context.Response.StatusCode=404; $context.Response.Close() } } finally { $listener.Stop(); $listener.Close() } }
try {
    Start-Sleep -Milliseconds 200
    Invoke-Case 'public URL' 'Public URL check failed' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace('https://github.com/halo-dev/halo/issues/1', "http://127.0.0.1:$port/issues/1").Replace('https://github.com/halo-dev/halo/pull/2', "http://127.0.0.1:$port/pull/2") | Set-Content "$r/docs/upstream-contributions.md" } @('-CheckPublicUrls')
} finally { Stop-Job $urlJob -ErrorAction SilentlyContinue; Remove-Job $urlJob -Force -ErrorAction SilentlyContinue }
Invoke-Case 'nested password' 'e2e/reports/x.txt contains' { param($r) Write-Text "$r/e2e/reports/x.txt" ('HaloQE!'+'2026') }
Invoke-Case 'token' 'docs/x.txt contains a credential' { param($r) Write-Text "$r/docs/x.txt" ('ghp_'+'abcdefghijklmnopqrstuvwxyz0123456789') }
Invoke-Case 'basic' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Authorization'+': Basic abc') }
Invoke-Case 'cookie' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Cookie'+': a=b') }
Invoke-Case 'set cookie' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Set-Cookie'+': a=b') }
Invoke-Case 'quoted password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password: "secret"' }
Invoke-Case 'unquoted colon password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password: secret' }
Invoke-Case 'unquoted equals password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password=secret' }
Invoke-Case 'detail' 'Upstream contribution detail require' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace(',"publicReviewFacts":{"checkedAt":"2026-09-02","issueCommentCount":0,"reviewCount":0,"issueComments":[],"reviews":[]}','') | Set-Content "$r/docs/upstream-contributions.md" }
Invoke-Case 'feedback count' 'is missing reviewCount' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace(',"reviewCount":0','') | Set-Content "$r/docs/upstream-contributions.md" }
Test-PartialJunitRegression
Test-UntrackedProvenanceRegression
Test-ProvenancePathRegressions
Test-RootArrayRegression
Test-UnsupportedHumanInferenceRegression
Write-Host 'verify-publication tests passed.'
