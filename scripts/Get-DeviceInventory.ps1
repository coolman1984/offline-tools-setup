param(
    [string]$OutputPath = 'C:\OfflineTools\state\device-inventory.json',
    [switch]$SummaryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Safe($ScriptBlock, $Fallback = $null) {
    try { & $ScriptBlock } catch { $Fallback }
}
function To-Gb($Bytes) {
    if ($null -eq $Bytes) { return $null }
    return [Math]::Round(([double]$Bytes / 1GB), 2)
}

$os = Safe { Get-CimInstance Win32_OperatingSystem }
$cs = Safe { Get-CimInstance Win32_ComputerSystem }
$bios = Safe { Get-CimInstance Win32_BIOS }
$cv = Safe { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' }
$cpu = @(Safe { Get-CimInstance Win32_Processor } @())
$memory = @(Safe { Get-CimInstance Win32_PhysicalMemory } @())
$gpu = @(Safe { Get-CimInstance Win32_VideoController } @())
$volumes = @(Safe { Get-Volume | Where-Object DriveLetter } @())
$disks = @(Safe { Get-Disk } @())
$partitions = @(Safe { Get-Partition | Select-Object DiskNumber,PartitionNumber,DriveLetter,Type,IsSystem,IsBoot,IsActive,@{N='SizeGB';E={To-Gb $_.Size}} } @())
$physical = @(Safe { Get-PhysicalDisk } @())
$netAdapters = @(Safe { Get-NetAdapter -IncludeHidden | Select-Object Name,InterfaceDescription,Status,MacAddress,LinkSpeed,MediaType,ifIndex } @())
$netConfig = @(Safe { Get-NetIPConfiguration -All } @())
$hotfixes = @(Safe { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 30 HotFixID,Description,InstalledOn,InstalledBy } @())
$startup = @(Safe { Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location,User } @())
$services = @(Safe { Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Select-Object Name,DisplayName,State,StartMode,StartName } @())
$devices = @(Safe { Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object Class,FriendlyName,InstanceId,Status,Problem } @())
$defender = Safe { Get-MpComputerStatus | Select-Object AntivirusEnabled,AntispywareEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,AntivirusSignatureVersion,AntivirusSignatureLastUpdated }
$tpm = Safe { Get-Tpm | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated,ManufacturerIdTxt,ManufacturerVersion }
$secureBoot = Safe { Confirm-SecureBootUEFI } $null
$executionPolicy = @(Safe { Get-ExecutionPolicy -List } @())
$proxy = Safe { (netsh winhttp show proxy | Out-String).Trim() } ''
$systemLocale = Safe { (Get-WinSystemLocale).Name } ([System.Globalization.CultureInfo]::CurrentUICulture.Name)

$bitlocker = @(Safe {
    Get-BitLockerVolume | Select-Object MountPoint,VolumeType,VolumeStatus,ProtectionStatus,LockStatus,EncryptionMethod,EncryptionPercentage,AutoUnlockEnabled,@{N='KeyProtectorTypes';E={@($_.KeyProtector | ForEach-Object KeyProtectorType)}}
} @())
$winReInfo = Safe { (& reagentc.exe /info 2>&1 | Out-String).Trim() } ''
$secureBootServicing = Safe { Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' }
$secureBoot2023Status = if ($secureBootServicing) { [string]$secureBootServicing.UEFICA2023Status } else { '' }
$secureBoot2023Error = if ($secureBootServicing) { [string]$secureBootServicing.UEFICA2023Error } else { '' }
$secureBootEvents = @(Safe {
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=@(1795,1800,1801,1803,1808); StartTime=(Get-Date).AddDays(-45)} -MaxEvents 30 |
        Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message
} @())

$diskReliability = foreach ($pd in $physical) {
    $rel = Safe { $pd | Get-StorageReliabilityCounter }
    [pscustomobject]@{
        FriendlyName = $pd.FriendlyName
        SerialNumber = $pd.SerialNumber
        MediaType = $pd.MediaType
        BusType = $pd.BusType
        HealthStatus = $pd.HealthStatus
        OperationalStatus = @($pd.OperationalStatus)
        SizeGB = To-Gb $pd.Size
        Temperature = $rel.Temperature
        Wear = $rel.Wear
        ReadErrorsTotal = $rel.ReadErrorsTotal
        WriteErrorsTotal = $rel.WriteErrorsTotal
        PowerOnHours = $rel.PowerOnHours
    }
}

$network = foreach ($n in $netConfig) {
    [pscustomobject]@{
        InterfaceAlias = $n.InterfaceAlias
        InterfaceIndex = $n.InterfaceIndex
        IPv4 = @($n.IPv4Address | ForEach-Object IPAddress)
        IPv6 = @($n.IPv6Address | ForEach-Object IPAddress)
        IPv4Gateway = @($n.IPv4DefaultGateway | ForEach-Object NextHop)
        DnsServers = @($n.DNSServer.ServerAddresses)
        NetProfile = $n.NetProfile.Name
    }
}

$recentEvents = @(Safe {
    $start = (Get-Date).AddDays(-7)
    Get-WinEvent -FilterHashtable @{LogName=@('System','Application'); Level=@(1,2); StartTime=$start} -MaxEvents 100 |
        Select-Object TimeCreated,LogName,ProviderName,Id,LevelDisplayName,Message
} @())

$envPathMachine = [Environment]::GetEnvironmentVariable('Path','Machine')
$envPathUser = [Environment]::GetEnvironmentVariable('Path','User')
$ubr = if ($cv -and $null -ne $cv.UBR) { [int]$cv.UBR } else { 0 }
$buildNumber = if ($cv -and $cv.CurrentBuildNumber) { [string]$cv.CurrentBuildNumber } else { [string]$os.BuildNumber }

$inventory = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    computer = [ordered]@{
        name = $env:COMPUTERNAME
        manufacturer = $cs.Manufacturer
        model = $cs.Model
        systemType = $cs.SystemType
        domain = $cs.Domain
        partOfDomain = $cs.PartOfDomain
        totalMemoryGB = To-Gb $cs.TotalPhysicalMemory
    }
    windows = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        buildNumber = $buildNumber
        ubr = $ubr
        fullBuild = "$buildNumber.$ubr"
        displayVersion = if ($cv) { [string]$cv.DisplayVersion } else { '' }
        editionId = if ($cv) { [string]$cv.EditionID } else { '' }
        architecture = $os.OSArchitecture
        systemLocale = $systemLocale
        installDate = $os.InstallDate
        lastBoot = $os.LastBootUpTime
        locale = $os.Locale
        windowsDirectory = $os.WindowsDirectory
        systemDirectory = $os.SystemDirectory
        pendingReboot = ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
    }
    bios = [ordered]@{
        manufacturer = $bios.Manufacturer
        version = $bios.SMBIOSBIOSVersion
        releaseDate = $bios.ReleaseDate
        serialNumber = $bios.SerialNumber
    }
    cpu = @($cpu | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,AddressWidth)
    memoryModules = @($memory | Select-Object Manufacturer,PartNumber,SerialNumber,@{N='CapacityGB';E={To-Gb $_.Capacity}},Speed,ConfiguredClockSpeed)
    gpu = @($gpu | Select-Object Name,DriverVersion,VideoProcessor,AdapterRAM,CurrentHorizontalResolution,CurrentVerticalResolution)
    volumes = @($volumes | Select-Object DriveLetter,FileSystemLabel,FileSystem,HealthStatus,@{N='SizeGB';E={To-Gb $_.Size}},@{N='FreeGB';E={To-Gb $_.SizeRemaining}})
    disks = @($disks | Select-Object Number,FriendlyName,SerialNumber,BusType,PartitionStyle,OperationalStatus,HealthStatus,@{N='SizeGB';E={To-Gb $_.Size}})
    partitions = $partitions
    physicalDiskHealth = @($diskReliability)
    networkAdapters = $netAdapters
    network = @($network)
    security = [ordered]@{
        secureBoot = $secureBoot
        secureBoot2023CertificateStatus = $secureBoot2023Status
        secureBoot2023Error = $secureBoot2023Error
        secureBootRelatedEvents = $secureBootEvents
        tpm = $tpm
        bitLockerVolumes = $bitlocker
        defender = $defender
        executionPolicy = $executionPolicy
        winHttpProxy = $proxy
    }
    recovery = [ordered]@{
        windowsRE = $winReInfo
        bitLockerVolumes = $bitlocker
        note = 'Inventory only. The suite does not modify BitLocker, Windows RE, boot configuration or recovery partitions.'
    }
    updates = $hotfixes
    deviceProblems = $devices
    autoServicesNotRunning = $services
    startupItems = $startup
    recentCriticalAndErrorEvents = $recentEvents
    environment = [ordered]@{
        temp = $env:TEMP
        tmp = $env:TMP
        machinePathLength = if ($envPathMachine) { $envPathMachine.Length } else { 0 }
        userPathLength = if ($envPathUser) { $envPathUser.Length } else { 0 }
        processorArchitecture = $env:PROCESSOR_ARCHITECTURE
    }
}

