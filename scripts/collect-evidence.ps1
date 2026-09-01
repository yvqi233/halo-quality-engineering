[CmdletBinding()]
param(
    [string]$ArtifactRoot,
    [string]$HealthUri = 'http://127.0.0.1:8090/system/setup',
    [string]$ProbeInput
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$ArtifactRoot = if ($ArtifactRoot) { $ArtifactRoot } else { Join-Path $repoRoot 'artifacts/environment' }
$composeFile = Join-Path $repoRoot 'environment/docker-compose.yml'
$lockFile = Join-Path $repoRoot 'environment/image-lock.env'
$sensitiveKeys = @('password', 'authorization', 'cookie', 'set-cookie', 'token', 'storagestate')
$localSecrets = @('HaloQE!2026', 'halo-qe-local')

function Resolve-DockerCli {
    if ($env:DOCKER_CLI) {
        return $env:DOCKER_CLI
    }
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $docker) {
        throw 'Docker CLI is unavailable. Set DOCKER_CLI or add docker to PATH.'
    }
    return $docker.Source
}

$DOCKER_CLI = Resolve-DockerCli

function Protect-Text {
    param([AllowNull()][object]$Value)

    $text = [string]$Value
    foreach ($secret in $localSecrets) {
        $text = $text -replace [regex]::Escape($secret), '[REDACTED]'
    }
    $text = [regex]::Replace($text, '(?im)(\bAuthorization\s*:\s*)(?:Basic|Bearer)\s+\S+', '$1"[REDACTED]"')
    $text = [regex]::Replace($text, '(?i)\b(Basic|Bearer)\s+\S+', '$1 [REDACTED]')
    $text = [regex]::Replace($text, '(?im)(\b(?:Set-Cookie|Cookie)\s*:\s*)[^\s;,\r\n]+', '$1"[REDACTED]"')
    $text = [regex]::Replace(
        $text,
        '(?i)(["'']?(?:password|authorization|cookie|set-cookie|token|storagestate)["'']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|[^,\s}\]]+)',
        '$1"[REDACTED]"')
    return $text
}

function Protect-Value {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        try {
            return Protect-Value (ConvertFrom-Json -InputObject $Value -ErrorAction Stop)
        } catch {
            return Protect-Text $Value
        }
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ($sensitiveKeys -contains ([string]$key).ToLowerInvariant()) {
                $copy[$key] = '[REDACTED]'
            } else {
                $copy[$key] = Protect-Value $Value[$key]
            }
        }
        return $copy
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Protect-Value $_ })
    }
    if ($Value -is [pscustomobject]) {
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($sensitiveKeys -contains $property.Name.ToLowerInvariant()) {
                $copy[$property.Name] = '[REDACTED]'
            } else {
                $copy[$property.Name] = Protect-Value $property.Value
            }
        }
        return $copy
    }
    return $Value
}

function Protect-DiagnosticText {
    param([AllowNull()][string]$Text)

    $lines = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not $line) {
            $lines += ''
            continue
        }
        try {
            $lines += ((Protect-Value (ConvertFrom-Json -InputObject $line -ErrorAction Stop)) | ConvertTo-Json -Depth 32 -Compress)
        } catch {
            $lines += Protect-Text $line
        }
    }
    return $lines -join [Environment]::NewLine
}

function Write-RedactedText {
    param([string]$Path, [AllowNull()][string]$Text)

    Set-Content -LiteralPath $Path -Value (Protect-DiagnosticText $Text) -Encoding utf8
}

function Invoke-ComposeDiagnostic {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $previousConsoleEncoding = [Console]::OutputEncoding
    $previousOutputEncoding = $OutputEncoding
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::OutputEncoding = $utf8
        $OutputEncoding = $utf8
        $output = & $DOCKER_CLI compose --project-name halo-qe --env-file $lockFile --file $composeFile @Arguments 2>&1 | Out-String
    } finally {
        [Console]::OutputEncoding = $previousConsoleEncoding
        $OutputEncoding = $previousOutputEncoding
    }
    if ($LASTEXITCODE -ne 0) {
        return "Docker Compose command failed (exit $LASTEXITCODE): $($Arguments -join ' ')`n$output"
    }
    return $output
}

function Get-HealthDiagnostic {
    $record = [ordered]@{ uri = $HealthUri }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -Uri $HealthUri
        $record.statusCode = [int]$response.StatusCode
        $record.headers = $response.Headers
        $record.body = $response.Content
    } catch {
        if ($_.Exception.Response) {
            $response = $_.Exception.Response
            $record.statusCode = [int]$response.StatusCode
            $record.headers = $response.Headers
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try { $record.body = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } else {
            $record.error = $_.Exception.Message
        }
    }
    return (Protect-Value $record) | ConvertTo-Json -Depth 32
}

if (-not (Test-Path -LiteralPath $composeFile) -or -not (Test-Path -LiteralPath $lockFile)) {
    throw 'The pinned environment files are missing.'
}

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Write-RedactedText (Join-Path $ArtifactRoot 'docker-ps.txt') (Invoke-ComposeDiagnostic ps --format json)
Write-RedactedText (Join-Path $ArtifactRoot 'halo.log') (Invoke-ComposeDiagnostic logs --no-color halo)
Write-RedactedText (Join-Path $ArtifactRoot 'postgres.log') (Invoke-ComposeDiagnostic logs --no-color postgres)
Set-Content -LiteralPath (Join-Path $ArtifactRoot 'health.json') -Value (Get-HealthDiagnostic) -Encoding utf8
if ($PSBoundParameters.ContainsKey('ProbeInput')) {
    Write-RedactedText (Join-Path $ArtifactRoot 'probe.txt') $ProbeInput
}

Write-Output "Redacted environment evidence written to $ArtifactRoot"
