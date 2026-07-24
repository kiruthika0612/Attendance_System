@echo off
echo Unblocking all files - please wait...
powershell -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue"
echo Done! You can now double-click Run.bat to launch the application.
echo This file is no longer needed after running it once.
pause
