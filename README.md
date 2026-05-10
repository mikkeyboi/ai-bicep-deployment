# ai-bicep-deployment

Spec-driven Bicep deployment for an Azure **AI All-in-One** foundation
(AI Foundry hub + project, Azure OpenAI, Anthropic Claude in Foundry,
Storage, Key Vault, observability, managed identity + RBAC).

> **Public repo notice.** This repository must contain **no** tenant IDs,
> subscription IDs, secrets, or personal data. Identifiers are injected
> at deploy time via GitHub Variables (CI) or script arguments (local).
> See [Constitution](.specify/memory/constitution.md) Principles II & III.

## Status

Spec-driven via [GitHub Spec Kit](https://github.com/github/spec-kit).
The first feature is **`001-aio-foundation`**:

- [Spec](specs/001-aio-foundation/spec.md)
- [Plan](specs/001-aio-foundation/plan.md)
- [Research](specs/001-aio-foundation/research.md)
- [Data model](specs/001-aio-foundation/data-model.md)
- [Module contracts](specs/001-aio-foundation/contracts/modules.contract.md)
- [Quickstart (operator runbook)](specs/001-aio-foundation/quickstart.md)
- [Tasks](specs/001-aio-foundation/tasks.md)

## Quick Start (TL;DR)

1. Read [`specs/001-aio-foundation/quickstart.md`](specs/001-aio-foundation/quickstart.md).
2. Run `scripts/setup-oidc.ps1` once to wire GitHub ↔ Azure OIDC.
3. `gh workflow run deploy.yml -f environment=dev` — or run
   `scripts/deploy.ps1` locally.

## Layout (planned, see `plan.md` for full tree)

```
infra/
  main.bicep             # subscription-scope entry
  workload.bicep         # rg-scope orchestrator
  parameters/            # main.<env>.bicepparam — only per-env diff
  shared/                # naming.bicep, tags.bicep, types.bicep, region-capabilities.bicep
  modules/               # one folder per resource family
scripts/                 # deploy.ps1/.sh, setup-oidc.ps1, verify-deploy.ps1
.github/workflows/       # validate.yml (PR), deploy.yml (OIDC, env-gated)
specs/                   # Spec Kit artifacts
.specify/                # Spec Kit templates & memory (constitution)
```

## License

MIT. See [LICENSE](LICENSE).
