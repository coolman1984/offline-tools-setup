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
$SetupPublishRoot = Join-Path $WorkRoot 'publish-setup'
$ShellPublishRoot = Join-Path $WorkRoot 'publish-shell'
$SetupProject = Join-Path $RepoRoot 'installer-ui\OfflineToolsSetup.csproj'
$ShellProject = Join-Path $RepoRoot 'suite-shell\OfflineToolsSuite.csproj'
$BootstrapRoot = Join-Path $BundleRoot 'payload\bootstrap'
$BundleScriptsRoot = Join-Path $BundleRoot 'scripts'
$ToolManifest = Get-Content (Join-Path $RepoRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$RequiredSdk = [string]$ToolManifest.microsoft.dotnetSdk.version

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $WorkRoot,$SdkRoot,$SetupPublishRoot,$ShellPublishRoot,$BootstrapRoot,$BundleScriptsRoot | Out-Null

$Dotnet = $null
$SystemDotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
if ($SystemDotnet) {
    try {
        $Sdks = @(& $SystemDotnet --list-sdks 2>$null)
        if ($Sdks | Where-Object { $_ -match ('^' + [regex]::Escape($RequiredSdk) + '\s') }) { $Dotnet = $SystemDotnet }
    } catch {}
}

if (-not $Dotnet) {
    Write-Step "Preparing deterministic temporary .NET SDK $RequiredSdk for UI build"
    $InstallScript = Join-Path $WorkRoot 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $InstallScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -Version $RequiredSdk -InstallDir $SdkRoot -NoPath
    if ($LASTEXITCODE -ne 0) { throw ".NET SDK $RequiredSdk bootstrap failed." }
    $Dotnet = Join-Path $SdkRoot 'dotnet.exe'
}

if (-not (Test-Path $Dotnet)) { throw "dotnet executable was not found: $Dotnet" }
$ActualSdk = (& $Dotnet --version).Trim()
if ($ActualSdk -ne $RequiredSdk) { throw "UI SDK mismatch. Required $RequiredSdk, resolved $ActualSdk." }

foreach ($Project in @($SetupProject,$ShellProject)) {
    Write-Step "Restoring pinned dependencies: $(Split-Path $Project -Leaf)"
    & $Dotnet restore $Project
    if ($LASTEXITCODE -ne 0) { throw "Restore failed: $Project" }
}

Write-Step 'Publishing Windows x64 self-contained setup engine'
& $Dotnet publish $SetupProject -c Release -r win-x64 --self-contained true -o $SetupPublishRoot -p:PublishSingleFile=true -p:PublishTrimmed=false --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Setup UI publish failed.' }
$SetupExe = Join-Path $SetupPublishRoot 'OfflineToolsSetup.exe'
if (-not (Test-Path $SetupExe)) { throw 'Published setup executable was not found.' }
Copy-Item $SetupExe (Join-Path $BootstrapRoot 'OfflineToolsSetup.exe') -Force

Write-Step 'Publishing Windows x64 self-contained tabbed suite shell'
& $Dotnet publish $ShellProject -c Release -r win-x64 --self-contained true -o $ShellPublishRoot -p:PublishSingleFile=true -p:PublishTrimmed=false --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Suite shell publish failed.' }
$ShellExe = Join-Path $ShellPublishRoot 'OfflineToolsSuite.exe'
if (-not (Test-Path $ShellExe)) { throw 'Published suite shell executable was not found.' }
Copy-Item $ShellExe (Join-Path $BootstrapRoot 'OfflineToolsSuite.exe') -Force

Write-Step 'Including target-side diagnostic and Windows Care tools'
foreach ($Diagnostic in @(
    'Test-OfficeAutomationHealth.ps1','Test-LegacyWindowsRuntimeReadiness.ps1',
    'Get-DeviceInventory.ps1','Invoke-SafeWindowsCare.ps1'
)) {
    $Source = Join-Path $RepoRoot ('scripts\' + $Diagnostic)
    if (-not (Test-Path $Source)) { throw "Required target tool is missing: $Diagnostic" }
    Copy-Item $Source (Join-Path $BundleScriptsRoot $Diagnostic) -Force
}

[pscustomobject]@{
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    dotnetSdk = $ActualSdk
    runtimeIdentifier = 'win-x64'
    selfContained = $true
    singleFile = $true
    launcher = 'OfflineToolsSuite.exe'
    setupEngine = 'OfflineToolsSetup.exe'
} | ConvertTo-Json | Set-Content (Join-Path $BootstrapRoot 'build-info.json') -Encoding UTF8

Write-Host "Tabbed suite shell ready: $(Join-Path $BootstrapRoot 'OfflineToolsSuite.exe')" -ForegroundColor Green
Write-Host "Professional setup engine ready: $(Join-Path $BootstrapRoot 'OfflineToolsSetup.exe')" -ForegroundColor Green
Write-Host "Pinned build SDK: $ActualSdk" -ForegroundColor Green
