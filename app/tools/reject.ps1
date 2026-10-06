# Clears the input, types a word, submits, screenshots the rejection banner.
param([string]$word, [string]$shot)
$adb = "C:\src\android-sdk\platform-tools\adb.exe"
$app = "C:\Users\PC\Documents\321-football\app"

# the X in the search bar
& $adb shell input tap 960 1510
Start-Sleep -Seconds 1
& powershell -NoProfile -ExecutionPolicy Bypass -File "$app\tools\type.ps1" -word $word
Start-Sleep -Seconds 1
& $adb shell input tap 700 2245   # GONDER
Start-Sleep -Seconds 2
& powershell -NoProfile -ExecutionPolicy Bypass -File "$app\tools\shot.ps1" -name $shot
