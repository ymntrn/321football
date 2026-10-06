param([string]$name = "shot")
$adb = "C:\src\android-sdk\platform-tools\adb.exe"
$dir = "C:\Users\PC\Documents\321-football\app\build\shots"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir "$name.png"
& $adb shell screencap -p /sdcard/_s.png
& $adb pull /sdcard/_s.png $out 2>&1 | Out-Null
& $adb shell rm /sdcard/_s.png
if (Test-Path $out) {
  Write-Output ("saved {0} ({1} KB)" -f $out, [math]::Round((Get-Item $out).Length/1KB,0))
} else {
  Write-Output "screenshot FAILED"
}
