$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $PSScriptRoot 'collect-evidence.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("halo-collector-test-" + [Guid]::NewGuid())
$fakeDocker = Join-Path $testRoot 'docker.cmd'
$fakeDockerScript = Join-Path $testRoot 'fake-docker.ps1'
$originalDockerCli = $env:DOCKER_CLI
$originalPath = $env:PATH

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

function Invoke-CollectorHarness {
    param([string]$ArtifactRoot)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector `
        -ArtifactRoot $ArtifactRoot -HealthUri 'http://127.0.0.1:1/health' `
        -ProbeInput @'
probe-auth-before Authorization: Basic probe~basic probe-auth-after
probe-bearer-before Bearer probe~bearer probe-bearer-after
probe-cookie-before Cookie: probe-cookie-value || probe-cookie-after
probe-set-cookie-before Set-Cookie: probe-set-cookie-value || probe-set-cookie-after
probe-multi-cookie-before Cookie: session=probe-cookie-first; csrf=probe-cookie-second, preference=probe-cookie-third || probe-multi-cookie-after
probe-multi-set-cookie-before Set-Cookie: session=probe-set-first; Path=/; HttpOnly, csrf=probe-set-second; SameSite=None, quoted="probe-set-third" || probe-multi-set-cookie-after
probe-fixed-before HaloQE!2026 probe-fixed-after
probe-local-before halo-qe-local probe-local-after
{"before":"probe-password-before","password":"probe-password-value","after":"probe-password-after"}
{"before":"probe-token-before","token":"probe-token-value","after":"probe-token-after"}
{"before":"probe-storage-before","storageState":"probe-storage-value","after":"probe-storage-after"}
'@
    if ($LASTEXITCODE -ne 0) { throw "Collector harness failed with exit $LASTEXITCODE." }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Set-Content -LiteralPath $fakeDockerScript -Encoding utf8 -Value @'
Write-Output 'auth-before Authorization: Bearer abc~secret auth-after'
Write-Output 'basic-before Basic standalone~credential basic-after'
Write-Output 'bearer-before Bearer standalone~token bearer-after'
Write-Output 'cookie-before Cookie: cookie-secret || cookie-after'
Write-Output 'set-cookie-before Set-Cookie: set-cookie-secret || set-cookie-after'
Write-Output 'multi-cookie-before Cookie: session=multi-cookie-first; csrf=multi-cookie-second, preference=multi-cookie-third || multi-cookie-after'
Write-Output 'multi-set-cookie-before Set-Cookie: session=multi-set-first; Path=/; HttpOnly, csrf=multi-set-second; SameSite=None, quoted="multi-set-third" || multi-set-cookie-after'
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
    Invoke-CollectorHarness $environmentArtifacts

    Remove-Item Env:DOCKER_CLI
    $env:PATH = "$testRoot;$originalPath"
    $pathArtifacts = Join-Path $testRoot 'from-path'
    Invoke-CollectorHarness $pathArtifacts

    $evidence = Get-ChildItem -LiteralPath $environmentArtifacts -File | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
    }
    $allEvidence = $evidence -join "`n"
    foreach ($secret in @(
            'abc~secret', 'basic~credential', 'standalone~credential', 'standalone~token',
            'cookie-secret', 'set-cookie-secret', 'multi-cookie-first', 'multi-cookie-second', 'multi-cookie-third',
            'multi-set-first', 'multi-set-second', 'multi-set-third', 'json-password-value', 'json-storage-value', 'json-token-value',
            'probe~basic', 'probe~bearer', 'probe-cookie-value', 'probe-set-cookie-value', 'probe-password-value',
            'probe-storage-value', 'probe-token-value', 'probe-cookie-first', 'probe-cookie-second', 'probe-cookie-third',
            'probe-set-first', 'probe-set-second', 'probe-set-third', 'HaloQE!2026', 'halo-qe-local')) {
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
    foreach ($sentinel in @(
            'auth-before', 'auth-after', 'basic-before', 'basic-after', 'bearer-before', 'bearer-after',
            'cookie-before', 'cookie-after', 'set-cookie-before', 'set-cookie-after',
            'multi-cookie-before', 'multi-cookie-after', 'multi-set-cookie-before', 'multi-set-cookie-after',
            'json-password-before', 'json-password-after', 'json-token-before', 'json-token-after',
            'json-storage-before', 'json-storage-after',
            'fixed-before', 'fixed-after', 'local-before', 'local-after', 'probe-auth-before', 'probe-auth-after',
            'probe-bearer-before', 'probe-bearer-after', 'probe-cookie-before', 'probe-cookie-after',
            'probe-set-cookie-before', 'probe-set-cookie-after', 'probe-fixed-before', 'probe-fixed-after',
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
    Write-Output 'collect-evidence hermetic tests passed'
} finally {
    if ($null -eq $originalDockerCli) { Remove-Item Env:DOCKER_CLI -ErrorAction SilentlyContinue } else { $env:DOCKER_CLI = $originalDockerCli }
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
