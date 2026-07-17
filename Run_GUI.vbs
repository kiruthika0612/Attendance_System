Set oShell = CreateObject("WScript.Shell")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
oShell.Run """C:\Users\kirut\AppData\Local\Apps\Tcl86\bin\wish.exe"" """ & strDir & "\attendance_system_gui.tcl""", 0, False
