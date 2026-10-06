# Boots the football321 AVD detached, then waits for adb to see it.
# 2 GB is deliberate: this machine has 7.7 GB total and the emulator has to
# share it with VS Code and Chrome.
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:JAVA_HOME = "C:\src\jdk"
$adb = "C:\src\android-sdk\platform-tools\adb.exe"

$running = & $adb devices | Select-String "emulator-"
if ($running) {
  Write-Output "emulator already running:"
  & $adb devices
  exit 0
}

Write-Output "launching AVD football321 ..."
Start-Process -FilePath "C:\src\android-sdk\emulator\emulator.exe" `
  -ArgumentList "-avd","football321","-memory","2048","-no-snapshot-save","-no-boot-anim" `
  -WindowStyle Normal

Write-Output "waiting for boot (up to 5 min) ..."
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 10
  $boot = & $adb shell getprop sys.boot_completed 2>$null
  if ($boot -match "1") {
    Write-Output "BOOTED"
    & $adb devices
    exit 0
  }
  Write-Output ("  still booting... {0}" -f (Get-Date -Format HH:mm:ss))
}
Write-Output "TIMED OUT waiting for boot"
& $adb devices
