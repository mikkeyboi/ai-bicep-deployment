# Module contracts — 003 Matrix Bridge

## `modules/matrix/file-share.bicep`

**Inputs**: `storageAccountName`, `shareName`, `quotaGiB` (default 5)
**Outputs**: `shareName`, `id`
**Invariants**:
- Bound to an existing storage account in the same RG.
- Access tier `TransactionOptimized`.
- No `listKeys()` in outputs.

## `modules/matrix/environment.bicep`

**Inputs**: `name`, `location`, `tags`, `logAnalyticsWorkspaceId`,
`storageAccountName`, `fileShareName`, `internalLoadBalancerEnabled` (true)
**Outputs**: `id`, `name`, `defaultDomain`, `storageName`
**Invariants**:
- Internal load balancer only (`internal: true`).
- Connects to Log Analytics via `logAnalyticsConfiguration`.
- Defines one `Microsoft.App/managedEnvironments/storages` named
  `continuwuity-data` bound to the file share.
- `listKeys()` may be invoked inline on the storage account to construct
  the storage definition; MUST NOT be exposed as an output.

## `modules/matrix/homeserver.bicep`

**Inputs**:
- `name`, `location`, `tags`
- `environmentId`, `userAssignedIdentityResourceId`,
  `userAssignedIdentityClientId`
- `keyVaultUri`
- `continuwuityImage`, `cloudflaredImage`
- `enableCloudflareTunnel` (bool)
- `serverName` (== `matrix.hostname`)
- `minReplicas`, `maxReplicas`
- `homeserverCpu`, `homeserverMemory`, `cloudflaredCpu`, `cloudflaredMemory`
- `storageMountName` (the env-level storage name, e.g. `continuwuity-data`)

**Outputs**: `id`, `name`, `fqdn` (internal-only)
**Invariants**:
- Ingress `external: false`, `targetPort: 8008`, `transport: auto`.
- continuwuity container always present.
- cloudflared sidecar present iff `enableCloudflareTunnel == true`.
- KV secret reference uses the workload UAMI for auth; no plaintext token
  anywhere in the resource.
- Single revision mode; `minReplicas == maxReplicas == 1` recommended.
- File share mounted at `/var/lib/continuwuity` on continuwuity only.
- `serverName` must be non-empty; module fails compilation otherwise.
