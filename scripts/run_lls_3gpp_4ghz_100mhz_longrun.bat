@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run_lls_3gpp_4ghz_100mhz_longrun.ps1" %*
exit /b %ERRORLEVEL%
