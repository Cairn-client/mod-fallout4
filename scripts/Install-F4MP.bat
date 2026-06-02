@echo off
REM Double-click launcher for the F4MP installer. Runs the PowerShell script
REM (bypassing the execution policy) from this same folder, then pauses so you
REM can read the result.
setlocal
cd /d "%~dp0"
echo Installing F4MP ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-F4MP.ps1" %*
echo.
pause
