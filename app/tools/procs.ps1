Get-Process java, dart, qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Select-Object Name, Id,
    @{n='CPUs';e={[math]::Round($_.CPU,0)}},
    @{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,0)}} |
  Format-Table -AutoSize | Out-String -Width 120
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("Free RAM MB : {0} of {1}" -f `
  [math]::Round($os.FreePhysicalMemory/1KB,0), [math]::Round($os.TotalVisibleMemorySize/1KB,0))
