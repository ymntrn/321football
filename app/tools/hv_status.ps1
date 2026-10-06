foreach ($f in @("HypervisorPlatform","VirtualMachinePlatform","Microsoft-Hyper-V-All")) {
  $s = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue).State
  Write-Output ("{0,-28} {1}" -f $f, $(if ($s) { $s } else { "not present" }))
}
Write-Output ("Free C: GB : {0}" -f [math]::Round((Get-PSDrive C).Free/1GB,1))
