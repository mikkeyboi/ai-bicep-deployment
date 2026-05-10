# Module Contracts: AIO Foundation

Each module exposes a typed input record and a small, key-free output
record. These contracts drive the test-first tasks in `tasks.md`.

---

## `infra/main.bicep` (subscription scope)

**Inputs**
- `config: environmentConfig` (see `data-model.md`)

**Behavior**
- Creates the resource group named via `naming.rg(...)`.
- Invokes `workload.bicep` at RG scope, passing `config` and the
  resolved `tags` map.
- Calls `region-capabilities` assertion before invoking workload.

**Outputs**
- `resourceGroupName: string`
- `workload: <workloadOutputs>`

**Invariants**
- No literals for region, SKU, or model — all from `config`.
- No call to `subscription().tenantId` is logged.

---

## `infra/workload.bicep` (resource-group scope)

**Inputs**
- `config: environmentConfig`
- `tags: object`

**Calls (in order)**
1. `log-analytics`, `app-insights`, `managed-identity`, `key-vault`, `storage`
2. `openai-account` (+ N × `openai-deployment`)
3. `foundry-claude-account` (+ N × `foundry-claude-deployment`)
4. `foundry-hub` (passing diagnostics + KV + storage + AI Search if enabled)
5. `foundry-project`
6. `foundry-connection` × { openai, claude }
7. `role-assignment` × N (MI → resources; Foundry MI → KV/Storage)
8. `diagnostic-settings` × N

**Outputs (key-free)**
- `foundryHubId`, `foundryProjectId`
- `openAiAccountId`, `openAiEndpoint`, `openAiDeploymentNames: string[]`
- `claudeAccountId`, `claudeEndpoint`, `claudeDeploymentNames: string[]`
- `keyVaultId`, `keyVaultUri`
- `storageAccountId`
- `managedIdentityId`, `managedIdentityPrincipalId`, `managedIdentityClientId`
- `logAnalyticsWorkspaceId`, `appInsightsId`

---

## `modules/openai-account/main.bicep`

**Inputs**
- `name: string`, `location: string`, `tags: object`
- `customSubdomain: string`
- `disableLocalAuth: bool` (default `true`)
- `publicNetworkAccess: ('Enabled' | 'Disabled')`

**Outputs**
- `id: string`, `name: string`, `endpoint: string`, `principalId: string` (system MI if used)

**Forbidden**
- Returning `listKeys()` output.

---

## `modules/openai-deployment/main.bicep`

**Inputs**
- `accountName: string`, `deployment: modelDeployment`, `tags: object`

**Outputs**
- `name: string`, `id: string`

**Behavior**
- Sets `properties.versionUpgradeOption` from input or `OnceNewDefaultVersionAvailable`.
- Pins `raiPolicyName` to input or `Microsoft.Default`.

---

## `modules/foundry-claude-account/main.bicep`

**Inputs**
- `name: string`, `location: string`, `tags: object`
- `kind: 'AIServices'` (fixed)
- `disableLocalAuth: bool` (default `true`)

**Outputs**
- `id`, `name`, `endpoint`

**Invariants**
- `location ∈ { 'eastus2', 'swedencentral' }`; otherwise compile-time error.

---

## `modules/foundry-claude-deployment/main.bicep`

**Inputs**
- `accountName: string`, `deployment: modelDeployment`, `tags: object`

**Outputs**
- `name`, `id`

**Behavior**
- `model.format` MUST be `'Anthropic'`; asserts otherwise.

---

## `modules/foundry-hub/main.bicep`

**Inputs**
- `name`, `location`, `tags`
- `keyVaultId`, `storageAccountId`, `appInsightsId`, `logAnalyticsWorkspaceId`
- `managedIdentityId`

**Outputs**
- `id`, `name`, `principalId`

---

## `modules/foundry-project/main.bicep`

**Inputs**
- `name`, `location`, `tags`, `hubId`

**Outputs**
- `id`, `name`, `discoveryUrl`

---

## `modules/foundry-connection/main.bicep`

**Inputs**
- `hubName: string`
- `connection: connectionSpec`

**Outputs**
- `id`, `name`

**Invariants**
- `connection.authType == 'AAD'`; reject `ApiKey`.

---

## `modules/key-vault/main.bicep`

**Inputs**
- `name`, `location`, `tags`
- `enableRbacAuthorization: bool` (fixed `true`)
- `enablePurgeProtection: bool`
- `publicNetworkAccess: ('Enabled' | 'Disabled')`

**Outputs**
- `id`, `name`, `uri`

---

## `modules/storage/main.bicep`

**Inputs**
- `name`, `location`, `tags`
- `sku: 'Standard_LRS'` (default), `kind: 'StorageV2'`
- `allowSharedKeyAccess: bool` (default `false`)
- `publicNetworkAccess`

**Outputs**
- `id`, `name`, `primaryBlobEndpoint`

---

## `modules/managed-identity/main.bicep`

**Inputs**
- `name`, `location`, `tags`

**Outputs**
- `id`, `name`, `principalId`, `clientId`

---

## `modules/role-assignment/main.bicep`

**Inputs**
- `roleAssignment: roleAssignmentSpec`

**Outputs**
- `id: string`

**Behavior**
- `name: guid(scope, principalId, roleDefinitionId)` for idempotency.

---

## `modules/log-analytics/main.bicep`

**Inputs**
- `name`, `location`, `tags`, `retentionInDays: int`

**Outputs**
- `id`, `name`, `customerId`

---

## `modules/app-insights/main.bicep`

**Inputs**
- `name`, `location`, `tags`, `workspaceResourceId: string`

**Outputs**
- `id`, `name`, `connectionString` (treated as non-secret per Microsoft guidance, but still not echoed in logs)

---

## `modules/diagnostic-settings/main.bicep`

**Inputs**
- `targetResourceId: string`, `workspaceResourceId: string`, `name: string`
- `logCategories: string[]?`, `metricCategories: string[]?`

**Outputs**
- `id`