$dir = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$inventory | ConvertTo-Json -Depth 14 | Set-Content $OutputPath -Encoding UTF8

$cpuName = if ($cpu.Count -gt 0) { [string]$cpu[0].Name } else { 'Unknown' }
Write-Host "DEVICE INVENTORY" -ForegroundColor Cyan
Write-Host "Computer : $($inventory.computer.manufacturer) $($inventory.computer.model)"
Write-Host "Windows  : $($inventory.windows.caption) build $($inventory.windows.fullBuild) $($inventory.windows.architecture)"
Write-Host "CPU      : $cpuName"
Write-Host "Memory   : $($inventory.computer.totalMemoryGB) GB"
Write-Host "Volumes  : $($volumes.Count)"
Write-Host "Device problems: $($devices.Count)"
Write-Host "Auto services not running: $($services.Count)"
Write-Host "Recent critical/error events: $($recentEvents.Count)"
if ($secureBoot -eq $true) {
    Write-Host "Secure Boot 2023 status: $(if($secureBoot2023Status){$secureBoot2023Status}else{'Not reported'})"
}
Write-Host "Inventory JSON: $OutputPath"

if (-not $SummaryOnly) {
    Write-Host "`nNETWORK" -ForegroundColor Cyan
    foreach ($n in $network) {
        Write-Host ("{0}: IPv4={1} Gateway={2} DNS={3}" -f $n.InterfaceAlias,($n.IPv4 -join ','),($n.IPv4Gateway -join ','),($n.DnsServers -join ','))
    }
    Write-Host "`nSTORAGE" -ForegroundColor Cyan
    foreach ($v in $inventory.volumes) {
        Write-Host ("{0}: {1} GB free / {2} GB ({3})" -f $v.DriveLetter,$v.FreeGB,$v.SizeGB,$v.HealthStatus)
    }
}

exit 0
