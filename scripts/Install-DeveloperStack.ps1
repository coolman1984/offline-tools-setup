param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$InstallAiTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Config = Get-Content (Join-Path $BundleRoot 'config\developer-stack.json') -Raw | ConvertFrom-Json
$Payload = Join-Path $BundleRoot 'payload\developer'
if (-not (Test-Path $Payload)) { throw 'Developer stack payload is missing from the offline bundle.' }
if ($Config.policy.localModelsAllowed -ne $false) { throw 'Policy violation: local models must remain disabled.' }
if ($Config.policy.bashAllowed -ne $false) { throw 'Policy violation: Bash must remain disabled on target PCs.' }

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Test-PortAvailable([int]$Port) {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$Port)
        $listener.Start()
        return $true
    } catch { return $false }
    finally { if ($listener) { try { $listener.Stop() } catch {} } }
}
function Get-FreeHubPort {
    $start = [int]$Config.core.gitea.preferredPort
    $end = [int]$Config.core.gitea.portSearchEnd
    for ($port=$start; $port -le $end; $port++) {
        if (Test-PortAvailable $port) { return $port }
    }
    throw "No free loopback port was found for the local development hub in range $start-$end."
}

$DevRoot = Join-Path $InstallRoot 'Developer'
$BinRoot = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force -Path $DevRoot,$BinRoot | Out-Null

Write-Step 'Installing portable PowerShell 7 in an isolated managed location'
$PsRoot = Join-Path $DevRoot 'PowerShell7'
Remove-Item $PsRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'powershell') $PsRoot -Recurse -Force
$Pwsh = Join-Path $PsRoot 'pwsh.exe'
if (-not (Test-Path $Pwsh)) { throw 'PowerShell 7 executable was not found.' }
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT','1','Machine')

Write-Step 'Installing portable VS Code with selected pre-bundled extensions'
$VsCodeRoot = Join-Path $DevRoot 'VSCode'
Remove-Item $VsCodeRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'vscode') $VsCodeRoot -Recurse -Force
$ExtensionRoot = Join-Path $VsCodeRoot 'data\extensions'
$SettingsDir = Join-Path $VsCodeRoot 'data\user-data\User'
New-Item -ItemType Directory -Force -Path $ExtensionRoot,$SettingsDir | Out-Null
$CoreExtensionSource = Join-Path $Payload 'vscode-extensions-core'
if (Test-Path $CoreExtensionSource) { Copy-Item (Join-Path $CoreExtensionSource '*') $ExtensionRoot -Recurse -Force }
if ($InstallAiTools) {
    $AiExtensionSource = Join-Path $Payload 'vscode-extensions-ai'
    if (Test-Path $AiExtensionSource) { Copy-Item (Join-Path $AiExtensionSource '*') $ExtensionRoot -Recurse -Force }
}
$VsSettings = @{
    'update.mode' = 'none'
    'extensions.autoUpdate' = $false
    'extensions.autoCheckUpdates' = $false
    'extensions.ignoreRecommendations' = $true
    'telemetry.telemetryLevel' = 'off'
    'workbench.enableExperiments' = $false
    'terminal.integrated.defaultProfile.windows' = 'PowerShell'
} | ConvertTo-Json -Depth 4
$VsSettings | Set-Content (Join-Path $SettingsDir 'settings.json') -Encoding UTF8
$CodeCmd = Join-Path $VsCodeRoot 'bin\code.cmd'
if (-not (Test-Path $CodeCmd)) { throw 'VS Code command not found after copy.' }

Write-Step 'Installing MinGit without changing the global PATH'
$GitRoot = Join-Path $DevRoot 'Git'
Remove-Item $GitRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'git') $GitRoot -Recurse -Force
$GitExe = Join-Path $GitRoot 'cmd\git.exe'
if (-not (Test-Path $GitExe)) { throw 'Git executable not found.' }

Write-Step 'Installing pre-staged core developer CLIs'
$CoreCliRoot = Join-Path $DevRoot 'CLI-Core'
Remove-Item $CoreCliRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'cli-core') $CoreCliRoot -Recurse -Force

$AiCliRoot = Join-Path $DevRoot 'CLI-AI'
if ($InstallAiTools) {
    Write-Step 'Installing selected AI coding CLIs from local payload'
    Remove-Item $AiCliRoot -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $Payload 'cli-ai') $AiCliRoot -Recurse -Force
}

[Environment]::SetEnvironmentVariable('DISABLE_AUTOUPDATER','1','Machine')
[Environment]::SetEnvironmentVariable('NO_UPDATE_NOTIFIER','1','Machine')
[Environment]::SetEnvironmentVariable('npm_config_offline','true','Machine')
[Environment]::SetEnvironmentVariable('npm_config_audit','false','Machine')
[Environment]::SetEnvironmentVariable('npm_config_fund','false','Machine')

