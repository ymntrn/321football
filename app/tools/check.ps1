# Dev helper: analyze + test the app with the toolchain this machine uses.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
$env:JAVA_HOME = "C:\src\jdk"
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:Path = "C:\src\flutter\bin;C:\src\jdk\bin;C:\src\android-sdk\platform-tools;C:\src\android-sdk\emulator;C:\src\android-sdk\cmdline-tools\latest\bin;" + $env:Path

# Flutter's Visual Studio probe reads these two and throws if either is unset.
# Some non-interactive shells do not inherit them, which makes `flutter test`
# fail with "%PROGRAMFILES(X86)% environment variable not found" even though
# nothing here needs Visual Studio.
if (-not (Test-Path Env:\ProgramFiles)) { $env:ProgramFiles = "C:\Program Files" }
if (-not [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) {
  Set-Item -Path "Env:ProgramFiles(x86)" -Value "C:\Program Files (x86)"
}

Set-Location "C:\Users\PC\Documents\321-football\app"

Write-Output "=== analyze ==="
& flutter analyze 2>&1 | Select-Object -Last 30

Write-Output ""
Write-Output "=== test ==="
& flutter test 2>&1 | Select-Object -Last 40
