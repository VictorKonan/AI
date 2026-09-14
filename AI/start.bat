@echo off
cd /d "%~dp0"
echo Starting 2D Asset Tool server...
start "2D Asset Server" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
timeout /t 1 /nobreak >nul
start "" "http://localhost:8000"
