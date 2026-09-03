$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $PSScriptRoot 'collect-evidence.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("halo-collector-test-" + [Guid]::NewGuid())
$fakeDocker = Join-Path $testRoot 'docker.cmd'
$fakeDockerScript = Join-Path $testRoot 'fake-docker.ps1'
$originalDockerCli = $env:DOCKER_CLI
$originalPath = $env:PATH
$originalFakeDockerFailure = $env:HALO_QE_FAKE_DOCKER_FAIL

function Assert-Contains {
    param([string]$Text, [string]$Expected)
    if (-not $Text.Contains($Expected)) {
        throw "Expected evidence to contain '$Expected'."
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected)
    if ($Text.Contains($Unexpected)) {
        throw "Evidence leaked '$Unexpected'."
    }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) {
        throw "Evidence matched forbidden pattern '$Pattern'."
    }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) {
        throw "Expected evidence to match '$Pattern'."
    }
}

function Invoke-CollectorHarness {
    param([string]$ArtifactRoot)

    $probeInput = @'
probe-auth-before Authorization: Basic probe~basic probe-auth-after
probe-bearer-before Bearer probe~bearer probe-bearer-after
probe-cookie-before
Cookie: probe-cookie-value
probe-cookie-after
probe-set-cookie-before
Set-Cookie: probe-set-cookie-value
probe-set-cookie-after
probe-boundary-set-cookie-before
Set-Cookie: sid=probe-boundary-first; Note=left || probe-boundary-right; Ext="<>[]{}:=|,/+*?!"
probe-boundary-set-cookie-after
probe-multi-cookie-before
Cookie: session=probe-cookie-first; csrf=probe-cookie-second, preference=probe-cookie-third
probe-multi-cookie-after
probe-multi-set-cookie-before
Set-Cookie: session=probe-set-first; Path=/; HttpOnly, csrf=probe-set-second; SameSite=None, quoted="probe-set-third"
probe-multi-set-cookie-after
probe-fixed-before HaloQE!2026 probe-fixed-after
probe-local-before halo-qe-local probe-local-after
{"before":"probe-password-before","password":"probe-password-value","after":"probe-password-after"}
{"before":"probe-token-before","token":"probe-token-value","after":"probe-token-after"}
{"before":"probe-storage-before","storageState":"probe-storage-value","after":"probe-storage-after"}
'@
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector `
            -ArtifactRoot $ArtifactRoot -HealthUri 'http://127.0.0.1:1/health' `
            -ProbeInput $probeInput 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    return [pscustomobject]@{ exitCode = $exitCode; output = $output -join "`n" }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Set-Content -LiteralPath $fakeDockerScript -Encoding utf8 -Value @'
if ($env:HALO_QE_FAKE_DOCKER_FAIL -eq '1') {
    $command = $args -join ' '
    if ($command -match ' ps --format json$') {
        Write-Output 'ps-failure-before Authorization: Bearer ps~secret ps-failure-after'
        exit 41
    }
    if ($command -match ' logs --no-color halo$') {
        Write-Output 'halo-failure-before'
        Write-Output 'Cookie: halo~secret'
        Write-Output 'halo-failure-after'
        exit 42
    }
    if ($command -match ' logs --no-color postgres$') {
        Write-Output '{"before":"postgres-failure-before","password":"postgres~secret","after":"postgres-failure-after"}'
        exit 43
    }
    throw "Unexpected fake Docker command: $command"
}
Write-Output 'auth-before Authorization: Bearer abc~secret auth-after'
Write-Output 'basic-before Basic standalone~credential basic-after'
Write-Output 'bearer-before Bearer standalone~token bearer-after'
Write-Output 'cookie-before'
Write-Output 'Cookie: cookie-secret'
Write-Output 'cookie-after'
Write-Output 'set-cookie-before'
Write-Output 'Set-Cookie: set-cookie-secret'
Write-Output 'set-cookie-after'
Write-Output 'boundary-set-cookie-before'
Write-Output 'Set-Cookie: sid=first-secret; Note=left || right-secret; Ext="<>[]{}:=|,/+*?!"'
Write-Output 'boundary-set-cookie-after'
Write-Output 'multi-cookie-before'
Write-Output 'Cookie: session=multi-cookie-first; csrf=multi-cookie-second, preference=multi-cookie-third'
Write-Output 'multi-cookie-after'
Write-Output 'multi-set-cookie-before'
Write-Output 'Set-Cookie: session=multi-set-first; Path=/; HttpOnly, csrf=multi-set-second; SameSite=None, quoted="multi-set-third"'
Write-Output 'multi-set-cookie-after'
Write-Output '{"before":"json-password-before","password":"json-password-value","after":"json-password-after"}'
Write-Output '{"before":"json-token-before","token":"json-token-value","after":"json-token-after"}'
Write-Output '{"before":"json-storage-before","storageState":"json-storage-value","after":"json-storage-after"}'
Write-Output 'fixed-before HaloQE!2026 fixed-after'
Write-Output 'local-before halo-qe-local local-after'
Write-Output 'diagnostic: 你好'
'@
    Set-Content -LiteralPath $fakeDocker -Encoding ascii -Value @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-docker.ps1" %*
'@

    $env:DOCKER_CLI = $fakeDocker
    $environmentArtifacts = Join-Path $testRoot 'from-env'
    $environmentResult = Invoke-CollectorHarness $environmentArtifacts
    if ($environmentResult.exitCode -ne 0) { throw "Collector harness failed with exit $($environmentResult.exitCode)." }

    Remove-Item Env:DOCKER_CLI
    $env:PATH = "$testRoot;$originalPath"
    $pathArtifacts = Join-Path $testRoot 'from-path'
    $pathResult = Invoke-CollectorHarness $pathArtifacts
    if ($pathResult.exitCode -ne 0) { throw "PATH collector harness failed with exit $($pathResult.exitCode)." }

    $evidence = Get-ChildItem -LiteralPath $environmentArtifacts -File | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
    }
    $allEvidence = $evidence -join "`n"
    foreach ($secret in @(
            'abc~secret', 'basic~credential', 'standalone~credential', 'standalone~token',
            'cookie-secret', 'set-cookie-secret', 'multi-cookie-first', 'multi-cookie-second', 'multi-cookie-third',
            'first-secret', 'right-secret', 'multi-set-first', 'multi-set-second', 'multi-set-third',
            'json-password-value', 'json-storage-value', 'json-token-value',
            'probe~basic', 'probe~bearer', 'probe-cookie-value', 'probe-set-cookie-value', 'probe-password-value',
            'probe-storage-value', 'probe-token-value', 'probe-cookie-first', 'probe-cookie-second', 'probe-cookie-third',
            'probe-boundary-first', 'probe-boundary-right', 'probe-set-first', 'probe-set-second', 'probe-set-third',
            'HaloQE!2026', 'halo-qe-local')) {
        Assert-NotContains $allEvidence $secret
    }
    foreach ($pattern in @(
            '(?im)\bAuthorization\s*:\s*(?:Basic|Bearer)\s+\S+',
            '(?im)\b(?:Basic|Bearer)\s+(?!\[REDACTED\])\S+',
            '(?im)\bCookie\s*:\s*(?!"\[REDACTED\]")\S+',
            '(?im)\bSet-Cookie\s*:\s*(?!"\[REDACTED\]")\S+')) {
        Assert-NotMatch $allEvidence $pattern
    }
    Assert-Contains $allEvidence '[REDACTED]'
    foreach ($recordPattern in @(
            '(?m)^cookie-before\r?\nCookie: "\[REDACTED\]"\r?\ncookie-after\r?$',
            '(?m)^set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nset-cookie-after\r?$',
            '(?m)^boundary-set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nboundary-set-cookie-after\r?$',
            '(?m)^multi-cookie-before\r?\nCookie: "\[REDACTED\]"\r?\nmulti-cookie-after\r?$',
            '(?m)^multi-set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nmulti-set-cookie-after\r?$',
            '(?m)^probe-cookie-before\r?\nCookie: "\[REDACTED\]"\r?\nprobe-cookie-after\r?$',
            '(?m)^probe-set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nprobe-set-cookie-after\r?$',
            '(?m)^probe-boundary-set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nprobe-boundary-set-cookie-after\r?$',
            '(?m)^probe-multi-cookie-before\r?\nCookie: "\[REDACTED\]"\r?\nprobe-multi-cookie-after\r?$',
            '(?m)^probe-multi-set-cookie-before\r?\nSet-Cookie: "\[REDACTED\]"\r?\nprobe-multi-set-cookie-after\r?$')) {
        Assert-Match $allEvidence $recordPattern
    }
    foreach ($sentinel in @(
            'auth-before', 'auth-after', 'basic-before', 'basic-after', 'bearer-before', 'bearer-after',
            'cookie-before', 'cookie-after', 'set-cookie-before', 'set-cookie-after',
            'multi-cookie-before', 'multi-cookie-after', 'multi-set-cookie-before', 'multi-set-cookie-after',
            'json-password-before', 'json-password-after', 'json-token-before', 'json-token-after',
            'json-storage-before', 'json-storage-after',
            'fixed-before', 'fixed-after', 'local-before', 'local-after', 'probe-auth-before', 'probe-auth-after',
            'probe-bearer-before', 'probe-bearer-after', 'probe-cookie-before', 'probe-cookie-after',
            'probe-set-cookie-before', 'probe-set-cookie-after', 'probe-fixed-before', 'probe-fixed-after',
            'probe-boundary-set-cookie-before', 'probe-boundary-set-cookie-after',
            'probe-multi-cookie-before', 'probe-multi-cookie-after',
            'probe-multi-set-cookie-before', 'probe-multi-set-cookie-after',
            'probe-local-before', 'probe-local-after', 'probe-password-before', 'probe-password-after',
            'probe-token-before', 'probe-token-after', 'probe-storage-before', 'probe-storage-after')) {
        Assert-Contains $allEvidence $sentinel
    }
    Assert-Contains $allEvidence 'diagnostic: 你好'
    if (-not (Test-Path -LiteralPath (Join-Path $pathArtifacts 'docker-ps.txt'))) {
        throw 'PATH Docker fallback did not produce evidence.'
    }

    $env:DOCKER_CLI = $fakeDocker
    $env:HALO_QE_FAKE_DOCKER_FAIL = '1'
    $failureArtifacts = Join-Path $testRoot 'from-failures'
    $failureResult = Invoke-CollectorHarness $failureArtifacts
    if ($failureResult.exitCode -eq 0) { throw 'Failed fake Compose diagnostics unexpectedly exited zero.' }
    Assert-Contains $failureResult.output 'TEST_TOOL'
    foreach ($exitCode in @(41, 42, 43)) { Assert-Contains $failureResult.output "exit $exitCode" }

    $failureFiles = @('docker-ps.txt', 'halo.log', 'postgres.log', 'health.json', 'COLLECTION_FAILED.txt')
    foreach ($name in $failureFiles) {
        $path = Join-Path $failureArtifacts $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "Failed evidence collection did not retain nonempty $name."
        }
    }
    $dockerFailure = Get-Content -Raw -LiteralPath (Join-Path $failureArtifacts 'docker-ps.txt') -Encoding utf8
    $haloFailure = Get-Content -Raw -LiteralPath (Join-Path $failureArtifacts 'halo.log') -Encoding utf8
    $postgresFailure = Get-Content -Raw -LiteralPath (Join-Path $failureArtifacts 'postgres.log') -Encoding utf8
    $marker = Get-Content -Raw -LiteralPath (Join-Path $failureArtifacts 'COLLECTION_FAILED.txt') -Encoding utf8
    foreach ($expectation in @(
            @($dockerFailure, 'ps-failure-before'), @($dockerFailure, 'ps-failure-after'),
            @($dockerFailure, 'Docker Compose command failed (exit 41): ps --format json'),
            @($haloFailure, 'halo-failure-before'), @($haloFailure, 'halo-failure-after'),
            @($haloFailure, 'Docker Compose command failed (exit 42): logs --no-color halo'),
            @($postgresFailure, 'postgres-failure-before'), @($postgresFailure, 'postgres-failure-after'),
            @($postgresFailure, 'Docker Compose command failed (exit 43): logs --no-color postgres'))) {
        Assert-Contains $expectation[0] $expectation[1]
    }
    Assert-Contains $marker 'failureKind=TEST_TOOL'
    Assert-Contains $marker 'failureCount=3'
    Assert-Contains $marker 'docker-ps.txt|exit=41|command=ps --format json'
    Assert-Contains $marker 'halo.log|exit=42|command=logs --no-color halo'
    Assert-Contains $marker 'postgres.log|exit=43|command=logs --no-color postgres'
    $allFailureEvidence = "$dockerFailure`n$haloFailure`n$postgresFailure`n$marker`n$($failureResult.output)"
    foreach ($secret in @('ps~secret', 'halo~secret', 'postgres~secret')) {
        Assert-NotContains $allFailureEvidence $secret
    }

    Remove-Item Env:HALO_QE_FAKE_DOCKER_FAIL
    $recoveryResult = Invoke-CollectorHarness $failureArtifacts
    if ($recoveryResult.exitCode -ne 0) { throw "Successful collector reuse failed with exit $($recoveryResult.exitCode)." }
    if (Test-Path -LiteralPath (Join-Path $failureArtifacts 'COLLECTION_FAILED.txt')) {
        throw 'Successful collector reuse retained a stale failure marker.'
    }
    Write-Output 'collect-evidence hermetic tests passed'
} finally {
    if ($null -eq $originalDockerCli) { Remove-Item Env:DOCKER_CLI -ErrorAction SilentlyContinue } else { $env:DOCKER_CLI = $originalDockerCli }
    if ($null -eq $originalFakeDockerFailure) { Remove-Item Env:HALO_QE_FAKE_DOCKER_FAIL -ErrorAction SilentlyContinue } else { $env:HALO_QE_FAKE_DOCKER_FAIL = $originalFakeDockerFailure }
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
