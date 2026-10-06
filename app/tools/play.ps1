# Drives one Practice round on the emulator and screenshots it.
param([string]$word = "REIN", [switch]$Send, [string]$shot = "play")
$adb = "C:\src\android-sdk\platform-tools\adb.exe"
$app = "C:\Users\PC\Documents\321-football\app"

Write-Output "waiting for the app to settle (DB open) ..."
Start-Sleep -Seconds 6
Write-Output "tapping KOLAY"
& $adb shell input tap 540 815
Start-Sleep -Seconds 3

& powershell -NoProfile -ExecutionPolicy Bypass -File "$app\tools\type.ps1" -word $word
Start-Sleep -Seconds 2
if ($Send) {
  & $adb shell input tap 700 2245
  Start-Sleep -Seconds 2
}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$app\tools\shot.ps1" -name $shot
