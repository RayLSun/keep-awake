@echo off
rem keep-awake one-click starter (Windows)
rem Double-click, answer the prompts, leave the window open.
rem Stop with Ctrl+C (everything is restored automatically).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0keep-awake.ps1" %*
echo.
echo [keep-awake] stopped.
pause
