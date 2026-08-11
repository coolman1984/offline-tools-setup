param(
    [Parameter(Mandatory=$true)][string]$PlanPath,
    [Parameter(Mandatory=$true)][string]$BundleRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
if (-not (Test-Path $PlanPath)) { throw "Installation plan not found: $PlanPath" }
$Plan = Get-Content $PlanPath -Raw | ConvertFrom-Json
$InstallRoot = if ($Plan.installRoot) { [string]$Plan.installRoot } else { 'C:\OfflineTools' }
$StateRoot = Join-Path $InstallRoot 'state'
$LogRoot = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $StateRoot,$LogRoot | Out-Null
$LogFile = Join-Path $LogRoot ("orchestrator-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $LogFile -Force | Out-Null
$CurrentPhase = 'start'

function Emit-Event([int]$Percent,[string]$Message) {
    Write-Output ("@@EVENT|{0}|{1}" -f $Percent,$Message)
}

function Save-State([string]$Phase,[string]$Status,[string]$ErrorMessage = '') {
    $State = [pscustomobject]@{
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        phase = $Phase
        status = $Status
        error = $ErrorMessage
        planPath = $PlanPath
        profiles = @($Plan.profiles)
        components = $Plan.components
    }
    $State | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $StateRoot 'setup-state.json') -Encoding UTF8
}

function Set-Phase([string]$Phase) {
    $script:CurrentPhase = $Phase
    Save-State $Phase 'running'
}

function Assert-Admin {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'The selected-profile installer must run as Administrator.'
    }
}

