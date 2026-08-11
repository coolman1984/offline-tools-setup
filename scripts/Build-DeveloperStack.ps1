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
    if (-not (Test-Path $Destination)) { throw "Download failed: $Url" }
}

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $DevRoot,$WorkRoot | Out-Null

Write-Step 'Preparing portable PowerShell 7'
$PsRelease = Invoke-RestMethod -Uri $Config.core.powershell.releaseApi -Headers @{ 'User-Agent'='offline-tools-setup' }
$PsAsset = $PsRelease.assets | Where-Object { $_.name -match $Config.core.powershell.assetRegex } | Select-Object -First 1
if (-not $PsAsset) { throw 'Could not resolve the current PowerShell 7 Windows x64 ZIP asset.' }
$PsZip = Join-Path $WorkRoot $PsAsset.name
Get-RemoteFile $PsAsset.browser_download_url $PsZip
$PsPayload = Join-Path $DevRoot 'powershell'
Remove-Item $PsPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PsPayload | Out-Null
Expand-Archive -Path $PsZip -DestinationPath $PsPayload -Force
if (-not (Test-Path (Join-Path $PsPayload 'pwsh.exe'))) { throw 'PowerShell 7 executable was not found.' }

Write-Step 'Preparing portable VS Code'
$VsCodeZip = Join-Path $WorkRoot 'vscode.zip'
Get-RemoteFile $Config.core.vscode.archiveUrl $VsCodeZip
$VsCodePayload = Join-Path $DevRoot 'vscode'
Remove-Item $VsCodePayload -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $VsCodeZip -DestinationPath $VsCodePayload -Force
$CodeCmd = Join-Path $VsCodePayload 'bin\code.cmd'
if (-not (Test-Path $CodeCmd)) { throw 'VS Code portable command was not found after extraction.' }

Write-Step 'Pre-installing separable VS Code extension payloads'
$VsCodeUserData = Join-Path $WorkRoot 'vscode-user-data'
New-Item -ItemType Directory -Force -Path $VsCodeUserData | Out-Null
$ExtensionGroups = @(
    @{ Name = 'core'; Path = (Join-Path $DevRoot 'vscode-extensions-core'); Extensions = @($Config.vscodeExtensionsCore) },
    @{ Name = 'ai'; Path = (Join-Path $DevRoot 'vscode-extensions-ai'); Extensions = @($Config.vscodeExtensionsAi) }
)
foreach ($Group in $ExtensionGroups) {
    Remove-Item $Group.Path -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Group.Path | Out-Null
    foreach ($Extension in $Group.Extensions) {
        Write-Host "Installing $($Group.Name) extension into bundle: $Extension"
        & $CodeCmd --user-data-dir $VsCodeUserData --extensions-dir $Group.Path --install-extension $Extension --force
        if ($LASTEXITCODE -ne 0) { throw "VS Code extension bundle failed: $Extension" }
    }
}

Write-Step 'Preparing MinGit for native Windows command shells'
$GitRelease = Invoke-RestMethod -Uri $Config.core.git.releaseApi -Headers @{ 'User-Agent'='offline-tools-setup' }
$GitAsset = $GitRelease.assets | Where-Object { $_.name -match $Config.core.git.assetRegex } | Select-Object -First 1
if (-not $GitAsset) { throw 'Could not resolve the latest MinGit x64 ZIP asset.' }
$GitZip = Join-Path $WorkRoot $GitAsset.name
Get-RemoteFile $GitAsset.browser_download_url $GitZip
$GitPayload = Join-Path $DevRoot 'git'
Remove-Item $GitPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $GitPayload | Out-Null
Expand-Archive -Path $GitZip -DestinationPath $GitPayload -Force
if (-not (Test-Path (Join-Path $GitPayload 'cmd\git.exe'))) { throw 'MinGit executable was not found.' }

Write-Step 'Preparing isolated Portable Git Bash compatibility fallback'
$PortableAsset = $GitRelease.assets | Where-Object { $_.name -match $Config.core.git.portableBashAssetRegex } | Select-Object -First 1
if (-not $PortableAsset) { throw 'Could not resolve the current Portable Git for Windows x64 asset.' }
$PortableArchive = Join-Path $WorkRoot $PortableAsset.name
Get-RemoteFile $PortableAsset.browser_download_url $PortableArchive
$BashPayload = Join-Path $DevRoot 'git-bash'
Remove-Item $BashPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $BashPayload | Out-Null
$proc = Start-Process -FilePath $PortableArchive -ArgumentList @('-y',("-o{0}" -f $BashPayload)) -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "Portable Git extraction failed with exit code $($proc.ExitCode)" }
$PostInstall = Join-Path $BashPayload 'post-install.bat'
if (Test-Path $PostInstall) { & $PostInstall | Out-Null }
$BashExe = Join-Path $BashPayload 'bin\bash.exe'
if (-not (Test-Path $BashExe)) { throw 'Portable Git Bash executable was not found after extraction.' }

