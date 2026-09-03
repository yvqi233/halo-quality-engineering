$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "halo-gate-process-$([Guid]::NewGuid().ToString('N'))"
$testScripts = Join-Path $testRoot 'scripts'
$currentPowerShell = (Get-Process -Id $PID).Path

function Assert-Contains {
    param([string]$Text, [string]$Expected)

    if (-not $Text.Contains($Expected)) { throw "Expected process output to contain '$Expected'." }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected)

    if ($Text.Contains($Unexpected)) { throw "Process output unexpectedly contained '$Unexpected':`n$Text" }
}

try {
    New-Item -ItemType Directory -Force -Path $testScripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'quality-gate.ps1') -Destination $testScripts
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'junit-results.ps1') -Destination $testScripts
    Set-Content -LiteralPath (Join-Path $testScripts 'environment.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$Action)
'@
    Set-Content -LiteralPath (Join-Path $testScripts 'collect-evidence.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$ArtifactRoot)
'@
    Set-Content -LiteralPath (Join-Path $testRoot 'gradlew.bat') -Encoding ascii -Value @'
@echo off
echo fake-gradle-sentinel
exit /b 41
'@
    $wrapperPath = Join-Path $testRoot 'invoke-gate.ps1'
    Set-Content -LiteralPath $wrapperPath -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$RunnerPath)
try {
    & $RunnerPath -Layer L0 -QuarantineMode MainChain
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine($_.InvocationInfo.PositionMessage)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 99
}
'@

    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $currentPowerShell -NoLogo -NoProfile -File $wrapperPath `
            -RunnerPath (Join-Path $testScripts 'quality-gate.ps1') 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    $processOutput = $output -join "`n"
    if ($exitCode -ne 1) { throw "Expected the fake Gradle failure to exit 1, observed $exitCode.`n$processOutput" }
    Assert-Contains $processOutput 'fake-gradle-sentinel'
    Assert-Contains $processOutput 'failed with exit code 41'
    Assert-NotContains $processOutput "The term 'Set-GateFailureKind' is not recognized"
    Assert-NotContains $processOutput 'Argument types do not match'
    Write-Output 'quality-gate process compatibility test passed'
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
