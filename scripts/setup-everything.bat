@echo off
REM === F4MP FULL SETUP (one click) ===
REM Builds the plugin, DOWNLOADS + installs F4SE 0.6.23 and the F4MP mod
REM (f4mp.esp + scripts), enables the plugin, and sets FALLOUT4_PATH.
REM
REM This needs an internet connection. Read the coloured summary at the end --
REM anything yellow is a step you must still do yourself (e.g. downgrading the
REM game to 1.10.163, which Steam can't automate).

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -All %*

echo.
pause
