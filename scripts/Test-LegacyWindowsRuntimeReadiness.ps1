param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateRoot = Join-Path $InstallRoot 'state'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
$caption = [string]$os.Caption
$netFx3 = $null
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
    $netFx3 = [pscustomobject]@{ featureName='NetFx3'; state=[string]$feature.State }
} catch {
    $netFx3 = [pscustomobject]@{ featureName='NetFx3'; state='Unknown'; error=$_.Exception.Message }
}

$source = Join-Path $BundleRoot 'payload\native\windows-sxs'
$sourcePresent = Test-Path $source
$warnings = New-Object System.Collections.Generic.List[string]

if ($netFx3.state -ne 'Enabled') {
    if ($caption -match 'Windows 10') {
        if (-not $sourcePresent) {
            $warnings.Add('.NET Framework 3.5 is not enabled. Windows 10 offline installation requires CAB files from matching Windows installation media; no matching source was bundled.')
        } else {
            $warnings.Add('.NET Framework 3.5 source media exists, but this diagnostic intentionally does not install it automatically because the CAB files must match the exact Windows version/build.')
        }
    } elseif ($caption -match 'Windows 11' -and $build -ge 28000) {
        $warnings.Add('This Windows 11 build uses the newer .NET Framework 3.5 distribution model. Use the Microsoft package specifically intended for this Windows release; do not reuse Windows 10 SxS media.')
    } else {
        $warnings.Add('.NET Framework 3.5 is not enabled. Install it only if a selected legacy application explicitly requires it.')
    }
}

$framework64 = @()
$framework32 = @()
try {
    $framework64 = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue |
        Get-ItemProperty -Name Version,Release -ErrorAction SilentlyContinue |
        Where-Object { $_.Version } |
        Select-Object PSChildName,Version,Release)
} catch {}
try {
    $framework32 = @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue |
        Get-ItemProperty -Name Version,Release -ErrorAction SilentlyContinue |
        Where-Object { $_.Version } |
        Select-Object PSChildName,Version,Release)
} catch {}

$report = [pscustomobject]@{
    generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    windows=[pscustomobject]@{ caption=$caption; build=$build; version=[string]$os.Version }
    netFramework35=$netFx3
    matchingMediaCandidatePresent=$sourcePresent
    installedFramework64=$framework64
    installedFramework32=$framework32
    warnings=@($warnings)
    automaticLegacyFrameworkInstallationPerformed=$false
}
$path = Join-Path $StateRoot 'legacy-windows-runtime-readiness.json'
$report | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding UTF8
Write-Host "Legacy Windows runtime readiness report: $path"
foreach ($warning in $warnings) { Write-Warning $warning }
exit 0
