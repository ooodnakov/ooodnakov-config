@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0o.ps1" %*
exit /b %ERRORLEVEL%
