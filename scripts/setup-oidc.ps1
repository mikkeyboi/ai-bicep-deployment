#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Create the GitHub OIDC trust between this repo and an Entra app
  registration with subscription-scoped Contributor (and optional
  User Access Administrator) roles.

.DESCRIPTION
  Idempotent. Creates:
    - One Entra app registration `gh-oidc-<repo>`
    - One service principal for the app
    - One federated credential per environment with subject
        repo:<owner>/<repo>:environment:<env>
    - Role assignment(s) at subscription scope
  Then prints the gh CLI commands the operator needs to run to set the
  GitHub Variables in each environment. No secrets are ever created or
  printed.

.EXAMPLE
  ./scripts/setup-oidc.ps1 -SubscriptionId <id> -TenantId <id> `
    -RepoOwner mikkeyboi -RepoName ai-bicep-deployment `
    -Environments dev,test,prod
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$SubscriptionId,
  [Parameter(Mandatory)] [string]$TenantId,
  [Parameter(Mandatory)] [string]$RepoOwner,
  [Parameter(Mandatory)] [string]$RepoName,
  [Parameter(Mandatory)]
  [ValidateScript({ if ($_.Count -eq 1 -and $_[0] -match ',') { throw "Pass -Environments as a real array, e.g. -Environments dev,test,prod (no quotes), not a single comma-joined string." }; $true })]
  [string[]]$Environments,
  [string]$AppDisplayName,
  [switch]$AssignUserAccessAdministrator
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $AppDisplayName) { $AppDisplayName = "gh-oidc-$RepoName" }

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
  $candidate = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
  if (Test-Path $candidate) { $az = $candidate } else { throw 'az CLI not found.' }
} else { $az = $az.Source }

& $az account set --subscription $SubscriptionId | Out-Null

# --- App registration (idempotent) ---
$apps = @(& $az ad app list --display-name $AppDisplayName --output json | ConvertFrom-Json)
if ($apps.Count -gt 0) {
  $app = $apps[0]
  Write-Host "App '$AppDisplayName' exists (appId $($app.appId))." -ForegroundColor Green
} else {
  Write-Host "Creating app '$AppDisplayName' ..." -ForegroundColor Yellow
  $app = & $az ad app create --display-name $AppDisplayName --output json | ConvertFrom-Json
}
$appId    = $app.appId
$appObjId = $app.id

# --- Service principal (idempotent) ---
$sps = @(& $az ad sp list --filter "appId eq '$appId'" --output json | ConvertFrom-Json)
if ($sps.Count -gt 0) {
  $sp = $sps[0]
} else {
  Write-Host 'Creating service principal ...' -ForegroundColor Yellow
  $sp = & $az ad sp create --id $appId --output json | ConvertFrom-Json
}
$spId = $sp.id

# --- Federated credentials, one per environment ---
$existing = @(& $az ad app federated-credential list --id $appObjId --output json | ConvertFrom-Json)
foreach ($env in $Environments) {
  $name    = "gh-$RepoName-$env"
  $subject = "repo:$RepoOwner/$RepoName`:environment:$env"
  $hit = $existing | Where-Object { $_.name -eq $name }
  if ($hit) {
    Write-Host "Federated credential '$name' exists." -ForegroundColor Green
    continue
  }
  Write-Host "Creating federated credential '$name' (subject $subject) ..." -ForegroundColor Yellow
  $body = @{
    name      = $name
    issuer    = 'https://token.actions.githubusercontent.com'
    subject   = $subject
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json -Compress
  $tmp = New-TemporaryFile
  $body | Set-Content -Path $tmp -Encoding utf8
  & $az ad app federated-credential create --id $appObjId --parameters "@$tmp" | Out-Null
  Remove-Item $tmp -Force
}

# --- Role assignments ---
$scope = "/subscriptions/$SubscriptionId"
$roles = @('Contributor')
if ($AssignUserAccessAdministrator) { $roles += 'User Access Administrator' }
foreach ($role in $roles) {
  $existingRa = @(& $az role assignment list --assignee $spId --scope $scope --role $role --output json | ConvertFrom-Json)
  if ($existingRa.Count -gt 0) {
    Write-Host "Role '$role' already assigned to SP at $scope." -ForegroundColor Green
  } else {
    Write-Host "Assigning role '$role' to SP at $scope ..." -ForegroundColor Yellow
    & $az role assignment create --assignee $spId --role $role --scope $scope | Out-Null
  }
}

Write-Host ''
Write-Host '====================================================================' -ForegroundColor Cyan
Write-Host 'Set the following GitHub Variables in each environment.' -ForegroundColor Cyan
Write-Host 'Use `gh variable set --env <env> NAME --body <value>` from this repo.' -ForegroundColor Cyan
Write-Host '====================================================================' -ForegroundColor Cyan
foreach ($env in $Environments) {
  Write-Host ''
  Write-Host "# --- environment: $env ---" -ForegroundColor Yellow
  Write-Host "gh variable set AZURE_CLIENT_ID       --env $env --body $appId"
  Write-Host "gh variable set AZURE_TENANT_ID       --env $env --body $TenantId"
  Write-Host "gh variable set AZURE_SUBSCRIPTION_ID --env $env --body $SubscriptionId"
  Write-Host "gh variable set AZURE_LOCATION        --env $env --body eastus2"
}
Write-Host ''
Write-Host 'Also create the matching GitHub Environments (Settings -> Environments)' -ForegroundColor Cyan
Write-Host 'and add required reviewers for non-dev environments.' -ForegroundColor Cyan
