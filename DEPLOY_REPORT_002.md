# Deploy Report: Feature 002 — New Foundry Resource

**Date**: 2026-05-11 (America/Edmonton, late evening 2026-05-10 local)
**Branch**: `002-new-foundry` → squash-merged into `main`
**Merge commit**: `6b2d9d9`
**Predecessor (last green main)**: `5805d74`
**Constitution**: bumped to **v1.2.0** (Principle IV clarification:
AI Foundry uses the unified Foundry resource).

## Branch commits (squashed)

| Hash | Message |
|------|---------|
| `b4c926f` | spec(002-new-foundry): amend constitution to v1.2.0 + author 002 spec |
| `1697558` | feat(infra): add foundry-account module (CognitiveServices kind=AIServices + projects) |
| `90b3b80` | refactor(infra): drop legacy foundry hub+project+connection and standalone OpenAI modules |
| `0fe8ad1` | refactor(infra): wire workload.bicep to new foundry-account; rename openAi->foundry in paramfiles |

## Validation summary

- `az bicep build infra/main.bicep` — clean (only pre-existing
  no-deployments-resources / use-safe-access / what-if-short-circuiting
  warnings).
- `az deployment sub validate` — `provisioningState: Succeeded` against
  `infra/parameters/main.dev.bicepparam`.
- Privacy grep — 0 hits for tenant id, subscription id, or personal
  emails over tracked files.

## Real deploy

- Deployment name: `aio-dev-newfoundry-20260511-0000`
- Scope: subscription `${SUBSCRIPTION_ID}`, target RG `rg-aio-dev-eus2`
- Region: `eastus2`
- Duration: **1m 6s**
- Result: **Succeeded**

### Resource diff vs. previous deploy (`5805d74`)

**Created**
- `aif-aio-dev-eus2-npnga` — `Microsoft.CognitiveServices/accounts`
  kind=`AIServices`, system-assigned identity, customSubDomain enabled,
  `disableLocalAuth: true`, `allowProjectManagement: true`
- `aif-aio-dev-eus2-npnga/proj-aio-dev-eus2` — child Foundry project
- 3 model deployments on the Foundry account:
  - `gpt-4-1` (model `gpt-4.1` v `2025-04-14`, Standard 50)
  - `gpt-4o` (model `gpt-4o` v `2024-11-20`, Standard 50)
  - `text-embedding-3-large` (Standard 120)
- Diagnostic settings on the Foundry account → Log Analytics
- 3 role assignments on the workload UAMI:
  - Cognitive Services User → Foundry account
  - Key Vault Secrets User → KV
  - Storage Blob Data Contributor → Storage

**Destroyed (manual `az resource delete` / `cognitiveservices account purge`
prior to redeploy, since the legacy quota and names had to free up)**
- `proj-aio-dev-eus2` (`Microsoft.MachineLearningServices/workspaces`
  kind=Project)
- `hub-aio-dev-eus2` (`Microsoft.MachineLearningServices/workspaces`
  kind=Hub)
- `oai-aio-dev-eus2-npnga` (`Microsoft.CognitiveServices/accounts`
  kind=OpenAI) — deleted **and purged**

**Reused unchanged**
- `log-aio-dev-eus2`, `id-aio-dev-eus2`, `staiodeveus2npnga`,
  `kv-aio-dev-eus2-npnga`, `appi-aio-dev-eus2`

## Smoke check (post-deploy)

```
az resource list -g rg-aio-dev-eus2
  log-aio-dev-eus2                          OperationalInsights/workspaces           Succeeded
  id-aio-dev-eus2                           ManagedIdentity/userAssignedIdentities   Succeeded
  staiodeveus2npnga                         Storage/storageAccounts                  Succeeded
  kv-aio-dev-eus2-npnga                     KeyVault/vaults                          Succeeded
  appi-aio-dev-eus2                         Insights/components                      Succeeded
  aif-aio-dev-eus2-npnga                    CognitiveServices/accounts               Succeeded
  aif-aio-dev-eus2-npnga/proj-aio-dev-eus2  CognitiveServices/accounts/projects      Succeeded

az cognitiveservices account deployment list -g rg-aio-dev-eus2 -n aif-aio-dev-eus2-npnga
  gpt-4-1
  gpt-4o
  text-embedding-3-large
```

All three model deployments present. Foundry project visible to the
new Foundry portal experience.

## Follow-ups

1. Promote `test` and `prod` paramfiles when ready — both already
   updated to the new `foundry: { … }` shape but **not** deployed in
   this PR.
2. The `Cognitive Services User` role on the Foundry account covers
   Azure OpenAI inference for the workload UAMI; revisit if Agent
   Service / capability hosts (`Agents`, `OpenAI`) are added later.
3. `region-capabilities.bicep` is still keyed by `OpenAI` model format,
   which remains correct under the unified Foundry account.
