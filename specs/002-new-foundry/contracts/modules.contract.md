# Module Contracts: 002 New Foundry

Supersedes the `foundry-hub`, `foundry-project`, `foundry-connection`,
`openai-account`, `openai-deployment` contracts from feature 001.

## `modules/foundry-account/main.bicep`

**Inputs**
- `name: string`, `location: string`, `tags: object`
- `customSubdomain: string`
- `publicNetworkAccess: ('Enabled' | 'Disabled')` (default `Enabled`)
- `disableLocalAuth: bool` (default `true`)
- `deployments: modelDeployment[]` (default `[]`)

**Outputs**
- `id: string`, `name: string`, `endpoint: string`
- `principalId: string` (system-assigned identity)
- `deploymentNames: string[]`

**Behavior**
- Deploys `Microsoft.CognitiveServices/accounts@2025-04-01-preview`
  kind=`AIServices` with `allowProjectManagement: true`.
- Iterates `deployments` and creates child
  `Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview`
  with `@batchSize(1)`.

**Forbidden**
- Returning `listKeys()`.

---

## `modules/foundry-account/project.bicep`

**Inputs**
- `accountName: string`
- `name: string`, `location: string`, `tags: object`
- `displayName: string?`
- `description: string?`

**Outputs**
- `id: string`, `name: string`

**Behavior**
- Deploys `Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview`
  with system-assigned identity.

---

## `infra/workload.bicep` (delta)

Removes `oai`, `oaiDeps`, `hub`, `proj`, `connOai` modules.
Adds `foundry` (account + deployments) and `foundryProj` (project).
RBAC: `raFoundry` grants `Cognitive Services User` to the workload UAMI
on the Foundry account (replacing `raOpenAi` on the old OpenAI
account). KV/Storage/Search role assignments unchanged.
Diagnostic settings: `diagOai` is replaced by `diagFoundry` scoped to
the new Foundry account.
