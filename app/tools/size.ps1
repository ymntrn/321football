function Size($label, $path) {
  if (-not (Test-Path $path)) { Write-Output ("{0,-34} absent" -f $label); return }
  $s = (Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
  if ($null -eq $s) { $s = 0 }
  Write-Output ("{0,-34} {1,8} MB" -f $label, [math]::Round($s/1MB,0))
}
$root = "C:\Users\PC\Documents\321-football"
Write-Output "=== 321-football total ==="
Size "TOTAL" $root
Write-Output ""
Write-Output "=== throwaway (regenerated on demand) ==="
Size "app\build" "$root\app\build"
Size "app\.dart_tool" "$root\app\.dart_tool"
Size "app\android\.gradle" "$root\app\android\.gradle"
Size "321_football_db\.venv" "$root\321_football_db\.venv"
Size "321_football_db\.sparql_cache" "$root\321_football_db\.sparql_cache"
Size "321_football_db\__pycache__" "$root\321_football_db\__pycache__"
Write-Output ""
Write-Output "=== real project data ==="
Size "app\lib (source)" "$root\app\lib"
Size "app\assets\db (ships)" "$root\app\assets\db"
Size "app\assets\fonts+img (ships)" "$root\app\assets\fonts"
Size "db\321_football.db (master)" "$root\321_football_db\321_football.db"
Size "db\321_football_slim.db" "$root\321_football_db\321_football_slim.db"
Write-Output ""
Write-Output "=== the actual app ==="
$apk = "$root\app\build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apk) {
  Write-Output ("{0,-34} {1,8} MB" -f "debug APK", [math]::Round((Get-Item $apk).Length/1MB,1))
}
