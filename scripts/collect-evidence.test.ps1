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

function Invoke-CollectorHarness {
    param([string]$ArtifactRoot)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector `
        -ArtifactRoot $ArtifactRoot -HealthUri 'http://127.0.0.1:1/health' `
        -ProbeInput 'Authorization: Basic basic~credential Cookie: probe-cookie Set-Cookie: probe-set-cookie Bearer probe~token HaloQE!2026 {"password":"probe-password","storageState":"probe-state"}'
    if ($LASTEXITCODE -ne 0) { throw "Collector harness failed with exit $LASTEXITCODE." }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Set-Content -LiteralPath $fakeDockerScript -Encoding utf8 -Value @'
Write-Output 'Authorization: Bearer abc~secret'
Write-Output 'Basic standalone~credential'
Write-Output 'Bearer standalone~token'
Write-Output 'Cookie: session=cookie-secret'
Write-Output 'Set-Cookie: session=set-cookie-secret'
Write-Output '{"password":"json-password","storageState":"json-state","token":"json-token"}'
Write-Output 'HaloQE!2026'
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
            'probe-cookie', 'probe-set-cookie', 'probe~token', 'probe-password', 'probe-state', 'HaloQE!2026')) {
        Assert-NotContains $allEvidence $secret
    }
    Assert-Contains $allEvidence '[REDACTED]'
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
