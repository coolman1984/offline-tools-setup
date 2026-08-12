@echo off
setlocal
cd /d "%~dp0"
title Offline Tools Setup - Professional Bundle Builder
cls
echo.
echo ============================================================
echo   OFFLINE AUTOMATION ^& DEVELOPMENT SUITE
echo   PROFESSIONAL COMPLETE BUNDLE BUILDER
echo ============================================================
echo   Run only on a trusted internet-connected Windows PC.
echo   Target PCs will perform ZERO software/package downloads.
echo ============================================================
echo.

set "NEED_VS_MEDIA=0"
if not exist "%~dp0native-source\vs-build-tools\vs_BuildTools.exe" set "NEED_VS_MEDIA=1"
if not exist "%~dp0native-source\vs-build-tools\Catalog.json" if not exist "%~dp0native-source\vs-build-tools\channelManifest.json" set "NEED_VS_MEDIA=1"
if "%NEED_VS_MEDIA%"=="1" (
  echo [1/3] Preparing transferable Microsoft C/C++ Build Tools media...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Prepare-NativeBuildToolsMedia.ps1"
  if errorlevel 1 (
    echo.
    echo ERROR: Native Build Tools media preparation failed.
    pause
    exit /b 1
  )
) else (
  echo [1/3] Existing approved Native Build Tools media found. Reusing it.
)

echo.
echo [2/3] Building the complete verified offline bundle...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Build-CompleteOfflineBundle.ps1"
set EXITCODE=%ERRORLEVEL%
if not "%EXITCODE%"=="0" (
  echo.
  echo Bundle build ended with error code %EXITCODE%.
  pause
  exit /b %EXITCODE%
)

echo.
if defined OFFLINE_TOOLS_SIGNING_THUMBPRINT (
  echo [3/3] Applying approved enterprise code signing...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Protect-BundleWithEnterpriseSigning.ps1" -BundleRoot "%~dp0offline-bundle" -CertificateThumbprint "%OFFLINE_TOOLS_SIGNING_THUMBPRINT%"
  if errorlevel 1 (
    echo ERROR: Enterprise signing failed. Unsigned bundle will NOT be declared ready.
    pause
    exit /b 1
  )
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0offline-bundle\scripts\Verify-OfflineBundle.ps1" -BundleRoot "%~dp0offline-bundle"
  if errorlevel 1 (
    echo ERROR: Signed bundle integrity verification failed.
    pause
    exit /b 1
  )
) else (
  echo [3/3] Enterprise signing not configured. Bundle remains integrity-verified but organization-unsigned.
)

echo.
echo ============================================================
echo   COMPLETE OFFLINE BUNDLE BUILT SUCCESSFULLY
echo ============================================================
echo Copy the offline-bundle folder to approved removable media.
echo.
pause
exit /b 0
