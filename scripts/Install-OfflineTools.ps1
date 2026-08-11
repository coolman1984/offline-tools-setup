param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [string[]]$PackageProfiles = @('core','office','pdf','ocr','data-database','web-python','quality')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Manifest = Get-Content (Join-Path $BundleRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'This installer only supports Windows.' -ForegroundColor Red
    exit 2
}

if ([Environment]::Is64BitOperatingSystem -ne $true) {
    Write-Host 'This bundle currently supports Windows x64 only.' -ForegroundColor Red
    exit 3
}

$OsCaption = (Get-CimInstance Win32_OperatingSystem).Caption
if ($OsCaption -notmatch 'Windows 10|Windows 11') {
    Write-Host "Unsupported operating system: $OsCaption" -ForegroundColor Red
    exit 4
}

if (-not (Test-IsAdministrator)) {
    Write-Host 'Requesting administrator rights...'
    $Args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-InstallRoot',"`"$InstallRoot`"")
    Start-Process powershell.exe -Verb RunAs -ArgumentList $Args
    exit 0
}

$LogDir = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $LogFile -Force | Out-Null

function Stop-WithError([string]$Message, [int]$Code = 1) {
    Write-Host $Message -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit $Code
}

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

Write-Step 'Verifying offline bundle integrity before installation'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Verify-OfflineBundle.ps1') -BundleRoot $BundleRoot
if ($LASTEXITCODE -ne 0) {
    Stop-WithError 'Bundle verification failed. Nothing will be installed.' 20
}

$env:PIP_NO_INDEX = '1'
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
$env:PIP_DEFAULT_TIMEOUT = '1'
$env:npm_config_offline = 'true'
$env:npm_config_audit = 'false'
$env:npm_config_fund = 'false'

$PythonRoot = Join-Path $InstallRoot 'Python'
$EnvRoot = Join-Path $InstallRoot 'envs'
$BinRoot = Join-Path $InstallRoot 'bin'
$NpmCacheRoot = Join-Path $InstallRoot 'npm-cache'
New-Item -ItemType Directory -Force -Path $PythonRoot,$EnvRoot,$BinRoot,$NpmCacheRoot | Out-Null

Write-Step 'Installing Python runtimes side-by-side'
foreach ($Python in $Manifest.python.versions) {
    $Version = $Python.version
    $TargetDir = Join-Path $PythonRoot $Version
    $PythonExe = Join-Path $TargetDir 'python.exe'
    $Installer = Join-Path $BundleRoot ("payload\installers\python\{0}" -f $Python.file)

    if (-not (Test-Path $PythonExe)) {
        if (-not (Test-Path $Installer)) { Stop-WithError "Missing Python installer: $Installer" 30 }
        Write-Host "Installing Python $Version"
        $Args = @(
            '/quiet',
            'InstallAllUsers=1',
            'PrependPath=0',
            'AppendPath=0',
            'Include_launcher=0',
            'Include_pip=1',
            'Include_test=0',
            'Include_doc=0',
            'AssociateFiles=0',
            'Shortcuts=0',
            "TargetDir=$TargetDir"
        )
        $Proc = Start-Process -FilePath $Installer -ArgumentList $Args -Wait -PassThru
        if ($Proc.ExitCode -notin 0,3010) {
            Stop-WithError "Python $Version installer failed with exit code $($Proc.ExitCode)" 31
        }
    } else {
        Write-Host "Python $Version already installed in managed location."
    }

    if (-not (Test-Path $PythonExe)) { Stop-WithError "Python $Version executable was not found after setup." 32 }

    $Parts = $Version.Split('.')
    $Short = "$($Parts[0])$($Parts[1])"
    "@echo off`r`n`"$PythonExe`" %*" | Set-Content (Join-Path $BinRoot "python$Short.cmd") -Encoding ASCII
    "@echo off`r`n`"$PythonExe`" -m pip %*" | Set-Content (Join-Path $BinRoot "pip$Short.cmd") -Encoding ASCII
}

Write-Step 'Creating managed Python environment'
$PrimaryVersion = $Manifest.python.primary
$PrimaryPython = Join-Path $PythonRoot "$PrimaryVersion\python.exe"
$PrimaryParts = $PrimaryVersion.Split('.')
$PrimaryTag = "py$($PrimaryParts[0])$($PrimaryParts[1])"
$Wheelhouse = Join-Path $BundleRoot "payload\wheelhouse\$PrimaryTag"
$FullEnv = Join-Path $EnvRoot "full-py$($PrimaryParts[0])$($PrimaryParts[1])"
$EnvPython = Join-Path $FullEnv 'Scripts\python.exe'

if (-not (Test-Path $Wheelhouse)) { Stop-WithError "Primary wheelhouse not found: $Wheelhouse" 40 }
if (-not (Test-Path $EnvPython)) {
    & $PrimaryPython -m venv $FullEnv
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Could not create primary virtual environment.' 41 }
}

