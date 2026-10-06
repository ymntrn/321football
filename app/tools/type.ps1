# Taps letters on the app's OWN keyboard widget.
#
# `adb shell input text` cannot be used: the keyboard is a Flutter widget, not
# a system IME, so there is no text field for Android to type into. Each
# letter is a coordinate tap.
#
# Coordinates are for the Pixel 6 AVD (1080x2400) and the FOUR-ROW keyboard
# from Figma 77:338. If turkish_keyboard.dart changes its metrics, re-measure
# from a screenshot and update the constants here.
param([string]$word = "REIN", [switch]$Send, [switch]$Space)

$adb = "C:\src\android-sdk\platform-tools\adb.exe"

$row1 = "QWERTYUIOPĞÜ"
$row2 = "ASDFGHJKLŞİ"
$row3 = "ZXCVBNMÖÇ"

$y1, $y2, $y3, $y4 = 1834, 1978, 2122, 2266
$x1, $x2, $x3 = 52, 96, 120
$slot = 88.5
$xBackspace = 938
$xSpace = 372
$xSend = 906

function TapChar($ch) {
  $i = $row1.IndexOf($ch)
  if ($i -ge 0) { $x = $x1 + $slot * $i; $y = $y1 }
  else {
    $i = $row2.IndexOf($ch)
    if ($i -ge 0) { $x = $x2 + $slot * $i; $y = $y2 }
    else {
      $i = $row3.IndexOf($ch)
      if ($i -ge 0) { $x = $x3 + $slot * $i; $y = $y3 }
      else { Write-Output ("  no key for '{0}'" -f $ch); return }
    }
  }
  & $adb shell input tap ([int]$x) ([int]$y)
  Write-Output ("  {0} -> ({1},{2})" -f $ch, [int]$x, [int]$y)
}

Write-Output ("typing '{0}'" -f $word)
foreach ($ch in $word.ToCharArray()) {
  if ($ch -eq ' ') { & $adb shell input tap $xSpace $y4; Write-Output "  (bosluk)" }
  else { TapChar $ch }
}

if ($Send) {
  Write-Output "pressing GONDER"
  & $adb shell input tap $xSend $y4
}
