param(
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$InstallTesseract,
    [switch]$InstallSqlServerExpress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SuccessCode([int]$Code) {
    return $Code -in 0,1638,3010
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-NativeComponents.ps1 must run as Administrator.'
}

$Manifest = Get-Content (Join-Path $BundleRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$MicrosoftDir = Join-Path $BundleRoot 'payload\installers\microsoft'

Write-Step 'Installing Microsoft Visual C++ runtime from local bundle'
$VcRedist = Join-Path $MicrosoftDir $Manifest.microsoft.visualCppRuntime.file
if (-not (Test-Path $VcRedist)) { throw "Missing Visual C++ runtime: $VcRedist" }
$Proc = Start-Process -FilePath $VcRedist -ArgumentList @('/install','/quiet','/norestart') -Wait -PassThru
if (-not (Test-SuccessCode $Proc.ExitCode)) { throw "Visual C++ runtime failed with exit code $($Proc.ExitCode)" }

Write-Step 'Installing Microsoft ODBC Driver for SQL Server from local bundle'
$OdbcMsi = Join-Path $MicrosoftDir $Manifest.microsoft.sqlOdbc.file
if (-not (Test-Path $OdbcMsi)) { throw "Missing SQL ODBC driver: $OdbcMsi" }
$OdbcArgs = @('/i',"`"$OdbcMsi`"",'IACCEPTMSODBCSQLLICENSETERMS=YES','ADDLOCAL=ALL','/qn','/norestart')
$Proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $OdbcArgs -Wait -PassThru
if ($Proc.ExitCode -notin 0,3010) { throw "SQL ODBC driver failed with exit code $($Proc.ExitCode)" }

if ($InstallTesseract) {
    $TesseractInstaller = Join-Path $BundleRoot $Manifest.ocr.tesseract.offlineInstallerRelativePath
    if (-not (Test-Path $TesseractInstaller)) {
        throw "Tesseract was selected but approved offline media is missing: $TesseractInstaller"
    }

    Write-Step 'Installing selected Tesseract OCR component from local bundle'
    $Proc = Start-Process -FilePath $TesseractInstaller -ArgumentList '/S' -Wait -PassThru
    if ($Proc.ExitCode -notin 0,3010) { throw "Tesseract installer failed with exit code $($Proc.ExitCode)" }

    $TesseractRoot = Join-Path $env:ProgramFiles 'Tesseract-OCR'
    $TessdataSource = Join-Path (Split-Path $TesseractInstaller -Parent) 'tessdata'
    $TessdataTarget = Join-Path $TesseractRoot 'tessdata'
    if ((Test-Path $TesseractRoot) -and (Test-Path $TessdataSource)) {
        New-Item -ItemType Directory -Force -Path $TessdataTarget | Out-Null
        Copy-Item (Join-Path $TessdataSource '*.traineddata') $TessdataTarget -Force
        $MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
        if (($MachinePath -split ';') -notcontains $TesseractRoot) {
            [Environment]::SetEnvironmentVariable('Path', ($MachinePath.TrimEnd(';') + ';' + $TesseractRoot), 'Machine')
        }
    }
} else {
    Write-Host 'Tesseract not selected; skipping native OCR engine.' -ForegroundColor DarkGray
}

if ($InstallSqlServerExpress) {
    $SqlMedia = Join-Path $BundleRoot $Manifest.microsoft.sqlServerExpress.offlineMediaRelativePath
    $SqlSetup = Join-Path $SqlMedia $Manifest.microsoft.sqlServerExpress.requiredSetupFile
    $SqlService = Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue

    if ($SqlService) {
        Write-Host 'SQL Server Express instance already exists; skipping installation.' -ForegroundColor Yellow
    } elseif (Test-Path $SqlSetup) {
        Write-Step 'Installing selected SQL Server Express from complete local media'
        $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $SqlArgs = @(
            '/Q',
            '/ACTION=Install',
            '/FEATURES=SQLEngine',
            '/INSTANCENAME=SQLEXPRESS',
            "/SQLSYSADMINACCOUNTS=`"$CurrentIdentity`"",
            '/SQLSVCSTARTUPTYPE=Automatic',
            '/TCPENABLED=1',
            '/NPENABLED=0',
            '/UpdateEnabled=False',
            '/IACCEPTSQLSERVERLICENSETERMS',
            '/SUPPRESSPRIVACYSTATEMENTNOTICE'
        )
        $Proc = Start-Process -FilePath $SqlSetup -ArgumentList $SqlArgs -Wait -PassThru
        if ($Proc.ExitCode -notin 0,3010) {
            throw "SQL Server Express setup failed with exit code $($Proc.ExitCode). Check SQL Server Setup Bootstrap logs."
        }
    } else {
        throw "SQL Server Express was selected but complete offline media is missing: $SqlSetup"
    }
} else {
    Write-Host 'SQL Server Express not selected; DuckDB, SQLite and SQL client support remain available.' -ForegroundColor DarkGray
}

Write-Host '`nSelected native components installed successfully.' -ForegroundColor Green
