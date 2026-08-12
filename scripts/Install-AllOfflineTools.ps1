param(
    [string]$InstallRoot = 'C:\OfflineTools'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BundleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host 'Requesting administrator rights...'
    $Args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-InstallRoot',"`"$InstallRoot`"")
    $Elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList $Args -Wait -PassThru
    exit $Elevated.ExitCode
}

Write-Host 'Verifying the complete bundle before any installation...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Verify-OfflineBundle.ps1') -BundleRoot $BundleRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '`nInstalling native Windows/database/OCR prerequisites...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Install-NativeComponents.ps1') -BundleRoot $BundleRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '`nInstalling Python, packages, Node.js and offline development environments...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Install-OfflineTools.ps1') -InstallRoot $InstallRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '`nInstalling VS Code, pre-bundled extensions, Git, Gitea and AI/developer CLIs...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Install-DeveloperStack.ps1') -InstallRoot $InstallRoot -BundleRoot $BundleRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '`nALL OFFLINE TOOLS SETUP COMPLETED SUCCESSFULLY.' -ForegroundColor Green
Write-Host 'No local AI models were installed. No target-side downloads are required.' -ForegroundColor Green
exit 0
