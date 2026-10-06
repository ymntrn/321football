# Downloads the exported Figma assets into assets/img/.
# Figma's MCP asset URLs expire after ~7 days, so these are committed rather
# than referenced. Re-export from Figma if the design changes.
$ProgressPreference = "SilentlyContinue"
$dir = "C:\Users\PC\Documents\321-football\app\assets\img"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$assets = [ordered]@{
  "rings.svg"     = "https://www.figma.com/api/mcp/asset/bd127cdf-d724-43b5-b53c-f3c15fd94c6c.svg"
  "glow.svg"      = "https://www.figma.com/api/mcp/asset/0a4e80de-6049-4857-ad00-3edb6373bcc0.svg"
  "undo.png"      = "https://www.figma.com/api/mcp/asset/319350ce-e1d2-4e88-b159-9e54b28f6a8e.png"
  "lightbulb.png" = "https://www.figma.com/api/mcp/asset/a7899aab-8234-4669-b6ff-9c60f0be543d.png"
  "coin.png"      = "https://www.figma.com/api/mcp/asset/71b0c357-3736-4da6-aa36-fc1c8f1315f5.png"
  "search.svg"    = "https://www.figma.com/api/mcp/asset/258a9d8b-2f0b-4806-a434-95c497140e30.svg"
}

foreach ($name in $assets.Keys) {
  $out = Join-Path $dir $name
  try {
    Invoke-WebRequest -Uri $assets[$name] -OutFile $out -TimeoutSec 120
    Write-Output ("  OK   {0,-16} {1} KB" -f $name, [math]::Round((Get-Item $out).Length/1KB,1))
  } catch {
    Write-Output ("  FAIL {0,-16} {1}" -f $name, $_.Exception.Message)
  }
}
