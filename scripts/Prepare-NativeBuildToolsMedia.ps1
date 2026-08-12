param(
    [string]$StagingRoot = 'C:\OTSVS',
    [string]$Destination = (Join-Path $PSScriptRoot '..\native-source\vs-build-tools')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StagingRoot = [System.IO.Path]::GetFullPath($StagingRoot)
$Destination = [System.IO.Path]::GetFullPath($Destination)
$RunId = '{0}-{1}' -f $PID,([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
$WorkRoot = "$($StagingRoot.TrimEnd('\'))-$RunId"
if ($WorkRoot.Length -ge 80) { throw 'Visual Studio offline layout staging path must remain under 80 characters.' }
$Bootstrapper = Join-Path ([System.IO.Path]::GetTempPath()) "vs_BuildTools-$RunId.exe"
$PendingDestination = "$Destination.pending-$RunId"
$BootstrapperUrl = 'https://aka.ms/vs/stable/vs_buildtools.exe'

Write-Host "Preparing Microsoft C/C++ Build Tools transferable offline layout..." -ForegroundColor Cyan
try {
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
    Invoke-WebRequest -Uri $BootstrapperUrl -OutFile $Bootstrapper -UseBasicParsing

    $Signature = Get-AuthenticodeSignature $Bootstrapper
    if ($Signature.Status -ne 'Valid' -or -not $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw 'Visual Studio Build Tools bootstrapper signature validation failed.'
    }

    $Args = @(
        '--layout',$WorkRoot,
        '--add','Microsoft.VisualStudio.Workload.VCTools',
        '--includeRecommended',
        '--lang','en-US',
        '--quiet','--wait','--norestart'
    )
    $Process = Start-Process -FilePath $Bootstrapper -ArgumentList $Args -Wait -PassThru
    if ($Process.ExitCode -notin 0,3010) { throw "Visual Studio Build Tools layout creation failed with exit code $($Process.ExitCode)" }

    if (-not (Test-Path (Join-Path $WorkRoot 'Catalog.json')) -and -not (Test-Path (Join-Path $WorkRoot 'channelManifest.json'))) {
        throw 'Visual Studio Build Tools layout metadata is missing; the incomplete layout will not be published.'
    }

    Copy-Item $Bootstrapper (Join-Path $WorkRoot 'vs_BuildTools.exe') -Force
    Remove-Item $PendingDestination -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $PendingDestination | Out-Null
    Copy-Item (Join-Path $WorkRoot '*') $PendingDestination -Recurse -Force

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force -ErrorAction Stop }
    Move-Item $PendingDestination $Destination -ErrorAction Stop
} finally {
    Remove-Item $Bootstrapper -Force -ErrorAction SilentlyContinue
    Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $PendingDestination -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Native Build Tools media prepared: $Destination" -ForegroundColor Green
Write-Host 'The target installer will use --noweb and the same VCTools workload so missing components fail instead of downloading.' -ForegroundColor Green
