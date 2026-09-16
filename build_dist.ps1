$src_app  = $PSScriptRoot
$src_tcl  = "C:\Users\kirut\AppData\Local\Apps\Tcl86"
$dist     = Join-Path $src_app "dist\AttendanceSystem"

Write-Host "Building distribution to: $dist"

# Clean previous dist
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null

# ---- 1. Copy app files ----
Write-Host "Copying app files..."
Copy-Item (Join-Path $src_app "attendance_system_gui.tcl") $dist
Copy-Item (Join-Path $src_app "fix_bom.ps1")              $dist

# Copy classes folder if it exists
$classesDir = Join-Path $src_app "classes"
if (Test-Path $classesDir) {
    Copy-Item $classesDir (Join-Path $dist "classes") -Recurse
}

# ---- 2. Copy wish.exe + essential DLLs ----
Write-Host "Copying Tcl/Tk runtime..."
$bin_dst = Join-Path $dist "bin"
New-Item -ItemType Directory -Path $bin_dst | Out-Null

$dlls = @(
    "wish.exe", "tclsh.exe",
    "tcl86t.dll", "tk86t.dll",
    "zlib1.dll", "libpng16.dll",
    "vcruntime140.dll", "vcruntime140_1.dll",
    "msvcp140.dll", "msvcp140_1.dll",
    "msvcp140_2.dll", "concrt140.dll"
)
foreach ($f in $dlls) {
    $full = Join-Path $src_tcl "bin\$f"
    if (Test-Path $full) {
        Copy-Item $full $bin_dst
    }
}

# ---- 3. Copy Tcl/Tk library folders ----
$lib_dst = Join-Path $dist "lib"
New-Item -ItemType Directory -Path $lib_dst | Out-Null

foreach ($folder in @("tcl8.6", "tk8.6", "tcl8")) {
    $s = Join-Path $src_tcl "lib\$folder"
    if (Test-Path $s) {
        Copy-Item $s (Join-Path $lib_dst $folder) -Recurse
        Write-Host "  Copied lib\$folder"
    }
}

# ---- 4. Write the launcher ----
Write-Host "Writing launcher..."
$launcher = @'
@echo off
setlocal
set DIR=%~dp0
set TCL_LIBRARY=%DIR%lib\tcl8.6
set TK_LIBRARY=%DIR%lib\tk8.6

REM Strip BOM from tcl script
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%DIR%fix_bom.ps1"

REM Launch wish (no console window)
start "" "%DIR%bin\wish.exe" "%DIR%attendance_system_gui.tcl"
'@
$launcher | Set-Content (Join-Path $dist "Run.bat") -Encoding ASCII

# VBS launcher (no black console window at all)
$vbs = @'
Dim fso, sh, dir
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Environment("PROCESS")("TCL_LIBRARY") = dir & "\lib\tcl8.6"
sh.Environment("PROCESS")("TK_LIBRARY")  = dir & "\lib\tk8.6"
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\fix_bom.ps1""", 0, True
sh.Run """" & dir & "\bin\wish.exe"" """ & dir & "\attendance_system_gui.tcl""", 0, False
'@
$vbs | Set-Content (Join-Path $dist "Run.vbs") -Encoding ASCII

Write-Host ""
Write-Host "Done! Distribution folder:"
Write-Host "  $dist"
Write-Host ""
Write-Host "To run: double-click  Run.vbs"
Write-Host "Share the entire 'dist\AttendanceSystem' folder - no install needed."
