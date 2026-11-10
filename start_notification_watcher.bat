@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch_windows_notifications.ps1"
echo.
echo Monitoring stopped.
pause
