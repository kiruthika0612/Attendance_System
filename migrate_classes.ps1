$base = Split-Path $MyInvocation.MyCommand.Path
$studentFiles = Get-ChildItem -Path $base -Filter "students_*.txt" -File
if ($studentFiles.Count -eq 0) { Write-Host "Nothing to migrate."; exit 0 }
foreach ($sf in $studentFiles) {
 $class = $sf.BaseName -replace "^students_", ""
 if ($class -eq "") { continue }
 $classDir = Join-Path $base "classes\$class"
 $destSF = Join-Path $classDir "students.txt"
 $destAF = Join-Path $classDir "attendance.txt"
 $srcAF = Join-Path $base "attendance_$class.txt"
 if (-not (Test-Path $classDir)) { New-Item -ItemType Directory -Path $classDir | Out-Null; Write-Host "Created: classes\$class" }
 if (-not (Test-Path $destSF)) { Copy-Item $sf.FullName $destSF; Write-Host " Copied students -> classes\$class\students.txt" }
 else { Write-Host " classes\$class\students.txt exists, skipped." }
 if (Test-Path $srcAF) { if (-not (Test-Path $destAF)) { Copy-Item $srcAF $destAF; Write-Host " Copied attendance -> classes\$class\attendance.txt" } else { Write-Host " classes\$class\attendance.txt exists, skipped." } }
 else { if (-not (Test-Path $destAF)) { New-Item -ItemType File -Path $destAF | Out-Null; Write-Host " Created empty attendance.txt for $class" } }
}
Write-Host "Done. Original flat files are untouched."
