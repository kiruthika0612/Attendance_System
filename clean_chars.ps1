$path = "$PSScriptRoot\attendance_system_gui.tcl"
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
# Replace em dash with plain ' - '
$content = $content -replace [char]0x2014, ' - '
# Replace any remaining non-ASCII characters
$content = [System.Text.RegularExpressions.Regex]::Replace($content, '[^\x00-\x7F]', '')
# Write back without BOM
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $content, $enc)
Write-Host "Done - all non-ASCII characters removed."
