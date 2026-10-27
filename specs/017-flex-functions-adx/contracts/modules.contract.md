# Module contracts — 017

## `modules/function-app/main.bicep`

**Inputs:** `name`, `planName`, `location`, `tags`, `storageAccountName`,
`deploymentContainerName` (default `app-package`), `runtimeName`, `runtimeVersion`,
`instanceMemoryMB`, `maximumInstanceCount`, `appSettings`, `appInsightsConnectionString`.

**Outputs:** `id`, `name`, `principalId`, `defaultHostName`, `planId`.

**Guarantees:**

- Creates a `FC1`/`FlexConsumption` serverfarm and a Linux function app on it.
- System-assigned identity; the deployment container is mounted with
  `authentication.type: SystemAssignedIdentity`. **No key is read, stored, or emitted.**
- Declares the deployment container, so the app's storage contract is not left to an
  imperative deploy script.
- `httpsOnly: true`.

**Explicit non-guarantee:** does **not** deploy application code, and does **not** grant
its own identity any role. Roles are assigned by the caller, which knows the scopes.

## `modules/data-explorer/main.bicep`

**Inputs:** `name`, `location`, `tags`, `skuName`, `skuTier`, `capacity`,
`databaseName`, `softDeletePeriod`, `hotCachePeriod`, `enableStreamingIngest`,
`publicNetworkAccess`.

**Outputs:** `id`, `name`, `uri`, `dataIngestionUri`, `databaseName`, `databaseId`,
`principalId`.

**Guarantees:**

- Cluster + one ReadWrite database, system-assigned identity, streaming ingestion on by
  default (the dashboard is meant to be live, not lagging a batch window).
- Capacity forced to 1 on any `Dev(No SLA)` SKU, which rejects higher values.
- `enablePurge: false`.

**Explicit non-guarantee:** provisions **no tables, functions, or database principals**.
KQL DDL and ingestor grants are data-plane operations owned by the consuming repo.

## Naming

| Function | Pattern | Constraint |
|---|---|---|
| `functionApp` | `func-<workload>-<env>-<region>[-<instance>]` | |
| `functionPlan` | `asp-<workload>-<env>-<region>[-<instance>]` | |
| `adxCluster` | `dec<workload><env><region><hash>` | 4–22 chars, lowercase alphanumeric; hyphens rejected by the RP, so flattened like storage |
