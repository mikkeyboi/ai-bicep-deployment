# Data Model: 007 Azure ML Workspace + Compute

## New types (`infra/shared/types.bicep`)

### `computeProcessor`

```bicep
type computeProcessor = 'cpu' | 'gpu'
```

Drives both the compute resource name (the `-cpu`/`-gpu` slot) and the
operator's VM-family choice. The whole point of the feature: adding `gpu`
is a one-line paramfile change that never renames the `cpu` targets.

### `amlComputeScale`

```bicep
type amlComputeScale = {
  minNodes: int   // @minValue(0) — 0 = scale to zero when idle
  maxNodes: int   // @minValue(1)
  nodeIdleTimeBeforeScaleDown: string   // ISO 8601, e.g. 'PT300S'
}
```

### `amlComputeInstanceConfig`

```bicep
type amlComputeInstanceConfig = {
  processor: computeProcessor
  vmSize: string
  idleTimeBeforeShutdown: string?   // ISO 8601, e.g. 'PT30M'; omit = no auto-shutdown
}
```

### `amlComputeClusterConfig`

```bicep
type amlComputeClusterConfig = {
  processor: computeProcessor
  vmSize: string
  vmPriority: ('Dedicated' | 'LowPriority')?   // default Dedicated
  scale: amlComputeScale
}
```

### `machineLearningConfig`

```bicep
type machineLearningConfig = {
  enabled: bool
  friendlyName: string?
  computeInstances: amlComputeInstanceConfig[]
  computeClusters: amlComputeClusterConfig[]
}
```

### `environmentConfig` (one optional field added)

```bicep
type environmentConfig = {
  ...
  matrix: matrixConfig?
  machineLearning: machineLearningConfig?   // NEW — optional, additive
}
```

Optional, so test/prod (which omit it) compile and `build-params`
unchanged. Verified: `bicep build-params` passes for dev/test/prod.

## Module-local types (`modules/machine-learning/main.bicep`)

The module receives compute records with names **already resolved** by
`workload.bicep` (naming-discipline rule — modules never build names):

```bicep
type resolvedComputeInstance = { name: string, vmSize: string, idleTimeBeforeShutdown: string? }
type resolvedComputeCluster  = { name: string, vmSize: string, vmPriority: ('Dedicated'|'LowPriority')?, scale: amlComputeScale }
```

## Resource shapes

### Workspace (`Microsoft.MachineLearningServices/workspaces@2024-10-01-preview`)

```
kind:        (omitted) => Default training workspace
identity:    SystemAssigned
sku:         { name: 'Basic', tier: 'Basic' }
properties:
  storageAccount:            <shared storage id>
  keyVault:                  <shared KV id>
  applicationInsights:       <shared App Insights id>
  systemDatastoresAuthMode:  'identity'      # keyless
  publicNetworkAccess:       Enabled (dev) / Disabled (prod) via enablePublicNetworkAccess
  friendlyName:              <optional, no PII>
```

### Compute instance (`…/workspaces/computes@2024-10-01-preview`)

```
properties.computeType:          ComputeInstance
properties.disableLocalAuth:     true
properties.properties.vmSize:    <from config>
properties.properties.applicationSharingPolicy: Personal
properties.properties.idleTimeBeforeShutdown:   <optional ISO 8601>
```

### Compute cluster (`…/workspaces/computes@2024-10-01-preview`)

```
properties.computeType:          AmlCompute
properties.disableLocalAuth:     true
properties.properties.vmSize:    <from config>
properties.properties.vmPriority: Dedicated | LowPriority
properties.properties.osType:    Linux
properties.properties.scaleSettings:
  minNodeCount: 0                # scales to zero
  maxNodeCount: <from config>
  nodeIdleTimeBeforeScaleDown: <ISO 8601>
```

## RBAC (workspace system-assigned MSI)

| Scope | Role | Module |
|---|---|---|
| shared storage | Storage Blob Data Contributor | `raMlBlob` |
| shared storage | Storage File Data Privileged Contributor | `raMlFile` |
| shared Key Vault | Key Vault Secrets Officer | `raMlKv` |

All guarded by `enableMl`. Distinct principal from the workload MI ⇒ no
`RoleAssignmentExists` collision.

## Outputs (`workload.bicep` → `main.bicep`)

- `mlEnabled: bool`
- `mlWorkspaceId: string`
- `mlWorkspaceName: string`
- `mlComputeInstanceNames: array`
- `mlComputeClusterNames: array`

Empty string / empty array / false when `machineLearning` is omitted or
disabled. No key/secret outputs (`listKeys()` forbidden).
