param(
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ManifestPath = Join-Path $BundleRoot 'bundle-sha256.json'
if (-not (Test-Path $ManifestPath)) {
    throw "Integrity manifest not found: $ManifestPath"
}

$Entries = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$Failures = @()

foreach ($Entry in $Entries) {
    $Relative = $Entry.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $Path = Join-Path $BundleRoot $Relative

    if (-not (Test-Path $Path)) {
        $Failures += "MISSING: $($Entry.path)"
        continue
    }

    $Actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Entry.sha256.ToLowerInvariant()) {
        $Failures += "HASH MISMATCH: $($Entry.path)"
    }
}

if ($Failures.Count -gt 0) {
    Write-Host 'Offline bundle verification FAILED.' -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 20
}

Write-Host "Offline bundle verified successfully ($($Entries.Count) files)." -ForegroundColor Green
exit 0
