$apk = "C:\Users\PC\Documents\321-football\app\build\app\outputs\flutter-apk\app-debug.apk"
for ($i = 0; $i -lt 60; $i++) {
  if (Test-Path $apk) {
    Write-Output ("APK READY after ~{0}s  ({1} MB)" -f ($i*20), [math]::Round((Get-Item $apk).Length/1MB,1))
    exit 0
  }
  $j = Get-Process java -ErrorAction SilentlyContinue
  if (-not $j) { Write-Output ("no java running at ~{0}s - build ended or failed" -f ($i*20)); exit 1 }
  Start-Sleep -Seconds 20
}
Write-Output "still building after ~20 min"
