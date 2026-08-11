@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul 2>&1
mode con cols=120 lines=36 >nul 2>&1
title Offline Automation ^& Development Suite
color 0B
cls

set "SETUP_UI=%~dp0payload\bootstrap\OfflineToolsSetup.exe"

if exist "%SETUP_UI%" (
  "%SETUP_UI%" --bundle-root "%~dp0"
  set "EXITCODE=%ERRORLEVEL%"
) else (
  echo.
  echo  Professional setup interface was not found in this bundle.
  echo  Falling back to the legacy complete installer.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-AllOfflineTools.ps1"
  set "EXITCODE=%ERRORLEVEL%"
)

echo.
if not "%EXITCODE%"=="0" (
  echo Setup ended with error code %EXITCODE%.
  echo Review C:\OfflineTools\logs for details.
) else (
  echo Setup session completed successfully.
)
echo.
pause
exit /b %EXITCODE%
