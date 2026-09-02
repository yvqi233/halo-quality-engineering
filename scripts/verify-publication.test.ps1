[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$verifier = Join-Path $PSScriptRoot 'verify-publication.ps1'

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
    Write-Text "$root/artifacts/stability/runs.jsonl" "{`"sequence`":1,`"commit`":`"$sha`",`"haloImage`":`"$digest`",`"result`":`"PASS`",`"durationSeconds`":1,`"failureKind`":`"NONE`"}`n"
    Write-Text "$root/evidence/raw/quality-gate/summary.jsonl" "{`"layer`":`"L0`",`"result`":`"PASS`",`"durationSeconds`":1}`n{`"layer`":`"L1`",`"result`":`"PASS`",`"durationSeconds`":1}`n{`"layer`":`"L2`",`"result`":`"PASS`",`"durationSeconds`":1}`n"
    Write-Text "$root/evidence/raw/quality-gate/L0-counts.json" '{}'; Write-Text "$root/evidence/raw/quality-gate/L1-counts.json" '{}'; Write-Text "$root/evidence/raw/quality-gate/L2-counts.json" '{"totalJourneys":1}'
    Write-Text "$root/evidence/raw/quality-gate/L2-phases.json" '{}'
    Write-Text "$root/evidence/raw/firefox/ordinary.xml" '<testsuites tests="11" failures="0" />'; Write-Text "$root/evidence/raw/firefox/expiry.xml" '<testsuites tests="1" failures="0" />'
    $facts = "{`"target`":{`"haloVersion`":`"2.26.1`",`"sourceCommit`":`"88c2ef14355c79a4dbd1d5c3246b3ea32836e06b`",`"haloImage`":`"$digest`"},`"stability`":{`"testedCommit`":`"$sha`",`"consecutivePassNoneRuns`":1,`"minimumDurationSeconds`":1,`"maximumDurationSeconds`":1,`"averageDurationSeconds`":1},`"fullGate`":{`"layers`": [{`"layer`":`"L0`",`"result`":`"PASS`",`"durationSeconds`":1},{`"layer`":`"L1`",`"result`":`"PASS`",`"durationSeconds`":1},{`"layer`":`"L2`",`"result`":`"PASS`",`"durationSeconds`":1}],`"preflightMissingEvidence`":0,`"finalComposeRows`":0},`"firefox`":{`"ordinaryPassed`":11,`"ordinaryExpected`":11,`"isolatedExpiryPassed`":1,`"isolatedExpiryExpected`":1,`"userJourneys`":1,`"retries`":0}}"
    $prov = '{"stabilityRecord":"artifacts/stability/runs.jsonl","gateSummary":"evidence/raw/quality-gate/summary.jsonl","gateCounts":["evidence/raw/quality-gate/L0-counts.json","evidence/raw/quality-gate/L1-counts.json","evidence/raw/quality-gate/L2-counts.json"],"gatePhases":"evidence/raw/quality-gate/L2-phases.json","firefoxOrdinaryJunit":"evidence/raw/firefox/ordinary.xml","firefoxExpiryJunit":"evidence/raw/firefox/expiry.xml"}'
    Write-Text "$root/evidence/qualification-v1.json" "{`"schemaVersion`":1,`"facts`":$facts,`"provenance`":$prov}"
    $readme = @(
        '# Fixture', '', '## Measured Results', '',
        'The machine-checked claim below is compared exactly with the authoritative tracked [raw qualification artifact](evidence/qualification-v1.json). The structured record is the only location for qualification values in this section.', '',
        '<!-- qualification-claims-v1 -->', '```json',
        ('{"schemaVersion":1,"evidence":"evidence/qualification-v1.json","facts":' + $facts + '}'), '```'
    ) -join "`n"
    Write-Text "$root/README.md" $readme
    $detail = '{"schemaVersion":1,"purpose":"x","reproductionEvidence":"evidence/qualification-v1.json","expectedActual":"x","duplicateSearch":"x","prChangeHead":"x","validation":"x","aiDisclosure":"x","reviewFeedback":"x","modificationHistory":["x"]}'
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
    $root=New-Fixture; try { & $Mutate $root; & git -C $root add .; $result=Invoke-Verifier -Root $root -AdditionalVerifierArguments $AdditionalVerifierArguments; Assert-True ($result.exitCode -ne 0) "$Name unexpectedly passed"; Assert-True (($result.output -join "`n") -match [regex]::Escape($Expected)) "$Name missing diagnostic $Expected" } finally { Remove-Item $root -Recurse -Force }
}
Assert-True (Test-Path $verifier) 'verifier missing'
$root=New-Fixture; try { $result=Invoke-Verifier -Root $root; Assert-True ($result.exitCode -eq 0) 'valid fixture failed'; Write-Text "$root/api-tests/bin/leak.txt" ('ghp_'+'abcdefghijklmnopqrstuvwxyz0123456789'); $result=Invoke-Verifier -Root $root; Assert-True ($result.exitCode -eq 0) 'untracked bin contaminated verifier' } finally { Remove-Item $root -Recurse -Force }
Invoke-Case 'ipv4' 'disallowed IPv4' { param($r) Write-Text "$r/docs/x.md" ('10.' + '20.30.40') }
Invoke-Case 'host' 'private-host name' { param($r) Write-Text "$r/docs/x.md" ('halo.'+'internal') }
Invoke-Case 'auth state' 'Tracked storageState' { param($r) Write-Text "$r/e2e/.auth/admin.json" '{}' }
Invoke-Case 'claim' 'README qualification claims' { param($r) (Get-Content -Raw "$r/README.md").Replace('"averageDurationSeconds":1','"averageDurationSeconds":9') | Set-Content "$r/README.md" }
Invoke-Case 'prose' 'documented boilerplate' { param($r) Add-Content "$r/README.md" 'the suite completed successfully after twelve runs' }
Invoke-Case 'local link' 'README qualification evidence' { param($r) (Get-Content -Raw "$r/README.md").Replace('evidence/qualification-v1.json","facts','evidence/missing.json","facts') | Set-Content "$r/README.md" }
Invoke-Case 'lifecycle' 'lifecycleStatus must be SUBMITTED' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace('"lifecycleStatus":"SUBMITTED"','"lifecycleStatus":"MERGED"') | Set-Content "$r/docs/upstream-contributions.md" }
$tcp = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $tcp.Start(); $port = ([Net.IPEndPoint]$tcp.LocalEndpoint).Port; $tcp.Stop()
$urlJob = Start-Job -ArgumentList $port -ScriptBlock { param($listenerPort) $listener=[Net.HttpListener]::new(); $listener.Prefixes.Add("http://127.0.0.1:$listenerPort/"); $listener.Start(); try { for ($index=0; $index -lt 3; $index++) { $context=$listener.GetContext(); $context.Response.StatusCode=404; $context.Response.Close() } } finally { $listener.Stop(); $listener.Close() } }
try {
    Start-Sleep -Milliseconds 200
    Invoke-Case 'public URL' 'Public URL check failed' { param($r) Add-Content "$r/docs/upstream-contributions.md" 'https://public.example.test/not-found' } @('-CheckPublicUrls', '-PublicUrlCheckBaseUri', "http://127.0.0.1:$port/")
} finally { Stop-Job $urlJob -ErrorAction SilentlyContinue; Remove-Job $urlJob -Force -ErrorAction SilentlyContinue }
Invoke-Case 'nested password' 'e2e/reports/x.txt contains' { param($r) Write-Text "$r/e2e/reports/x.txt" ('HaloQE!'+'2026') }
Invoke-Case 'token' 'docs/x.txt contains a credential' { param($r) Write-Text "$r/docs/x.txt" ('ghp_'+'abcdefghijklmnopqrstuvwxyz0123456789') }
Invoke-Case 'basic' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Authorization'+': Basic abc') }
Invoke-Case 'cookie' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Cookie'+': a=b') }
Invoke-Case 'set cookie' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" ('Set-Cookie'+': a=b') }
Invoke-Case 'quoted password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password: "secret"' }
Invoke-Case 'unquoted colon password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password: secret' }
Invoke-Case 'unquoted equals password' 'docs/x.txt contains an unredacted' { param($r) Write-Text "$r/docs/x.txt" 'password=secret' }
Invoke-Case 'detail' 'Upstream contribution detail is miss' { param($r) (Get-Content -Raw "$r/docs/upstream-contributions.md").Replace(',"reviewFeedback":"x"','') | Set-Content "$r/docs/upstream-contributions.md" }
Write-Host 'verify-publication tests passed.'
