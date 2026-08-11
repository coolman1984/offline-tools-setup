param(
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$InstallRoot = 'C:\OfflineTools',
    [switch]$InstallTesseract,
    [switch]$InstallSqlServerExpress,
    [switch]$InstallWebView2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Set-RebootRequired([string]$Reason) {
    $StateRoot = Join-Path $InstallRoot 'state'
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    [pscustomobject]@{ required=$true; reason=$Reason; recordedAtUtc=[DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content (Join-Path $StateRoot 'reboot-required.json') -Encoding UTF8
}
function Invoke-Installer {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][object[]]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [int[]]$SuccessCodes = @(0,1638,1641,3010),
        [int]$BusyRetries = 12,
        [int]$BusyDelaySeconds = 15
    )
    for ($Attempt=0; $Attempt -le $BusyRetries; $Attempt++) {
        $Proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru
        $Code = $Proc.ExitCode
        if ($SuccessCodes -contains $Code) {
            if ($Code -in 1641,3010) { Set-RebootRequired "$DisplayName returned $Code" }
            return $Code
        }
        if ($Code -eq 1618 -and $Attempt -lt $BusyRetries) {
            Write-Warning "$DisplayName is waiting for another Windows Installer transaction. Retry $($Attempt + 1)/$BusyRetries."
            Start-Sleep -Seconds $BusyDelaySeconds
            continue
        }
        throw "$DisplayName failed with exit code $Code"
    }
    throw "$DisplayName could not start because Windows Installer remained busy."
}

if (-not (Test-IsAdministrator)) { throw 'Install-NativeComponents.ps1 must run as Administrator.' }
$Manifest = Get-Content (Join-Path $BundleRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$MicrosoftDir = Join-Path $BundleRoot 'payload\installers\microsoft'
$BinRoot = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force -Path $BinRoot | Out-Null

Write-Step 'Installing Microsoft Visual C++ runtimes for x64 and x86 application compatibility'
foreach ($Runtime in @($Manifest.microsoft.visualCppRuntimes)) {
    $VcRedist = Join-Path $MicrosoftDir ([string]$Runtime.file)
    if (-not (Test-Path $VcRedist)) { throw "Missing Visual C++ runtime: $VcRedist" }
    Invoke-Installer -FilePath $VcRedist -ArgumentList @('/install','/quiet','/norestart') -DisplayName ("Microsoft Visual C++ Runtime " + [string]$Runtime.architecture) | Out-Null
}

Write-Step 'Installing Microsoft ODBC Driver for SQL Server from local bundle'
$OdbcMsi = Join-Path $MicrosoftDir ([string]$Manifest.microsoft.sqlOdbc.file)
if (-not (Test-Path $OdbcMsi)) { throw "Missing SQL ODBC driver: $OdbcMsi" }
$OdbcArgs = @('/i',"`"$OdbcMsi`"",'IACCEPTMSODBCSQLLICENSETERMS=YES','ADDLOCAL=ALL','/qn','/norestart')
Invoke-Installer -FilePath 'msiexec.exe' -ArgumentList $OdbcArgs -DisplayName 'Microsoft SQL Server ODBC Driver' | Out-Null

if ($InstallTesseract) {
    $TesseractInstaller = Join-Path $BundleRoot ([string]$Manifest.ocr.tesseract.offlineInstallerRelativePath)
    if (-not (Test-Path $TesseractInstaller)) { throw "Tesseract was selected but approved offline media is missing: $TesseractInstaller" }
    Write-Step 'Installing selected Tesseract OCR component from local bundle'
    Invoke-Installer -FilePath $TesseractInstaller -ArgumentList @('/S') -DisplayName 'Tesseract OCR' -SuccessCodes @(0,1641,3010) -BusyRetries 2 -BusyDelaySeconds 10 | Out-Null
    $TesseractRoot = Join-Path $env:ProgramFiles 'Tesseract-OCR'
    $TessdataSource = Join-Path (Split-Path $TesseractInstaller -Parent) 'tessdata'
    $TessdataTarget = Join-Path $TesseractRoot 'tessdata'
    if ((Test-Path $TesseractRoot) -and (Test-Path $TessdataSource)) {
        New-Item -ItemType Directory -Force -Path $TessdataTarget | Out-Null
        Copy-Item (Join-Path $TessdataSource '*.traineddata') $TessdataTarget -Force
        $TesseractExe = Join-Path $TesseractRoot 'tesseract.exe'
        if (Test-Path $TesseractExe) {
            "@echo off`r`n`"$TesseractExe`" %*`r`n" | Set-Content (Join-Path $BinRoot 'tesseract-ots.cmd') -Encoding ASCII
        }
    }
}

if ($InstallWebView2) {
    $WebView2Installer = Join-Path $BundleRoot ([string]$Manifest.microsoft.webView2.offlineInstallerRelativePath)
    if (-not (Test-Path $WebView2Installer)) { throw "WebView2 was selected but the offline standalone installer is missing: $WebView2Installer" }
    Write-Step 'Installing Microsoft WebView2 Runtime from offline standalone media'
    Invoke-Installer -FilePath $WebView2Installer -ArgumentList @('/silent','/install') -DisplayName 'Microsoft WebView2 Runtime' -SuccessCodes @(0,1641,3010) -BusyRetries 4 -BusyDelaySeconds 15 | Out-Null
}

if ($InstallSqlServerExpress) {
    $SqlMedia = Join-Path $BundleRoot ([string]$Manifest.microsoft.sqlServerExpress.offlineMediaRelativePath)
    $SqlSetup = Join-Path $SqlMedia ([string]$Manifest.microsoft.sqlServerExpress.requiredSetupFile)
    $SqlService = Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
    if ($SqlService) {
        Write-Host 'SQL Server Express instance already exists; preserving it.' -ForegroundColor Yellow
    } elseif (Test-Path $SqlSetup) {
        Write-Step 'Installing selected SQL Server Express from complete local media'
        $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $SqlArgs = @(
            '/Q','/ACTION=Install','/FEATURES=SQLEngine','/INSTANCENAME=SQLEXPRESS',
            "/SQLSYSADMINACCOUNTS=`"$CurrentIdentity`"",'/SQLSVCSTARTUPTYPE=Automatic',
            '/TCPENABLED=1','/NPENABLED=0','/UpdateEnabled=False',
            '/IACCEPTSQLSERVERLICENSETERMS','/SUPPRESSPRIVACYSTATEMENTNOTICE'
        )
        Invoke-Installer -FilePath $SqlSetup -ArgumentList $SqlArgs -DisplayName 'SQL Server Express' -SuccessCodes @(0,1641,3010) -BusyRetries 4 -BusyDelaySeconds 20 | Out-Null
    } else {
        throw "SQL Server Express was selected but complete offline media is missing: $SqlSetup"
    }
}

Write-Host '`nSelected native components installed successfully.' -ForegroundColor Green
