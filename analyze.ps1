$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\michaelleung\source\ai-bicep-deployment'
$w = Get-Content whatif.json -Raw | ConvertFrom-Json
$changes = $w.changes
Write-Host "Total changes: $($changes.Count)"
$changes | Group-Object changeType | Sort-Object Name | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }
Write-Host "`nBy resource type:"
$changes | ForEach-Object {
  $id = $_.resourceId
  $idx = $id.IndexOf('/providers/')
  if ($idx -ge 0) {
    $tail = $id.Substring($idx + 11)
    $parts = $tail -split '/'
    "$($parts[0])/$($parts[1])"
  } else { 'Unknown' }
} | Group-Object | Sort-Object Name | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }
Write-Host "`nClaude/AIServices/SaaS/Anthropic guard:"
$hits = $changes | Where-Object { $_.resourceId -match 'claude|AIServices|Microsoft\.SaaS|fdy|Anthropic' }
if ($hits) { $hits | ForEach-Object { Write-Host "  HIT: $($_.resourceId)" } } else { Write-Host "  NONE - clean" }
