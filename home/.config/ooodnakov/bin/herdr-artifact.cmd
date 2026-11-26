@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0herdr-artifact.ps1" %*
exit /b %ERRORLEVEL%
