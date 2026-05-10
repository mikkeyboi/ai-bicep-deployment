# Quickstart: AIO Foundation (Operator Runbook)

**Feature**: 001-aio-foundation
**Audience**: Repo owner doing the one-time setup, then any contributor.
**Goal (SC-001)**: Green `Deploy (dev)` run within ~60 minutes.

> All commands assume PowerShell 7+ (`pwsh`). For bash, swap `$VAR` for
> `$VAR` and use the equivalent `--flag` form.

## 0. Prerequisites (one-time, per machine)

```pwsh
az --version          # >= 2.60
bicep --version       # bundled with az; az bicep upgrade if needed
gh --version          # GitHub CLI; optional but used in steps below
```

You are already logged in:
```pwsh
az login --tenant <YOUR_TENANT_ID>
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

## 1. One-time Azure setup: register providers + accept Marketplace

```pwsh
az provider register -n Microsoft.CognitiveServices
az provider register -n Microsoft.MachineLearningServices
az provider register -n Microsoft.Storage
az provider register -n Microsoft.KeyVault
az provider register -n Microsoft.OperationalInsights
az provider register -n Microsoft.Insights
az provider register -n Microsoft.ManagedIdentity
```

Accept the **Anthropic Claude in Microsoft Foundry** Marketplace offer
once for the subscription:
- Portal → Marketplace → search "Claude in Microsoft Foundry" →
  *Subscribe* → choose your subscription. (One-time, no resource is
  created here.)

If you intend to use **GPT-image-1 / 1.5**, apply via the Microsoft
limited-access form linked from the Azure OpenAI image-generation docs.
The `dev` parameter file leaves these disabled by default.

## 2. One-time GitHub ↔ Azure OIDC trust

Run the helper (it is non-interactive and idempotent):

```pwsh
./scripts/setup-oidc.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -TenantId       <YOUR_TENANT_ID> `
  -GitHubOrg      mikkeyboi `
  -GitHubRepo     ai-bicep-deployment `
  -Environments   dev,test,prod
```

The script:
1. Creates an Entra app registration `gh-oidc-ai-bicep-deployment`.
2. Creates one **federated credential** per environment with
   `subject = repo:mikkeyboi/ai-bicep-deployment:environment:<env>`.
3. Creates the matching service principal.
4. Assigns `Contributor` at subscription scope; `User Access Administrator`
   only if requested (needed because `roleAssignment` modules write RBAC).
5. Prints the values to set in GitHub:
   - **Variables**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION` (default `eastus2`).
   - No secrets are printed because none are created.

Set them via:
```pwsh
gh variable set AZURE_CLIENT_ID       --body <printed-value>
gh variable set AZURE_TENANT_ID       --body <printed-value>
gh variable set AZURE_SUBSCRIPTION_ID --body <printed-value>
gh variable set AZURE_LOCATION        --body eastus2
```

In the GitHub UI: **Settings → Environments → New environment** for
`dev`, `test`, `prod`. Add **required reviewers** for `test` and `prod`.

## 3. First local deploy (dry-run)

```pwsh
./scripts/deploy.ps1 `
  -Environment   dev `
  -Subscription  <YOUR_SUBSCRIPTION_ID> `
  -Tenant        <YOUR_TENANT_ID> `
  -WhatIf
```

Read the diff. When happy:

```pwsh
./scripts/deploy.ps1 -Environment dev -Subscription <id> -Tenant <id>
```

End-to-end takes ≤ 25 minutes (SC-006).

## 4. First CI deploy

```pwsh
gh workflow run deploy.yml -f environment=dev
gh run watch
```

Expected resources in `rg-aio-dev-eus2`:
- 1× AI Foundry hub, 1× project
- 1× Azure OpenAI account with the configured deployments
- 1× Foundry Claude-hosting account with the configured Claude deployments
- 1× Storage, 1× Key Vault, 1× Log Analytics, 1× App Insights
- 1× user-assigned MI + role assignments
- Diagnostic settings on every PaaS resource

## 5. Day-2: add a model

Edit only `infra/parameters/main.dev.bicepparam`, append to the array,
open a PR. The PR will:
- Comment with the `what-if` diff (one resource added).
- Block merge if `gitleaks` finds anything.
After merge, `Deploy (dev)` runs automatically.

## 6. Tear down

```pwsh
az group delete -n rg-aio-dev-eus2 --yes --no-wait
```

If a Cognitive Services account or Key Vault was previously soft-deleted
under the same name, purge it before redeploy:

```pwsh
az cognitiveservices account purge --name <name> --location eastus2 --resource-group rg-aio-dev-eus2
az keyvault purge                  --name <name> --location eastus2
```
