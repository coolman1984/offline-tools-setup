param(
    [Parameter(Mandatory=$true)][string]$SourceWindowsPath,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\native-source\windows-repair'),
    [int]$Build = 0,
    [int]$Ubr = -1,
    [ValidateSet('x64','x86','arm64')][string]$Architecture = 'x64',
    [string[]]$Languages = @(),
    [string]$SourceDescription = 'Approved offline Windows repair source'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SourceWindowsPath = [System.IO.Path]::GetFullPath($SourceWindowsPath)
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-Path (Join-Path $SourceWindowsPath 'System32'))) {
    throw "SourceWindowsPath must point to an expanded Windows directory containing System32: $SourceWindowsPath"
}

# If the caller points at the currently running Windows directory, metadata can be discovered safely.
$runningWindows = [System.IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
$isRunningWindowsSource = $SourceWindowsPath.TrimEnd('\').Equals($runningWindows,[System.StringComparison]::OrdinalIgnoreCase)
if ($isRunningWindowsSource) {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if ($Build -eq 0) { $Build = [int]$cv.CurrentBuildNumber }
    if ($Ubr -lt 0) { $Ubr = [int]$cv.UBR }
    if ($Languages.Count -eq 0) {
        try { $Languages = @((Get-WinSystemLocale).Name) } catch { $Languages = @([System.Globalization.CultureInfo]::CurrentUICulture.Name) }
    }
    $Architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
}

if ($Build -le 0 -or $Ubr -lt 0) {
    throw 'Build and Ubr are required for mounted/offline Windows sources. For a running Windows source they can be detected automatically.'
}
if ($Languages.Count -eq 0) {
    throw 'At least one source language must be supplied for an offline/mounted Windows source.'
}

$Languages = @($Languages | Where-Object { $_ } | ForEach-Object Trim | Select-Object -Unique)
$primaryLanguage = $Languages[0]
$profileId = "$Build.$Ubr-$Architecture-$primaryLanguage"
$TargetRoot = Join-Path $OutputRoot $profileId
$TargetWindows = Join-Path $TargetRoot 'Windows'

Write-Host "Preparing Windows repair source profile: $profileId" -ForegroundColor Cyan
Write-Host "Source : $SourceWindowsPath"
Write-Host "Target : $TargetWindows"
Write-Host "Build  : $Build.$Ubr"
Write-Host "Arch   : $Architecture"
Write-Host "Lang   : $($Languages -join ', ')"

Remove-Item $TargetRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null

# Robocopy handles large Windows trees, long paths and junction avoidance more reliably than a naive recursive copy.
$robo = Start-Process -FilePath 'robocopy.exe' -ArgumentList @(
    "`"$SourceWindowsPath`"", "`"$TargetWindows`"", '/E','/COPY:DAT','/DCOPY:DAT','/R:1','/W:1','/XJ','/SL','/NFL','/NDL','/NP'
) -Wait -PassThru -NoNewWindow
if ($robo.ExitCode -gt 7) { throw "Robocopy failed while preparing the Windows repair source (exit $($robo.ExitCode))." }
if (-not (Test-Path (Join-Path $TargetWindows 'System32'))) { throw 'Prepared Windows repair source is incomplete.' }

$metadata = [ordered]@{
    schemaVersion = 1
    build = $Build
    ubr = $Ubr
    fullBuild = "$Build.$Ubr"
    architecture = $Architecture
    languages = $Languages
    windowsRelativePath = 'Windows'
    description = $SourceDescription
    preparedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceWasRunningWindows = $isRunningWindowsSource
    sourcePathRecordedForBuilderAudit = $SourceWindowsPath
    repairPolicy = [ordered]@{
        targetRequiresExactBuildAndUbr = $true
        targetRequiresArchitectureMatch = $true
        targetRequiresSystemLocaleInLanguages = $true
        targetUsesLimitAccess = $true
    }
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $TargetRoot 'source-metadata.json') -Encoding UTF8

Write-Host "`nVerified repair source prepared: $TargetRoot" -ForegroundColor Green
Write-Warning 'Keep this source serviced and language-compatible with the target fleet. A target patched beyond the repair source can fail servicing.'
