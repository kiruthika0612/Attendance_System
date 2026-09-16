Dim fso, shell, dir, tcl, ps1

Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

dir = fso.GetParentFolderName(WScript.ScriptFullName)
tcl = dir & "\attendance_system_gui.tcl"
ps1 = dir & "\fix_bom.ps1"

' Strip BOM silently before launch
shell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, True

' Launch wish with no console window
shell.Run """C:\Users\kirut\AppData\Local\Apps\Tcl86\bin\wish.exe"" """ & tcl & """", 0, False
