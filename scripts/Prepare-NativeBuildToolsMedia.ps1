param(
    [string]$StagingRoot = 'C:\OTSVS',
    [string]$Destination = (Join-Path $PSScriptRoot '..\native-source\vs-build-tools')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($StagingRoot.Length -ge 80) { throw 'Visual Studio offline layout staging path must remain under 80 characters.' }
$StagingRoot = [System.IO.Path]::GetFullPath($StagingRoot)
$Destination = [System.IO.Path]::GetFullPath($Destination)
$Bootstrapper = Join-Path $StagingRoot 'vs_BuildTools.exe'
$BootstrapperUrl = 'https://aka.ms/vs/stable/vs_buildtools.exe'

Write-Host "Preparing Microsoft C/C++ Build Tools transferable offline layout..." -ForegroundColor Cyan
Remove-Item $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null
Invoke-WebRequest -Uri $BootstrapperUrl -OutFile $Bootstrapper -UseBasicParsing

$Signature = Get-AuthenticodeSignature $Bootstrapper
if ($Signature.Status -ne 'Valid' -or -not $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'Visual Studio Build Tools bootstrapper signature validation failed.'
}

$Args = @(
    '--layout',$StagingRoot,
    '--add','Microsoft.VisualStudio.Workload.VCTools',
    '--includeRecommended',
    '--lang','en-US',
    '--quiet','--wait','--norestart'
)
$Process = Start-Process -FilePath $Bootstrapper -ArgumentList $Args -Wait -PassThru
if ($Process.ExitCode -notin 0,3010) { throw "Visual Studio Build Tools layout creation failed with exit code $($Process.ExitCode)" }

if (-not (Test-Path (Join-Path $StagingRoot 'Catalog.json')) -and -not (Test-Path (Join-Path $StagingRoot 'channelManifest.json'))) {
    Write-Warning 'Layout metadata was not found at the expected names; verify the layout before target deployment.'
}

Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item (Join-Path $StagingRoot '*') $Destination -Recurse -Force

Write-Host "Native Build Tools media prepared: $Destination" -ForegroundColor Green
Write-Host 'The target installer will use --noweb and the same VCTools workload so missing components fail instead of downloading.' -ForegroundColor Green
