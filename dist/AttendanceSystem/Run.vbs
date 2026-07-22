Dim fso, sh, dir
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Environment("PROCESS")("TCL_LIBRARY") = dir & "\lib\tcl8.6"
sh.Environment("PROCESS")("TK_LIBRARY")  = dir & "\lib\tk8.6"
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\fix_bom.ps1""", 0, True
sh.Run """" & dir & "\bin\wish.exe"" """ & dir & "\attendance_system_gui.tcl""", 0, False