function Invoke-PythonValidation {
    param(
        [Parameter(Mandatory=$true)][string]$PythonExe,
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = 20,
        [switch]$WarningOnly
    )

    $ValidationRoot = Join-Path $InstallRoot 'work\validation'
    New-Item -ItemType Directory -Force -Path $ValidationRoot | Out-Null
    $ScriptPath = Join-Path $ValidationRoot (([guid]::NewGuid().ToString('N')) + '.py')
    $Code | Set-Content $ScriptPath -Encoding UTF8

    try {
        $Proc = Start-Process -FilePath $PythonExe -ArgumentList @("`"$ScriptPath`"") -PassThru -WindowStyle Hidden
        if (-not $Proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $Proc.Kill() } catch {}
            $Message = "$Name timed out after $TimeoutSeconds seconds."
            if ($WarningOnly) { Write-Warning $Message; return $false }
            throw $Message
        }
        if ($Proc.ExitCode -ne 0) {
            $Message = "$Name failed with exit code $($Proc.ExitCode)."
            if ($WarningOnly) { Write-Warning $Message; return $false }
            throw $Message
        }
        return $true
    }
    finally {
        Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Assert-Admin
    Save-State 'start' 'running'

    Emit-Event 3 'Validating installation plan'
    if ($Plan.schemaVersion -ne 1) { throw "Unsupported installation plan schema: $($Plan.schemaVersion)" }

    Emit-Event 8 'Verifying complete offline bundle integrity'
    Set-Phase 'verify'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Verify-OfflineBundle.ps1') -BundleRoot $BundleRoot
    if ($LASTEXITCODE -ne 0) { throw "Bundle integrity verification failed with exit code $LASTEXITCODE" }
    Save-State 'verify' 'complete'

    Emit-Event 14 'Applying Windows workstation prerequisites'
    Set-Phase 'windows-prerequisites'
    $LongPathKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    try {
        $CurrentLongPath = (Get-ItemProperty -Path $LongPathKey -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
        if ($CurrentLongPath -ne 1) {
            Set-ItemProperty -Path $LongPathKey -Name LongPathsEnabled -Type DWord -Value 1
        }
    } catch {
        Write-Warning "Could not enable Win32 long paths automatically: $($_.Exception.Message)"
    }
    Save-State 'windows-prerequisites' 'complete'

    Emit-Event 20 'Installing selected native Windows components'
    Set-Phase 'native-components'
    $NativeArgs = @('-BundleRoot',$BundleRoot)
    if ($Plan.includeTesseract -eq $true) { $NativeArgs += '-InstallTesseract' }
    if ($Plan.includeSqlServerExpress -eq $true) { $NativeArgs += '-InstallSqlServerExpress' }
    & (Join-Path $BundleRoot 'scripts\Install-NativeComponents.ps1') @NativeArgs
    if ($LASTEXITCODE -ne 0) { throw "Native component installation failed with exit code $LASTEXITCODE" }
    Save-State 'native-components' 'complete'

    Emit-Event 38 'Installing Python runtimes, selected packages and managed Node.js'
    Set-Phase 'language-stack'
    $PythonProfiles = @($Plan.pythonRequirementProfiles | ForEach-Object { [string]$_ })
    & (Join-Path $BundleRoot 'scripts\Install-OfflineTools.ps1') -InstallRoot $InstallRoot -PackageProfiles $PythonProfiles
    if ($LASTEXITCODE -ne 0) { throw "Language and package stack failed with exit code $LASTEXITCODE" }
    Save-State 'language-stack' 'complete'

    Emit-Event 68 'Installing professional editor, Git and local development hub'
    Set-Phase 'developer-stack'
    if ($Plan.installAiTools -eq $true) {
        & (Join-Path $BundleRoot 'scripts\Install-DeveloperStack.ps1') -InstallRoot $InstallRoot -BundleRoot $BundleRoot -InstallAiTools
    } else {
        & (Join-Path $BundleRoot 'scripts\Install-DeveloperStack.ps1') -InstallRoot $InstallRoot -BundleRoot $BundleRoot
    }
    if ($LASTEXITCODE -ne 0) { throw "Developer stack failed with exit code $LASTEXITCODE" }
    Save-State 'developer-stack' 'complete'

    Emit-Event 86 'Running professional post-install validation'
    Set-Phase 'validation'
    $PythonFull = Join-Path $InstallRoot 'envs'
    $ManagedPython = Get-ChildItem $PythonFull -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\Scripts\\python\.exe$' } |
        Select-Object -First 1
    if (-not $ManagedPython) { throw 'Managed Python environment was not found during validation.' }

    if (@($Plan.profiles) -contains 'office') {
        if ($Plan.scan.officeInstalled -eq $true) {
            Emit-Event 90 'Validating Microsoft Office automation interface'
            $OfficeTest = @"
import win32com.client
app = None
try:
    app = win32com.client.DispatchEx('Excel.Application')
    app.Visible = False
    app.DisplayAlerts = False
    wb = app.Workbooks.Add()
    wb.Worksheets(1).Cells(1,1).Value = 'Offline Tools Setup'
    wb.Close(False)
finally:
    if app is not None:
        app.Quit()
print('Office COM automation OK')
"@
            Invoke-PythonValidation -PythonExe $ManagedPython.FullName -Code $OfficeTest -Name 'Excel COM validation' -TimeoutSeconds 25 -WarningOnly | Out-Null
        } else {
            Write-Warning 'Office file automation is installed, but Microsoft Office desktop applications were not detected; COM validation skipped.'
        }
    }

    if (@($Plan.profiles) -contains 'pdf') {
        Emit-Event 93 'Validating PDF creation and parsing'
        $PdfTest = @"
from reportlab.pdfgen import canvas
import tempfile, os, pypdf
p = tempfile.mktemp(suffix='.pdf')
try:
    c = canvas.Canvas(p)
    c.drawString(20, 20, 'Offline Tools Setup')
    c.save()
    assert len(pypdf.PdfReader(p).pages) == 1
finally:
    if os.path.exists(p):
        os.remove(p)
print('PDF pipeline OK')
"@
        Invoke-PythonValidation -PythonExe $ManagedPython.FullName -Code $PdfTest -Name 'PDF creation/parsing validation' -TimeoutSeconds 20 | Out-Null
    }

    Save-State 'validation' 'complete'

    Emit-Event 97 'Writing installation receipt'
    Set-Phase 'receipt'
    $RebootFile = Join-Path $StateRoot 'reboot-required.json'
    $Receipt = [pscustomobject]@{
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'success'
        rebootRequired = (Test-Path $RebootFile)
        profiles = @($Plan.profiles)
        components = $Plan.components
        pythonRequirementProfiles = @($Plan.pythonRequirementProfiles)
        installAiTools = [bool]$Plan.installAiTools
        includeTesseract = [bool]$Plan.includeTesseract
        includeSqlServerExpress = [bool]$Plan.includeSqlServerExpress
        log = $LogFile
        plan = $PlanPath
    }
    $Receipt | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $StateRoot 'last-install.json') -Encoding UTF8
    Save-State 'complete' 'success'

    Emit-Event 100 'Installation completed successfully'
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    $Message = $_.Exception.Message
    Save-State $CurrentPhase 'error' $Message
    Write-Host "INSTALLATION ERROR: $Message" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
