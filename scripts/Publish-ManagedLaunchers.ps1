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
$Bash = Join-Path $InstallRoot 'Developer\GitBash\bin\bash.exe'
$GiteaPortFile = Join-Path $InstallRoot 'Developer\Gitea\PORT.txt'
$GiteaPort = if (Test-Path $GiteaPortFile) { (Get-Content $GiteaPortFile -Raw).Trim() } else { '13080' }
$GiteaUrl = "http://127.0.0.1:$GiteaPort/"

if (Test-Path $Pwsh) { Write-CmdLauncher 'pwsh-ots' "`"$Pwsh`" %*" }
if (Test-Path $Code) { Write-CmdLauncher 'code-ots' "`"$Code`" %*" }
if (Test-Path $Git) { Write-CmdLauncher 'git-ots' "`"$Git`" %*" }
if (Test-Path $Bash) { Write-CmdLauncher 'bash-ots' "`"$Bash`" %*" }

# Exact managed Python wrappers. They deliberately ignore PYTHONHOME/PYTHONPATH and user-site
# packages so an older workstation configuration cannot contaminate the suite.
$PythonRoot = Join-Path $InstallRoot 'Python'
foreach ($dir in Get-ChildItem $PythonRoot -Directory -ErrorAction SilentlyContinue) {
    $exe = Join-Path $dir.FullName 'python.exe'
    if (-not (Test-Path $exe)) { continue }
    $parts = $dir.Name.Split('.')
    if ($parts.Count -lt 2) { continue }
    $short = $parts[0] + $parts[1]
    $pythonEnv = "set PYTHONHOME=`r`nset PYTHONPATH=`r`nset PYTHONNOUSERSITE=1"
    Write-CmdLauncher ("python" + $short) "$pythonEnv`r`n`"$exe`" %*"
    Write-CmdLauncher ("pip" + $short) "$pythonEnv`r`nset PIP_NO_INDEX=1`r`n`"$exe`" -m pip %*"
}
if ($PythonPrimary) {
    $pythonEnv = "set PYTHONHOME=`r`nset PYTHONPATH=`r`nset PYTHONNOUSERSITE=1"
    Write-CmdLauncher 'python-full' "$pythonEnv`r`n`"$($PythonPrimary.FullName)`" %*"
    Write-CmdLauncher 'pip-full' "$pythonEnv`r`nset PIP_NO_INDEX=1`r`n`"$($PythonPrimary.FullName)`" -m pip %*"
}

$nodeEnvironment = "set PATH=$NodeRoot;%PATH%`r`nset NODE_PATH=`r`nset NODE_OPTIONS=--use-system-ca"
if (Test-Path (Join-Path $NodeRoot 'node.exe')) {
    Write-CmdLauncher 'node-ots' "$nodeEnvironment`r`n`"$(Join-Path $NodeRoot 'node.exe')`" %*"
}
if (Test-Path (Join-Path $NodeRoot 'npm.cmd')) {
    $npmEnvironment = "$nodeEnvironment`r`nset npm_config_offline=true`r`nset npm_config_audit=false`r`nset npm_config_fund=false`r`nset npm_config_script_shell=%ComSpec%"
    Write-CmdLauncher 'npm-ots' "$npmEnvironment`r`n`"$(Join-Path $NodeRoot 'npm.cmd')`" %*"
}
Write-CmdLauncher 'dev-hub' "start `"`" $GiteaUrl"

$coreCli = Join-Path $InstallRoot 'Developer\CLI-Core'
$aiCli = Join-Path $InstallRoot 'Developer\CLI-AI'
$headers = Join-Path $InstallRoot 'Node\headers'
$headerDir = Get-ChildItem $headers -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$pythonPath = if ($PythonPrimary) { $PythonPrimary.FullName } else { '' }
$pythonLine = if ($pythonPath) { "set NODE_GYP_FORCE_PYTHON=$pythonPath`r`nset npm_config_python=$pythonPath" } else { '' }
$headersLine = if ($headerDir) { "set npm_config_nodedir=$($headerDir.FullName)" } else { '' }
$scriptShellLine = 'set npm_config_script_shell=%ComSpec%'

foreach ($tool in @('pnpm','yarn','tsc','tsx','eslint','prettier','vsce','node-gyp')) {
    $cmd = Join-Path $coreCli ($tool + '.cmd')
    if (Test-Path $cmd) {
        $extra = if ($tool -eq 'node-gyp') { "$pythonLine`r`n$headersLine" } else { '' }
        Write-CmdLauncher ($tool + '-ots') "$nodeEnvironment`r`n$scriptShellLine`r`n$extra`r`n`"$cmd`" %*"
    }
}

if ($IncludeAiTools) {
    foreach ($tool in @('codex','cline','kilo','opencode')) {
        $cmd = Join-Path $aiCli ($tool + '.cmd')
        if (Test-Path $cmd) {
            Write-CmdLauncher $tool "$nodeEnvironment`r`n$scriptShellLine`r`n`"$cmd`" %*"
        }
    }
    $claude = Join-Path $aiCli 'claude.cmd'
    if ((Test-Path $claude) -and (Test-Path $Bash)) {
        Write-CmdLauncher 'claude' "$nodeEnvironment`r`nset CLAUDE_CODE_GIT_BASH_PATH=$Bash`r`nset DISABLE_AUTOUPDATER=1`r`n`"$claude`" %*"
    }
}

Write-Host "Managed launcher gateway ready: $BinRoot"
Write-Host "Local development hub: $GiteaUrl"
Write-Host 'Managed Python/Node commands are isolated from stale user environment variables.'
Write-Host 'Portable Git Bash is exposed only as bash-ots and is never the default shell.'
Write-Host 'Only this directory should be exposed through the machine PATH.'
