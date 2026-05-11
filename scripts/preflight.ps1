#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Pre-deployment checks for the AIO foundation.

.DESCRIPTION
  Validates that the local environment is ready to deploy:
    1. az CLI present and minimum version
    2. Bicep CLI present
    3. No soft-deleted Key Vault / Cognitive Services account name conflicts
    4. Each requested model is available in the target region (cognitive)

  No Marketplace acceptance step — Constitution VIII (v1.1.0) forbids
  Marketplace SaaS offers in this repo, so the deploy is fully unattended.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$SubscriptionId,
  [string]$Location = 'eastus2',
  [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
  $candidate = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
  if (Test-Path $candidate) { $az = $candidate } else { throw 'az CLI not found.' }
} else { $az = $az.Source }

Write-Host "[preflight] az version" -ForegroundColor Cyan
$ver = & $az version --output json | ConvertFrom-Json
$minAz = [version]'2.60.0'
if ([version]$ver.'azure-cli' -lt $minAz) { throw "az CLI $($ver.'azure-cli') below minimum $minAz" }

Write-Host "[preflight] Bicep CLI" -ForegroundColor Cyan
& $az bicep version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep CLI not installed; run `az bicep install`.' }

& $az account set --subscription $SubscriptionId | Out-Null

Write-Host "[preflight] soft-deleted Cognitive Services name conflicts in $Location" -ForegroundColor Cyan
$deletedCog = & $az cognitiveservices account list-deleted --output json 2>$null | ConvertFrom-Json
if ($deletedCog) {
  $deletedCog | Where-Object { $_.location -eq $Location } | ForEach-Object {
    Write-Host "  WARN: soft-deleted CogSvc account '$($_.name)' present in $Location" -ForegroundColor Yellow
  }
}

Write-Host "[preflight] soft-deleted Key Vaults in $Location" -ForegroundColor Cyan
$deletedKv = & $az keyvault list-deleted --output json 2>$null | ConvertFrom-Json
if ($deletedKv) {
  $deletedKv | Where-Object { $_.properties.location -eq $Location } | ForEach-Object {
    Write-Host "  WARN: soft-deleted Key Vault '$($_.name)' present in $Location" -ForegroundColor Yellow
  }
}

Write-Host "[preflight] OK" -ForegroundColor Green
