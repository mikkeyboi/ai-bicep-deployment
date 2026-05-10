# Implementation Report — 001-aio-foundation

**Branch:** `001-aio-foundation`
**Status:** Implementation complete; pending operator OIDC bootstrap and first deploy.

## What was built

### Infrastructure (`infra/`)
- `main.bicep` — subscription-scope entry point. Creates the resource group, runs a `regionCapability` guard, and dispatches to `workload.bicep`.
- `workload.bicep` — resource-group-scope orchestrator: identity → log analytics → app insights → storage → key vault → AI Search → OpenAI account + deployments → Foundry/Claude AIServices account + deployments → Foundry hub + project → connections → role assignments → diagnostic settings.
- `shared/types.bicep` — typed `environmentConfig`, `modelDeployment`, `connectionSpec`, `roleAssignmentSpec`.
- `shared/naming.bicep` — CAF-style naming user-defined function.
- `shared/tags.bicep` — standard tag set (`environment`, `workload`, `costCenter`, `owner`, `managedBy=bicep`, `deploymentId`).
- `shared/region-capabilities.bicep` — declarative region/model capability matrix that fails fast on a bad region.
- `modules/` — 15 hand-rolled modules (managed-identity, log-analytics, app-insights, storage, key-vault, ai-search, openai-account, openai-deployment, foundry-claude-account, foundry-claude-deployment, foundry-hub, foundry-project, foundry-connection, role-assignment, diagnostic-settings). Avoids public AVM dependencies for transparency on a public repo.
- `parameters/main.{dev,test,prod}.bicepparam` — three environment param files. Dev is fully populated; test/prod are reduced placeholders ready to grow.

### CI (`/.github/workflows/`)
- `validate.yml` — PR-triggered: bicep lint → build → gitleaks → Azure OIDC login (dev env) → `validate` → `what-if` → sticky PR comment with the diff.
- `deploy.yml` — `workflow_dispatch` with environment input + push-to-main on `infra/**`: OIDC login → validate → what-if → create. Uses `vars.AZURE_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID/LOCATION` from each GitHub Environment. **No client secrets anywhere.**

### Scripts (`/scripts/`)
- `setup-oidc.ps1` — idempotent: creates Entra app, SP, federated credentials per environment, role assignments at subscription scope. Prints the exact `gh variable set` commands to run.
- `deploy.ps1` / `deploy.sh` — local deploy (validate → what-if → confirm → create). All IDs come from required parameters; nothing hardcoded.
- `preflight.ps1` — checks az/bicep version, lists soft-deleted KV/CogSvc name conflicts, reminds about Marketplace acceptance for Claude.
- `verify-deploy.ps1` — post-deploy smoke checks (RG exists, deployments present, KV in RBAC mode).

### Security & repo hygiene
- `.gitignore` — excludes `.env`, `*.local.bicepparam`, `.azure/`, `build/`, `*.tmp.*`.
- `.gitleaks.toml` — generic rules (any GUID in source, any gmail address, 32-hex Cognitive key shape, SAS token shape). The config file itself contains **no operator-specific values** — it is safe to publish.
- `bicepconfig.json` — strict linter, all warnings surfaced, experimental features disabled.

### Spec Kit artifacts
All Phase 0–2 docs from the prior turn are unchanged; the `tasks.md` checklist was updated as work completed.

## Validation results

| Gate | Result | Notes |
|------|--------|-------|
| `bicep lint infra/main.bicep` | ✅ exit 0 | 7 warnings, all benign (use-safe-access nits, what-if short-circuiting on union-typed module params, no-deployments-resources on the intentional capability-guard `Microsoft.Resources/deployments` stub). |
| `bicep build infra/main.bicep` | ✅ exit 0 | Same warnings, no errors. |
| `az deployment sub validate` (dev paramfile, target sub) | ✅ exit 0 | Provider preflight passed. |
| `az deployment sub what-if` (dev) | ✅ **22 creates, 0 deletes, 0 modifies, 5 unsupported** | Unsupported = nested cross-scope `Microsoft.Authorization/roleAssignments` — known what-if limitation, will deploy normally. |
| `gitleaks detect` | ✅ no leaks | Built-in role-definition GUIDs in `infra/modules/role-assignment/main.bicep` are explicitly allowlisted (Microsoft public constants). |
| Privacy grep (tenant ID, sub ID, both gmail addresses) over the entire working tree | ✅ **0 hits** | Confirmed against `Get-ChildItem -Recurse -Force` (not just tracked files). |

### What-if summary (creates, dev environment)

