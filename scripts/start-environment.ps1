[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$environmentScript = Join-Path $PSScriptRoot 'environment.ps1'

& $environmentScript -Action Up
if (-not $?) { throw 'Environment startup failed during Up.' }

& $environmentScript -Action Initialize
if (-not $?) { throw 'Environment startup failed during Initialize.' }
