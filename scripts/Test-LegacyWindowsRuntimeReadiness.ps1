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
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$ubr = if ($cv -and $null -ne $cv.UBR) { [int]$cv.UBR } else { 0 }
$systemLocale = try { (Get-WinSystemLocale).Name } catch { [System.Globalization.CultureInfo]::CurrentUICulture.Name }
$warnings = New-Object System.Collections.Generic.List[string]

$netFx3 = $null
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
    $netFx3 = [pscustomobject]@{ featureName='NetFx3'; state=[string]$feature.State }
} catch {
    $netFx3 = [pscustomobject]@{ featureName='NetFx3'; state='Unknown'; error=$_.Exception.Message }
}

$source = Join-Path $BundleRoot 'payload\native\windows-sxs'
$sourcePresent = Test-Path $source

if ($netFx3.state -ne 'Enabled') {
    if ($caption -match 'Windows 10') {
        if (-not $sourcePresent) {
            $warnings.Add('.NET Framework 3.5 is not enabled. Windows 10 offline installation requires files from matching Windows installation media; no matching source was bundled.')
        } else {
            $warnings.Add('.NET Framework 3.5 source media exists, but this diagnostic intentionally does not install it automatically because the source must match the Windows servicing level.')
        }
    } elseif ($caption -match 'Windows 11' -and $build -ge 28000) {
        $warnings.Add('This Windows 11 build uses a newer .NET Framework 3.5 distribution model. Do not reuse Windows 10 SxS media.')
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

# Recovery and encryption are inventory-only. The suite never suspends BitLocker,
# changes BCD, enables/disables WinRE, resizes recovery partitions, or writes Secure Boot variables.
$winReInfo = ''
try { $winReInfo = (& reagentc.exe /info 2>&1 | Out-String).Trim() } catch { $winReInfo = $_.Exception.Message }
if ($winReInfo -match 'Windows RE status:\s+Disabled') {
    $warnings.Add('Windows Recovery Environment is reported as disabled. This suite will not enable or reconfigure WinRE automatically; review recovery policy before risky maintenance.')
}

$bitLocker = @()
try {
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $bitLocker = @(Get-BitLockerVolume | Select-Object MountPoint,VolumeType,VolumeStatus,ProtectionStatus,LockStatus,EncryptionMethod,EncryptionPercentage,AutoUnlockEnabled,@{N='KeyProtectorTypes';E={@($_.KeyProtector | ForEach-Object KeyProtectorType)}})
    }
} catch {}

$secureBootEnabled = $null
try { $secureBootEnabled = Confirm-SecureBootUEFI } catch {}
$secureBootServicing = $null
try { $secureBootServicing = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue } catch {}
$secureBoot2023Status = if ($secureBootServicing) { [string]$secureBootServicing.UEFICA2023Status } else { '' }
$secureBoot2023Error = if ($secureBootServicing) { [string]$secureBootServicing.UEFICA2023Error } else { '' }
$secureBootEvents = @()
try {
    $secureBootEvents = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=@(1795,1800,1801,1803,1808); StartTime=(Get-Date).AddDays(-45)} -MaxEvents 30 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message)
} catch {}
if (@($secureBootEvents | Where-Object { $_.Id -in 1795,1801 }).Count -gt 0) {
    $warnings.Add('Recent Secure Boot servicing events indicate that the 2023 certificate transition needs administrator/OEM review. The suite reports this only and never changes firmware or Secure Boot variables.')
}

$tpm = $null
try {
    if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
        $tpm = Get-Tpm | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated,ManufacturerIdTxt,ManufacturerVersion
    }
} catch {}

$report = [pscustomobject]@{
    generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    windows=[pscustomobject]@{
        caption=$caption
        build=$build
        ubr=$ubr
        fullBuild="$build.$ubr"
        version=[string]$os.Version
        editionId=if($cv){[string]$cv.EditionID}else{''}
        displayVersion=if($cv){[string]$cv.DisplayVersion}else{''}
        architecture=if([Environment]::Is64BitOperatingSystem){'x64'}else{'x86'}
        systemLocale=$systemLocale
    }
    netFramework35=$netFx3
    matchingMediaCandidatePresent=$sourcePresent
    installedFramework64=$framework64
    installedFramework32=$framework32
    recovery=[pscustomobject]@{
        windowsRE=$winReInfo
        bitLockerVolumes=$bitLocker
        tpm=$tpm
        secureBootEnabled=$secureBootEnabled
        secureBoot2023CertificateStatus=$secureBoot2023Status
        secureBoot2023Error=$secureBoot2023Error
        secureBootRelatedEvents=$secureBootEvents
        modificationPerformed=$false
    }
    warnings=@($warnings)
    automaticLegacyFrameworkInstallationPerformed=$false
    automaticRecoveryOrEncryptionChangePerformed=$false
}
$path = Join-Path $StateRoot 'legacy-windows-runtime-readiness.json'
$report | ConvertTo-Json -Depth 12 | Set-Content $path -Encoding UTF8
Write-Host "Windows runtime and recovery readiness report: $path"
foreach ($warning in $warnings) { Write-Warning $warning }
exit 0
