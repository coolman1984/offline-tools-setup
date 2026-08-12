param(
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\offline-bundle'),
    [string]$NativeSourceDir = (Join-Path $PSScriptRoot '..\native-source'),
    [switch]$IncludeHeavyOcr,
    [switch]$CreateZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$Manifest = Get-Content (Join-Path $RepoRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Get-Sha256([string]$Path) { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-RelativeBundlePath([string]$Root,[string]$FullPath) {
    $NormalizedRoot = $Root.TrimEnd('\')
    return $FullPath.Substring($NormalizedRoot.Length).TrimStart('\').Replace('\','/')
}
function Get-RemoteFile([string]$Url,[string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    if (-not (Test-Path $Destination)) { throw "Download failed: $Url" }
}
function Assert-MicrosoftSignature([string]$Path) {
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Microsoft signature validation failed: $Path ($($sig.Status))"
    }
}

Write-Step 'Building core language/package bundle'
$CoreArgs = @('-OutputDir',$OutputDir)
if ($IncludeHeavyOcr) { $CoreArgs += '-IncludeHeavyOcr' }
& (Join-Path $PSScriptRoot 'Build-OfflineBundle.ps1') @CoreArgs
if ($LASTEXITCODE -ne 0) { throw "Core bundle builder failed with exit code $LASTEXITCODE" }
$HeavyOcrIncluded = $false
if ($IncludeHeavyOcr) {
    $HeavyOcrDirs = @(Get-ChildItem (Join-Path $OutputDir 'payload\wheelhouse') -Directory -Filter 'py*-ocr-heavy' -ErrorAction SilentlyContinue)
    $HeavyOcrFailures = @(Get-ChildItem (Join-Path $OutputDir 'payload\wheelhouse') -File -Filter '_missing-packages.txt' -Recurse -ErrorAction SilentlyContinue)
    if ($HeavyOcrDirs.Count -ne @($Manifest.python.versions).Count -or $HeavyOcrFailures.Count -gt 0) {
        throw 'Heavy OCR was requested, but one or more Python versions have an incomplete offline wheelhouse.'
    }
    $HeavyOcrIncluded = $true
}

Write-Step 'Adding Microsoft runtime prerequisites for both x64 and x86 applications'
$MicrosoftDir = Join-Path $OutputDir 'payload\installers\microsoft'
New-Item -ItemType Directory -Force -Path $MicrosoftDir | Out-Null
foreach ($runtime in @($Manifest.microsoft.visualCppRuntimes)) {
    $target = Join-Path $MicrosoftDir ([string]$runtime.file)
    Get-RemoteFile ([string]$runtime.url) $target
    Assert-MicrosoftSignature $target
}
$OdbcTarget = Join-Path $MicrosoftDir ([string]$Manifest.microsoft.sqlOdbc.file)
Get-RemoteFile ([string]$Manifest.microsoft.sqlOdbc.url) $OdbcTarget
Assert-MicrosoftSignature $OdbcTarget

Write-Step 'Adding .NET 10 LTS SDK for the optional native build profile'
$DotNetDir = Join-Path $OutputDir 'payload\installers\dotnet'
$DotNetTarget = Join-Path $DotNetDir ([string]$Manifest.microsoft.dotnetSdk.file)
Get-RemoteFile ([string]$Manifest.microsoft.dotnetSdk.url) $DotNetTarget
Assert-MicrosoftSignature $DotNetTarget

Write-Step 'Preparing local Node.js headers so node-gyp never downloads on target PCs'
$NodeInstallerDir = Join-Path $OutputDir 'payload\installers\node'
$HeadersArchive = Join-Path $NodeInstallerDir ([string]$Manifest.node.headersFile)
Get-RemoteFile ([string]$Manifest.node.headersUrl) $HeadersArchive
$Shasums = Join-Path $NodeInstallerDir 'SHASUMS256.txt'
$HeaderLine = Get-Content $Shasums | Where-Object { $_ -match ('\s' + [regex]::Escape([string]$Manifest.node.headersFile) + '$') } | Select-Object -First 1
if (-not $HeaderLine) { throw 'Node headers checksum was not found in SHASUMS256.txt.' }
$ExpectedHeaderHash = ($HeaderLine -split '\s+')[0].ToLowerInvariant()
if ((Get-Sha256 $HeadersArchive) -ne $ExpectedHeaderHash) { throw 'Node headers SHA-256 validation failed.' }
$HeaderWork = Join-Path $RepoRoot 'work\node-headers'
Remove-Item $HeaderWork -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $HeaderWork | Out-Null
$Tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if (-not $Tar) { throw 'tar.exe is required on the connected builder to unpack the official Node headers archive.' }
& $Tar.Source -xzf $HeadersArchive -C $HeaderWork
if ($LASTEXITCODE -ne 0) { throw 'Could not unpack Node.js headers.' }
$HeaderTop = Get-ChildItem $HeaderWork -Directory | Select-Object -First 1
if (-not $HeaderTop) { throw 'Node.js headers archive did not contain the expected directory.' }
$HeaderPayload = Join-Path $OutputDir 'payload\developer\node-headers'
Remove-Item $HeaderPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $HeaderPayload | Out-Null
Copy-Item (Join-Path $HeaderTop.FullName '*') $HeaderPayload -Recurse -Force

Write-Step 'Adding optional approved native and Windows repair media when supplied'
$SqlIncluded = $false
$TesseractIncluded = $false
$BuildToolsIncluded = $false
$WebView2Included = $false
$NetFx35SourceIncluded = $false
$WindowsRepairProfiles = @()

$SqlSource = Join-Path $NativeSourceDir 'sql-server-express'
$SqlDestination = Join-Path $OutputDir ([string]$Manifest.microsoft.sqlServerExpress.offlineMediaRelativePath)
if (Test-Path (Join-Path $SqlSource 'setup.exe')) {
    New-Item -ItemType Directory -Force -Path $SqlDestination | Out-Null
    Copy-Item (Join-Path $SqlSource '*') $SqlDestination -Recurse -Force
    $SqlIncluded = $true
}

$TesseractSource = Join-Path $NativeSourceDir 'tesseract\tesseract-installer.exe'
$TesseractDestinationDir = Join-Path $OutputDir 'payload\native\tesseract'
if (Test-Path $TesseractSource) {
    New-Item -ItemType Directory -Force -Path $TesseractDestinationDir | Out-Null
    Copy-Item $TesseractSource (Join-Path $TesseractDestinationDir 'tesseract-installer.exe') -Force
    $TessdataDir = Join-Path $TesseractDestinationDir 'tessdata'
    New-Item -ItemType Directory -Force -Path $TessdataDir | Out-Null
    Get-RemoteFile 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/eng.traineddata' (Join-Path $TessdataDir 'eng.traineddata')
    Get-RemoteFile 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/ara.traineddata' (Join-Path $TessdataDir 'ara.traineddata')
    $TesseractIncluded = $true
}

$BuildToolsSource = Join-Path $NativeSourceDir 'vs-build-tools'
$BuildToolsDestination = Join-Path $OutputDir ([string]$Manifest.microsoft.visualStudioBuildTools.offlineMediaRelativePath)
if (Test-Path (Join-Path $BuildToolsSource 'vs_BuildTools.exe')) {
    New-Item -ItemType Directory -Force -Path $BuildToolsDestination | Out-Null
    Copy-Item (Join-Path $BuildToolsSource '*') $BuildToolsDestination -Recurse -Force
    $BuildToolsIncluded = $true
}

$WebView2Source = Join-Path $NativeSourceDir 'webview2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
$WebView2Destination = Join-Path $OutputDir ([string]$Manifest.microsoft.webView2.offlineInstallerRelativePath)
if (Test-Path $WebView2Source) {
    New-Item -ItemType Directory -Force -Path (Split-Path $WebView2Destination -Parent) | Out-Null
    Copy-Item $WebView2Source $WebView2Destination -Force
    Assert-MicrosoftSignature $WebView2Destination
    $WebView2Included = $true
}

$NetFxSource = Join-Path $NativeSourceDir 'windows-sxs'
$NetFxDestination = Join-Path $OutputDir ([string]$Manifest.microsoft.netFramework35.windows10SourceRelativePath)
if (Test-Path $NetFxSource) {
    New-Item -ItemType Directory -Force -Path $NetFxDestination | Out-Null
    Copy-Item (Join-Path $NetFxSource '*') $NetFxDestination -Recurse -Force
    $NetFx35SourceIncluded = $true
}

# Windows repair source profiles must be prepared by Prepare-WindowsRepairSource.ps1.
# Each profile contains source-metadata.json plus an expanded Windows directory.
$WindowsRepairSource = Join-Path $NativeSourceDir 'windows-repair'
$WindowsRepairDestination = Join-Path $OutputDir 'payload\windows-repair'
if (Test-Path $WindowsRepairSource) {
    New-Item -ItemType Directory -Force -Path $WindowsRepairDestination | Out-Null
    foreach ($profileDir in Get-ChildItem $WindowsRepairSource -Directory -ErrorAction SilentlyContinue) {
        $metadataPath = Join-Path $profileDir.FullName 'source-metadata.json'
        $windowsDir = Join-Path $profileDir.FullName 'Windows'
        if (-not (Test-Path $metadataPath) -or -not (Test-Path (Join-Path $windowsDir 'System32'))) {
            Write-Warning "Skipping unverified Windows repair profile: $($profileDir.FullName)"
            continue
        }
        try {
            $meta = Get-Content $metadataPath -Raw | ConvertFrom-Json
            if ([int]$meta.build -le 0 -or [int]$meta.ubr -lt 0 -or -not $meta.architecture) { throw 'Invalid metadata' }
        } catch {
            Write-Warning "Skipping Windows repair profile with invalid metadata: $metadataPath"
            continue
        }
        $target = Join-Path $WindowsRepairDestination $profileDir.Name
        Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $profileDir.FullName $target -Recurse -Force
        $WindowsRepairProfiles += [pscustomobject]@{
            id = $profileDir.Name
            fullBuild = "$($meta.build).$($meta.ubr)"
            architecture = [string]$meta.architecture
            languages = @($meta.languages)
        }
        Write-Host "Included verified Windows repair profile: $($profileDir.Name)" -ForegroundColor Green
    }
}

Write-Step 'Building the complete offline developer stack'
& (Join-Path $PSScriptRoot 'Build-DeveloperStack.ps1') -BundleRoot $OutputDir
if ($LASTEXITCODE -ne 0) { throw "Developer stack builder failed with exit code $LASTEXITCODE" }

Write-Step 'Copying profile definitions, Windows Care policy and target scripts'
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir 'config'),(Join-Path $OutputDir 'requirements\profiles'),(Join-Path $OutputDir 'scripts') | Out-Null
Copy-Item (Join-Path $RepoRoot 'config\setup-profiles.json') (Join-Path $OutputDir 'config\setup-profiles.json') -Force
Copy-Item (Join-Path $RepoRoot 'config\windows-care.json') (Join-Path $OutputDir 'config\windows-care.json') -Force
Copy-Item (Join-Path $RepoRoot 'requirements\profiles\*.txt') (Join-Path $OutputDir 'requirements\profiles') -Force
foreach ($scriptName in @(
    'Install-NativeComponents.ps1','Install-AllOfflineTools.ps1','Install-DeveloperStack.ps1','Install-SelectedProfiles.ps1',
    'Invoke-EnvironmentHardening.ps1','Publish-ManagedLaunchers.ps1','Install-NativeBuildTools.ps1',
    'Get-DeviceInventory.ps1','Invoke-SafeWindowsCare.ps1','Test-OfficeAutomationHealth.ps1','Test-LegacyWindowsRuntimeReadiness.ps1'
)) {
    $source = Join-Path $RepoRoot ('scripts\' + $scriptName)
    if (Test-Path $source) { Copy-Item $source (Join-Path $OutputDir ('scripts\' + $scriptName)) -Force }
}
Copy-Item (Join-Path $RepoRoot 'START-HERE.cmd') (Join-Path $OutputDir 'START-HERE.cmd') -Force

Write-Step 'Building self-contained professional setup and tabbed suite interfaces'
& (Join-Path $PSScriptRoot 'Build-SetupUi.ps1') -BundleRoot $OutputDir
if ($LASTEXITCODE -ne 0) { throw "Setup UI builder failed with exit code $LASTEXITCODE" }

$NativeStatus = [pscustomobject]@{
    visualCppRuntimeX64 = $true
    visualCppRuntimeX86 = $true
    dotnetSdk = $true
    nodeHeaders = $true
    sqlOdbc = $true
    sqlServerExpressMedia = $SqlIncluded
    tesseract = $TesseractIncluded
    heavyOcrWheelhouse = $HeavyOcrIncluded
    visualStudioBuildToolsMedia = $BuildToolsIncluded
    webView2 = $WebView2Included
    netFramework35MatchingWindowsMedia = $NetFx35SourceIncluded
    windowsRepairProfiles = @($WindowsRepairProfiles)
    developerStack = $true
    professionalSetupUi = $true
    tabbedSuiteShell = $true
    windowsSafeCare = $true
    deviceInventory = $true
    portableGitBashFallback = $true
    targetDownloadsAllowed = $false
    aiServiceNetworkOnly = $true
    localGenerativeAiModels = $false
}
$NativeStatus | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDir 'native-components.json') -Encoding UTF8

Write-Step 'Removing Mark-of-the-Web from trusted builder-created bundle files when present'
Get-ChildItem $OutputDir -File -Recurse | ForEach-Object {
    try { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
}

Write-Step 'Rebuilding final SHA-256 manifest after all payload additions'
$HashEntries = Get-ChildItem $OutputDir -File -Recurse | Where-Object { $_.Name -ne 'bundle-sha256.json' } | ForEach-Object {
    [pscustomobject]@{
        path = Get-RelativeBundlePath $OutputDir $_.FullName
        sha256 = Get-Sha256 $_.FullName
        size = $_.Length
    }
}
$HashEntries | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDir 'bundle-sha256.json') -Encoding UTF8

Write-Step 'Verifying the completed bundle before declaring it ready'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OutputDir 'scripts\Verify-OfflineBundle.ps1') -BundleRoot $OutputDir
if ($LASTEXITCODE -ne 0) { throw "Final bundle verification failed with exit code $LASTEXITCODE" }

if ($CreateZip) {
    Write-Step 'Creating final transport ZIP'
    $ZipPath = "$OutputDir.zip"
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host "Created: $ZipPath" -ForegroundColor Green
}

Write-Host "`nComplete professional offline bundle ready: $OutputDir" -ForegroundColor Green
Write-Host 'Target installation performs zero software/package/extension downloads.' -ForegroundColor Green
Write-Host 'Windows repair operations use only metadata-verified matching local repair media when supplied.' -ForegroundColor Green
