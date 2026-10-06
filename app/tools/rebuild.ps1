$env:JAVA_HOME = "C:\src\jdk"
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:Path = "C:\src\flutter\bin;C:\src\jdk\bin;C:\src\android-sdk\platform-tools;" + $env:Path
if (-not [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) {
  Set-Item -Path "Env:ProgramFiles(x86)" -Value "C:\Program Files (x86)"
}
Set-Location "C:\Users\PC\Documents\321-football\app"

Write-Output "analyze ..."
& flutter analyze 2>&1 | Select-Object -Last 12

Write-Output "building (incremental) ..."
& flutter build apk --debug 2>&1 | Select-Object -Last 12

$adb = "C:\src\android-sdk\platform-tools\adb.exe"
$apk = "build\app\outputs\flutter-apk\app-debug.apk"
Write-Output "installing ..."
& $adb install -r $apk
& $adb shell am force-stop com.yamanturan.football321
& $adb shell am start -n com.yamanturan.football321/.MainActivity
Write-Output "relaunched"