```
+ rg-aio-dev-eus2
+ Microsoft.MachineLearningServices/workspaces/hub-aio-dev-eus2          (Foundry hub)
+ Microsoft.MachineLearningServices/workspaces/proj-aio-dev-eus2         (Foundry project)
+ ...hub/connections/aoai-conn, aiservices-conn
+ Microsoft.CognitiveServices/accounts/oai-aio-dev-eus2-npnga            (OpenAI)
+   /deployments/gpt-5-chat
+   /deployments/gpt-4o
+   /deployments/text-embedding-3-large
+ Microsoft.CognitiveServices/accounts/aif-aio-dev-eus2-npnga            (AIServices for Claude)
+   /deployments/claude-sonnet-4-5
+   /deployments/claude-haiku-4-5
+ Microsoft.Search/searchServices/srch-aio-dev-eus2-npnga
+ Microsoft.Storage/storageAccounts/staiodeveus2npnga
+ Microsoft.KeyVault/vaults/kv-aio-dev-eus2-npnga
+ Microsoft.OperationalInsights/workspaces/log-aio-dev-eus2
+ Microsoft.Insights/components/appi-aio-dev-eus2
+ Microsoft.ManagedIdentity/userAssignedIdentities/id-aio-dev-eus2
+ 5x diagnosticSettings/to-law (oai, aif, kv, st, srch)
x 5x roleAssignments (UAMI -> OpenAI/AIServices/KV/Storage/Search) — what-if-unsupported, will create
```

## Deviations from plan

1. **`claude-opus-4-7` not deployed.** Not yet listed by the Cognitive Services model catalog in `eastus2`. Closest preview is `claude-opus-4-5`; left commented in `main.dev.bicepparam` with instructions. Re-check with `az cognitiveservices model list --location eastus2` periodically and uncomment when available.
2. **`gpt-image-1` / `gpt-image-1.5` left commented.** Both are Microsoft limited-access; deploying without approval would fail at create. Operator will request access and uncomment.
3. **No public AVM modules used.** Plan suggested AVM where convenient. On audit, hand-rolled modules were chosen for full input/output transparency on a public repo, and to avoid pinning to AVM versions that may break. All modules are <100 lines and easy to review.
4. **Foundry hub uses the legacy `Microsoft.MachineLearningServices/workspaces` ARM type.** This is still the supported surface for "Foundry classic" hubs as of API 2024-10-01. The newer `Microsoft.CognitiveServices/aiServices` Foundry resource type is preview-only and not yet stable.

## Blockers / deferred

- **Marketplace acceptance for Claude in Foundry** — operator must accept the "Claude in Microsoft Foundry" Marketplace offer once per subscription before the Claude deployments will succeed. Not scriptable without elevated tenant perms; covered in `quickstart.md` and `preflight.ps1`.
- **GitHub Environments** — must be created in repo Settings → Environments (`dev`, `test`, `prod`) and have `vars` populated by `setup-oidc.ps1`. Add required reviewers on `test` and `prod` for the manual gate.

## Next steps (operator)

Run these in order from a `pwsh` shell with `az login` already done and the `gh` CLI authenticated:

```powershell
cd C:\Users\michaelleung\source\ai-bicep-deployment

# 1. Pre-flight (warns about soft-deleted name conflicts etc.)
./scripts/preflight.ps1 -SubscriptionId <YOUR_SUB_ID> -Location eastus2

# 2. Optional: deploy locally first to confirm everything works.
./scripts/deploy.ps1 -Environment dev -Subscription <YOUR_SUB_ID> -Tenant <YOUR_TENANT_ID> -Location eastus2 -WhatIf
./scripts/deploy.ps1 -Environment dev -Subscription <YOUR_SUB_ID> -Tenant <YOUR_TENANT_ID> -Location eastus2

# 3. Set up GitHub OIDC + the three GitHub Environments.
#    This creates an Entra app, federated credentials per env, and prints
#    the exact `gh variable set` commands you need to paste.
./scripts/setup-oidc.ps1 `
  -SubscriptionId <YOUR_SUB_ID> `
  -TenantId       <YOUR_TENANT_ID> `
  -RepoOwner      mikkeyboi `
  -RepoName       ai-bicep-deployment `
  -Environments   dev,test,prod

# 4. In the GitHub UI: Settings -> Environments -> create dev/test/prod
#    (paste the AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID /
#    AZURE_LOCATION variables that step 3 printed). Add required reviewers
#    on test and prod.

# 5. Open the PR for review.
gh pr create --base main --head 001-aio-foundation --fill --web

# 6. After PR merges, deploy via Actions:
gh workflow run deploy.yml -f environment=dev
```

For Claude:
- Portal → Marketplace → search "Claude in Microsoft Foundry" → Subscribe (one-time per subscription).
- Then re-run the deploy.

For GPT image models:
- Apply at https://aka.ms/oai/gpt-image-access. When approved, uncomment the relevant block in `infra/parameters/main.dev.bicepparam` and redeploy.
