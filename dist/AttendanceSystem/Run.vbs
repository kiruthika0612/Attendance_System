Dim fso, sh, dir
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)

' SAFETY CHECK: detect if running from inside a ZIP / Temp folder
If InStr(LCase(dir), "temp") > 0 Or InStr(LCase(dir), ".zip") > 0 Then
    MsgBox "Please EXTRACT the ZIP file first!" & vbCrLf & vbCrLf & _
           "Steps:" & vbCrLf & _
           "  1. Right-click AttendanceSystem.zip" & vbCrLf & _
           "  2. Click 'Extract All'" & vbCrLf & _
           "  3. Open the extracted folder" & vbCrLf & _
           "  4. Double-click Run.vbs", _
           vbCritical, "Extract ZIP First"
    WScript.Quit
End If

' CHECK: make sure wish.exe is present
If Not fso.FileExists(dir & "\bin\wish.exe") Then
    MsgBox "Missing file: bin\wish.exe" & vbCrLf & vbCrLf & _
           "The folder may be incomplete." & vbCrLf & _
           "Please re-download and extract AttendanceSystem.zip", _
           vbCritical, "Missing Files"
    WScript.Quit
End If

' Unblock all files (removes internet download Zone.Identifier flag)
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""Get-ChildItem -Path '" & dir & "' -Recurse | Unblock-File -ErrorAction SilentlyContinue""", 0, True

' Strip BOM from tcl script
sh.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\fix_bom.ps1""", 0, True

' Set library paths and launch wish with no console
sh.Environment("PROCESS")("TCL_LIBRARY") = dir & "\lib\tcl8.6"
sh.Environment("PROCESS")("TK_LIBRARY")  = dir & "\lib\tk8.6"
sh.Run """" & dir & "\bin\wish.exe"" """ & dir & "\attendance_system_gui.tcl""", 0, False
