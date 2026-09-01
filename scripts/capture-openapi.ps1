param(
    [switch]$AcceptReviewedBaseline
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baselinePath = Join-Path $repoRoot 'contracts/baseline/halo-2.26-openapi.json'
$endpoint = 'http://127.0.0.1:8090/v3/api-docs/apis_aggregated.api_v1alpha1'

function ConvertTo-StableJsonValue {
    param([Parameter(Mandatory = $true)][AllowNull()]$Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $ordered[[string]$key] = ConvertTo-StableJsonValue -Value $Value[$key]
        }
        return $ordered
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-StableJsonValue -Value $property.Value
        }
        return $ordered
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-StableJsonValue -Value $_ })
    }

    return $Value
}

if ((Test-Path -LiteralPath $baselinePath) -and -not $AcceptReviewedBaseline) {
    throw 'Baseline exists. Review the OpenAPI document and rerun with -AcceptReviewedBaseline to replace it.'
}

$response = Invoke-WebRequest -UseBasicParsing -Uri $endpoint
if ([int]$response.StatusCode -ne 200) {
    throw "OpenAPI endpoint returned HTTP $($response.StatusCode)."
}

$document = $response.Content | ConvertFrom-Json
$stableDocument = ConvertTo-StableJsonValue -Value $document
$json = $stableDocument | ConvertTo-Json -Depth 100

New-Item -ItemType Directory -Force (Split-Path -Parent $baselinePath) | Out-Null
$temporaryPath = "$baselinePath.tmp"
[System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $baselinePath -Force
Write-Output "Captured reviewed OpenAPI baseline to $baselinePath"
