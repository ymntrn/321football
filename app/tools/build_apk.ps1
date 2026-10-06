# Build the debug APK with the emulator shut down, so Gradle gets the RAM.
$env:JAVA_HOME = "C:\src\jdk"
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:Path = "C:\src\flutter\bin;C:\src\jdk\bin;C:\src\android-sdk\platform-tools;" + $env:Path
if (-not [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) {
  Set-Item -Path "Env:ProgramFiles(x86)" -Value "C:\Program Files (x86)"
}

Write-Output "stopping emulator and gradle daemons to free memory ..."
Get-Process qemu-system-x86_64, emulator, java -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("free RAM now: {0} MB" -f [math]::Round($os.FreePhysicalMemory/1KB,0))

Set-Location "C:\Users\PC\Documents\321-football\app"
Write-Output "building debug APK ..."
& flutter build apk --debug 2>&1 | Select-Object -Last 25
