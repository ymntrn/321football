$adb = "C:\src\android-sdk\platform-tools\adb.exe"
$apk = "C:\Users\PC\Documents\321-football\app\build\app\outputs\flutter-apk\app-debug.apk"

Write-Output ("APK: {0} MB" -f [math]::Round((Get-Item $apk).Length/1MB,1))
Write-Output "installing ..."
& $adb install -r $apk

Write-Output "clearing old app data so we time a true first launch ..."
& $adb shell pm clear com.yamanturan.football321 2>&1 | Out-Null

Write-Output "launching and timing cold start ..."
& $adb logcat -c
$t0 = Get-Date
& $adb shell am start -W -n com.yamanturan.football321/.MainActivity
Write-Output ("wall clock to am start return: {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds)
