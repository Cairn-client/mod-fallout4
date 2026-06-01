@echo off
REM F4MP one-click build + deploy. Double-click this file.
REM It builds f4mp.dll and copies it (plus the Papyrus scripts) into your
REM Fallout 4 Data folder. Read the coloured summary at the end.
REM
REM Pass extra options through, e.g.:
REM   deploy.bat -BuildServer -SetEnvVar
REM   deploy.bat -Fallout4Path "D:\SteamLibrary\steamapps\common\Fallout 4"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*

echo.
pause