$UniqueProfiles = @($PackageProfiles | Where-Object { $_ } | Select-Object -Unique)
if ($UniqueProfiles -notcontains 'core') { $UniqueProfiles = @('core') + $UniqueProfiles }

foreach ($Profile in $UniqueProfiles) {
    $RequirementsFile = Join-Path $BundleRoot ("requirements\profiles\{0}.txt" -f $Profile)
    if (-not (Test-Path $RequirementsFile)) { Stop-WithError "Unknown or missing Python package profile: $Profile" 42 }
    Write-Step "Installing offline Python profile: $Profile"
    & $EnvPython -m pip install --no-index --find-links $Wheelhouse -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) { Stop-WithError "Offline Python profile failed: $Profile" 43 }
}

"@echo off`r`n`"$EnvPython`" %*" | Set-Content (Join-Path $BinRoot 'python-full.cmd') -Encoding ASCII
"@echo off`r`n`"$EnvPython`" -m pip %*" | Set-Content (Join-Path $BinRoot 'pip-full.cmd') -Encoding ASCII

Write-Step 'Installing Node.js LTS from local media'
$NodeMsi = Join-Path $BundleRoot ("payload\installers\node\{0}" -f $Manifest.node.msiFile)
if (-not (Test-Path $NodeMsi)) { Stop-WithError "Missing Node.js installer: $NodeMsi" 50 }
$NodeExe = Join-Path $env:ProgramFiles 'nodejs\node.exe'
if (-not (Test-Path $NodeExe)) {
    $Proc = Start-Process msiexec.exe -ArgumentList @('/i',"`"$NodeMsi`"",'/qn','/norestart') -Wait -PassThru
    if ($Proc.ExitCode -notin 0,3010) { Stop-WithError "Node.js setup failed with exit code $($Proc.ExitCode)" 51 }
}
if (-not (Test-Path $NodeExe)) { Stop-WithError 'Node.js executable not found after setup.' 52 }

Write-Step 'Copying complete offline npm cache'
$BundleNpmCache = Join-Path $BundleRoot 'payload\npm-cache'
if (-not (Test-Path $BundleNpmCache)) { Stop-WithError 'Offline npm cache is missing.' 53 }
Copy-Item (Join-Path $BundleNpmCache '*') $NpmCacheRoot -Recurse -Force
$NpmCmd = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
"@echo off`r`nset npm_config_offline=true`r`nset npm_config_cache=$NpmCacheRoot`r`n`"$NpmCmd`" %*" | Set-Content (Join-Path $BinRoot 'npm-offline.cmd') -Encoding ASCII

Write-Step 'Adding managed command wrappers to machine PATH'
$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
if (-not $MachinePath) { $MachinePath = '' }
if (($MachinePath -split ';') -notcontains $BinRoot) {
    [Environment]::SetEnvironmentVariable('Path', ($MachinePath.TrimEnd(';') + ';' + $BinRoot).TrimStart(';'), 'Machine')
}

Write-Step 'Running profile-aware smoke tests'
$Imports = @('requests','pydantic')
if ($UniqueProfiles -contains 'office') { $Imports += @('openpyxl','win32com.client','docx','pptx') }
if ($UniqueProfiles -contains 'pdf') { $Imports += @('pypdf','fitz','pdfplumber') }
if ($UniqueProfiles -contains 'ocr') { $Imports += @('PIL','cv2') }
if ($UniqueProfiles -contains 'data-database') { $Imports += @('pandas','numpy','duckdb','sqlalchemy') }
if ($UniqueProfiles -contains 'web-python') { $Imports += @('fastapi','flask','django') }
$ImportStatement = ($Imports | Select-Object -Unique | ForEach-Object { "import $_" }) -join '; '
& $PrimaryPython --version
if ($LASTEXITCODE -ne 0) { Stop-WithError 'Primary Python smoke test failed.' 60 }
& $EnvPython -c "$ImportStatement; print('Selected Python profiles OK')"
if ($LASTEXITCODE -ne 0) { Stop-WithError 'Selected Python package smoke test failed.' 61 }
& $NodeExe --version
if ($LASTEXITCODE -ne 0) { Stop-WithError 'Node.js smoke test failed.' 62 }

$Summary = @"
Offline Tools Setup completed successfully.

Install root: $InstallRoot
Primary Python: $PrimaryVersion
Managed Python environment: $FullEnv
Python profiles: $($UniqueProfiles -join ', ')
Node.js: $($Manifest.node.version)
Offline npm cache: $NpmCacheRoot
Log: $LogFile

Commands available after opening a new terminal:
  python-full
  pip-full
  python311 / pip311
  python312 / pip312
  python313 / pip313
  python314 / pip314
  npm-offline
"@

Write-Host "`n$Summary" -ForegroundColor Green
$Summary | Set-Content (Join-Path $InstallRoot 'INSTALL-SUMMARY.txt') -Encoding UTF8
Stop-Transcript | Out-Null
exit 0