Write-Step 'Preparing Gitea local development hub'
$GiteaPayload = Join-Path $DevRoot 'gitea'
New-Item -ItemType Directory -Force -Path $GiteaPayload | Out-Null
Get-RemoteFile $Config.core.gitea.url (Join-Path $GiteaPayload 'gitea.exe')

Write-Step 'Preparing portable Node runtime for CLI packaging'
$NodeZip = Join-Path $BundleRoot ("payload\installers\node\{0}" -f $ToolManifest.node.zipFile)
if (-not (Test-Path $NodeZip)) { throw "Node portable archive is missing: $NodeZip" }
$PortableNodeRoot = Join-Path $WorkRoot 'node'
Expand-Archive -Path $NodeZip -DestinationPath $PortableNodeRoot -Force
$NodeFolder = Get-ChildItem $PortableNodeRoot -Directory | Select-Object -First 1
if (-not $NodeFolder) { throw 'Portable Node.js directory not found.' }
$NpmCmd = Join-Path $NodeFolder.FullName 'npm.cmd'
$env:PATH = $NodeFolder.FullName + ';' + $env:PATH

Write-Step 'Preparing core developer CLI payload'
$CoreCliPayload = Join-Path $DevRoot 'cli-core'
Remove-Item $CoreCliPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $CoreCliPayload | Out-Null
$CorePackages = @($Config.nodeCli | ForEach-Object { [string]$_ })
& $NpmCmd install --global --prefix $CoreCliPayload --no-audit --no-fund @CorePackages
if ($LASTEXITCODE -ne 0) { throw 'Core developer CLI staging failed.' }

Write-Step 'Preparing optional AI CLI payload'
$AiCliPayload = Join-Path $DevRoot 'cli-ai'
Remove-Item $AiCliPayload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $AiCliPayload | Out-Null
$AiPackages = @($Config.aiCli | Where-Object { $_.supported -eq $true } | ForEach-Object { [string]$_.package })
if ($AiPackages.Count -gt 0) {
    & $NpmCmd install --global --prefix $AiCliPayload --no-audit --no-fund @AiPackages
    if ($LASTEXITCODE -ne 0) { throw 'AI developer CLI staging failed.' }
}

Write-Step 'Preparing OpenCode Desktop Windows payload'
$OpenCode = $Config.desktopApps | Where-Object { $_.name -eq 'OpenCode Desktop' } | Select-Object -First 1
if ($OpenCode) {
    $Release = Invoke-RestMethod -Uri $OpenCode.releaseApi -Headers @{ 'User-Agent'='offline-tools-setup' }
    $Asset = $Release.assets | Where-Object { $_.name -eq $OpenCode.assetPattern } | Select-Object -First 1
    if ($Asset) {
        $DesktopDir = Join-Path $DevRoot 'desktop\opencode'
        Get-RemoteFile $Asset.browser_download_url (Join-Path $DesktopDir $Asset.name)
    } else {
        Write-Warning 'OpenCode Desktop Windows asset was not found in the current release.'
    }
}

Write-Step 'Copying optional approved desktop payloads if supplied'
foreach ($Name in @('chatgpt','claude')) {
    $Source = Join-Path $RepoRoot ("vendor\desktop\{0}" -f $Name)
    if (Test-Path $Source) {
        $Destination = Join-Path $DevRoot ("desktop\{0}" -f $Name)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item (Join-Path $Source '*') $Destination -Recurse -Force
        Write-Host "Included pre-acquired $Name desktop payload."
    }
}

$ConfigDestination = Join-Path $BundleRoot 'config\developer-stack.json'
New-Item -ItemType Directory -Force -Path (Split-Path $ConfigDestination -Parent) | Out-Null
Copy-Item (Join-Path $RepoRoot 'config\developer-stack.json') $ConfigDestination -Force
Write-Host "Developer stack payload ready: $DevRoot" -ForegroundColor Green
Write-Host 'Portable Git Bash fallback is bundled but isolated and never selected as the default shell.' -ForegroundColor Green
Write-Host 'Claude Code payload is bundled; target execution remains conditional on corporate policy allowing the isolated bash.exe.' -ForegroundColor Yellow
