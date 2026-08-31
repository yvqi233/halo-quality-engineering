param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Up', 'Down', 'Logs', 'Initialize')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot 'environment/docker-compose.yml'
$lockFile = Join-Path $repoRoot 'environment/image-lock.env'
$dockerCli = if ($env:DOCKER_CLI) {
    $env:DOCKER_CLI
} else {
    (Get-Command docker -ErrorAction Stop).Source
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    if (-not (Test-Path -LiteralPath $lockFile)) {
        throw 'Missing environment/image-lock.env. Run scripts/pin-images.ps1 first.'
    }

    & $dockerCli compose --project-name halo-qe --env-file $lockFile --file $composeFile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose action failed: $($Arguments -join ' ')" }
}

function Get-SetupStatusCode {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 `
            -Headers @{ Accept = 'text/html' } -Uri 'http://127.0.0.1:8090/system/setup'
        return [int]$response.StatusCode
    } catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        throw
    }
}

function Wait-ForSetupEndpoint {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(180)
    $lastError = $null
    do {
        try {
            $statusCode = Get-SetupStatusCode
            if ($statusCode -in 200, 302) {
                Write-Output "Halo setup endpoint is ready (HTTP $statusCode)."
                return
            }
            $lastError = "HTTP $statusCode"
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 2
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    throw "Halo setup endpoint did not become ready within 180 seconds. Last result: $lastError"
}

function Initialize-Halo {
    $fields = [ordered]@{
        username = 'qe-admin'
        password = 'HaloQE!2026'
        email = 'qe-admin@example.test'
        siteTitle = 'Halo QE'
        language = 'en'
        externalUrl = 'http://127.0.0.1:8090/'
    }
    $body = ($fields.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f [Uri]::EscapeDataString($_.Key), [Uri]::EscapeDataString($_.Value)
    }) -join '&'

    try {
        $response = Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -Method Post `
            -ContentType 'application/x-www-form-urlencoded' -Body $body `
            -Uri 'http://127.0.0.1:8090/system/setup'
        $statusCode = [int]$response.StatusCode
    } catch {
        if (-not $_.Exception.Response) { throw }
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -notin 204, 302) {
        throw "Halo initialization failed with HTTP $statusCode."
    }
    Write-Output "Halo initialization completed (HTTP $statusCode)."
}

switch ($Action) {
    'Up' {
        Invoke-Compose up --detach
        Wait-ForSetupEndpoint
    }
    'Down' {
        Invoke-Compose down --volumes --remove-orphans
    }
    'Logs' {
        Invoke-Compose logs --no-color
    }
    'Initialize' {
        Initialize-Halo
    }
}
