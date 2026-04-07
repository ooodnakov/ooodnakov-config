@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0oooconf.ps1" %*
exit /b %ERRORLEVEL%
