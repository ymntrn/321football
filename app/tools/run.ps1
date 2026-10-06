$env:JAVA_HOME = "C:\src\jdk"
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:Path = "C:\src\flutter\bin;C:\src\jdk\bin;C:\src\android-sdk\platform-tools;C:\src\android-sdk\emulator;" + $env:Path
if (-not (Test-Path Env:\ProgramFiles)) { $env:ProgramFiles = "C:\Program Files" }
if (-not [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) {
  Set-Item -Path "Env:ProgramFiles(x86)" -Value "C:\Program Files (x86)"
}
Set-Location "C:\Users\PC\Documents\321-football\app"
& flutter run -d emulator-5554 --debug 2>&1
