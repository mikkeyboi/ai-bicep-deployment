# Module Contracts: 007 Azure ML Workspace + Compute

## NEW module `infra/modules/machine-learning/main.bicep`

**Purpose**: Deploy a standard Azure ML workspace (`kind=Default`) bound
to pre-existing shared dependencies, with keyless datastores, plus any
number of compute instances and clusters.

### Inputs

| Param | Type | Notes |
|---|---|---|
| `name` | string | Workspace name (resolved by caller via `naming.mlWorkspace`). |
| `location` | string | |
| `tags` | object | Standard tag map. |
| `friendlyName` | string | Optional display name; `''` ⇒ null. No PII. |
| `publicNetworkAccess` | `'Enabled'`\|`'Disabled'` | From `enablePublicNetworkAccess`. |
| `storageAccountId` | string | Shared storage resource ID. |
| `keyVaultId` | string | Shared Key Vault resource ID. |
| `appInsightsId` | string | Shared App Insights resource ID. |
| `computeInstances` | `resolvedComputeInstance[]` | Names pre-resolved by caller. |
| `computeClusters` | `resolvedComputeCluster[]` | Names pre-resolved by caller. |

### Outputs (key-free)

| Output | Type |
|---|---|
| `id` | string |
| `name` | string |
| `principalId` | string (workspace system-assigned MSI) |
| `computeInstanceNames` | array |
| `computeClusterNames` | array |

**Forbidden**: `listKeys()`, `kind: 'Hub'`, hardcoded region/SKU/VM
literals, building names inside the module.

## `infra/shared/naming.bicep` (delta)

Adds three exported functions:

```bicep
func mlWorkspace(workload, env, location, instance) => nameOf('mlw', …)
func mlComputeInstance(workload, env, location, processor) => nameOf('ci', …, processor)
func mlComputeCluster(workload, env, location, processor) => nameOf('cc', …, processor)
```

The processor occupies the existing instance slot — the GPU-ready hinge.

## `infra/shared/types.bicep` (delta)

Adds `computeProcessor`, `amlComputeScale`, `amlComputeInstanceConfig`,
`amlComputeClusterConfig`, `machineLearningConfig`; extends
`environmentConfig` with optional `machineLearning`.

## `infra/modules/role-assignment/main.bicep` (delta)

Adds one entry to `roleMap` (built-in role name → built-in role-definition
GUID; the literal GUID lives only in `role-assignment/main.bicep`, which is
allowlisted for gitleaks):

```bicep
'Storage File Data Privileged Contributor': '<built-in-role-guid>'
```

## `infra/workload.bicep` (delta)

All guarded by `enableMl` (= `config.?machineLearning.?enabled ?? false`):

- Resolve `mlwName`, and map config compute arrays → resolved-name records
  (`mlInstances`, `mlClusters`).
- `ml` module invocation (binds shared storage/KV/App Insights).
- `raMlBlob`, `raMlFile`, `raMlKv` — RBAC for the workspace MSI.
- `mlwExisting` + `diagMl` — diagnostic settings to Log Analytics.
- Outputs `mlEnabled`, `mlWorkspaceId`, `mlWorkspaceName`,
  `mlComputeInstanceNames`, `mlComputeClusterNames`.

## `infra/main.bicep` (delta)

`workloadOutputs` object surfaces the five `ml*` outputs.

## `infra/parameters/main.dev.bicepparam` (delta)

Adds the `machineLearning` block: 1 CPU compute instance + 1 CPU cluster
(scale 0→4), with a commented GPU re-add stub. test/prod omit it.
