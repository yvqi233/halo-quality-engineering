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
probe-cookie-before Cookie: probe-cookie-value probe-cookie-after
probe-set-cookie-before Set-Cookie: probe-set-cookie-value probe-set-cookie-after
probe-fixed-before HaloQE!2026 probe-fixed-after
probe-local-before halo-qe-local probe-local-after
{"diagnostic":"probe-json-sentinel","password":"probe-password","storageState":"probe-state","token":"probe-token"}
'@
    if ($LASTEXITCODE -ne 0) { throw "Collector harness failed with exit $LASTEXITCODE." }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Set-Content -LiteralPath $fakeDockerScript -Encoding utf8 -Value @'
Write-Output 'auth-before Authorization: Bearer abc~secret auth-after'
Write-Output 'basic-before Basic standalone~credential basic-after'
Write-Output 'bearer-before Bearer standalone~token bearer-after'
Write-Output 'cookie-before Cookie: cookie-secret cookie-after'
Write-Output 'set-cookie-before Set-Cookie: set-cookie-secret set-cookie-after'
Write-Output '{"diagnostic":"json-sentinel","password":"json-password","storageState":"json-state","token":"json-token"}'
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
            'cookie-secret', 'set-cookie-secret', 'json-password', 'json-state', 'json-token',
            'probe~basic', 'probe~bearer', 'probe-cookie-value', 'probe-set-cookie-value', 'probe-password',
            'probe-state', 'probe-token', 'HaloQE!2026', 'halo-qe-local')) {
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
            'cookie-before', 'cookie-after', 'set-cookie-before', 'set-cookie-after', 'json-sentinel',
            'fixed-before', 'fixed-after', 'local-before', 'local-after', 'probe-auth-before', 'probe-auth-after',
            'probe-bearer-before', 'probe-bearer-after', 'probe-cookie-before', 'probe-cookie-after',
            'probe-set-cookie-before', 'probe-set-cookie-after', 'probe-fixed-before', 'probe-fixed-after',
            'probe-local-before', 'probe-local-after', 'probe-json-sentinel')) {
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
