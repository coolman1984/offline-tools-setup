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
$BundleScriptsRoot = Join-Path $BundleRoot 'scripts'
$ToolManifest = Get-Content (Join-Path $RepoRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$RequiredSdk = [string]$ToolManifest.microsoft.dotnetSdk.version

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $WorkRoot,$SdkRoot,$PublishRoot,$BootstrapRoot,$BundleScriptsRoot | Out-Null

$Dotnet = $null
$SystemDotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
if ($SystemDotnet) {
    try {
        $Sdks = @(& $SystemDotnet --list-sdks 2>$null)
        if ($Sdks | Where-Object { $_ -match ('^' + [regex]::Escape($RequiredSdk) + '\s') }) {
            $Dotnet = $SystemDotnet
        }
    } catch {}
}

if (-not $Dotnet) {
    Write-Step "Preparing deterministic temporary .NET SDK $RequiredSdk for setup UI build"
    $InstallScript = Join-Path $WorkRoot 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $InstallScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -Version $RequiredSdk -InstallDir $SdkRoot -NoPath
    if ($LASTEXITCODE -ne 0) { throw ".NET SDK $RequiredSdk bootstrap failed." }
    $Dotnet = Join-Path $SdkRoot 'dotnet.exe'
}

if (-not (Test-Path $Dotnet)) { throw "dotnet executable was not found: $Dotnet" }
$ActualSdk = (& $Dotnet --version).Trim()
if ($ActualSdk -ne $RequiredSdk) { throw "Setup UI SDK mismatch. Required $RequiredSdk, resolved $ActualSdk." }

Write-Step 'Restoring pinned setup UI dependencies'
& $Dotnet restore $Project
if ($LASTEXITCODE -ne 0) { throw 'Setup UI restore failed.' }

Write-Step 'Publishing Windows x64 self-contained single-file setup UI'
& $Dotnet publish $Project -c Release -r win-x64 --self-contained true -o $PublishRoot -p:PublishSingleFile=true -p:PublishTrimmed=false --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Setup UI publish failed.' }

$Exe = Join-Path $PublishRoot 'OfflineToolsSetup.exe'
if (-not (Test-Path $Exe)) { throw 'Published setup UI executable was not found.' }
Copy-Item $Exe (Join-Path $BootstrapRoot 'OfflineToolsSetup.exe') -Force

Write-Step 'Including target-side compatibility diagnostic tools'
foreach ($Diagnostic in @('Test-OfficeAutomationHealth.ps1','Test-LegacyWindowsRuntimeReadiness.ps1')) {
    $Source = Join-Path $RepoRoot ('scripts\' + $Diagnostic)
    if (-not (Test-Path $Source)) { throw "Required compatibility diagnostic is missing: $Diagnostic" }
    Copy-Item $Source (Join-Path $BundleScriptsRoot $Diagnostic) -Force
}

[pscustomobject]@{
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    dotnetSdk = $ActualSdk
    runtimeIdentifier = 'win-x64'
    selfContained = $true
    singleFile = $true
} | ConvertTo-Json | Set-Content (Join-Path $BootstrapRoot 'build-info.json') -Encoding UTF8

Write-Host "Professional setup UI ready: $(Join-Path $BootstrapRoot 'OfflineToolsSetup.exe')" -ForegroundColor Green
Write-Host "Pinned build SDK: $ActualSdk" -ForegroundColor Green
