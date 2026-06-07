# Module Contracts: 004 East US Image Foundry

No new modules. Reuses `modules/foundry-account/main.bicep` and
`modules/foundry-account/project.bicep` from feature 002 unchanged.

## `infra/workload.bicep` (delta)

Adds, all guarded by `enableSecondaryFoundry`
(= `config.?secondaryFoundry.?enabled ?? false`):

- `foundry2` — `foundry-account/main.bicep` in `secondaryLocation`
  (= `config.secondaryFoundry.location ?? config.location`), with
  `disableLocalAuth: config.?secondaryFoundry.?disableLocalAuth ?? true`
  and `deployments: config.secondaryFoundry.deployments`.
- `foundry2Proj` — `foundry-account/project.bicep` (child project).
- `raFoundry2` — `Cognitive Services User` for the workload UAMI on the
  eastus account.
- `aif2Existing` + `diagFoundry2` — diagnostic settings to Log Analytics.
- Outputs `secondaryFoundry*` (id, endpoint, projectId, location,
  deploymentNames).

Names come from `naming.foundry()` / `naming.project()` using
`secondaryLocation`, so the eastus account is `aif-…-eus-…` (distinct
from the eastus2 `aif-…-eus2-…`).

## `infra/main.bicep` (delta)

- Capability gate extended: `secondaryModels` are validated against
  `secondaryLocation` (not `config.location`). `capabilityOk` now
  requires both primary and secondary model sets to be supported; the
  failure message reports the offending model's *own* region.
- `workloadOutputs` surfaces the five `secondaryFoundry*` outputs.

## `infra/shared/region-capabilities.bicep` (delta)

Adds an `eastus` entry to the `supported` map:

```
eastus: [
  'OpenAI:gpt-4.1', 'OpenAI:gpt-4o', 'OpenAI:gpt-4o-mini',
  'OpenAI:text-embedding-3-large', 'OpenAI:text-embedding-3-small',
  'OpenAI:gpt-image-2',
  'Microsoft:MAI-Image-2.5',
]
```

**Forbidden** (unchanged): returning `listKeys()`; any partner/Marketplace
`format`; hardcoded region/SKU/model literals inside modules.
