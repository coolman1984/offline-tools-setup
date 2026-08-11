param(
    [string]$InstallRoot = 'C:\OfflineTools',
    [switch]$IncludeAiTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BinRoot = Join-Path $InstallRoot 'bin'
$NodeRoot = Join-Path $InstallRoot 'Node\current'
$PythonPrimary = Get-ChildItem (Join-Path $InstallRoot 'envs') -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Scripts\\python\.exe$' } | Select-Object -First 1
New-Item -ItemType Directory -Force -Path $BinRoot | Out-Null

function Write-CmdLauncher {
    param([string]$Name,[string]$Body)
    $path = Join-Path $BinRoot ($Name + '.cmd')
    "@echo off`r`n$Body`r`n" | Set-Content -Path $path -Encoding ASCII
}

$Pwsh = Join-Path $InstallRoot 'Developer\PowerShell7\pwsh.exe'
$Code = Join-Path $InstallRoot 'Developer\VSCode\bin\code.cmd'
$Git = Join-Path $InstallRoot 'Developer\Git\cmd\git.exe'
$GiteaPortFile = Join-Path $InstallRoot 'Developer\Gitea\PORT.txt'
$GiteaPort = if (Test-Path $GiteaPortFile) { (Get-Content $GiteaPortFile -Raw).Trim() } else { '13080' }
$GiteaUrl = "http://127.0.0.1:$GiteaPort/"

if (Test-Path $Pwsh) { Write-CmdLauncher 'pwsh-ots' "`"$Pwsh`" %*" }
if (Test-Path $Code) { Write-CmdLauncher 'code-ots' "`"$Code`" %*" }
if (Test-Path $Git) { Write-CmdLauncher 'git-ots' "`"$Git`" %*" }
if (Test-Path (Join-Path $NodeRoot 'node.exe')) { Write-CmdLauncher 'node-ots' "`"$(Join-Path $NodeRoot 'node.exe')`" %*" }
if (Test-Path (Join-Path $NodeRoot 'npm.cmd')) {
    Write-CmdLauncher 'npm-ots' "set npm_config_offline=true`r`nset npm_config_audit=false`r`nset npm_config_fund=false`r`n`"$(Join-Path $NodeRoot 'npm.cmd')`" %*"
}
Write-CmdLauncher 'dev-hub' "start `"`" $GiteaUrl"

$coreCli = Join-Path $InstallRoot 'Developer\CLI-Core'
$aiCli = Join-Path $InstallRoot 'Developer\CLI-AI'
$headers = Join-Path $InstallRoot 'Node\headers'
$headerDir = Get-ChildItem $headers -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$pythonPath = if ($PythonPrimary) { $PythonPrimary.FullName } else { '' }
$nodePrefix = "set PATH=$NodeRoot;%PATH%"
$caLine = 'set NODE_OPTIONS=--use-system-ca'
$pythonLine = if ($pythonPath) { "set NODE_GYP_FORCE_PYTHON=$pythonPath" } else { '' }
$headersLine = if ($headerDir) { "set npm_config_nodedir=$($headerDir.FullName)" } else { '' }

foreach ($tool in @('pnpm','yarn','tsc','tsx','eslint','prettier','vsce','node-gyp')) {
    $cmd = Join-Path $coreCli ($tool + '.cmd')
    if (Test-Path $cmd) {
        $extra = if ($tool -eq 'node-gyp') { "$pythonLine`r`n$headersLine" } else { '' }
        Write-CmdLauncher ($tool + '-ots') "$nodePrefix`r`n$caLine`r`n$extra`r`n`"$cmd`" %*"
    }
}

if ($IncludeAiTools) {
    foreach ($tool in @('codex','cline','kilo','opencode')) {
        $cmd = Join-Path $aiCli ($tool + '.cmd')
        if (Test-Path $cmd) {
            Write-CmdLauncher $tool "$nodePrefix`r`n$caLine`r`n`"$cmd`" %*"
        }
    }
}

Write-Host "Managed launcher gateway ready: $BinRoot"
Write-Host "Local development hub: $GiteaUrl"
Write-Host 'Only this directory should be exposed through the machine PATH.'
