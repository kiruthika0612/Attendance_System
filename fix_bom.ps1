$p = Join-Path $PSScriptRoot "attendance_system_gui.tcl"
$bytes = [System.IO.File]::ReadAllBytes($p)
# Remove UTF-8 BOM (EF BB BF) if present
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length - 1)]
    [System.IO.File]::WriteAllBytes($p, $bytes)
    Write-Host "BOM removed successfully."
} else {
    Write-Host "No BOM found - file is already clean."
}
