// infra/shared/types.bicep
// User-defined types shared across modules and parameter files.
// See specs/002-new-foundry/data-model.md for the canonical contract.

metadata description = 'Shared user-defined types for the AIO foundation (constitution v1.2.0).'

// ----- Model deployment -----

@export()
@description('SKU options for Cognitive Services / Foundry model deployments.')
type modelSkuName = 'Standard' | 'GlobalStandard' | 'DataZoneStandard' | 'ProvisionedManaged'

@export()
@description('Provider/format for a model deployment. Constitution VIII restricts this stack to first-party Azure OpenAI models on the unified Foundry account.')
type modelFormat = 'OpenAI'

@export()
@description('Auto-upgrade behaviour for a model deployment.')
type modelUpgradeOption = 'OnceNewDefaultVersionAvailable' | 'NoAutoUpgrade' | 'OnceCurrentVersionExpired'

@export()
@description('A single model deployment under a Foundry (AIServices) account.')
type modelDeployment = {
  @description('Logical deployment name, e.g. "gpt-4-1".')
  name: string
  model: {
    format: modelFormat
    name: string
    version: string
  }
  sku: {
    name: modelSkuName
    @minValue(1)
    capacity: int
  }
  raiPolicyName: string?
  versionUpgradeOption: modelUpgradeOption?
}

// ----- Role assignment input for the role-assignment module -----

@export()
type principalType = 'ServicePrincipal' | 'User' | 'Group'

@export()
type roleAssignmentSpec = {
  principalId: string
  // Built-in role name (resolved to ID in module) or a full GUID.
  roleDefinitionIdOrName: string
  scopeResourceId: string
  principalType: principalType
  description: string?
}

// ----- Per-environment configuration -----

@export()
type envName = 'dev' | 'test' | 'prod'

@export()
@description('Foundry account configuration. Replaces the legacy `openAi` block in v1.2.0; the standalone OpenAI account is gone and models live on the Foundry account itself.')
type foundryAccountConfig = {
  enabled: bool
  customSubdomain: string?
  deployments: modelDeployment[]
}

@export()
@description('Top-level shape consumed by infra/main.bicep.')
type environmentConfig = {
  environment: envName
  location: string
  workloadName: string
  instance: string?
  owner: string
  costCenter: string
  enablePurgeProtection: bool
  enablePublicNetworkAccess: bool
  diagnosticsRetentionDays: int
  foundry: foundryAccountConfig
  enableAiSearch: bool?
}
