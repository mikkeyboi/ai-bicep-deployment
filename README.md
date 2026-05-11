# ai-bicep-deployment

Bicep + GitHub Actions OIDC provisioning for an Azure AI "all-in-one"
foundation: AI Foundry (hub + project), Azure OpenAI with frontier
models, AI Search, Storage, Key Vault, Log Analytics, App Insights,
managed identity, and RBAC.

> **Public repo.** No tenant IDs, subscription IDs, keys, or personal
> data live in source. See `.specify/memory/constitution.md`.
>
> **Consumption-only.** Per Constitution Principle VIII (v1.1.0), this
> stack provisions only first-party Azure resources that bill against
> Azure consumption / MCA-E credits. Azure Marketplace SaaS offers
> (e.g., Anthropic Claude in Microsoft Foundry, Cohere, Mistral premium)
> are out of scope.

## Quickstart (3 steps)

1. **OIDC trust** — once per repo:
   ```pwsh
   ./scripts/setup-oidc.ps1 `
     -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
     -TenantId       <YOUR_TENANT_ID> `
     -GitHubOrg      mikkeyboi `
     -GitHubRepo     ai-bicep-deployment `
     -Environments   dev,test,prod
   ```
2. **GitHub Variables** — set `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_LOCATION` in each
   GitHub Environment (the script above prints exact `gh variable set`
   commands).
3. **Deploy** — local dry-run first, then CI:
   ```pwsh
   ./scripts/deploy.ps1 -Environment dev `
     -Subscription <YOUR_SUBSCRIPTION_ID> -Tenant <YOUR_TENANT_ID> -WhatIf
   gh workflow run deploy.yml -f environment=dev
   ```

Full operator runbook: [`specs/001-aio-foundation/quickstart.md`](specs/001-aio-foundation/quickstart.md).

## Layout

```
infra/
  main.bicep                # subscription-scope entry; creates RG, calls workload
  workload.bicep            # RG-scope orchestrator
  shared/                   # types, naming, tags, region capabilities
  modules/                  # one folder per resource family
  parameters/main.<env>.bicepparam
.github/workflows/          # validate.yml (PR gate), deploy.yml (OIDC)
scripts/                    # deploy.ps1, deploy.sh, setup-oidc.ps1, preflight.ps1
specs/001-aio-foundation/   # spec, plan, research, data-model, contracts, tasks
.specify/                   # Spec Kit templates, scripts, constitution
```

## Governing principles

`.specify/memory/constitution.md`. Every PR is reviewed against it.

## Contributing

- Create a branch `NNN-<slug>`; add/update a spec under `specs/`.
- Open a PR — `validate.yml` lints, builds, runs `what-if`, and
  `gitleaks`-scans the diff. The `what-if` summary is posted as a
  PR comment.
- Squash-merge after approval; `Deploy (dev)` runs automatically.

## License

MIT — see [LICENSE](LICENSE).
