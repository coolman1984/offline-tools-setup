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

if not exist "%~dp0native-source\vs-build-tools\vs_BuildTools.exe" (
  echo [1/2] Preparing transferable Microsoft C/C++ Build Tools media...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Prepare-NativeBuildToolsMedia.ps1"
  if errorlevel 1 (
    echo.
    echo ERROR: Native Build Tools media preparation failed.
    pause
    exit /b 1
  )
) else (
  echo [1/2] Existing approved Native Build Tools media found. Reusing it.
)

echo.
echo [2/2] Building the complete verified offline bundle...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Build-CompleteOfflineBundle.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Bundle build ended with error code %EXITCODE%.
) else (
  echo ============================================================
  echo   COMPLETE OFFLINE BUNDLE BUILT SUCCESSFULLY
  echo ============================================================
  echo Copy the offline-bundle folder to approved removable media.
)
echo.
pause
exit /b %EXITCODE%
