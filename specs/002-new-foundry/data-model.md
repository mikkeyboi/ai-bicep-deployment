# Data Model: 002 New Foundry

## Updated types

### `foundryAccountConfig`

```bicep
type foundryAccountConfig = {
  enabled: bool
  customSubdomain: string?
  deployments: modelDeployment[]
}
```

`modelDeployment` is unchanged from feature 001 (format='OpenAI', name,
version, sku{name,capacity}, raiPolicyName?, versionUpgradeOption?).

### `environmentConfig` (delta)

```bicep
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
  foundry: foundryAccountConfig    // was: openAi: openAiConfig
  enableAiSearch: bool?
}
```

`openAi` is **removed**; `foundry` replaces it (same shape, different
semantic owner). The standalone OpenAI account/module is gone.
`connectionSpec` and `connectionCategory` types are removed (no Foundry
connections in 002).

## Resource shape

### Foundry account

```
type:        Microsoft.CognitiveServices/accounts
apiVersion:  2025-04-01-preview
kind:        AIServices
sku:         { name: 'S0' }
identity:    SystemAssigned
properties:
  allowProjectManagement: true        # required for child projects
  customSubDomainName:    <name>
  disableLocalAuth:       true        # Entra-only
  publicNetworkAccess:    Enabled     # dev; Disabled for prod later
  networkAcls.defaultAction: Allow|Deny
```

### Foundry project (child)

```
type:        Microsoft.CognitiveServices/accounts/projects
apiVersion:  2025-04-01-preview
identity:    SystemAssigned
properties:
  description: '<workload> <env>'
  displayName: <name>
```

### Model deployments (child of account)

```
type:        Microsoft.CognitiveServices/accounts/deployments
apiVersion:  2025-04-01-preview
sku:         { name, capacity }
properties:
  model:                { format, name, version }
  raiPolicyName:        Microsoft.Default
  versionUpgradeOption: OnceNewDefaultVersionAvailable
```
