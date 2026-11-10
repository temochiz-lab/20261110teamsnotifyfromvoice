@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0notify_windows.ps1"
if errorlevel 1 (
  echo ??????????????
  pause
)
