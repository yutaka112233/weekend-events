@echo off
rem ============================================================
rem  update.bat - weekly updater for events.json
rem
rem  Usage:
rem    update.bat          run and keep the window open (manual run)
rem    update.bat /quiet   run without pausing (for Task Scheduler)
rem
rem  This file is intentionally ASCII-only: .bat files are read
rem  using the console code page, so Japanese text here can break
rem  depending on the machine's settings. All messages, logging,
rem  validation, backup/restore and the toast notification live
rem  in update.ps1.
rem
rem  See README.md for the Task Scheduler setup.
rem ============================================================

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update.ps1"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
  echo.
  echo [OK] events.json updated.
) else (
  echo.
  echo [FAILED] exit code %RC% - see the logs folder for details.
)

if /i "%~1"=="/quiet" goto :end
echo.
pause

:end
exit /b %RC%
