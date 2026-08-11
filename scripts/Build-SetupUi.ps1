param(
    [Parameter(Mandatory=$true)][string]$BundleRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$WorkRoot = Join-Path $RepoRoot 'work\setup-ui'
$SdkRoot = Join-Path $WorkRoot 'dotnet'
$PublishRoot = Join-Path $WorkRoot 'publish'
$Project = Join-Path $RepoRoot 'installer-ui\OfflineToolsSetup.csproj'
$BootstrapRoot = Join-Path $BundleRoot 'payload\bootstrap'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $WorkRoot,$SdkRoot,$PublishRoot,$BootstrapRoot | Out-Null

$Dotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
$NeedsSdk = $true
if ($Dotnet) {
    try {
        $Major = [int]((& $Dotnet --version).Split('.')[0])
        if ($Major -ge 10) { $NeedsSdk = $false }
    } catch {}
}

if ($NeedsSdk) {
    Write-Step 'Preparing temporary .NET 10 SDK for setup UI build'
    $InstallScript = Join-Path $WorkRoot 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $InstallScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -Channel '10.0' -InstallDir $SdkRoot -NoPath
    if ($LASTEXITCODE -ne 0) { throw '.NET 10 SDK bootstrap failed.' }
    $Dotnet = Join-Path $SdkRoot 'dotnet.exe'
}

if (-not (Test-Path $Dotnet)) { throw "dotnet executable was not found: $Dotnet" }

Write-Step 'Restoring pinned setup UI dependencies'
& $Dotnet restore $Project
if ($LASTEXITCODE -ne 0) { throw 'Setup UI restore failed.' }

Write-Step 'Publishing Windows x64 self-contained single-file setup UI'
& $Dotnet publish $Project -c Release -r win-x64 --self-contained true -o $PublishRoot -p:PublishSingleFile=true -p:PublishTrimmed=false
if ($LASTEXITCODE -ne 0) { throw 'Setup UI publish failed.' }

$Exe = Join-Path $PublishRoot 'OfflineToolsSetup.exe'
if (-not (Test-Path $Exe)) { throw 'Published setup UI executable was not found.' }
Copy-Item $Exe (Join-Path $BootstrapRoot 'OfflineToolsSetup.exe') -Force

Write-Host "Professional setup UI ready: $(Join-Path $BootstrapRoot 'OfflineToolsSetup.exe')" -ForegroundColor Green
