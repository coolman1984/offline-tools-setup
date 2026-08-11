@echo off
setlocal
cd /d "%~dp0"
title Offline Tools Setup
echo.
echo ============================================================
echo   OFFLINE TOOLS SETUP - Windows 10/11 x64
echo   No internet will be used by the target installer.
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-OfflineTools.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Installation ended with error code %EXITCODE%.
) else (
  echo Installation completed successfully.
)
echo.
pause
exit /b %EXITCODE%
