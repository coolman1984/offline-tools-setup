param(
    [Parameter(Mandatory=$true)][string[]]$Actions,
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$StateRoot = 'C:\OfflineTools\state\windows-care',
    [int]$TempAgeDays = 14
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if ($Actions.Count -eq 1 -and $Actions[0] -like '*,*') {
    $Actions = @($Actions[0].Split(',') | ForEach-Object Trim | Where-Object { $_ })
}
$Actions = @($Actions | Select-Object -Unique)
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $StateRoot "windows-care-$RunId.log"
$SummaryFile = Join-Path $StateRoot "windows-care-$RunId.json"
Start-Transcript -Path $LogFile -Force | Out-Null

$Results = New-Object System.Collections.Generic.List[object]

function Write-CareEvent([string]$Action,[string]$Message) {
    Write-Output "@@CARE|$Action|$Message"
}
function Add-Result([string]$Action,[string]$Status,[string]$Summary,[object]$Data=$null) {
    $Results.Add([pscustomobject]@{
        action = $Action
        status = $Status
        summary = $Summary
        data = $Data
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Invoke-Native([string]$Action,[string]$File,[string[]]$Arguments,[string]$Description) {
    Write-CareEvent $Action $Description
    $output = & $File @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host $output
    if ($code -eq 0) {
        Add-Result $Action 'ok' $Description $output.Trim()
        return $true
    }
    Add-Result $Action 'warning' "$Description returned exit code $code" $output.Trim()
    return $false
}
function Get-TreeStats([string]$Path,[datetime]$OlderThan = [datetime]::MaxValue) {
    if (-not (Test-Path $Path)) { return [pscustomobject]@{ path=$Path; files=0; bytes=0; gb=0 } }
    $files = @(Get-ChildItem -LiteralPath $Path -File -Force -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $OlderThan -eq [datetime]::MaxValue -or $_.LastWriteTime -lt $OlderThan })
    $sum = ($files | Measure-Object Length -Sum).Sum
    $bytes = if ($null -eq $sum) { [long]0 } else { [long]$sum }
    return [pscustomobject]@{ path=$Path; files=$files.Count; bytes=$bytes; gb=[Math]::Round($bytes/1GB,3) }
}
function Get-FileStats([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{path=$Path;exists=$false;bytes=0;gb=0} }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $bytes = if ($item) { [long]$item.Length } else { [long]0 }
    return [pscustomobject]@{path=$Path;exists=$true;bytes=$bytes;gb=[Math]::Round($bytes/1GB,3)}
}
function Remove-OldTempFiles([string]$Path,[datetime]$Cutoff) {
    if (-not (Test-Path $Path)) { return [pscustomobject]@{path=$Path;removed=0;bytes=0;gb=0;failed=0} }
    $removed = 0; [long]$bytes = 0; $failed = 0
    $files = @(Get-ChildItem -LiteralPath $Path -File -Force -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $Cutoff })
    foreach ($file in $files) {
        try {
            $len = $file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++; $bytes += $len
        } catch { $failed++ }
    }
    return [pscustomobject]@{path=$Path;removed=$removed;bytes=$bytes;gb=[Math]::Round($bytes/1GB,3);failed=$failed}
}
function Test-PendingReboot {
    return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
           (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
           ($null -ne (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue))
}
function Get-WindowsIdentity {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $locale = $null
    try { $locale = (Get-WinSystemLocale).Name } catch { $locale = [System.Globalization.CultureInfo]::CurrentUICulture.Name }
    $build = 0
    [void][int]::TryParse([string]$cv.CurrentBuildNumber,[ref]$build)
    $ubr = if ($null -ne $cv.UBR) { [int]$cv.UBR } else { 0 }
    return [pscustomobject]@{
        caption = [string]$os.Caption
        build = $build
        ubr = $ubr
        fullBuild = "$build.$ubr"
        architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
        locale = $locale
        editionId = [string]$cv.EditionID
        displayVersion = [string]$cv.DisplayVersion
    }
}
function Find-VerifiedRepairSource([string]$Root,[object]$Target) {
    if (-not (Test-Path $Root)) { return $null }
    foreach ($dir in Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue) {
        $metadataPath = Join-Path $dir.FullName 'source-metadata.json'
        if (-not (Test-Path $metadataPath)) { continue }
        try { $m = Get-Content $metadataPath -Raw | ConvertFrom-Json } catch { continue }
        if ([int]$m.build -ne [int]$Target.build) { continue }
        if ([int]$m.ubr -ne [int]$Target.ubr) { continue }
        if ([string]$m.architecture -ne [string]$Target.architecture) { continue }
        $languages = @($m.languages | ForEach-Object { [string]$_ })
        if ($languages.Count -gt 0 -and $languages -notcontains [string]$Target.locale) { continue }
        $relativeWindows = if ($m.windowsRelativePath) { [string]$m.windowsRelativePath } else { 'Windows' }
        $windowsPath = Join-Path $dir.FullName $relativeWindows
        if (-not (Test-Path (Join-Path $windowsPath 'System32'))) { continue }
        return [pscustomobject]@{ path=$windowsPath; metadata=$m; metadataPath=$metadataPath }
    }
    return $null
}
function Try-CreateSafetyRestorePoint {
    Write-CareEvent '_safety-checkpoint' 'Attempting a Windows restore point before selected repair actions'
    $command = "`$ErrorActionPreference='Stop'; Checkpoint-Computer -Description 'OfflineTools Safe Care $RunId' -RestorePointType MODIFY_SETTINGS"
    try {
        $output = & powershell.exe -NoProfile -Command $command 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            Add-Result '_safety-checkpoint' 'ok' 'Windows restore point created before repairs.' $output.Trim()
        } else {
            Add-Result '_safety-checkpoint' 'warning' 'Restore point could not be created. System Restore may be disabled or Windows may have created another restore point within the last 24 hours.' $output.Trim()
        }
    } catch {
        Add-Result '_safety-checkpoint' 'warning' 'Restore point creation was unavailable; repairs will continue using their own conservative/reversible safeguards.' $_.Exception.Message
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if (-not (Test-Admin)) { throw 'Administrator rights are required for Windows Care.' }

$SystemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
$WindowsDir = $env:WINDIR
$Cutoff = (Get-Date).AddDays(-[Math]::Abs($TempAgeDays))
$TargetWindows = Get-WindowsIdentity

$RepairActionIds = @('cleanup-stale-temp','cleanup-delivery-cache','component-cleanup','dism-restore-local','sfc-repair','windows-update-reset')
$HasRepairs = @($Actions | Where-Object { $RepairActionIds -contains $_ }).Count -gt 0
if ($HasRepairs) { Try-CreateSafetyRestorePoint }

foreach ($Action in $Actions) {
    try {
        switch ($Action) {
            'disk-space-analysis' {
                Write-CareEvent $Action 'Analyzing safe disk-space candidates and large system-maintenance files'
                $deliveryCache = Join-Path $WindowsDir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
                $targets = @(
                    (Get-TreeStats $env:TEMP $Cutoff),
                    (Get-TreeStats (Join-Path $WindowsDir 'Temp') $Cutoff),
                    (Get-TreeStats (Join-Path $WindowsDir 'SoftwareDistribution\Download')),
                    (Get-TreeStats $deliveryCache),
                    (Get-TreeStats (Join-Path $env:ProgramData 'Microsoft\Windows\WER')),
                    (Get-TreeStats (Join-Path $WindowsDir 'Minidump')),
                    (Get-TreeStats (Join-Path $WindowsDir 'Logs\CBS')),
                    (Get-TreeStats (Join-Path $WindowsDir 'Logs\DISM')),
                    (Get-TreeStats (Join-Path $SystemDrive 'Windows.old'))
                )
                $largeSystemFiles = @(
                    (Get-FileStats (Join-Path $SystemDrive 'hiberfil.sys')),
                    (Get-FileStats (Join-Path $SystemDrive 'pagefile.sys')),
                    (Get-FileStats (Join-Path $SystemDrive 'swapfile.sys')),
                    (Get-FileStats (Join-Path $WindowsDir 'MEMORY.DMP'))
                )
                $drive = Get-PSDrive -Name $SystemDrive.TrimEnd(':')
                $data = [pscustomobject]@{
                    freeGB = [Math]::Round($drive.Free/1GB,2)
                    usedGB = [Math]::Round($drive.Used/1GB,2)
                    staleCutoff = $Cutoff
                    cleanupCandidates = $targets
                    largeSystemFilesForInformationOnly = $largeSystemFiles
                    note = 'Hibernation/pagefile/swap/dump files are reported for explanation only and are not automatically deleted by Windows Care.'
                }
                $data | Format-List | Out-String | Write-Host
                Add-Result $Action 'ok' 'Disk-space candidates analyzed; nothing was deleted.' $data
            }
            'pending-reboot' {
                $pending = Test-PendingReboot
                $status = if ($pending) { 'warning' } else { 'ok' }
                $message = if ($pending) { 'Windows restart is pending.' } else { 'No common restart marker detected.' }
                Add-Result $Action $status $message $pending
                Write-Host "Pending restart: $pending"
            }
            'windows-installer-health' {
                Write-CareEvent $Action 'Checking Windows Installer service and transaction state'
                $svc = Get-Service msiserver -ErrorAction SilentlyContinue
                $msiexec = Get-Item (Join-Path $WindowsDir 'System32\msiexec.exe') -ErrorAction SilentlyContinue
                $inProgress = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress'
                $data = [pscustomobject]@{
                    serviceStatus = if ($svc) { [string]$svc.Status } else { 'Missing' }
                    serviceStartType = if ($svc) { [string]$svc.StartType } else { 'Unknown' }
                    executableVersion = if ($msiexec) { [string]$msiexec.VersionInfo.FileVersion } else { $null }
                    transactionInProgressMarker = $inProgress
                }
                $status = if (-not $svc -or -not $msiexec -or $inProgress) { 'warning' } else { 'ok' }
                Add-Result $Action $status 'Windows Installer health inspected without changing the service.' $data
                $data | Format-List | Out-String | Write-Host
            }
            'time-service-health' {
                Write-CareEvent $Action 'Checking Windows time service and synchronization state'
                $svc = Get-Service w32time -ErrorAction SilentlyContinue
                $statusText = & w32tm.exe /query /status /verbose 2>&1 | Out-String
                $code = $LASTEXITCODE
                $data = [pscustomobject]@{ serviceStatus=if($svc){[string]$svc.Status}else{'Missing'}; queryExitCode=$code; status=$statusText.Trim() }
                $status = if ($svc -and $code -eq 0) { 'ok' } else { 'warning' }
                Add-Result $Action $status 'Windows time state inspected; no clock or service settings were changed.' $data
                Write-Host $statusText
            }
            'vss-health' {
                Write-CareEvent $Action 'Inspecting Volume Shadow Copy writers and existing snapshots'
                $writers = & vssadmin.exe list writers 2>&1 | Out-String
                $writersCode = $LASTEXITCODE
                $shadows = & vssadmin.exe list shadows "/for=$SystemDrive" 2>&1 | Out-String
                $shadowsCode = $LASTEXITCODE
                $data = [pscustomobject]@{writersExitCode=$writersCode;writers=$writers.Trim();shadowsExitCode=$shadowsCode;shadows=$shadows.Trim()}
                $status = if ($writersCode -eq 0 -and $shadowsCode -eq 0) { 'ok' } else { 'warning' }
                Add-Result $Action $status 'VSS health inspected. No shadow copies were deleted or resized.' $data
                Write-Host $writers
                Write-Host $shadows
            }
            'runtime-readiness' {
                Write-CareEvent $Action 'Inspecting legacy Windows runtime readiness'
                $script = Join-Path $BundleRoot 'scripts\Test-LegacyWindowsRuntimeReadiness.ps1'
                if (-not (Test-Path $script)) { Add-Result $Action 'skipped' 'Legacy runtime diagnostic script is missing from the bundle.'; continue }
                & powershell.exe -NoProfile -File $script -BundleRoot $BundleRoot
                $code = $LASTEXITCODE
                $report = 'C:\OfflineTools\state\legacy-windows-runtime-readiness.json'
                $data = if (Test-Path $report) { Get-Content $report -Raw | ConvertFrom-Json } else { $null }
                Add-Result $Action (if($code -eq 0){'ok'}else{'warning'}) 'Windows runtime readiness diagnostic completed without installing optional Windows features.' $data
            }
            'development-environment-health' {
                Write-CareEvent $Action 'Inspecting PATH, PowerShell policy, application control and conflicting developer commands'
                $script = Join-Path $BundleRoot 'scripts\Invoke-EnvironmentHardening.ps1'
                if (-not (Test-Path $script)) { Add-Result $Action 'skipped' 'Environment readiness diagnostic script is missing from the bundle.'; continue }
                & powershell.exe -NoProfile -File $script -ReportOnly
                $code = $LASTEXITCODE
                $report = 'C:\OfflineTools\state\environment-readiness.json'
                $data = if (Test-Path $report) { Get-Content $report -Raw | ConvertFrom-Json } else { $null }
                Add-Result $Action (if($code -eq 0){'ok'}else{'warning'}) 'Development environment readiness diagnostic completed without changing PATH or corporate policy.' $data
            }
            'component-store-analysis' {
                Invoke-Native $Action 'dism.exe' @('/Online','/Cleanup-Image','/AnalyzeComponentStore') 'Analyzing Windows component store' | Out-Null
            }
            'dism-checkhealth' {
                Invoke-Native $Action 'dism.exe' @('/Online','/Cleanup-Image','/CheckHealth') 'Running DISM CheckHealth' | Out-Null
            }
            'dism-scanhealth' {
                Invoke-Native $Action 'dism.exe' @('/Online','/Cleanup-Image','/ScanHealth') 'Running deep DISM ScanHealth; this can take a long time' | Out-Null
            }
            'sfc-verify' {
                Invoke-Native $Action 'sfc.exe' @('/verifyonly') 'Verifying protected Windows files without repair' | Out-Null
            }
            'chkdsk-scan' {
                Invoke-Native $Action 'chkdsk.exe' @($SystemDrive,'/scan') 'Running online file-system scan without scheduling offline repair' | Out-Null
            }
            'storage-health' {
                Write-CareEvent $Action 'Reading physical disk health and reliability counters'
                $items = @()
                foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
                    $rel = $pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                    $items += [pscustomobject]@{
                        name=$pd.FriendlyName; serial=$pd.SerialNumber; media=$pd.MediaType; bus=$pd.BusType;
                        health=$pd.HealthStatus; operational=@($pd.OperationalStatus); sizeGB=[Math]::Round($pd.Size/1GB,2);
                        temperature=$rel.Temperature; wear=$rel.Wear; readErrors=$rel.ReadErrorsTotal; writeErrors=$rel.WriteErrorsTotal; powerOnHours=$rel.PowerOnHours
                    }
                }
                $items | Format-Table -AutoSize | Out-String | Write-Host
                Add-Result $Action 'ok' 'Storage health collected where hardware exposes reliability counters.' $items
            }
            'device-problems' {
                Write-CareEvent $Action 'Enumerating devices reporting Plug and Play problems'
                $output = & pnputil.exe /enum-devices /problem /deviceids 2>&1 | Out-String
                $code = $LASTEXITCODE
                Write-Host $output
                Add-Result $Action (if($code -eq 0){'ok'}else{'warning'}) 'Device problem enumeration completed. No drivers were changed.' $output.Trim()
            }
            'recent-critical-events' {
                Write-CareEvent $Action 'Reading recent critical and error events'
                $start = (Get-Date).AddDays(-7)
                $events = @(Get-WinEvent -FilterHashtable @{LogName=@('System','Application'); Level=@(1,2); StartTime=$start} -MaxEvents 80 -ErrorAction SilentlyContinue |
                    Select-Object TimeCreated,LogName,ProviderName,Id,LevelDisplayName,Message)
                $events | Select-Object -First 20 TimeCreated,LogName,ProviderName,Id,LevelDisplayName | Format-Table -AutoSize | Out-String | Write-Host
                Add-Result $Action 'ok' "Collected $($events.Count) recent critical/error events." $events
            }
            'windows-update-health' {
                Write-CareEvent $Action 'Checking Windows Update services and recent errors'
                $services = @(Get-Service wuauserv,bits,cryptsvc,msiserver -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType)
                $cache = Get-TreeStats (Join-Path $WindowsDir 'SoftwareDistribution\Download')
                $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; StartTime=(Get-Date).AddDays(-14)} -MaxEvents 40 -ErrorAction SilentlyContinue |
                    Select-Object TimeCreated,Id,LevelDisplayName,Message)
                $data = [pscustomobject]@{services=$services;downloadCache=$cache;pendingReboot=(Test-PendingReboot);recentEvents=$events;windows=$TargetWindows}
                $services | Format-Table -AutoSize | Out-String | Write-Host
                Add-Result $Action 'ok' 'Windows Update health collected without changing services or cache.' $data
            }
            'power-health' {
                Write-CareEvent $Action 'Generating Windows power efficiency report; this usually takes about a minute'
                $powerRoot = Join-Path $StateRoot "power-$RunId"
                New-Item -ItemType Directory -Force -Path $powerRoot | Out-Null
                & powercfg.exe /energy /output (Join-Path $powerRoot 'energy.html') /duration 60 2>&1 | Write-Host
                & powercfg.exe /batteryreport /output (Join-Path $powerRoot 'battery.html') 2>&1 | Write-Host
                Add-Result $Action 'ok' 'Power reports generated where supported.' $powerRoot
            }
            'cleanup-stale-temp' {
                Write-CareEvent $Action "Removing only temporary files older than $TempAgeDays days"
                $results = @(
                    (Remove-OldTempFiles $env:TEMP $Cutoff),
                    (Remove-OldTempFiles (Join-Path $WindowsDir 'Temp') $Cutoff),
                    (Remove-OldTempFiles 'C:\OfflineTools\temp' $Cutoff)
                )
                $sum = ($results | Measure-Object bytes -Sum).Sum
                $freed = if ($null -eq $sum) { [long]0 } else { [long]$sum }
                $results | Format-Table -AutoSize | Out-String | Write-Host
                Add-Result $Action 'ok' ("Removed stale temporary files; freed {0:N2} GB. Locked files were skipped." -f ($freed/1GB)) $results
            }
            'cleanup-delivery-cache' {
                Write-CareEvent $Action 'Clearing unpinned Delivery Optimization cache with the Windows cmdlet'
                if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                    Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                    Add-Result $Action 'ok' 'Delivery Optimization cache cleared. Pinned content was not explicitly included.'
                } else {
                    Add-Result $Action 'skipped' 'Delivery Optimization cleanup cmdlet is unavailable on this Windows installation.'
                }
            }
            'component-cleanup' {
                Invoke-Native $Action 'dism.exe' @('/Online','/Cleanup-Image','/StartComponentCleanup') 'Running supported Windows component cleanup; ResetBase is not used' | Out-Null
            }
            'dism-restore-local' {
                Write-CareEvent $Action "Looking for verified local repair media matching Windows $($TargetWindows.fullBuild), $($TargetWindows.architecture), $($TargetWindows.locale)"
                $repair = Find-VerifiedRepairSource (Join-Path $BundleRoot 'payload\windows-repair') $TargetWindows
                if (-not $repair) {
                    Add-Result $Action 'skipped' "No repair source matched build/revision $($TargetWindows.fullBuild), architecture $($TargetWindows.architecture), and locale $($TargetWindows.locale). No network repair was attempted." $TargetWindows
                    Write-Warning 'Matching verified Windows repair source was not found.'
                } else {
                    Invoke-Native $Action 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth',("/Source:{0}" -f $repair.path),'/LimitAccess') "Repairing Windows image from verified local source $($repair.path)" | Out-Null
                }
            }
            'sfc-repair' {
                Invoke-Native $Action 'sfc.exe' @('/scannow') 'Repairing protected Windows system files with System File Checker' | Out-Null
            }
            'windows-update-reset' {
                Write-CareEvent $Action 'Rebuilding Windows Update working folders using reversible timestamped backups'
                if (Test-PendingReboot) {
                    Add-Result $Action 'skipped' 'Windows restart is already pending. Update cache rebuild was skipped until after restart.'
                    continue
                }
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $sd = Join-Path $WindowsDir 'SoftwareDistribution'
                $cr = Join-Path $WindowsDir 'System32\catroot2'
                $serviceNames = @('wuauserv','bits','cryptsvc')
                try {
                    foreach ($svc in $serviceNames) { Stop-Service $svc -Force -ErrorAction SilentlyContinue }
                    if (Test-Path $sd) { Rename-Item $sd "SoftwareDistribution.ots-backup-$stamp" -ErrorAction Stop }
                    if (Test-Path $cr) { Rename-Item $cr "catroot2.ots-backup-$stamp" -ErrorAction Stop }
                    Add-Result $Action 'ok' 'Windows Update working folders were rebuilt. Timestamped backups were preserved for recovery.'
                }
                finally {
                    foreach ($svc in @('cryptsvc','bits','wuauserv')) { Start-Service $svc -ErrorAction SilentlyContinue }
                }
            }
            default {
                Add-Result $Action 'skipped' 'Unknown Windows Care action.'
            }
        }
    }
    catch {
        Write-Warning "$Action failed: $($_.Exception.Message)"
        Add-Result $Action 'error' $_.Exception.Message
    }
}

$summary = [pscustomobject]@{
    runId = $RunId
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    windows = $TargetWindows
    actions = $Actions
    tempAgeDays = $TempAgeDays
    results = @($Results)
    log = $LogFile
    guardrails = @(
        'No manual deletion of WinSxS or Windows Installer cache',
        'No boot configuration changes',
        'No security-control disabling',
        'No driver deletion or automatic driver replacement',
        'No DISM ResetBase',
        'No automatic offline CHKDSK repair scheduling',
        'No user Documents/Desktop/Downloads deletion',
        'DISM local repair requires matching build revision architecture and locale metadata'
    )
}
$summary | ConvertTo-Json -Depth 12 | Set-Content $SummaryFile -Encoding UTF8
Write-Host "`nWindows Care summary: $SummaryFile" -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch {}
if (@($Results | Where-Object status -eq 'error').Count -gt 0) { exit 2 }
exit 0