Write-Step 'Installing local Gitea development hub on a conflict-safe loopback port'
$ServiceName = 'OfflineDevelopmentHub'
$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($ExistingService -and $ExistingService.Status -ne 'Stopped') {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
$GiteaPort = Get-FreeHubPort
$GiteaRoot = Join-Path $DevRoot 'Gitea'
$GiteaData = Join-Path $GiteaRoot 'data'
$GiteaRepos = Join-Path $GiteaData 'repositories'
$GiteaConfigDir = Join-Path $GiteaRoot 'custom\conf'
New-Item -ItemType Directory -Force -Path $GiteaRoot,$GiteaData,$GiteaRepos,$GiteaConfigDir | Out-Null
Copy-Item (Join-Path $Payload 'gitea\gitea.exe') (Join-Path $GiteaRoot 'gitea.exe') -Force
$GiteaExe = Join-Path $GiteaRoot 'gitea.exe'
$GiteaConfig = Join-Path $GiteaConfigDir 'app.ini'
$NormalizedRoot = $GiteaRoot.Replace('\','/')
$AppIni = @"
APP_NAME = Offline Development Hub
RUN_MODE = prod
WORK_PATH = $NormalizedRoot

[database]
DB_TYPE = sqlite3
PATH = $NormalizedRoot/data/gitea.db

[repository]
ROOT = $NormalizedRoot/data/repositories

[server]
DOMAIN = 127.0.0.1
HTTP_ADDR = 127.0.0.1
HTTP_PORT = $GiteaPort
ROOT_URL = http://127.0.0.1:$GiteaPort/
OFFLINE_MODE = true
DISABLE_SSH = true

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true

[security]
INSTALL_LOCK = true
"@
$AppIni | Set-Content $GiteaConfig -Encoding UTF8
$GiteaPort | Set-Content (Join-Path $GiteaRoot 'PORT.txt') -Encoding ASCII
& $GiteaExe --work-path $GiteaRoot --config $GiteaConfig migrate
if ($LASTEXITCODE -ne 0) { throw 'Gitea database migration failed.' }

$AdminMarker = Join-Path $GiteaRoot 'FIRST-LOGIN.txt'
if (-not (Test-Path $AdminMarker)) {
    $Password = ([guid]::NewGuid().ToString('N').Substring(0,20) + '!Aa9')
    & $GiteaExe --work-path $GiteaRoot --config $GiteaConfig admin user create --username offline-admin --password $Password --email offline-admin@localhost --admin --must-change-password
    if ($LASTEXITCODE -eq 0) {
        @"
Offline Development Hub
URL: http://127.0.0.1:$GiteaPort/
Username: offline-admin
Temporary password: $Password
Change this password on first login.
"@ | Set-Content $AdminMarker -Encoding UTF8
    }
}

if (-not $ExistingService) {
    $BinaryPath = ('"{0}" --work-path "{1}" --config "{2}" web' -f $GiteaExe,$GiteaRoot,$GiteaConfig)
    New-Service -Name $ServiceName -BinaryPathName $BinaryPath -DisplayName 'Offline Development Hub' -StartupType Automatic | Out-Null
}
Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700
$ServiceState = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $ServiceState -or $ServiceState.Status -ne 'Running') {
    throw "Local development hub service could not start on port $GiteaPort. Check Windows service and application-control policy logs."
}

if ($InstallAiTools) {
    Write-Step 'Staging approved AI desktop application payloads'
    $DesktopTarget = Join-Path $DevRoot 'DesktopInstallers'
    New-Item -ItemType Directory -Force -Path $DesktopTarget | Out-Null
    if (Test-Path (Join-Path $Payload 'desktop')) { Copy-Item (Join-Path $Payload 'desktop\*') $DesktopTarget -Recurse -Force }
}

Write-Step 'Creating local command wrappers without adding tool directories to PATH'
"@echo off`r`n`"$CodeCmd`" %*`r`n" | Set-Content (Join-Path $BinRoot 'code-offline.cmd') -Encoding ASCII
"@echo off`r`n`"$Pwsh`" %*`r`n" | Set-Content (Join-Path $BinRoot 'pwsh-offline.cmd') -Encoding ASCII
"@echo off`r`n`"$GitExe`" %*`r`n" | Set-Content (Join-Path $BinRoot 'git-offline.cmd') -Encoding ASCII
"@echo off`r`nstart `"`" http://127.0.0.1:$GiteaPort/`r`n" | Set-Content (Join-Path $BinRoot 'dev-hub.cmd') -Encoding ASCII

Write-Step 'Developer stack smoke tests'
& $Pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0) { throw 'PowerShell 7 smoke test failed.' }
& $GitExe --version
if ($LASTEXITCODE -ne 0) { throw 'Git smoke test failed.' }
foreach ($Command in @('pnpm.cmd','yarn.cmd','tsc.cmd','node-gyp.cmd')) {
    if (-not (Test-Path (Join-Path $CoreCliRoot $Command))) { throw "Missing core developer CLI launcher: $Command" }
}
if ($InstallAiTools) {
    foreach ($Command in @('codex.cmd','cline.cmd','kilo.cmd','opencode.cmd')) {
        if (-not (Test-Path (Join-Path $AiCliRoot $Command))) { throw "Missing AI CLI launcher: $Command" }
    }
}

Write-Host '`nWINDOWS-NATIVE DEVELOPER STACK INSTALLED.' -ForegroundColor Green
Write-Host "Local development hub: http://127.0.0.1:$GiteaPort/" -ForegroundColor Green
Write-Host 'No developer tool directory was added directly to the global PATH.' -ForegroundColor Green
Write-Host 'Claude Code remains outside the guaranteed profile because Git Bash and WSL are forbidden.' -ForegroundColor Yellow
