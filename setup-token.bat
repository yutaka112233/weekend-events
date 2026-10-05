@echo off
rem ============================================================
rem  setup-token.bat - register a long-lived (about 1 year) token
rem  for the automatic weekly update, so it does not stop when the
rem  normal Claude Code login expires.
rem
rem  Double-click this file and follow the instructions in the window.
rem  ASCII-only on purpose: see the note in update.bat.
rem ============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup-token.ps1"
