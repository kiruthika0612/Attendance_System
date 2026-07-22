$bytes = [System.IO.File]::ReadAllBytes("$PSScriptRoot\attendance_system_gui.tcl")
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "BOM PRESENT - file needs fixing"
} else {
    Write-Host "No BOM - file is clean. First byte: $($bytes[0])"
}
