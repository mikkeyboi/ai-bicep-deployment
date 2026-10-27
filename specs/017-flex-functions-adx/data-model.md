# Data model — 017

## `dataExplorerConfig` (optional)

| Field | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | — | Required when block present |
| `skuName` | string? | `Dev(No SLA)_Standard_E2a_v4` | Dev tier is single-node, no SLA |
| `skuTier` | `'Basic' \| 'Standard'`? | `Basic` | Union, so a typo fails at compile time |
| `capacity` | int? | 1 | Forced to 1 on the dev tier by the module |
| `databaseName` | string? | `hvac` | |
| `softDeletePeriod` | string? | `P31D` | ISO 8601 duration |
| `hotCachePeriod` | string? | `P7D` | |

## `functionAppConfig` (optional)

| Field | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | — | Required when block present |
| `runtimeVersion` | string? | `3.12` | Outlives the Linux Consumption EOL |
| `instanceMemoryMB` | `2048 \| 4096`? | 2048 | Union: Flex accepts only these |
| `maximumInstanceCount` | int? | 40 | Caps spend; each invocation is a metered model call |
| `appSettings` | object? | `{}` | **Non-secret only** |

## Injected settings (not author-supplied)

`workload.bicep` merges resolved coordinates into `appSettings` so the parameter file
never carries an endpoint that could drift:

| Setting | Source |
|---|---|
| `ADX_CLUSTER_URI` | `adx.outputs.uri` (only when ADX enabled) |
| `ADX_DATABASE` | `adx.outputs.databaseName` |
| `TRIAGE_STATE_ACCOUNT` | resolved storage name |
| `AIPLATFORM_PROJECT_ENDPOINT` | `foundry.outputs.endpoint` + project (only when Foundry enabled) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | `appi.outputs.connectionString` |

## New outputs

`adxEnabled`, `adxClusterId`, `adxClusterUri`, `adxDatabaseName`, `functionAppEnabled`,
`functionAppId`, `functionAppName`, `functionAppHostName`, `functionAppPrincipalId`.

`functionAppPrincipalId` exists specifically so the KQL apply step can grant the database
ingestor role without a human copying a GUID between portals.
