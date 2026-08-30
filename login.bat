@echo off
rem ============================================================
rem  login.bat - sign the Claude Code CLI in (one time only)
rem
rem  update.bat needs the command line Claude Code to be signed in.
rem  This runs:  claude auth login
rem  Just follow the browser sign-in that opens. Nothing to type.
rem
rem  ASCII-only on purpose: see the note in update.bat.
rem ============================================================

setlocal
cd /d "%~dp0"

set "CLAUDE_EXE="

rem 1) claude on PATH
for /f "delims=" %%i in ('where claude 2^>nul') do (
  if not defined CLAUDE_EXE set "CLAUDE_EXE=%%i"
)

rem 2) claude.exe bundled with the Claude desktop app (newest folder wins)
if not defined CLAUDE_EXE (
  for /f "delims=" %%i in ('dir /b /s /o-d "%APPDATA%\Claude\claude-code\claude.exe" 2^>nul') do (
    if not defined CLAUDE_EXE set "CLAUDE_EXE=%%i"
  )
)

if not defined CLAUDE_EXE (
  echo.
  echo Claude Code was not found.
  echo Install it first, then run this file again:
  echo.
  echo     winget install --id Anthropic.ClaudeCode
  echo.
  pause
  exit /b 1
)

echo.
echo   Using: %CLAUDE_EXE%
echo.
echo   Sign in in the browser window that opens.
echo   Nothing to type here.
echo.

"%CLAUDE_EXE%" auth login

echo.
echo   ---- current status ----
"%CLAUDE_EXE%" auth status

echo.
echo Done. Press any key to close this window.
pause >nul
exit /b 0
