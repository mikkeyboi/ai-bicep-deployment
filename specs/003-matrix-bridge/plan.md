# Plan — 003 Matrix Bridge

## Directory additions

```
infra/modules/matrix/
  file-share.bicep         # File share on existing storage account
  environment.bicep        # Microsoft.App/managedEnvironments + storage link
  homeserver.bicep         # Microsoft.App/containerApps with 2 containers
config/matrix/
  continuwuity.toml        # config template (federation off, registration off)
specs/003-matrix-bridge/
  spec.md, research.md, plan.md, data-model.md, quickstart.md, tasks.md
  contracts/modules.contract.md
```

## Dependency stack

- ACA Managed Environment depends on: Log Analytics (existing), Storage
  account + File Share (extended).
- ACA Container App depends on: Environment, UAMI (existing), Key Vault
  (existing) for secret reference.
- continuwuity depends on: File share mount, hostname param.
- cloudflared depends on: KV secret reference resolving at runtime.

## Constitution check (v1.2.0)

| Principle | Status | Note |
| --- | --- | --- |
| I. Declarative & Idempotent | ✅ | Pure Bicep, no imperative az steps in the deploy path |
| II. No Secrets/IDs/PII in Source | ✅ | Hostname parameterised, token in KV, no IDs in code |
| III. OIDC-First Auth | ✅ | Reuses existing OIDC SP; no new credential introduced |
| IV. Modular Templates | ✅ | New `infra/modules/matrix/*` modules, single entry via workload.bicep |
| V. Naming & Tagging | ✅ | Uses existing `naming.bicep`; adds `cae`, `ca` helpers |
| VI. Validation Gates | ✅ | Lint/build/validate/what-if/gitleaks unchanged |
| VII. Env Parity | ✅ | Flag `enableMatrix` per-env; modules identical across envs |
| VIII. Azure Consumption Billing Only | ✅ | continuwuity + cloudflared are container images; ACA is consumption |

No complexity exceptions.
