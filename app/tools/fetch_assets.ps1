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
  # Versus (27:42), exported 6 Oct 2026. The cloud session that built the
  # screen could not reach figma.com, so these are fetched here, on the PC.
  "versus_banner_top.svg"    = "https://www.figma.com/api/mcp/asset/d61aa367-1f91-41f2-bd0c-5216980d0aa7.svg"
  "versus_banner_bottom.svg" = "https://www.figma.com/api/mcp/asset/d10897cf-55dd-48f8-97db-452e3c165083.svg"
  "versus_vs.svg"            = "https://www.figma.com/api/mcp/asset/c63d5167-3c63-4d29-87a8-4a376b5b63a3.svg"
  # Front door (branch front-door-and-ranked), exported 6 Oct 2026 from a
  # cloud session that could not reach figma.com. Until these are fetched
  # each slot shows a stand-in (an icon or emoji), so nothing breaks.
  "nav_leaderboard.png" = "https://www.figma.com/api/mcp/asset/114523e4-5b21-4b0a-96b3-b3accfa6b256.png"  # 8:36
  "nav_shop.png"        = "https://www.figma.com/api/mcp/asset/788d206e-0524-4b44-aaea-8ba08d826b80.png"  # 8:34
  "nav_settings.png"    = "https://www.figma.com/api/mcp/asset/3d5e0b41-dbc7-4d6c-9f58-86211a370aab.png"  # 8:29
  "nav_person.png"      = "https://www.figma.com/api/mcp/asset/69a72e53-b832-467f-ab3e-2a024cc6082f.png"  # 8:32
  "trophy.png"          = "https://www.figma.com/api/mcp/asset/baa9ec94-8632-4b53-994c-9874476940af.png"  # 53:519
  "lb_earth.png"        = "https://www.figma.com/api/mcp/asset/18a612d6-0b7b-4aa2-ad97-66b7d5637981.png"  # 51:600
  "lb_people.png"       = "https://www.figma.com/api/mcp/asset/e55d19ad-de9c-427e-8e25-cede54fd1b18.png"  # 51:602
  "pencil.png"          = "https://www.figma.com/api/mcp/asset/9a2256b1-b4bd-40f1-8ca3-d119d9454704.png"  # 53:547
  "stat_matches.png"    = "https://www.figma.com/api/mcp/asset/ef2ba69d-e0f7-4a04-b62e-2e34fd618783.png"  # 53:549
  "stat_winrate.png"    = "https://www.figma.com/api/mcp/asset/091410c2-911f-46e0-bcf5-4e9650ee45c8.png"  # 53:555
  "stat_streak.png"     = "https://www.figma.com/api/mcp/asset/9adbcc9d-4ffb-4465-943a-d3c0256a195b.png"  # 53:562
  "stat_fastest.png"    = "https://www.figma.com/api/mcp/asset/4a3fd10d-40aa-4d5a-bc48-37409d8b5ca8.png"  # 53:569
  # Apple's official "Apple ile Giriş Yap" button (53:582). Shown exactly as
  # exported, disabled. Never restyle it.
  "apple_signin.png"    = "https://www.figma.com/api/mcp/asset/afb8e097-ce24-44c1-a9e9-3ec72c81d9cc.png"
}

foreach ($name in $assets.Keys) {
  $out = Join-Path $dir $name
  try {
    Invoke-WebRequest -Uri $assets[$name] -OutFile $out -TimeoutSec 120
    Write-Output ("  OK   {0,-26} {1} KB" -f $name, [math]::Round((Get-Item $out).Length/1KB,1))
  } catch {
    Write-Output ("  FAIL {0,-26} {1}" -f $name, $_.Exception.Message)
  }
}
