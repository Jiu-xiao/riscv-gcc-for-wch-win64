@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-full-build.ps1" %*
endlocal
