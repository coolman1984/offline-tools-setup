@echo off
setlocal
cd /d "%~dp0"
title Offline Tools Setup - Bundle Builder
echo.
echo ============================================================
echo   OFFLINE TOOLS SETUP - COMPLETE BUNDLE BUILDER
echo   Run this ONLY on a trusted internet-connected Windows PC.
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Build-CompleteOfflineBundle.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Bundle build ended with error code %EXITCODE%.
) else (
  echo Complete offline bundle built successfully.
  echo Copy the offline-bundle folder to approved removable media.
)
echo.
pause
exit /b %EXITCODE%
