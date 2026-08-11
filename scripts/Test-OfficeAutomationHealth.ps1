param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-OfficeClickToRun {
    $views = @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)
    foreach ($view in $views) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\Office\ClickToRun\Configuration')
            if ($key) {
                $platform = [string]$key.GetValue('Platform')
                $version = [string]$key.GetValue('VersionToReport')
                $products = [string]$key.GetValue('ProductReleaseIds')
                $path = [string]$key.GetValue('InstallationPath')
                $key.Dispose(); $base.Dispose()
                if ($platform -or $version -or $products) {
                    return [pscustomobject]@{ installed=$true; platform=$platform; version=$version; products=$products; installationPath=$path; registryView=[string]$view }
                }
            }
            $base.Dispose()
        } catch {}
    }
    return [pscustomobject]@{ installed=$false; platform=''; version=''; products=''; installationPath=''; registryView='' }
}

function Invoke-ComProbe([string]$PowerShellExe,[string]$ProgId) {
    if (-not (Test-Path $PowerShellExe)) { return [pscustomobject]@{ available=$false; success=$false; error='PowerShell host not found' } }
    $code = "`$app=`$null; try { `$app=New-Object -ComObject '$ProgId' -ErrorAction Stop; `$app.Visible=`$false; if (`$app.PSObject.Properties.Name -contains 'DisplayAlerts') { `$app.DisplayAlerts=`$false }; exit 0 } catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 9 } finally { if (`$app) { try { `$app.Quit() } catch {} } }"
    $outFile = Join-Path $env:TEMP (([guid]::NewGuid().ToString('N'))+'.out.txt')
    $errFile = Join-Path $env:TEMP (([guid]::NewGuid().ToString('N'))+'.err.txt')
    try {
        $proc = Start-Process -FilePath $PowerShellExe -ArgumentList @('-NoProfile','-NonInteractive','-Command',$code) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (-not $proc.WaitForExit($TimeoutSeconds*1000)) {
            try { $proc.Kill() } catch {}
            return [pscustomobject]@{ available=$true; success=$false; error="Timed out after $TimeoutSeconds seconds" }
        }
        $errorText = if (Test-Path $errFile) { (Get-Content $errFile -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
        return [pscustomobject]@{ available=$true; success=($proc.ExitCode -eq 0); error=$errorText; exitCode=$proc.ExitCode }
    } finally {
        Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
    }
}

$office = Read-OfficeClickToRun
$x64PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$x86PowerShell = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
$x64Excel = if ($office.installed) { Invoke-ComProbe $x64PowerShell 'Excel.Application' } else { $null }
$x86Excel = if ($office.installed) { Invoke-ComProbe $x86PowerShell 'Excel.Application' } else { $null }

$managedPythonArchitecture = if ([Environment]::Is64BitOperatingSystem) { 'x64-managed-python' } else { 'x86-managed-python' }
$warnings = New-Object System.Collections.Generic.List[string]
if ($office.installed -and $office.platform -eq 'x86') {
    $warnings.Add('32-bit Office detected on 64-bit Windows. File-level automation is unaffected; COM automation is validated separately because process-bitness and old registrations can matter.')
}
if ($office.installed -and $x64Excel -and -not $x64Excel.success) {
    $warnings.Add('64-bit Excel COM probe failed. Office may need repair or TypeLib remediation, especially after a 32-bit to 64-bit Office migration.')
}
if ($office.installed -and $x86Excel -and -not $x86Excel.success) {
    $warnings.Add('32-bit Excel COM probe failed. Check Office installation/registration before relying on COM automation.')
}

$StateRoot = Join-Path $InstallRoot 'state'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$report = [pscustomobject]@{
    generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    office=$office
    managedPythonArchitecture=$managedPythonArchitecture
    excelCom=[pscustomobject]@{ x64Host=$x64Excel; x86Host=$x86Excel }
    warnings=@($warnings)
    automaticRegistryDeletionPerformed=$false
    remediationNote='If COM fails after Office architecture migration, use Microsoft Office TypeLib remediation guidance or Office repair. This tool does not blindly delete registry keys.'
}
$path = Join-Path $StateRoot 'office-automation-health.json'
$report | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding UTF8

Write-Host "Office automation health report: $path"
foreach ($warning in $warnings) { Write-Warning $warning }
exit 0
