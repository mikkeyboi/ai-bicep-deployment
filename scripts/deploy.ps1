#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Deploy the AIO foundation Bicep template to a target environment.

.DESCRIPTION
  Validates -> what-if -> (confirm) -> create against the user's existing
  `az login` context. Refuses to run if -Subscription or -Tenant are
  missing, or if the active az context does not match.

  No defaults hardcode any tenant/subscription ID.

.EXAMPLE
  ./scripts/deploy.ps1 -Environment dev -Subscription <id> -Tenant <id> -WhatIf
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet('dev','test','prod')]
  [string]$Environment,

  [Parameter(Mandatory)]
  [string]$Subscription,

  [Parameter(Mandatory)]
  [string]$Tenant,

  [string]$Location = 'eastus2',

  [string]$MatrixHostname,

  [switch]$WhatIf,

  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Mask-Guid([string]$id) {
  if ([string]::IsNullOrWhiteSpace($id)) { return '' }
  if ($id.Length -lt 12) { return $id }
  return ($id.Substring(0,4) + '....' + $id.Substring($id.Length-4))
}

# --- Locate az.exe (might not be on PATH on Windows) ---
$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
  $candidate = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
  if (Test-Path $candidate) { $az = $candidate } else { throw 'az CLI not found on PATH and default install path missing.' }
} else { $az = $az.Source }

# --- Verify active az context matches ---
$ctx = & $az account show --output json | ConvertFrom-Json
if ($ctx.id -ne $Subscription) {
  Write-Host "Setting active subscription to $(Mask-Guid $Subscription) ..." -ForegroundColor Yellow
  & $az account set --subscription $Subscription
  $ctx = & $az account show --output json | ConvertFrom-Json
}
if ($ctx.tenantId -ne $Tenant) {
  throw "Active az tenant ($(Mask-Guid $ctx.tenantId)) does not match -Tenant ($(Mask-Guid $Tenant)). Run az login --tenant <id>."
}

$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..')
$template   = Join-Path $repoRoot 'infra/main.bicep'
$paramfile  = Join-Path $repoRoot "infra/parameters/main.$Environment.bicepparam"

if (-not (Test-Path $paramfile)) { throw "Parameter file not found: $paramfile" }

# Matrix hostname: parameterised; never in repo. Pass via -MatrixHostname or
# pre-set $env:MATRIX_HOSTNAME. The paramfile reads it via
# readEnvironmentVariable('MATRIX_HOSTNAME', '').
if ($PSBoundParameters.ContainsKey('MatrixHostname') -and -not [string]::IsNullOrWhiteSpace($MatrixHostname)) {
  $env:MATRIX_HOSTNAME = $MatrixHostname
}

$deployName = "aio-$Environment-{0:yyyyMMdd-HHmmss}" -f (Get-Date).ToUniversalTime()

Write-Host "Subscription : $(Mask-Guid $Subscription)" -ForegroundColor Cyan
Write-Host "Tenant       : $(Mask-Guid $Tenant)"        -ForegroundColor Cyan
Write-Host "Environment  : $Environment"                -ForegroundColor Cyan
Write-Host "Location     : $Location"                   -ForegroundColor Cyan
Write-Host "Template     : $template"
Write-Host "Parameters   : $paramfile"
Write-Host "Deployment   : $deployName"
Write-Host ''

Write-Host '== validate ==' -ForegroundColor Green
& $az deployment sub validate --location $Location --template-file $template --parameters $paramfile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "az deployment sub validate failed (exit $LASTEXITCODE)." }

Write-Host '== what-if ==' -ForegroundColor Green
& $az deployment sub what-if --location $Location --template-file $template --parameters $paramfile
if ($LASTEXITCODE -ne 0) { throw "az deployment sub what-if failed (exit $LASTEXITCODE)." }

if ($WhatIf) { Write-Host 'WhatIf-only mode: stopping before create.' -ForegroundColor Yellow; return }

if (-not $Yes) {
  $answer = Read-Host 'Proceed with deployment? [y/N]'
  if ($answer -notmatch '^(y|Y|yes)$') { Write-Host 'Aborted.'; return }
}

Write-Host '== create ==' -ForegroundColor Green
& $az deployment sub create --name $deployName --location $Location --template-file $template --parameters $paramfile
if ($LASTEXITCODE -ne 0) { throw "az deployment sub create failed (exit $LASTEXITCODE)." }

Write-Host "Deployment $deployName complete." -ForegroundColor Green
