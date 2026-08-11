param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-PathEntry([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().Trim('"').TrimEnd('\').ToLowerInvariant()
}

function Get-PathAnalysis([string]$PathValue) {
    $items = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seen = @{}
    $duplicates = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        $key = Normalize-PathEntry $item
        if ($seen.ContainsKey($key)) { $duplicates.Add($item) } else { $seen[$key] = $true }
    }
    return [pscustomobject]@{
        length = $PathValue.Length
        entries = $items.Count
        duplicateEntries = @($duplicates)
    }
}

function Send-EnvironmentChangedMessage {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { return }
    $source = @'
using System;
using System.Runtime.InteropServices;
public static class OfflineToolsEnvironmentBroadcast {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $result = [UIntPtr]::Zero
        [void][OfflineToolsEnvironmentBroadcast]::SendMessageTimeout(
            [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result)
    } catch {
        Write-Warning "Could not broadcast environment change: $($_.Exception.Message)"
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
if (-not (Test-IsAdministrator)) { throw 'Administrator rights are required.' }

$StateRoot = Join-Path $InstallRoot 'state'
$TempRoot = Join-Path $InstallRoot 'temp'
$BinRoot = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force -Path $StateRoot,$TempRoot,$BinRoot | Out-Null

$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
if (-not $machinePath) { $machinePath = '' }
$before = Get-PathAnalysis $machinePath

$executionPolicies = @()
try {
    $executionPolicies = @(Get-ExecutionPolicy -List | ForEach-Object {
        [pscustomobject]@{ scope = [string]$_.Scope; policy = [string]$_.ExecutionPolicy }
    })
} catch {}
$languageMode = [string]$ExecutionContext.SessionState.LanguageMode

$appLockerService = $null
try {
    $svc = Get-Service -Name AppIDSvc -ErrorAction Stop
    $appLockerService = [string]$svc.Status
} catch {}

$controlledFolderAccess = $null
try {
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        $controlledFolderAccess = [int](Get-MpPreference).EnableControlledFolderAccess
    }
} catch {}

$developerMode = $false
try {
    $developerModeValue = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    $developerMode = ($developerModeValue -eq 1)
} catch {}

$proxy = ''
try {
    $proxy = (& netsh.exe winhttp show advproxy 2>&1 | Out-String).Trim()
    if (-not $proxy) { $proxy = (& netsh.exe winhttp show proxy 2>&1 | Out-String).Trim() }
} catch {}

$pythonCommands = @()
try {
    $pythonCommands = @(Get-Command python.exe -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } | Select-Object -Unique)
} catch {}

$longPathsWasEnabled = $false
try {
    $longPathsWasEnabled = ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled -eq 1)
} catch {}

if (-not $ReportOnly) {
    # Keep installer temporary files in one predictable short local path.
    $env:TEMP = $TempRoot
    $env:TMP = $TempRoot

    if (-not $longPathsWasEnabled) {
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -PropertyType DWord -Value 1 -Force | Out-Null
    }

    # Never use SETX for PATH. Preserve unrelated entries, remove duplicate entries,
    # remove historical OfflineTools subdirectories, and expose exactly one managed entry.
    $backupPath = Join-Path $StateRoot ("machine-path-before-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $machinePath | Set-Content -Path $backupPath -Encoding Unicode

    $managedRootKey = (Normalize-PathEntry $InstallRoot) + '\'
    $binKey = Normalize-PathEntry $BinRoot
    $result = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($entry in @($machinePath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $key = Normalize-PathEntry $entry
        if (-not $key) { continue }
        if ($key.StartsWith($managedRootKey) -or $key -eq (Normalize-PathEntry $InstallRoot)) {
            # Old suite PATH entries are intentionally collapsed into the single bin entry.
            continue
        }
        if (-not $seen.ContainsKey($key)) {
            $result.Add($entry.Trim())
            $seen[$key] = $true
        }
    }
    if (-not $seen.ContainsKey($binKey)) { $result.Add($BinRoot) }
    $newPath = ($result -join ';')
    if ($newPath.Length -gt 30000) {
        throw "Machine PATH is unusually large ($($newPath.Length) characters). Automatic modification was stopped to protect existing configuration."
    }
    [Environment]::SetEnvironmentVariable('Path',$newPath,'Machine')
    $machinePath = $newPath
    Send-EnvironmentChangedMessage
}

$after = Get-PathAnalysis $machinePath
$machinePolicy = @($executionPolicies | Where-Object { $_.scope -eq 'MachinePolicy' } | Select-Object -First 1).policy
$userPolicy = @($executionPolicies | Where-Object { $_.scope -eq 'UserPolicy' } | Select-Object -First 1).policy

$blockingReasons = New-Object System.Collections.Generic.List[string]
if ($languageMode -ne 'FullLanguage') {
    $blockingReasons.Add("PowerShell language mode is $languageMode. Corporate application-control policy may block installer scripts.")
}
if ($machinePolicy -eq 'Restricted' -or $userPolicy -eq 'Restricted') {
    $blockingReasons.Add('PowerShell script execution is restricted by Group Policy. The installer will not attempt to bypass corporate policy.')
}
if ($machinePolicy -eq 'AllSigned' -or $userPolicy -eq 'AllSigned') {
    $blockingReasons.Add('Group Policy requires signed PowerShell scripts. Use the organization signing workflow before target deployment.')
}

$report = [pscustomobject]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    installRoot = $InstallRoot
    reportOnly = [bool]$ReportOnly
    path = [pscustomobject]@{
        before = $before
        after = $after
        managedEntry = $BinRoot
        strategy = 'single-managed-path-entry'
    }
    longPaths = [pscustomobject]@{
        wasEnabled = $longPathsWasEnabled
        enabledNow = if ($ReportOnly) { $longPathsWasEnabled } else { $true }
    }
    powershell = [pscustomobject]@{
        languageMode = $languageMode
        executionPolicies = $executionPolicies
    }
    security = [pscustomobject]@{
        appLockerService = $appLockerService
        controlledFolderAccessMode = $controlledFolderAccess
        developerMode = $developerMode
    }
    network = [pscustomobject]@{
        winHttpProxy = $proxy
    }
    discovery = [pscustomobject]@{
        externalPythonCommands = $pythonCommands
    }
    blockingReasons = @($blockingReasons)
}

$reportPath = Join-Path $StateRoot 'environment-readiness.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Environment readiness report: $reportPath"
Write-Host "Machine PATH: $($after.length) chars, $($after.entries) entries, $(@($after.duplicateEntries).Count) duplicates"
Write-Host "PowerShell language mode: $languageMode"
if ($controlledFolderAccess -ne $null) { Write-Host "Controlled Folder Access mode: $controlledFolderAccess" }

if (-not $ReportOnly -and $blockingReasons.Count -gt 0) {
    Write-Warning 'Corporate policy compatibility issues were detected. Security policy was not changed.'
    foreach ($reason in $blockingReasons) { Write-Warning $reason }
    exit 11
}

exit 0
