# Data Model: AIO Foundation

**Feature**: 001-aio-foundation
**Date**: 2026-05-10

User-defined types live in `infra/shared/types.bicep` and are imported
by modules and parameter files. This document is the contract.

## Types

### `environmentConfig`
Top-level shape of every `main.<env>.bicepparam`.

```bicep
type environmentConfig = {
  // Identity & placement
  environment: ('dev' | 'test' | 'prod')
  location: string                        // Azure region, e.g. 'eastus2'
  workloadName: string                    // 'aio' by default
  instance: string?                       // optional suffix, e.g. '01'

  // Ownership / cost
  owner: string                           // GitHub handle or team slug, NOT email
  costCenter: string                      // free-form, default 'poc'

  // Model surface
  openAi: openAiConfig
  claude: claudeConfig

  // Optional toggles
  enablePurgeProtection: bool             // default true for prod, false otherwise
  enablePublicNetworkAccess: bool         // default false for prod, true otherwise
  diagnosticsRetentionDays: int           // default 30
}
```

### `openAiConfig`
```bicep
type openAiConfig = {
  enabled: bool                           // default true
  customSubdomain: string?                // override; otherwise derived from naming
  deployments: modelDeployment[]
}
```

### `claudeConfig`
```bicep
type claudeConfig = {
  enabled: bool                           // default true
  // Marketplace subscription must be accepted out-of-band; see quickstart.
  deployments: modelDeployment[]
}
```

### `modelDeployment`
A single OpenAI or partner model deployment.

```bicep
type modelDeployment = {
  name: string                            // logical deployment name, e.g. 'gpt-5-chat'
  model: {
    format: ('OpenAI' | 'Anthropic')
    name: string                          // e.g. 'gpt-5-chat', 'claude-sonnet-4-5'
    version: string                       // e.g. '2025-08-07' or 'latest'
  }
  sku: {
    name: ('Standard' | 'GlobalStandard' | 'DataZoneStandard' | 'ProvisionedManaged')
    capacity: int                         // TPM units, e.g. 50
  }
  raiPolicyName: string?                  // optional; defaults to 'Microsoft.Default'
  versionUpgradeOption: ('OnceNewDefaultVersionAvailable' | 'NoAutoUpgrade' | 'OnceCurrentVersionExpired')?
}
```

### `connectionSpec`
Describes a Foundry hub connection to a Cognitive Services account.

```bicep
type connectionSpec = {
  name: string
  category: ('AzureOpenAI' | 'AIServices')
  targetResourceId: string                // resourceId of the cognitive account
  authType: 'AAD'                         // managed identity / Entra; never 'ApiKey'
}
```

### `roleAssignmentSpec`
```bicep
type roleAssignmentSpec = {
  principalId: string                     // MI principal id (output of mi module)
  roleDefinitionIdOrName: string          // GUID or built-in role name
  scopeResourceId: string                 // resource the role is granted on
  principalType: ('ServicePrincipal' | 'User' | 'Group')
  description: string?
}
```

## Relationships

```
environmentConfig
 ├── openAi.deployments[*] -> modelDeployment        (deployed under OpenAI account)
 ├── claude.deployments[*] -> modelDeployment        (deployed under Claude/Foundry account)
 └── (implied) one foundry hub + project, connected to both accounts via connectionSpec[]

managedIdentity (1) ──< roleAssignmentSpec[*] >── { openAiAccount, claudeAccount, storage, keyVault }
foundryHub (1) ──< foundryProject (1..n) >
foundryHub (1) ──< connectionSpec[*] >── { openAiAccount, claudeAccount }
```

## Validation Rules (enforced in `infra/shared/region-capabilities.bicep`)

A static map of `{ region: { provider: { model: minVersion } } }` is
checked at compile time. A model deployment whose `(provider, name)` is
not present in the map for the chosen `location` causes a `assert`
failure with a message like:

```
[region-capabilities] Model 'gpt-image-1' is not available in
'canadacentral'. Allowed regions: ['eastus2', 'eastus']. See
research.md D3/D4.
```

## Defaults Provided in `main.dev.bicepparam`

```bicep
using '../main.bicep'

param config = {
  environment: 'dev'
  location: 'eastus2'
  workloadName: 'aio'
  owner: 'mikkeyboi'           // GitHub handle, NOT email
  costCenter: 'poc'
  enablePurgeProtection: false
  enablePublicNetworkAccess: true
  diagnosticsRetentionDays: 30
  openAi: {
    enabled: true
    deployments: [
      { name: 'gpt-5-chat',             model: { format: 'OpenAI',    name: 'gpt-5-chat',             version: 'latest' }, sku: { name: 'GlobalStandard', capacity: 50  } }
      { name: 'gpt-4o',                 model: { format: 'OpenAI',    name: 'gpt-4o',                 version: 'latest' }, sku: { name: 'GlobalStandard', capacity: 50  } }
      { name: 'text-embedding-3-large', model: { format: 'OpenAI',    name: 'text-embedding-3-large', version: 'latest' }, sku: { name: 'GlobalStandard', capacity: 120 } }
    ]
  }
  claude: {
    enabled: true
    deployments: [
      { name: 'claude-sonnet-4-5', model: { format: 'Anthropic', name: 'claude-sonnet-4-5', version: 'latest' }, sku: { name: 'GlobalStandard', capacity: 1 } }
      { name: 'claude-haiku-4-5',  model: { format: 'Anthropic', name: 'claude-haiku-4-5',  version: 'latest' }, sku: { name: 'GlobalStandard', capacity: 1 } }
    ]
  }
}
```
