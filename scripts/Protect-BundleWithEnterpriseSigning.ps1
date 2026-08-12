param(
    [Parameter(Mandatory=$true)][string]$BundleRoot,
    [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
if (-not (Test-Path $BundleRoot)) { throw "Bundle root not found: $BundleRoot" }

function Get-CodeSigningCertificate([string]$Thumbprint) {
    $clean = $Thumbprint.Replace(' ','').ToUpperInvariant()
    foreach ($storePath in @('Cert:\CurrentUser\My','Cert:\LocalMachine\My')) {
        $cert = Get-ChildItem $storePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint.Replace(' ','').ToUpperInvariant() -eq $clean -and $_.HasPrivateKey } |
            Select-Object -First 1
        if ($cert) { return $cert }
    }
    throw "Code-signing certificate with a private key was not found: $Thumbprint"
}

function Find-SignTool {
    $roots = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'),
        (Join-Path $env:ProgramFiles 'Windows Kits\10\bin')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $candidate = Get-ChildItem $root -Filter signtool.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Refresh-IntegrityManifest {
    $entries = Get-ChildItem $BundleRoot -File -Recurse |
        Where-Object { $_.Name -ne 'bundle-sha256.json' } |
        ForEach-Object {
            $relative = $_.FullName.Substring($BundleRoot.TrimEnd('\').Length).TrimStart('\').Replace('\','/')
            [pscustomobject]@{
                path = $relative
                sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                size = $_.Length
            }
        }
    $entries | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $BundleRoot 'bundle-sha256.json') -Encoding UTF8
}

$cert = Get-CodeSigningCertificate $CertificateThumbprint
if (-not ($cert.EnhancedKeyUsageList | Where-Object { $_.ObjectId.Value -eq '1.3.6.1.5.5.7.3.3' })) {
    throw 'The selected certificate does not advertise the Code Signing enhanced key usage.'
}

Write-Host 'Signing PowerShell control scripts with the approved enterprise certificate...' -ForegroundColor Cyan
$PowerShellFiles = Get-ChildItem (Join-Path $BundleRoot 'scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $PowerShellFiles) {
    $params = @{
        FilePath = $file.FullName
        Certificate = $cert
        HashAlgorithm = 'SHA256'
        ErrorAction = 'Stop'
    }
    if ($TimestampUrl) { $params.TimestampServer = $TimestampUrl }
    $result = Set-AuthenticodeSignature @params
    if ($result.Status -notin 'Valid','UnknownError') {
        throw "PowerShell signing failed for $($file.Name): $($result.StatusMessage)"
    }
}

$UiExecutables = @(Get-ChildItem (Join-Path $BundleRoot 'payload\bootstrap') -Filter '*.exe' -File -ErrorAction SilentlyContinue)
$SignedUiExecutables = @()
if ($UiExecutables.Count -eq 0) { throw 'No professional interface executables were found to sign.' }
if ($UiExecutables.Count -gt 0) {
    $SignTool = Find-SignTool
    if ($SignTool) {
        Write-Host 'Signing all professional interface executables...' -ForegroundColor Cyan
        foreach ($UiExe in $UiExecutables) {
            $args = @('sign','/sha1',$cert.Thumbprint,'/fd','SHA256')
            if ($TimestampUrl) { $args += @('/tr',$TimestampUrl,'/td','SHA256') }
            $args += $UiExe.FullName
            $proc = Start-Process -FilePath $SignTool -ArgumentList $args -Wait -PassThru
            if ($proc.ExitCode -ne 0) { throw "signtool failed for $($UiExe.Name) with exit code $($proc.ExitCode)" }
            $SignedUiExecutables += $UiExe
        }
    } else {
        throw 'signtool.exe was not found; interface executables cannot be declared enterprise-signed.'
    }
}

Write-Host 'Verifying signed PowerShell files...' -ForegroundColor Cyan
foreach ($file in $PowerShellFiles) {
    $signature = Get-AuthenticodeSignature $file.FullName
    if ($signature.Status -ne 'Valid') {
        throw "Signature verification failed: $($file.FullName) => $($signature.Status)"
    }
}
foreach ($file in $SignedUiExecutables) {
    $signature = Get-AuthenticodeSignature $file.FullName
    if ($signature.Status -ne 'Valid') {
        throw "Executable signature verification failed: $($file.FullName) => $($signature.Status)"
    }
}

Refresh-IntegrityManifest
[pscustomobject]@{
    signedAtUtc = [DateTime]::UtcNow.ToString('o')
    certificateSubject = $cert.Subject
    certificateThumbprint = $cert.Thumbprint
    timestampUrl = $TimestampUrl
    scriptsSigned = @($PowerShellFiles).Count
    interfaceExecutablesSigningAttempted = @($UiExecutables).Count
} | ConvertTo-Json | Set-Content (Join-Path $BundleRoot 'enterprise-signing.json') -Encoding UTF8
Refresh-IntegrityManifest

Write-Host 'Enterprise signing complete and the SHA-256 bundle manifest was refreshed.' -ForegroundColor Green
Write-Host 'The target tool never changes AppLocker, WDAC, or PowerShell Group Policy to bypass enterprise controls.' -ForegroundColor Green
