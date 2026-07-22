@echo off
setlocal
set DIR=%~dp0
set TCL_LIBRARY=%DIR%lib\tcl8.6
set TK_LIBRARY=%DIR%lib\tk8.6

REM Strip BOM from tcl script
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%DIR%fix_bom.ps1"

REM Launch wish (no console window)
start "" "%DIR%bin\wish.exe" "%DIR%attendance_system_gui.tcl"
