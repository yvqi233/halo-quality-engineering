[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$wrapper = Join-Path $PSScriptRoot 'start-environment.ps1'

function Assert-True {
    param([bool]$Value, [string]$Message)

    if (-not $Value) { throw $Message }
}

function Write-Text {
    param([string]$Path, [string]$Text)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

Assert-True (Test-Path -LiteralPath $wrapper -PathType Leaf) 'start-environment.ps1 is missing.'

$root = Join-Path ([IO.Path]::GetTempPath()) "start-environment-$([Guid]::NewGuid().ToString('N'))"
$scripts = Join-Path $root 'scripts'
$actionLog = Join-Path $root 'actions.txt'
$savedActionLog = $env:HALO_QE_ACTION_LOG
$savedFailUp = $env:HALO_QE_FAIL_UP
try {
    New-Item -ItemType Directory -Path $scripts | Out-Null
    Copy-Item -LiteralPath $wrapper -Destination (Join-Path $scripts 'start-environment.ps1')
    $fakeEnvironment = @'
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Up', 'Down', 'Logs', 'Initialize')]
    [string]$Action
)
Add-Content -LiteralPath $env:HALO_QE_ACTION_LOG -Value $Action
if ($Action -eq 'Up' -and $env:HALO_QE_FAIL_UP -eq '1') { throw 'simulated Up failure' }
'@
    Write-Text (Join-Path $scripts 'environment.ps1') $fakeEnvironment
    $env:HALO_QE_ACTION_LOG = $actionLog
    $env:HALO_QE_FAIL_UP = '0'

    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'start-environment.ps1') 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "standalone startup failed: $($output -join ' | ')"
    Assert-True (((Get-Content -LiteralPath $actionLog) -join '|') -eq 'Up|Initialize') 'standalone startup did not invoke exactly Up then Initialize.'

    Remove-Item -LiteralPath $actionLog
    $env:HALO_QE_FAIL_UP = '1'
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'start-environment.ps1') 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-True ($exitCode -ne 0) 'standalone startup unexpectedly succeeded after Up failed.'
    Assert-True (((Get-Content -LiteralPath $actionLog) -join '|') -eq 'Up') 'Initialize ran after Up failed.'
} finally {
    $env:HALO_QE_ACTION_LOG = $savedActionLog
    $env:HALO_QE_FAIL_UP = $savedFailUp
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'start-environment tests passed.'
