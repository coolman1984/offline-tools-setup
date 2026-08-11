param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Config = Get-Content (Join-Path $BundleRoot 'config\developer-stack.json') -Raw | ConvertFrom-Json
$Payload = Join-Path $BundleRoot 'payload\developer'
if (-not (Test-Path $Payload)) { throw 'Developer stack payload is missing from the offline bundle.' }
if ($Config.policy.localModelsAllowed -ne $false) { throw 'Policy violation: local models must remain disabled.' }

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Add-MachinePath([string]$PathToAdd) {
    if (-not (Test-Path $PathToAdd)) { return }
    $Current = [Environment]::GetEnvironmentVariable('Path','Machine')
    if (($Current -split ';') -notcontains $PathToAdd) {
        [Environment]::SetEnvironmentVariable('Path', ($Current.TrimEnd(';') + ';' + $PathToAdd), 'Machine')
    }
}

$DevRoot = Join-Path $InstallRoot 'Developer'
New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null

Write-Step 'Installing portable VS Code with pre-bundled extensions'
$VsCodeSource = Join-Path $Payload 'vscode'
$VsCodeRoot = Join-Path $DevRoot 'VSCode'
Remove-Item $VsCodeRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $VsCodeSource $VsCodeRoot -Recurse -Force
$PortableData = Join-Path $VsCodeRoot 'data'
$ExtensionRoot = Join-Path $PortableData 'extensions'
$SettingsDir = Join-Path $PortableData 'user-data\User'
New-Item -ItemType Directory -Force -Path $ExtensionRoot,$SettingsDir | Out-Null
$ExtensionSource = Join-Path $Payload 'vscode-extensions'
if (Test-Path $ExtensionSource) { Copy-Item (Join-Path $ExtensionSource '*') $ExtensionRoot -Recurse -Force }
$VsSettings = @{
    'update.mode' = 'none'
    'extensions.autoUpdate' = $false
    'extensions.autoCheckUpdates' = $false
    'extensions.ignoreRecommendations' = $true
    'telemetry.telemetryLevel' = 'off'
    'workbench.enableExperiments' = $false
} | ConvertTo-Json -Depth 4
$VsSettings | Set-Content (Join-Path $SettingsDir 'settings.json') -Encoding UTF8
$CodeCmd = Join-Path $VsCodeRoot 'bin\code.cmd'
if (-not (Test-Path $CodeCmd)) { throw 'VS Code command not found after copy.' }
Add-MachinePath (Join-Path $VsCodeRoot 'bin')

Write-Step 'Installing portable Git and Git Bash'
$GitRoot = Join-Path $DevRoot 'Git'
Remove-Item $GitRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'git') $GitRoot -Recurse -Force
$GitCmdDir = Join-Path $GitRoot 'cmd'
$GitBash = Join-Path $GitRoot 'bin\bash.exe'
if (-not (Test-Path (Join-Path $GitCmdDir 'git.exe'))) { throw 'Git executable not found.' }
Add-MachinePath $GitCmdDir
if (Test-Path $GitBash) {
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH',$GitBash,'Machine')
}

Write-Step 'Installing pre-staged AI and developer CLIs'
$CliRoot = Join-Path $DevRoot 'CLI'
Remove-Item $CliRoot -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Payload 'cli') $CliRoot -Recurse -Force
Add-MachinePath $CliRoot
[Environment]::SetEnvironmentVariable('DISABLE_AUTOUPDATER','1','Machine')
[Environment]::SetEnvironmentVariable('NO_UPDATE_NOTIFIER','1','Machine')
[Environment]::SetEnvironmentVariable('npm_config_offline','true','Machine')
[Environment]::SetEnvironmentVariable('npm_config_audit','false','Machine')
[Environment]::SetEnvironmentVariable('npm_config_fund','false','Machine')

Write-Step 'Installing local Gitea development hub'
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
HTTP_PORT = 3000
ROOT_URL = http://127.0.0.1:3000/
OFFLINE_MODE = true
DISABLE_SSH = true

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true

[security]
INSTALL_LOCK = true

[other]
SHOW_FOOTER_VERSION = true
SHOW_FOOTER_TEMPLATE_LOAD_TIME = false
"@
$AppIni | Set-Content $GiteaConfig -Encoding UTF8
& $GiteaExe migrate --config $GiteaConfig
if ($LASTEXITCODE -ne 0) { throw 'Gitea database migration failed.' }

$AdminMarker = Join-Path $GiteaRoot 'FIRST-LOGIN.txt'
if (-not (Test-Path $AdminMarker)) {
    $Password = ([guid]::NewGuid().ToString('N').Substring(0,20) + '!Aa9')
    & $GiteaExe admin user create --config $GiteaConfig --username offline-admin --password $Password --email offline-admin@localhost --admin --must-change-password
    if ($LASTEXITCODE -eq 0) {
        @"
Offline Development Hub
URL: http://127.0.0.1:3000/
Username: offline-admin
Temporary password: $Password
Change this password on first login.
"@ | Set-Content $AdminMarker -Encoding UTF8
    } else {
        Write-Warning 'Could not create the initial Gitea admin automatically. The server is installed; create an admin with the Gitea CLI.'
    }
}

$ServiceName = 'OfflineDevelopmentHub'
$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $ExistingService) {
    $BinaryPath = ('"{0}" web --config "{1}"' -f $GiteaExe,$GiteaConfig)
    New-Service -Name $ServiceName -BinaryPathName $BinaryPath -DisplayName 'Offline Development Hub' -StartupType Automatic | Out-Null
}
Start-Service -Name $ServiceName -ErrorAction SilentlyContinue

Write-Step 'Staging desktop application installers without network downloads'
$DesktopTarget = Join-Path $DevRoot 'DesktopInstallers'
New-Item -ItemType Directory -Force -Path $DesktopTarget | Out-Null
$DesktopSource = Join-Path $Payload 'desktop'
if (Test-Path $DesktopSource) { Copy-Item (Join-Path $DesktopSource '*') $DesktopTarget -Recurse -Force }

Write-Step 'Creating local launchers'
$Launchers = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force -Path $Launchers | Out-Null
"@echo off`r`n`"$CodeCmd`" %*" | Set-Content (Join-Path $Launchers 'code-offline.cmd') -Encoding ASCII
"@echo off`r`nstart `"`" http://127.0.0.1:3000/" | Set-Content (Join-Path $Launchers 'dev-hub.cmd') -Encoding ASCII
Add-MachinePath $Launchers

Write-Step 'Developer stack smoke tests'
& (Join-Path $GitCmdDir 'git.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'Git smoke test failed.' }
foreach ($Command in @('codex.cmd','claude.cmd','cline.cmd','kilo.cmd','opencode.cmd')) {
    $Path = Join-Path $CliRoot $Command
    if (-not (Test-Path $Path)) { throw "Missing AI CLI launcher: $Command" }
}

Write-Host '`nOFFLINE DEVELOPER STACK INSTALLED.' -ForegroundColor Green
Write-Host 'No models were installed. No package/extension downloads are required on the target PC.' -ForegroundColor Green
Write-Host 'Open a new terminal before using the new PATH entries.' -ForegroundColor Green
