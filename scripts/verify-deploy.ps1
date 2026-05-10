#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Post-deploy smoke checks.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$SubscriptionId,
  [Parameter(Mandatory)] [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) { $az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' }

& $az account set --subscription $SubscriptionId | Out-Null

Write-Host "[verify] resource group $ResourceGroup" -ForegroundColor Cyan
$rg = & $az group show --name $ResourceGroup --output json 2>$null | ConvertFrom-Json
if (-not $rg) { throw "Resource group $ResourceGroup not found." }
Write-Host "  OK ($($rg.location))"

Write-Host "[verify] resources in group" -ForegroundColor Cyan
$res = & $az resource list -g $ResourceGroup --output json | ConvertFrom-Json
$res | Group-Object type | Select-Object Count, Name | Format-Table -AutoSize

Write-Host "[verify] OpenAI account deployments" -ForegroundColor Cyan
$oai = $res | Where-Object { $_.type -eq 'Microsoft.CognitiveServices/accounts' -and $_.kind -eq 'OpenAI' }
foreach ($a in $oai) {
  $deps = & $az cognitiveservices account deployment list --name $a.name -g $ResourceGroup --output json | ConvertFrom-Json
  Write-Host "  $($a.name) -> $($deps.Count) deployment(s): $(($deps | ForEach-Object { $_.name }) -join ', ')"
}

Write-Host "[verify] Foundry/AIServices account deployments" -ForegroundColor Cyan
$fdy = $res | Where-Object { $_.type -eq 'Microsoft.CognitiveServices/accounts' -and $_.kind -eq 'AIServices' }
foreach ($a in $fdy) {
  $deps = & $az cognitiveservices account deployment list --name $a.name -g $ResourceGroup --output json | ConvertFrom-Json
  Write-Host "  $($a.name) -> $($deps.Count) deployment(s): $(($deps | ForEach-Object { $_.name }) -join ', ')"
}

Write-Host "[verify] Key Vault is RBAC mode" -ForegroundColor Cyan
$kvs = $res | Where-Object { $_.type -eq 'Microsoft.KeyVault/vaults' }
foreach ($k in $kvs) {
  $kv = & $az keyvault show --name $k.name --output json | ConvertFrom-Json
  Write-Host "  $($k.name) enableRbacAuthorization=$($kv.properties.enableRbacAuthorization)"
}

Write-Host "[verify] OK" -ForegroundColor Green
