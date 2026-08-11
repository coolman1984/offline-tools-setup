param(
    [string]$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$InstallRoot = 'C:\OfflineTools'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Set-RebootRequired([string]$Reason) {
    $StateRoot = Join-Path $InstallRoot 'state'
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    [pscustomobject]@{ required=$true; reason=$Reason; recordedAtUtc=[DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content (Join-Path $StateRoot 'reboot-required.json') -Encoding UTF8
}
function Invoke-Setup([string]$FilePath,[object[]]$Arguments,[string]$Name,[int[]]$SuccessCodes=@(0,1638,1641,3010)) {
    $Proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru
    if ($Proc.ExitCode -in 1641,3010) { Set-RebootRequired "$Name returned $($Proc.ExitCode)" }
    if ($SuccessCodes -notcontains $Proc.ExitCode) { throw "$Name failed with exit code $($Proc.ExitCode)" }
}

if (-not (Test-IsAdministrator)) { throw 'Native build toolchain installation requires Administrator rights.' }
$Manifest = Get-Content (Join-Path $BundleRoot 'config\tool-manifest.json') -Raw | ConvertFrom-Json
$BinRoot = Join-Path $InstallRoot 'bin'
New-Item -ItemType Directory -Force -Path $BinRoot | Out-Null

Write-Host "`n==> Installing .NET 10 LTS SDK from local media" -ForegroundColor Cyan
$DotNetInstaller = Join-Path $BundleRoot ('payload\installers\dotnet\' + [string]$Manifest.microsoft.dotnetSdk.file)
if (-not (Test-Path $DotNetInstaller)) { throw "Missing .NET SDK installer: $DotNetInstaller" }
$RequiredSdk = [string]$Manifest.microsoft.dotnetSdk.version
$InstalledSdks = @()
try { $InstalledSdks = @(& dotnet.exe --list-sdks 2>$null) } catch {}
if (-not ($InstalledSdks | Where-Object { $_ -match ('^' + [regex]::Escape($RequiredSdk) + '\s') })) {
    Invoke-Setup $DotNetInstaller @('/install','/quiet','/norestart') '.NET SDK'
}
$DotNetExe = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $DotNetExe) {
    $DotNetCandidate = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
    if (Test-Path $DotNetCandidate) { $DotNetExe = Get-Item $DotNetCandidate }
}
if (-not $DotNetExe) { throw '.NET SDK installation completed but dotnet.exe was not found.' }
"@echo off`r`n`"$($DotNetExe.Source)`" %*`r`n" | Set-Content (Join-Path $BinRoot 'dotnet-ots.cmd') -Encoding ASCII

Write-Host "`n==> Installing Microsoft C/C++ Build Tools from complete offline layout" -ForegroundColor Cyan
$BuildToolsRoot = Join-Path $BundleRoot ([string]$Manifest.microsoft.visualStudioBuildTools.offlineMediaRelativePath)
$BuildToolsSetup = Join-Path $BuildToolsRoot ([string]$Manifest.microsoft.visualStudioBuildTools.requiredSetupFile)
if (-not (Test-Path $BuildToolsSetup)) {
    throw "Native Build Toolchain was selected, but complete Visual Studio Build Tools offline media is missing: $BuildToolsSetup"
}
$VsArgs = @(
    '--quiet','--wait','--norestart','--noweb',
    '--add',[string]$Manifest.microsoft.visualStudioBuildTools.workload,
    '--includeRecommended'
)
Invoke-Setup $BuildToolsSetup $VsArgs 'Visual Studio Build Tools' @(0,1641,3010)

$VsWhereCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
)
$VsWhere = $VsWhereCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $VsWhere) { throw 'Visual Studio Build Tools installed but vswhere.exe was not found.' }
$VsInstall = (& $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if (-not $VsInstall) { throw 'MSVC x64/x86 compiler component was not detected after installation.' }
$VcVars = Join-Path $VsInstall 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $VcVars)) { throw "MSVC environment script was not found: $VcVars" }

$NativeShell = "@echo off`r`ncall `"$VcVars`" >nul`r`ncmd.exe /k`r`n"
$NativeShell | Set-Content (Join-Path $BinRoot 'native-shell-ots.cmd') -Encoding ASCII
$ClWrapper = "@echo off`r`ncall `"$VcVars`" >nul`r`ncl.exe %*`r`n"
$ClWrapper | Set-Content (Join-Path $BinRoot 'cl-ots.cmd') -Encoding ASCII
$MsBuildWrapper = "@echo off`r`ncall `"$VcVars`" >nul`r`nmsbuild.exe %*`r`n"
$MsBuildWrapper | Set-Content (Join-Path $BinRoot 'msbuild-ots.cmd') -Encoding ASCII

Write-Host "`n==> Staging pre-bundled Node.js headers for zero-download native addon builds" -ForegroundColor Cyan
$HeadersSource = Join-Path $BundleRoot 'payload\developer\node-headers'
if (-not (Test-Path (Join-Path $HeadersSource 'include\node'))) { throw 'Pre-bundled Node.js headers are missing or incomplete.' }
$HeadersTarget = Join-Path $InstallRoot ('Node\headers\' + [string]$Manifest.node.version)
Remove-Item $HeadersTarget -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $HeadersTarget | Out-Null
Copy-Item (Join-Path $HeadersSource '*') $HeadersTarget -Recurse -Force

$ManagedPython = Get-ChildItem (Join-Path $InstallRoot 'envs') -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Scripts\\python\.exe$' } | Select-Object -First 1
$NodeGyp = Join-Path $InstallRoot 'Developer\CLI-Core\node-gyp.cmd'
$NodeRoot = Join-Path $InstallRoot 'Node\current'
if ($ManagedPython -and (Test-Path $NodeGyp)) {
    $Body = "@echo off`r`nset PATH=$NodeRoot;%PATH%`r`nset NODE_GYP_FORCE_PYTHON=$($ManagedPython.FullName)`r`nset npm_config_nodedir=$HeadersTarget`r`n`"$NodeGyp`" --nodedir=`"$HeadersTarget`" %*`r`n"
    $Body | Set-Content (Join-Path $BinRoot 'node-gyp-ots.cmd') -Encoding ASCII
}

Write-Host "`n==> Validating compiler and SDK toolchain" -ForegroundColor Cyan
& (Join-Path $BinRoot 'cl-ots.cmd') 2>&1 | Select-Object -First 5 | Write-Host
if ($LASTEXITCODE -notin 0,2) { throw 'MSVC compiler validation failed.' }
& $DotNetExe.Source --version
if ($LASTEXITCODE -ne 0) { throw '.NET SDK validation failed.' }

Write-Host '`nNative Windows build toolchain installed successfully.' -ForegroundColor Green
