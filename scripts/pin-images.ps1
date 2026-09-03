$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dockerCli = if ($env:DOCKER_CLI) {
    $env:DOCKER_CLI
} else {
    (Get-Command docker -ErrorAction Stop).Source
}

$images = [ordered]@{
    HALO_IMAGE = 'halohub/halo:2.26'
    POSTGRES_IMAGE = 'postgres:16.8-alpine'
}

$lines = foreach ($entry in $images.GetEnumerator()) {
    & $dockerCli pull $entry.Value | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Unable to pull $($entry.Value)" }

    $digest = & $dockerCli image inspect --format '{{index .RepoDigests 0}}' $entry.Value
    if ($LASTEXITCODE -ne 0 -or $digest -notmatch '@sha256:[0-9a-f]{64}$') {
        throw "Missing RepoDigest for $($entry.Value)"
    }

    "$($entry.Key)=$digest"
}

$temporaryLock = Join-Path $repoRoot 'environment/image-lock.env.new'
$lockFile = Join-Path $repoRoot 'environment/image-lock.env'
$lines | Set-Content -LiteralPath $temporaryLock -Encoding ascii
Move-Item -LiteralPath $temporaryLock -Destination $lockFile -Force

Write-Output "Pinned $($images.Count) container images in environment/image-lock.env."
