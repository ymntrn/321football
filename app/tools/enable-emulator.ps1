# =====================================================================
#  321 Football - enable Android emulator acceleration
#
#  RUN THIS ONCE, AS ADMINISTRATOR:
#    right-click the file  ->  "Run with PowerShell"  (accept the UAC prompt)
#  or from an admin PowerShell:
#    powershell -ExecutionPolicy Bypass -File tools\enable-emulator.ps1
#
#  WHAT IT DOES
#  The Android emulator needs hardware virtualisation. Your CPU supports it
#  (VirtualizationFirmwareEnabled = True) but the Windows Hypervisor Platform
#  feature is switched off, and turning a Windows optional feature on requires
#  administrator rights plus a restart. That is the only reason this script
#  needs elevation - it installs nothing and downloads nothing.
#
#  A RESTART IS REQUIRED afterwards. Nothing else in the project needs admin.
# =====================================================================

$ErrorActionPreference = "Stop"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  This script must run as administrator." -ForegroundColor Red
    Write-Host "  Right-click it and choose 'Run with PowerShell', or open" -ForegroundColor Yellow
    Write-Host "  PowerShell as admin and run it from there." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host ""
Write-Host "  Enabling Windows Hypervisor Platform..." -ForegroundColor Cyan

$needsRestart = $false

foreach ($feature in @("HypervisorPlatform", "VirtualMachinePlatform")) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
    if ($state -eq "Enabled") {
        Write-Host ("    {0}: already enabled" -f $feature) -ForegroundColor Green
        continue
    }
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -All
    Write-Host ("    {0}: enabled" -f $feature) -ForegroundColor Green
    if ($result.RestartNeeded) { $needsRestart = $true }
}

Write-Host ""
if ($needsRestart) {
    Write-Host "  Done. RESTART YOUR PC to finish." -ForegroundColor Yellow
    Write-Host "  After the restart the emulator will boot normally -" -ForegroundColor Yellow
    Write-Host "  just tell Claude you're back and it'll pick up from there." -ForegroundColor Yellow
} else {
    Write-Host "  Done - no restart needed." -ForegroundColor Green
}
Write-Host ""
Read-Host "Press Enter to close"
