// infra/shared/types.bicep
// User-defined types shared across modules and parameter files.
// See specs/002-new-foundry/data-model.md for the canonical contract.

metadata description = 'Shared user-defined types for the AIO foundation (constitution v1.2.0).'

// ----- Model deployment -----

@export()
@description('SKU options for Cognitive Services / Foundry model deployments.')
type modelSkuName = 'Standard' | 'GlobalStandard' | 'DataZoneStandard' | 'ProvisionedManaged'

@export()
@description('Provider/format for a model deployment. Constitution VIII restricts this stack to first-party models sold directly by Azure (consumption-billed): Azure OpenAI (format=OpenAI) and Microsoft MAI (format=Microsoft). Partner / Azure Marketplace formats (Anthropic, Cohere, Mistral premium, etc.) remain forbidden.')
type modelFormat = 'OpenAI' | 'Microsoft'

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
  @description('Optional region override for this Foundry account. When omitted, the account is deployed to the top-level config.location. Used by secondaryFoundry to host models that are only available in a different region (e.g. eastus-only image models).')
  location: string?
  @description('Optional. When false, Entra ID is NOT enforced and account-level API keys (local auth) are usable. Defaults to true (Entra-only) when omitted, per the "managed identity over keys" security posture. Keys are never emitted as outputs (listKeys() is forbidden); they are fetched at runtime via `az cognitiveservices account keys list`.')
  disableLocalAuth: bool?
  deployments: modelDeployment[]
}

// ----- Matrix homeserver (feature 003) -----

@export()
@description('Matrix homeserver (continuwuity) on ACA + Cloudflare Tunnel.')
type matrixConfig = {
  // Public Cloudflare-Tunnel hostname. Sourced from env at compile time;
  // MUST NOT be hardcoded in a tracked file (Constitution II).
  hostname: string
  // Pinned container images (no :latest).
  continuwuityImage: string
  cloudflaredImage: string
  // Sidecar gate. Lets the operator deploy continuwuity alone for a first
  // pass before the KV tunnel-token secret is set.
  enableCloudflareTunnel: bool
  // Replica counts. continuwuity is single-instance (RocksDB).
  minReplicas: int
  maxReplicas: int
  // Container resources.
  homeserverCpu: string
  homeserverMemory: string
  cloudflaredCpu: string
  cloudflaredMemory: string
  // File share quota (GiB).
  shareQuotaGiB: int
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
  @description('Optional. A second Foundry (AIServices) account in a different region, for models only available outside the primary location (e.g. eastus-only image models). Its own `location` and `disableLocalAuth` come from this block. When omitted or enabled=false, no second account is deployed.')
  secondaryFoundry: foundryAccountConfig?
  enableAiSearch: bool?
  enableMatrix: bool?
  matrix: matrixConfig?
}
