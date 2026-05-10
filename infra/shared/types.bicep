// infra/shared/types.bicep
// User-defined types shared across modules and parameter files.
// See specs/001-aio-foundation/data-model.md for the canonical contract.

metadata description = 'Shared user-defined types for the AIO foundation.'

// ----- Model deployment (OpenAI or partner) -----

@export()
@description('SKU options for Cognitive Services / Foundry model deployments.')
type modelSkuName = 'Standard' | 'GlobalStandard' | 'DataZoneStandard' | 'ProvisionedManaged'

@export()
@description('Provider/format for a model deployment.')
type modelFormat = 'OpenAI' | 'Anthropic'

@export()
@description('Auto-upgrade behaviour for a model deployment.')
type modelUpgradeOption = 'OnceNewDefaultVersionAvailable' | 'NoAutoUpgrade' | 'OnceCurrentVersionExpired'

@export()
@description('A single model deployment under an OpenAI- or Foundry-style account.')
type modelDeployment = {
  @description('Logical deployment name, e.g. "gpt-5-chat".')
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

// ----- Connection from Foundry hub to a Cognitive account -----

@export()
type connectionCategory = 'AzureOpenAI' | 'AIServices'

@export()
type connectionSpec = {
  name: string
  category: connectionCategory
  targetResourceId: string
  // AAD-only: never use ApiKey-style auth from Foundry to its accounts.
  authType: 'AAD'
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
type openAiConfig = {
  enabled: bool
  customSubdomain: string?
  deployments: modelDeployment[]
}

@export()
type claudeConfig = {
  enabled: bool
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
  openAi: openAiConfig
  claude: claudeConfig
  enableAiSearch: bool?
}
