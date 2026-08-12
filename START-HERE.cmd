@echo off
setlocal EnableExtensions
cd /d "%~dp0"
chcp 65001 >nul 2>&1

set "DESKTOP_UI=%~dp0payload\bootstrap\OfflineToolsDesktop.exe"
set "SUITE_UI=%~dp0payload\bootstrap\OfflineToolsSuite.exe"
set "SETUP_UI=%~dp0payload\bootstrap\OfflineToolsSetup.exe"

if not exist "%DESKTOP_UI%" if not exist "%SUITE_UI%" if not exist "%SETUP_UI%" (
  mode con cols=126 lines=38 >nul 2>&1
  title Offline Automation ^& Development Suite
  color 0C
  cls
  echo.
  echo  ERROR: Professional interfaces were not found.
  echo  This folder is source code or an incomplete/corrupted bundle.
  echo  On the connected builder, run BUILD-BUNDLE.cmd first, then use
  echo  START-HERE.cmd from the generated offline-bundle folder.
  echo.
  pause
  exit /b 11
)

rem Elevate the launcher itself so child exit codes are preserved.  Previously the
rem legacy installer spawned an elevated child and immediately reported success.
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo Requesting administrator rights...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=Start-Process -FilePath '%~f0' -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
  exit /b %ERRORLEVEL%
)

if exist "%DESKTOP_UI%" (
  "%DESKTOP_UI%" --bundle-root "%~dp0"
  exit /b %ERRORLEVEL%
)

mode con cols=126 lines=38 >nul 2>&1
title Offline Automation ^& Development Suite
color 0B
cls

if exist "%SUITE_UI%" (
  echo.
  echo  Modern desktop interface was not found. Starting the console suite fallback.
  echo.
  "%SUITE_UI%" "%~dp0"
  set "EXITCODE=%ERRORLEVEL%"
) else (
  echo.
  echo  Suite shell was not found. Starting setup engine directly.
  echo.
  "%SETUP_UI%" --bundle-root "%~dp0"
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
