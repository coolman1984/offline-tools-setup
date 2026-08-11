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

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativeBundlePath([string]$Root, [string]$FullPath) {
    $NormalizedRoot = $Root.TrimEnd('\')
    return $FullPath.Substring($NormalizedRoot.Length).TrimStart('\').Replace('\','/')
}

function Get-RemoteFile([string]$Url, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    if (-not (Test-Path $Destination)) { throw "Download failed: $Url" }
}

Write-Step 'Building core language/package bundle'
$CoreArgs = @('-OutputDir', $OutputDir)
if ($IncludeHeavyOcr) { $CoreArgs += '-IncludeHeavyOcr' }
& (Join-Path $PSScriptRoot 'Build-OfflineBundle.ps1') @CoreArgs
if ($LASTEXITCODE -ne 0) { throw "Core bundle builder failed with exit code $LASTEXITCODE" }

Write-Step 'Adding Microsoft native prerequisites'
$MicrosoftDir = Join-Path $OutputDir 'payload\installers\microsoft'
New-Item -ItemType Directory -Force -Path $MicrosoftDir | Out-Null
Get-RemoteFile $Manifest.microsoft.visualCppRuntime.url (Join-Path $MicrosoftDir $Manifest.microsoft.visualCppRuntime.file)
Get-RemoteFile $Manifest.microsoft.sqlOdbc.url (Join-Path $MicrosoftDir $Manifest.microsoft.sqlOdbc.file)

Write-Step 'Adding optional native offline media when supplied'
$SqlIncluded = $false
$TesseractIncluded = $false

$SqlSource = Join-Path $NativeSourceDir 'sql-server-express'
$SqlDestination = Join-Path $OutputDir $Manifest.microsoft.sqlServerExpress.offlineMediaRelativePath
if (Test-Path (Join-Path $SqlSource 'setup.exe')) {
    New-Item -ItemType Directory -Force -Path $SqlDestination | Out-Null
    Copy-Item (Join-Path $SqlSource '*') $SqlDestination -Recurse -Force
    $SqlIncluded = $true
    Write-Host 'SQL Server Express offline media included.' -ForegroundColor Green
} else {
    Write-Warning 'SQL Server Express extracted media not found. Database client support will still be included.'
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
    Write-Host 'Tesseract OCR installer and English/Arabic models included.' -ForegroundColor Green
} else {
    Write-Warning 'Tesseract Windows installer not supplied. RapidOCR remains available as the built-in OCR baseline.'
}

Write-Step 'Copying complete target installer scripts'
Copy-Item (Join-Path $RepoRoot 'scripts\Install-NativeComponents.ps1') (Join-Path $OutputDir 'scripts\Install-NativeComponents.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'scripts\Install-AllOfflineTools.ps1') (Join-Path $OutputDir 'scripts\Install-AllOfflineTools.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'START-HERE.cmd') (Join-Path $OutputDir 'START-HERE.cmd') -Force

$NativeStatus = [pscustomobject]@{
    visualCppRuntime = $true
    sqlOdbc = $true
    sqlServerExpressMedia = $SqlIncluded
    tesseract = $TesseractIncluded
}
$NativeStatus | ConvertTo-Json | Set-Content (Join-Path $OutputDir 'native-components.json') -Encoding UTF8

Write-Step 'Rebuilding final SHA-256 manifest after native payload additions'
$HashEntries = Get-ChildItem $OutputDir -File -Recurse | Where-Object { $_.Name -ne 'bundle-sha256.json' } | ForEach-Object {
    [pscustomobject]@{
        path = Get-RelativeBundlePath $OutputDir $_.FullName
        sha256 = Get-Sha256 $_.FullName
        size = $_.Length
    }
}
$HashEntries | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDir 'bundle-sha256.json') -Encoding UTF8

if ($CreateZip) {
    Write-Step 'Creating final transport ZIP'
    $ZipPath = "$OutputDir.zip"
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host "Created: $ZipPath" -ForegroundColor Green
}

Write-Host "`nComplete offline bundle ready: $OutputDir" -ForegroundColor Green
Write-Host 'Target machines do not need internet access.' -ForegroundColor Green
