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
if ($Plan.schemaVersion -ne 1) { throw "Unsupported installation plan schema: $($Plan.schemaVersion)" }
$PlanBundleRoot = [System.IO.Path]::GetFullPath([string]$Plan.bundleRoot)
if ($PlanBundleRoot -ne $BundleRoot) { throw 'Installation plan bundle root does not match the launched bundle.' }
$InstallRoot = [System.IO.Path]::GetFullPath($(if ($Plan.installRoot) { [string]$Plan.installRoot } else { 'C:\OfflineTools' }))
if ($InstallRoot -ne [System.IO.Path]::GetFullPath('C:\OfflineTools')) { throw "Unsafe or unsupported installation root: $InstallRoot" }
$StateRoot = Join-Path $InstallRoot 'state'
$LogRoot = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $StateRoot,$LogRoot | Out-Null
$LogFile = Join-Path $LogRoot ("orchestrator-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $LogFile -Force | Out-Null
$CurrentPhase = 'start'

function Emit-Event([int]$Percent,[string]$Message) { Write-Output ("@@EVENT|{0}|{1}" -f $Percent,$Message) }
function Save-State([string]$Phase,[string]$Status,[string]$ErrorMessage = '') {
    [pscustomobject]@{
        updatedAtUtc=[DateTime]::UtcNow.ToString('o'); phase=$Phase; status=$Status; error=$ErrorMessage;
        planPath=$PlanPath; profiles=@($Plan.profiles); components=$Plan.components
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $StateRoot 'setup-state.json') -Encoding UTF8
}
function Set-Phase([string]$Phase) { $script:CurrentPhase=$Phase; Save-State $Phase 'running' }
function Assert-Admin {
    $Identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal=New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator rights are required.' }
}
function Invoke-PythonValidation {
    param([string]$PythonExe,[string]$Code,[string]$Name,[int]$TimeoutSeconds=20,[switch]$WarningOnly)
    $ValidationRoot=Join-Path $InstallRoot 'work\validation'
    New-Item -ItemType Directory -Force -Path $ValidationRoot | Out-Null
    $ScriptPath=Join-Path $ValidationRoot (([guid]::NewGuid().ToString('N'))+'.py')
    $Code | Set-Content $ScriptPath -Encoding UTF8
    try {
        $Proc=Start-Process -FilePath $PythonExe -ArgumentList @("`"$ScriptPath`"") -PassThru -WindowStyle Hidden
        if (-not $Proc.WaitForExit($TimeoutSeconds*1000)) {
            try { $Proc.Kill() } catch {}
            $Message="$Name timed out after $TimeoutSeconds seconds."
            if ($WarningOnly) { Write-Warning $Message; return $false }; throw $Message
        }
        if ($Proc.ExitCode -ne 0) {
            $Message="$Name failed with exit code $($Proc.ExitCode)."
            if ($WarningOnly) { Write-Warning $Message; return $false }; throw $Message
        }
        return $true
    } finally { Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue }
}
function Get-AllSelectedComponents {
    $items=New-Object System.Collections.Generic.List[string]
    if ($Plan.components) {
        foreach ($property in $Plan.components.PSObject.Properties) {
            foreach ($value in @($property.Value)) { if ($value) { $items.Add([string]$value) } }
        }
    }
    return @($items)
}

try {
    Assert-Admin
    Save-State 'start' 'running'
    $AllComponents=Get-AllSelectedComponents
    $NativeBuildSelected=(@($Plan.profiles) -contains 'native-build')

    Emit-Event 3 'Validating installation plan'
    Emit-Event 7 'Verifying complete offline bundle integrity'
    Set-Phase 'verify'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'scripts\Verify-OfflineBundle.ps1') -BundleRoot $BundleRoot
    if ($LASTEXITCODE -ne 0) { throw "Bundle integrity verification failed with exit code $LASTEXITCODE" }
    Save-State 'verify' 'complete'

    if (($AllComponents -contains 'tesseract') -and -not (Test-Path (Join-Path $BundleRoot 'payload\native\tesseract\tesseract-installer.exe'))) {
        throw 'The plan selects Tesseract, but its verified local installation media is missing.'
    }
    if (($AllComponents -contains 'sql-server-express') -and -not (Test-Path (Join-Path $BundleRoot 'payload\native\sql-server-express\setup.exe'))) {
        throw 'The plan selects SQL Server Express, but its verified local installation media is missing.'
    }
    if (($AllComponents -contains 'webview2') -and -not (Test-Path (Join-Path $BundleRoot 'payload\native\webview2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'))) {
        throw 'The plan selects WebView2, but its verified local installation media is missing.'
    }
    if ($NativeBuildSelected -and -not (Test-Path (Join-Path $BundleRoot 'payload\native\vs-build-tools\vs_BuildTools.exe'))) {
        throw 'The plan selects native build tools, but the verified Visual Studio layout is missing.'
    }
    if ($AllComponents -contains 'advanced-ocr') {
        $HeavyRoots = @(Get-ChildItem (Join-Path $BundleRoot 'payload\wheelhouse') -Directory -Filter 'py*-ocr-heavy' -ErrorAction SilentlyContinue)
        if ($HeavyRoots.Count -eq 0 -or (Get-ChildItem $HeavyRoots.FullName -File -Filter '_missing-packages.txt' -ErrorAction SilentlyContinue)) {
            throw 'The plan selects advanced OCR, but its offline wheelhouse is missing or incomplete.'
        }
    }

    Emit-Event 12 'Checking corporate policy, PATH and Windows compatibility'
    Set-Phase 'environment-hardening'
    & (Join-Path $BundleRoot 'scripts\Invoke-EnvironmentHardening.ps1') -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0) { throw "Windows environment compatibility check stopped setup with exit code $LASTEXITCODE. Review $StateRoot\environment-readiness.json" }
    Save-State 'environment-hardening' 'complete'

    Emit-Event 20 'Installing selected native Windows runtimes and components'
    Set-Phase 'native-components'
    $NativeArgs=@('-BundleRoot',$BundleRoot,'-InstallRoot',$InstallRoot)
    if ($Plan.includeTesseract -eq $true) { $NativeArgs += '-InstallTesseract' }
    if ($Plan.includeSqlServerExpress -eq $true) { $NativeArgs += '-InstallSqlServerExpress' }
    if ($AllComponents -contains 'webview2') { $NativeArgs += '-InstallWebView2' }
    & (Join-Path $BundleRoot 'scripts\Install-NativeComponents.ps1') @NativeArgs
    if ($LASTEXITCODE -ne 0) { throw "Native component installation failed with exit code $LASTEXITCODE" }
    Save-State 'native-components' 'complete'

    Emit-Event 34 'Installing isolated Python runtimes, selected packages and managed Node.js'
    Set-Phase 'language-stack'
    $PythonProfiles=@($Plan.pythonRequirementProfiles | ForEach-Object { [string]$_ })
    if ($AllComponents -contains 'advanced-ocr') {
        & (Join-Path $BundleRoot 'scripts\Install-OfflineTools.ps1') -InstallRoot $InstallRoot -PackageProfiles $PythonProfiles -IncludeHeavyOcr
    } else {
        & (Join-Path $BundleRoot 'scripts\Install-OfflineTools.ps1') -InstallRoot $InstallRoot -PackageProfiles $PythonProfiles
    }
    if ($LASTEXITCODE -ne 0) { throw "Language and package stack failed with exit code $LASTEXITCODE" }
    Save-State 'language-stack' 'complete'

    Emit-Event 58 'Installing professional editor, Git and local development hub'
    Set-Phase 'developer-stack'
    if ($Plan.installAiTools -eq $true) {
        & (Join-Path $BundleRoot 'scripts\Install-DeveloperStack.ps1') -InstallRoot $InstallRoot -BundleRoot $BundleRoot -InstallAiTools
    } else {
        & (Join-Path $BundleRoot 'scripts\Install-DeveloperStack.ps1') -InstallRoot $InstallRoot -BundleRoot $BundleRoot
    }
    if ($LASTEXITCODE -ne 0) { throw "Developer stack failed with exit code $LASTEXITCODE" }
    Save-State 'developer-stack' 'complete'

    if ($NativeBuildSelected) {
        Emit-Event 72 'Installing offline C/C++ and .NET native build toolchain'
        Set-Phase 'native-build-toolchain'
        & (Join-Path $BundleRoot 'scripts\Install-NativeBuildTools.ps1') -BundleRoot $BundleRoot -InstallRoot $InstallRoot
        if ($LASTEXITCODE -ne 0) { throw "Native build toolchain failed with exit code $LASTEXITCODE" }
        Save-State 'native-build-toolchain' 'complete'
    }

    Emit-Event 80 'Publishing managed command gateway and cleaning PATH exposure'
    Set-Phase 'managed-launchers'
    if ($Plan.installAiTools -eq $true) {
        & (Join-Path $BundleRoot 'scripts\Publish-ManagedLaunchers.ps1') -InstallRoot $InstallRoot -IncludeAiTools
    } else {
        & (Join-Path $BundleRoot 'scripts\Publish-ManagedLaunchers.ps1') -InstallRoot $InstallRoot
    }
    if ($LASTEXITCODE -ne 0) { throw 'Managed launcher creation failed.' }
    & (Join-Path $BundleRoot 'scripts\Invoke-EnvironmentHardening.ps1') -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0) { throw 'Final PATH/environment hardening failed.' }
    Save-State 'managed-launchers' 'complete'

    Emit-Event 87 'Running professional post-install validation'
    Set-Phase 'validation'
    $ManagedPython=Get-ChildItem (Join-Path $InstallRoot 'envs') -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\Scripts\\python\.exe$' } | Select-Object -First 1
    if (-not $ManagedPython) { throw 'Managed Python environment was not found during validation.' }

    & $ManagedPython.FullName -m pip check
    if ($LASTEXITCODE -ne 0) { throw 'Python dependency consistency check failed.' }

    if (@($Plan.profiles) -contains 'office') {
        if ($Plan.scan.officeInstalled -eq $true) {
            Emit-Event 90 'Validating Microsoft Office automation interface'
            $OfficeTest=@"
import win32com.client
app=None
try:
    app=win32com.client.DispatchEx('Excel.Application')
    app.Visible=False
    app.DisplayAlerts=False
    wb=app.Workbooks.Add()
    wb.Worksheets(1).Cells(1,1).Value='Offline Tools Setup'
    wb.Close(False)
finally:
    if app is not None: app.Quit()
"@
            Invoke-PythonValidation -PythonExe $ManagedPython.FullName -Code $OfficeTest -Name 'Excel COM validation' -TimeoutSeconds 25 -WarningOnly | Out-Null
        }
    }

    if (@($Plan.profiles) -contains 'pdf') {
        Emit-Event 92 'Validating PDF creation and parsing'
        $PdfTest="from reportlab.pdfgen import canvas; import tempfile,os,pypdf; p=tempfile.mktemp(suffix='.pdf'); c=canvas.Canvas(p); c.drawString(20,20,'Offline Tools'); c.save(); assert len(pypdf.PdfReader(p).pages)==1; os.remove(p)"
        Invoke-PythonValidation -PythonExe $ManagedPython.FullName -Code $PdfTest -Name 'PDF validation' -TimeoutSeconds 20 | Out-Null
    }

    if ($NativeBuildSelected) {
        Emit-Event 94 'Validating native compiler and .NET SDK'
        & (Join-Path $InstallRoot 'bin\dotnet-ots.cmd') --version
        if ($LASTEXITCODE -ne 0) { throw '.NET SDK smoke test failed.' }
        & (Join-Path $InstallRoot 'bin\cl-ots.cmd') 2>$null | Out-Null
        if ($LASTEXITCODE -notin 0,2) { throw 'MSVC compiler smoke test failed.' }
    }
    Save-State 'validation' 'complete'

    Emit-Event 97 'Writing installation receipt'
    Set-Phase 'receipt'
    $RebootFile=Join-Path $StateRoot 'reboot-required.json'
    [pscustomobject]@{
        completedAtUtc=[DateTime]::UtcNow.ToString('o'); status='success'; rebootRequired=(Test-Path $RebootFile);
        profiles=@($Plan.profiles); components=$Plan.components; pythonRequirementProfiles=@($Plan.pythonRequirementProfiles);
        installAiTools=[bool]$Plan.installAiTools; nativeBuildToolchain=$NativeBuildSelected;
        includeTesseract=[bool]$Plan.includeTesseract; includeSqlServerExpress=[bool]$Plan.includeSqlServerExpress;
        managedMachinePathEntry=(Join-Path $InstallRoot 'bin'); log=$LogFile; plan=$PlanPath
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $StateRoot 'last-install.json') -Encoding UTF8
    Save-State 'complete' 'success'

    Emit-Event 100 'Installation completed successfully'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    $Message=$_.Exception.Message
    Save-State $CurrentPhase 'error' $Message
    Write-Host "INSTALLATION ERROR: $Message" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
