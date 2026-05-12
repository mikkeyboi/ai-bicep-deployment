# Data model — 003 Matrix Bridge

## Paramfile additions (top-level `config`)

```bicep
config: {
  ...existing fields...
  enableMatrix: bool
  matrix: matrixConfig?
}
```

## New type: `matrixConfig`

```bicep
type matrixConfig = {
  // Public hostname Cloudflare Tunnel terminates at. NEVER hardcoded.
  // Sourced from $env:MATRIX_HOSTNAME via readEnvironmentVariable() in
  // the paramfile, or from -MatrixHostname on scripts/deploy.ps1.
  hostname: string
  // Pinned image tags. Bumps land in paramfiles, not code.
  continuwuityImage: string         // e.g. 'forgejo.ellis.link/continuwuation/continuwuity:v0.5.5'
  cloudflaredImage: string          // e.g. 'docker.io/cloudflare/cloudflared:2026.3.0'
  // Sidecar gate. Lets operator deploy continuwuity alone for first pass.
  enableCloudflareTunnel: bool
  // ACA scaling
  minReplicas: int                  // recommended 1 (continuwuity has stateful in-memory caches)
  maxReplicas: int                  // recommended 1 (single-instance only, RocksDB doesn't shard)
  // CPU/memory per container
  homeserverCpu: string             // e.g. '0.5'
  homeserverMemory: string          // e.g. '1Gi'
  cloudflaredCpu: string            // e.g. '0.25'
  cloudflaredMemory: string         // e.g. '0.5Gi'
}
```

## Azure Files share

- Name: `continuwuity-data`
- Quota: 5 GiB (default; grows with usage; ample for a personal homeserver)
- Access tier: `TransactionOptimized`
- Lives on the existing workload storage account
  (no new account created).

## Key Vault secret (operator-managed)

| Name | Value source | Used by |
| --- | --- | --- |
| `cloudflare-tunnel-token` | Manually set via `az keyvault secret set` after Cloudflare tunnel creation | cloudflared sidecar (via ACA secret reference) |

## ACA secret references on the container app

```bicep
secrets: [
  {
    name: 'cloudflare-tunnel-token'
    keyVaultUrl: '${keyVaultUri}secrets/cloudflare-tunnel-token'
    identity: workloadMiResourceId
  }
]
```

## continuwuity env vars

| Var | Value |
| --- | --- |
| `CONTINUWUITY_SERVER_NAME` | `${matrix.hostname}` |
| `CONTINUWUITY_DATABASE_PATH` | `/var/lib/continuwuity` |
| `CONTINUWUITY_ADDRESS` | `0.0.0.0` |
| `CONTINUWUITY_PORT` | `8008` |
| `CONTINUWUITY_ALLOW_FEDERATION` | `false` |
| `CONTINUWUITY_ALLOW_REGISTRATION` | `false` |
| `CONTINUWUITY_ALLOW_CHECK_FOR_UPDATES` | `false` |
| `CONTINUWUITY_NEW_USER_DISPLAYNAME_SUFFIX` | `""` |

## cloudflared env / args

- Command: `tunnel --no-autoupdate run`
- Secret env var: `TUNNEL_TOKEN` (sourced from ACA secret
  `cloudflare-tunnel-token`)
