@echo off
rem ============================================================
rem  serve.bat - open the event list in your browser
rem
rem  Double-click this file. It starts a small local server and
rem  opens http://localhost:8765/ automatically.
rem  To stop it: press Ctrl+C here, or just close this window.
rem
rem  ASCII-only on purpose: .bat files are read with the console
rem  code page, so Japanese text here can break. All Japanese
rem  messages live in serve.ps1.
rem ============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\serve.ps1"
