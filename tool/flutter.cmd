@echo off
rem Run the local helper with a policy scoped to this child process only.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0flutter.ps1" %*
exit /b %ERRORLEVEL%
