Dim fso, sh, dir
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)

' Unblock all files (removes internet download Zone.Identifier flag)
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""Get-ChildItem -Path '" & dir & "' -Recurse | Unblock-File -ErrorAction SilentlyContinue""", 0, True

' Strip BOM from tcl script
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\fix_bom.ps1""", 0, True

' Set library paths and launch wish with no console
sh.Environment("PROCESS")("TCL_LIBRARY") = dir & "\lib\tcl8.6"
sh.Environment("PROCESS")("TK_LIBRARY")  = dir & "\lib\tk8.6"
sh.Run """" & dir & "\bin\wish.exe"" """ & dir & "\attendance_system_gui.tcl""", 0, False
