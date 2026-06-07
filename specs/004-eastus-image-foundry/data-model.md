# Data Model: 004 East US Image Foundry

## Updated types (`infra/shared/types.bicep`)

### `modelFormat` (widened)

```bicep
type modelFormat = 'OpenAI' | 'Microsoft'
```

Adds `'Microsoft'` for MAI models sold directly by Azure. Partner /
Marketplace formats remain excluded (Constitution VIII guardrail at the
type level).

### `foundryAccountConfig` (two optional fields added)

```bicep
type foundryAccountConfig = {
  enabled: bool
  customSubdomain: string?
  location: string?           // NEW — region override (defaults to config.location)
  disableLocalAuth: bool?     // NEW — false re-enables API keys (defaults to true)
  deployments: modelDeployment[]
}
```

Both new fields are optional, so the existing primary `foundry` block
and the test/prod paramfiles compile unchanged.

### `environmentConfig` (one optional field added)

```bicep
type environmentConfig = {
  ...
  foundry: foundryAccountConfig
  secondaryFoundry: foundryAccountConfig?   // NEW — optional eastus account
  enableAiSearch: bool?
  enableMatrix: bool?
  matrix: matrixConfig?
}
```

`modelDeployment` is unchanged (its `model.format` now accepts
`'Microsoft'` by virtue of the widened `modelFormat`).

## Resource shape (secondary account)

Identical to the primary account (same `foundry-account` module), with:

```
location:               eastus               # from secondaryFoundry.location
properties.disableLocalAuth: false           # from secondaryFoundry.disableLocalAuth
deployments:
  - { name: gpt-image-2,  model:{format:OpenAI,    name:gpt-image-2,   version:latest},     sku:{GlobalStandard,1} }
  - { name: mai-image-2-5, model:{format:Microsoft, name:MAI-Image-2.5, version:2026-06-02}, sku:{GlobalStandard,1} }
```

## New outputs (`workload.bicep` → `main.bicep`)

- `secondaryFoundryAccountId: string`
- `secondaryFoundryAccountEndpoint: string`
- `secondaryFoundryProjectId: string`
- `secondaryFoundryLocation: string`
- `secondaryFoundryDeploymentNames: array`

All empty-string / empty-array when `secondaryFoundry.enabled` is false
or the block is omitted. No key/secret outputs.
