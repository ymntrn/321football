Get-Process | Group-Object -Property ProcessName | ForEach-Object {
  [PSCustomObject]@{
    Name  = $_.Name
    Count = $_.Count
    RAM_MB = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum)/1MB, 0)
  }
} | Sort-Object RAM_MB -Descending | Select-Object -First 15 |
  Format-Table -AutoSize | Out-String -Width 120
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("Free RAM MB : {0} of {1}" -f `
  [math]::Round($os.FreePhysicalMemory/1KB,0), [math]::Round($os.TotalVisibleMemorySize/1KB,0))
