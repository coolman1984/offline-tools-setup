param(
    [Parameter(Mandatory=$true)][string]$BundleRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$SourceRoot = Join-Path $RepoRoot 'desktop-ui'
$WorkRoot = Join-Path $RepoRoot 'work\pyside6-desktop-ui'
$BuildSource = Join-Path $WorkRoot 'source'
$VenvRoot = Join-Path $WorkRoot 'venv'
$BootstrapRoot = Join-Path $BundleRoot 'payload\bootstrap'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

if (-not (Test-Path (Join-Path $SourceRoot 'main.py'))) { throw 'PySide6 desktop UI source is missing.' }
if (-not (Test-Path (Join-Path $SourceRoot 'qml\Main.qml'))) { throw 'PySide6 QML interface is missing.' }

$PythonExe = $null
$PythonPrefix = @()
foreach ($candidate in @('python.exe','python','py.exe','py')) {
    $resolved = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source -ErrorAction SilentlyContinue
    if (-not $resolved) { continue }
    try {
        if ($candidate -like 'py*') {
            $version = & $resolved -3.13 -c "import sys; print('.'.join(map(str,sys.version_info[:2])))" 2>$null
            if ($LASTEXITCODE -eq 0) { $PythonExe = $resolved; $PythonPrefix = @('-3.13'); break }
        } else {
            $version = & $resolved -c "import sys; print('.'.join(map(str,sys.version_info[:2])))" 2>$null
            if ($LASTEXITCODE -eq 0) { $PythonExe = $resolved; $PythonPrefix = @(); break }
        }
    } catch {}
}
if (-not $PythonExe) { throw 'Python 3.11+ is required on the connected builder to compile the PySide6 desktop UI.' }

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $WorkRoot,$BuildSource,$BootstrapRoot | Out-Null
Copy-Item (Join-Path $SourceRoot '*') $BuildSource -Recurse -Force

Write-Step 'Creating isolated PySide6 build environment'
& $PythonExe @PythonPrefix -m venv $VenvRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not create the PySide6 build environment.' }
$VenvPython = Join-Path $VenvRoot 'Scripts\python.exe'
& $VenvPython -m pip install --disable-pip-version-check --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare pip in the PySide6 build environment.' }
& $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $BuildSource 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'PySide6 build dependencies could not be installed.' }

$Deploy = Join-Path $VenvRoot 'Scripts\pyside6-deploy.exe'
if (-not (Test-Path $Deploy)) { throw 'pyside6-deploy was not installed with PySide6.' }

Write-Step 'Compiling the Fluent PySide6/QML desktop interface'
Push-Location $BuildSource
try {
    & $Deploy 'main.py' -f --name 'OfflineToolsDesktop' --extra-modules 'Quick,Qml,QuickControls2'
    if ($LASTEXITCODE -ne 0) { throw 'pyside6-deploy failed.' }
} finally {
    Pop-Location
}

$DesktopExe = Get-ChildItem $BuildSource -Filter 'OfflineToolsDesktop.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $DesktopExe) { throw 'Compiled OfflineToolsDesktop.exe was not found after deployment.' }
if ($DesktopExe.Length -lt 1MB) { throw "Compiled desktop executable is unexpectedly small: $($DesktopExe.Length) bytes" }

Copy-Item $DesktopExe.FullName (Join-Path $BootstrapRoot 'OfflineToolsDesktop.exe') -Force

[pscustomobject]@{
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    ui = 'PySide6 + Qt Quick/QML'
    style = 'FluentWinUI3 Light'
    deployment = 'pyside6-deploy onefile'
    executable = 'OfflineToolsDesktop.exe'
    sourceProject = 'desktop-ui/pyproject.toml'
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $BootstrapRoot 'desktop-ui-build-info.json') -Encoding UTF8

Write-Host "Fluent desktop UI ready: $(Join-Path $BootstrapRoot 'OfflineToolsDesktop.exe')" -ForegroundColor Green
