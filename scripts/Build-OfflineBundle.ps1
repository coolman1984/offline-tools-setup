param(
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\offline-bundle'),
    [switch]$IncludeHeavyOcr,
    [switch]$CreateZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $RepoRoot 'config\tool-manifest.json'
$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$WorkDir = Join-Path $RepoRoot 'work\bundle-builder'

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RemoteFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string]$ExpectedSha256
    )

    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null

    if (Test-Path $Destination) {
        if (-not $ExpectedSha256 -or (Get-Sha256 $Destination) -eq $ExpectedSha256.ToLowerInvariant()) {
            Write-Host "Using cached: $Destination"
            return
        }
        Remove-Item $Destination -Force
    }

    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

    if ($ExpectedSha256) {
        $Actual = Get-Sha256 $Destination
        if ($Actual -ne $ExpectedSha256.ToLowerInvariant()) {
            throw "SHA-256 mismatch for $Destination. Expected $ExpectedSha256, got $Actual"
        }
    }
}

function Get-RequirementLines([string]$Path) {
    return Get-Content $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Invoke-PipDownloadForTarget {
    param(
        [string]$BuilderPython,
        [string]$PythonVersion,
        [string]$RequirementFile,
        [string]$Destination,
        [bool]$FailOnMissing
    )

    $Parts = $PythonVersion.Split('.')
    $Minor = "$($Parts[0]).$($Parts[1])"
    $Abi = "cp$($Parts[0])$($Parts[1])"
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    $Failures = @()
    foreach ($Package in (Get-RequirementLines $RequirementFile)) {
        Write-Host "[$Minor] $Package"
        $Args = @(
            '-m','pip','download',
            '--disable-pip-version-check',
            '--only-binary=:all:',
            '--platform','win_amd64',
            '--python-version',$Minor,
            '--implementation','cp',
            '--abi',$Abi,
            '--abi','abi3',
            '--abi','none',
            '--dest',$Destination,
            $Package
        )
        & $BuilderPython @Args
        if ($LASTEXITCODE -ne 0) {
            $Failures += $Package
            Write-Warning "No complete wheel resolution for $Package on Python $Minor"
        }
    }

    if ($Failures.Count -gt 0) {
        $FailureFile = Join-Path $Destination '_missing-packages.txt'
        $Failures | Set-Content -Path $FailureFile -Encoding UTF8
        if ($FailOnMissing) {
            throw "Primary Python $Minor is missing offline wheels. See $FailureFile"
        }
    }
}

Write-Step 'Preparing directories'
Remove-Item $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutputDir,$WorkDir | Out-Null

$PythonInstallerDir = Join-Path $OutputDir 'payload\installers\python'
$NodeInstallerDir = Join-Path $OutputDir 'payload\installers\node'
$WheelRoot = Join-Path $OutputDir 'payload\wheelhouse'
$NpmCache = Join-Path $OutputDir 'payload\npm-cache'
New-Item -ItemType Directory -Force -Path $PythonInstallerDir,$NodeInstallerDir,$WheelRoot,$NpmCache | Out-Null

Write-Step 'Downloading Python installers from python.org'
foreach ($Python in $Manifest.python.versions) {
    $Target = Join-Path $PythonInstallerDir $Python.file
    $Expected = if ($Python.PSObject.Properties.Name -contains 'sha256') { $Python.sha256 } else { $null }
    Get-RemoteFile -Url $Python.url -Destination $Target -ExpectedSha256 $Expected
}

Write-Step 'Downloading Node.js LTS installer and portable builder runtime'
$NodeMsi = Join-Path $NodeInstallerDir $Manifest.node.msiFile
$NodeZip = Join-Path $NodeInstallerDir $Manifest.node.zipFile
$NodeShasums = Join-Path $NodeInstallerDir 'SHASUMS256.txt'
Get-RemoteFile -Url $Manifest.node.msiUrl -Destination $NodeMsi
Get-RemoteFile -Url $Manifest.node.zipUrl -Destination $NodeZip
Get-RemoteFile -Url $Manifest.node.shasumsUrl -Destination $NodeShasums

$ShasumLine = Get-Content $NodeShasums | Where-Object { $_ -match [regex]::Escape($Manifest.node.msiFile) } | Select-Object -First 1
if (-not $ShasumLine) { throw 'Node.js MSI was not found in SHASUMS256.txt' }
$ExpectedNodeHash = ($ShasumLine -split '\s+')[0].ToLowerInvariant()
if ((Get-Sha256 $NodeMsi) -ne $ExpectedNodeHash) { throw 'Node.js MSI hash verification failed.' }

Write-Step 'Creating temporary Python builder runtime'
$Primary = $Manifest.python.versions | Where-Object { $_.version -eq $Manifest.python.primary } | Select-Object -First 1
if (-not $Primary) { throw 'Primary Python is missing from manifest.' }
$PrimaryInstaller = Join-Path $PythonInstallerDir $Primary.file
$BuilderPythonRoot = Join-Path $WorkDir 'python-builder'
$BuilderPython = Join-Path $BuilderPythonRoot 'python.exe'
$PythonArgs = @(
    '/quiet',
    'InstallAllUsers=0',
    'PrependPath=0',
    'Include_launcher=0',
    'Include_test=0',
    'Include_doc=0',
    'AssociateFiles=0',
    'Shortcuts=0',
    "TargetDir=$BuilderPythonRoot"
)
$Proc = Start-Process -FilePath $PrimaryInstaller -ArgumentList $PythonArgs -Wait -PassThru
if ($Proc.ExitCode -notin 0,3010) { throw "Temporary Python install failed with exit code $($Proc.ExitCode)" }
if (-not (Test-Path $BuilderPython)) { throw 'Temporary builder Python was not created.' }
& $BuilderPython -m pip --version

Write-Step 'Building per-version Python wheelhouses'
$Recommended = Join-Path $RepoRoot 'requirements\recommended.txt'
foreach ($Python in $Manifest.python.versions) {
    $Tag = 'py' + (($Python.version.Split('.')[0..1]) -join '')
    $Destination = Join-Path $WheelRoot $Tag
    $IsPrimary = $Python.version -eq $Manifest.python.primary
    Invoke-PipDownloadForTarget -BuilderPython $BuilderPython -PythonVersion $Python.version -RequirementFile $Recommended -Destination $Destination -FailOnMissing:$IsPrimary
}

if ($IncludeHeavyOcr) {
    Write-Step 'Building optional heavy OCR wheelhouses'
    $Heavy = Join-Path $RepoRoot 'requirements\ocr-heavy.txt'
    foreach ($Python in $Manifest.python.versions) {
        $Tag = 'py' + (($Python.version.Split('.')[0..1]) -join '')
        $Destination = Join-Path $WheelRoot ($Tag + '-ocr-heavy')
        Invoke-PipDownloadForTarget -BuilderPython $BuilderPython -PythonVersion $Python.version -RequirementFile $Heavy -Destination $Destination -FailOnMissing:$false
    }
}

Write-Step 'Building offline npm cache'
$PortableNodeRoot = Join-Path $WorkDir 'node-portable'
Expand-Archive -Path $NodeZip -DestinationPath $PortableNodeRoot -Force
$NodeFolder = Get-ChildItem $PortableNodeRoot -Directory | Select-Object -First 1
if (-not $NodeFolder) { throw 'Could not find portable Node.js directory.' }
$NpmCmd = Join-Path $NodeFolder.FullName 'npm.cmd'
$SeedDir = Join-Path $WorkDir 'web-fullstack-seed'
New-Item -ItemType Directory -Force -Path $SeedDir | Out-Null
Copy-Item (Join-Path $RepoRoot 'templates\web-fullstack\package.json') (Join-Path $SeedDir 'package.json') -Force
Push-Location $SeedDir
try {
    & $NpmCmd install --ignore-scripts --cache $NpmCache --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm cache seed failed.' }
} finally {
    Pop-Location
}
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir 'templates\web-fullstack') | Out-Null
Copy-Item (Join-Path $SeedDir 'package.json') (Join-Path $OutputDir 'templates\web-fullstack\package.json') -Force
Copy-Item (Join-Path $SeedDir 'package-lock.json') (Join-Path $OutputDir 'templates\web-fullstack\package-lock.json') -Force

