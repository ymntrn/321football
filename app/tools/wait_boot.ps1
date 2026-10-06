$adb = "C:\src\android-sdk\platform-tools\adb.exe"
for ($i = 0; $i -lt 40; $i++) {
  $b = (& $adb shell getprop sys.boot_completed 2>$null) -join ""
  if ($b.Trim() -eq "1") {
    Write-Output ("BOOTED after ~{0}s" -f ($i * 10))
    & $adb shell getprop ro.build.version.release
    & $adb devices
    exit 0
  }
  Start-Sleep -Seconds 10
}
Write-Output "still not booted after ~400s"
& $adb devices
