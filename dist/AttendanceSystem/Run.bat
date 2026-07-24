@echo off
cd /d "%~dp0"

:: Unblock all files in this folder (removes the internet download flag)
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue"

:: Strip BOM from tcl script silently
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0fix_bom.ps1"

:: Launch wish with no visible console window
start "" /B "%~dp0bin\wish.exe" "%~dp0attendance_system_gui.tcl"
