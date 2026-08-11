param(
    [Parameter(Mandatory=$true)][string]$BundleRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Config = Get-Content (Join-Path $RepoRoot 'config\developer-stack.json') -Raw | ConvertFrom-Json
$ToolManifest = Get-Content (Join-Path $RepoRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$DevRoot = Join-Path $BundleRoot 'payload\developer'
$WorkRoot = Join-Path $RepoRoot 'work\developer-stack'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Get-RemoteFile([string]$Url,[string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $DevRoot,$WorkRoot | Out-Null

Write-Step 'Preparing portable VS Code'
$VsCodeZip = Join-Path $WorkRoot 'vscode.zip'
Get-RemoteFile $Config.core.vscode.archiveUrl $VsCodeZip
$VsCodePayload = Join-Path $DevRoot 'vscode'
Remove-Item $VsCodePayload -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $VsCodeZip -DestinationPath $VsCodePayload -Force
$CodeCmd = Join-Path $VsCodePayload 'bin\code.cmd'
if (-not (Test-Path $CodeCmd)) { throw 'VS Code portable command was not found after extraction.' }

Write-Step 'Pre-installing VS Code extensions while internet is available'
$ExtensionPayload = Join-Path $DevRoot 'vscode-extensions'
$VsCodeUserData = Join-Path $WorkRoot 'vscode-user-data'
New-Item -ItemType Directory -Force -Path $ExtensionPayload,$VsCodeUserData | Out-Null
foreach ($Extension in $Config.vscodeExtensions) {
    Write-Host "Installing extension into bundle: $Extension"
    & $CodeCmd --user-data-dir $VsCodeUserData --extensions-dir $ExtensionPayload --install-extension $Extension --force
    if ($LASTEXITCODE -ne 0) { throw "VS Code extension bundle failed: $Extension" }
}

Write-Step 'Preparing portable Git for Windows'
$GitRelease = Invoke-RestMethod -Uri $Config.core.git.releaseApi -Headers @{ 'User-Agent'='offline-tools-setup' }
$GitAsset = $GitRelease.assets | Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' } | Select-Object -First 1
if (-not $GitAsset) { throw 'Could not resolve the latest PortableGit x64 asset.' }
$GitSfx = Join-Path $WorkRoot $GitAsset.name
Get-RemoteFile $GitAsset.browser_download_url $GitSfx
$GitPayload = Join-Path $DevRoot 'git'
New-Item -ItemType Directory -Force -Path $GitPayload | Out-Null
$GitProc = Start-Process -FilePath $GitSfx -ArgumentList @('-y',("-o`"{0}`"" -f $GitPayload)) -Wait -PassThru
if ($GitProc.ExitCode -ne 0) { throw "PortableGit extraction failed: $($GitProc.ExitCode)" }
if (-not (Test-Path (Join-Path $GitPayload 'cmd\git.exe'))) { throw 'Portable Git executable was not found.' }

Write-Step 'Preparing Gitea local GitHub-like server'
$GiteaPayload = Join-Path $DevRoot 'gitea'
New-Item -ItemType Directory -Force -Path $GiteaPayload | Out-Null
Get-RemoteFile $Config.core.gitea.url (Join-Path $GiteaPayload 'gitea.exe')

Write-Step 'Preparing complete AI and developer CLI prefix'
$NodeZip = Join-Path $BundleRoot ("payload\installers\node\{0}" -f $ToolManifest.node.zipFile)
if (-not (Test-Path $NodeZip)) { throw "Node portable archive is missing: $NodeZip" }
$PortableNodeRoot = Join-Path $WorkRoot 'node'
Expand-Archive -Path $NodeZip -DestinationPath $PortableNodeRoot -Force
$NodeFolder = Get-ChildItem $PortableNodeRoot -Directory | Select-Object -First 1
if (-not $NodeFolder) { throw 'Portable Node.js directory not found.' }
$NpmCmd = Join-Path $NodeFolder.FullName 'npm.cmd'
$env:PATH = $NodeFolder.FullName + ';' + $env:PATH
$CliPayload = Join-Path $DevRoot 'cli'
New-Item -ItemType Directory -Force -Path $CliPayload | Out-Null
$Packages = @()
foreach ($Item in $Config.aiCli) { $Packages += [string]$Item.package }
foreach ($Item in $Config.nodeCli) { $Packages += [string]$Item }
& $NpmCmd install --global --prefix $CliPayload --no-audit --no-fund @Packages
if ($LASTEXITCODE -ne 0) { throw 'Developer CLI staging failed.' }

Write-Step 'Preparing OpenCode Desktop Windows payload'
$OpenCode = $Config.desktopApps | Where-Object { $_.name -eq 'OpenCode Desktop' } | Select-Object -First 1
if ($OpenCode) {
    $Release = Invoke-RestMethod -Uri $OpenCode.releaseApi -Headers @{ 'User-Agent'='offline-tools-setup' }
    $Asset = $Release.assets | Where-Object { $_.name -eq $OpenCode.assetPattern } | Select-Object -First 1
    if ($Asset) {
        $DesktopDir = Join-Path $DevRoot 'desktop\opencode'
        Get-RemoteFile $Asset.browser_download_url (Join-Path $DesktopDir $Asset.name)
    } else {
        Write-Warning 'OpenCode Desktop Windows asset was not found in the current release. CLI and VS Code extension are still bundled.'
    }
}

Write-Step 'Copying optional enterprise desktop payloads if supplied'
foreach ($Name in @('chatgpt','claude')) {
    $Source = Join-Path $RepoRoot ("vendor\desktop\{0}" -f $Name)
    if (Test-Path $Source) {
        $Destination = Join-Path $DevRoot ("desktop\{0}" -f $Name)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item (Join-Path $Source '*') $Destination -Recurse -Force
        Write-Host "Included pre-acquired $Name desktop payload."
    } else {
        Write-Warning "Optional $Name desktop payload not supplied. Put its approved offline installer under vendor\desktop\$Name before building."
    }
}

$ConfigDestination = Join-Path $BundleRoot 'config\developer-stack.json'
New-Item -ItemType Directory -Force -Path (Split-Path $ConfigDestination -Parent) | Out-Null
Copy-Item (Join-Path $RepoRoot 'config\developer-stack.json') $ConfigDestination -Force
Write-Host "Developer stack payload ready: $DevRoot" -ForegroundColor Green
