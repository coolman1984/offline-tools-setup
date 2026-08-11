@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul 2>&1
mode con cols=126 lines=38 >nul 2>&1
title Offline Automation ^& Development Suite
color 0B
cls

set "SUITE_UI=%~dp0payload\bootstrap\OfflineToolsSuite.exe"
set "SETUP_UI=%~dp0payload\bootstrap\OfflineToolsSetup.exe"

if exist "%SUITE_UI%" (
  "%SUITE_UI%" "%~dp0"
  set "EXITCODE=%ERRORLEVEL%"
) else if exist "%SETUP_UI%" (
  echo.
  echo  Tabbed suite shell was not found. Starting setup engine directly.
  echo.
  "%SETUP_UI%" --bundle-root "%~dp0"
  set "EXITCODE=%ERRORLEVEL%"
) else (
  echo.
  echo  Professional interfaces were not found in this bundle.
  echo  Falling back to the legacy complete installer.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-AllOfflineTools.ps1"
  set "EXITCODE=%ERRORLEVEL%"
)

echo.
if not "%EXITCODE%"=="0" (
  echo Suite session ended with error code %EXITCODE%.
  echo Review C:\OfflineTools\logs and C:\OfflineTools\state for details.
) else (
  echo Suite session completed successfully.
)
echo.
pause
exit /b %EXITCODE%
