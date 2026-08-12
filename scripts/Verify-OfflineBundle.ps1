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
$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot).TrimEnd('\')
$SeenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if (@($Entries).Count -eq 0) {
    $Failures += 'EMPTY MANIFEST: no bundle files are recorded.'
}

foreach ($Entry in $Entries) {
    if (-not $Entry.path -or -not $Entry.sha256 -or $Entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        $Failures += "INVALID ENTRY: $($Entry.path)"
        continue
    }
    if (-not $SeenPaths.Add([string]$Entry.path)) {
        $Failures += "DUPLICATE ENTRY: $($Entry.path)"
        continue
    }
    $Relative = $Entry.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $Path = [System.IO.Path]::GetFullPath((Join-Path $BundleRoot $Relative))
    if (-not $Path.StartsWith($BundleRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Failures += "UNSAFE PATH: $($Entry.path)"
        continue
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $Failures += "MISSING: $($Entry.path)"
        continue
    }

    if ($null -ne $Entry.size -and (Get-Item -LiteralPath $Path).Length -ne [int64]$Entry.size) {
        $Failures += "SIZE MISMATCH: $($Entry.path)"
        continue
    }

    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Entry.sha256.ToLowerInvariant()) {
        $Failures += "HASH MISMATCH: $($Entry.path)"
    }
}

foreach ($RequiredPath in @(
    'START-HERE.cmd',
    'config/setup-profiles.json',
    'scripts/Install-SelectedProfiles.ps1',
    'payload/bootstrap/OfflineToolsDesktop.exe',
    'payload/bootstrap/OfflineToolsSuite.exe',
    'payload/bootstrap/OfflineToolsSetup.exe'
)) {
    if (-not $SeenPaths.Contains($RequiredPath) -or -not (Test-Path -LiteralPath (Join-Path $BundleRoot $RequiredPath) -PathType Leaf)) {
        $Failures += "REQUIRED FILE MISSING FROM VERIFIED BUNDLE: $RequiredPath"
    }
}

foreach ($File in Get-ChildItem $BundleRoot -File -Recurse) {
    if ($File.Name -eq 'bundle-sha256.json') { continue }
    $Relative = $File.FullName.Substring($BundleRoot.Length).TrimStart('\').Replace('\','/')
    if (-not $SeenPaths.Contains($Relative)) {
        $Failures += "UNTRACKED FILE: $Relative"
    }
}

if ($Failures.Count -gt 0) {
    Write-Host 'Offline bundle verification FAILED.' -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 20
}

Write-Host "Offline bundle verified successfully ($($Entries.Count) files)." -ForegroundColor Green
exit 0