Write-Step 'Copying offline installer control files'
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir 'config'),(Join-Path $OutputDir 'requirements'),(Join-Path $OutputDir 'scripts') | Out-Null
Copy-Item $ManifestPath (Join-Path $OutputDir 'config\tool-manifest.json') -Force
Copy-Item (Join-Path $RepoRoot 'requirements\*.txt') (Join-Path $OutputDir 'requirements') -Force
Copy-Item (Join-Path $RepoRoot 'scripts\Install-OfflineTools.ps1') (Join-Path $OutputDir 'scripts\Install-OfflineTools.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'scripts\Verify-OfflineBundle.ps1') (Join-Path $OutputDir 'scripts\Verify-OfflineBundle.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'START-HERE.cmd') (Join-Path $OutputDir 'START-HERE.cmd') -Force

Write-Step 'Creating SHA-256 integrity manifest'
$HashEntries = Get-ChildItem $OutputDir -File -Recurse | Where-Object { $_.Name -ne 'bundle-sha256.json' } | ForEach-Object {
    [pscustomobject]@{
        path = [System.IO.Path]::GetRelativePath($OutputDir, $_.FullName).Replace('\\','/')
        sha256 = Get-Sha256 $_.FullName
        size = $_.Length
    }
}
$HashEntries | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDir 'bundle-sha256.json') -Encoding UTF8

$BuildInfo = [pscustomobject]@{
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    architecture = $Manifest.target.architecture
    pythonPrimary = $Manifest.python.primary
    pythonVersions = @($Manifest.python.versions.version)
    nodeVersion = $Manifest.node.version
    offlineOnly = $true
}
$BuildInfo | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDir 'bundle-info.json') -Encoding UTF8

if ($CreateZip) {
    Write-Step 'Creating transport ZIP'
    $ZipPath = "$OutputDir.zip"
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host "Created: $ZipPath" -ForegroundColor Green
}

Write-Host "`nOffline bundle ready: $OutputDir" -ForegroundColor Green
Write-Host 'Copy this directory to USB/external SSD/approved offline media and run START-HERE.cmd on the target PC.' -ForegroundColor Green
