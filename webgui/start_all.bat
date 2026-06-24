@echo off
setlocal
cd /d "%~dp0"
start "6GR WebGUI Backend" cmd /c start_backend.bat
timeout /t 3 >nul
start "6GR WebGUI Frontend" cmd /c start_frontend.bat
start "" http://localhost:5173

