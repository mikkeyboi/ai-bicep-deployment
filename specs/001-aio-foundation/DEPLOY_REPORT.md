# Deploy Report - 001-aio-foundation (env=dev)

**Date:** 2026-05-10 (MDT)
**Branch:** `001-aio-foundation`
**Target subscription:** `<subscription-id>` (Visual Studio Enterprise)
**Region:** `eastus2`
**Resource group:** `rg-aio-dev-eus2`
**Deployment name:** `aio-dev-20260510-232050`
**Outcome:** ✅ **Succeeded** in `PT1M45.9671392S` (~106 s, post-fix run)

## Summary

First successful end-to-end deploy of the AIO foundation `dev` slice. The
template provisions:

- Azure OpenAI account (`oai-aio-dev-eus2-npnga`) with 3 model deployments
- Azure AI Foundry hub (`hub-aio-dev-eus2`) + project (`proj-aio-dev-eus2`)
- User-assigned managed identity, Key Vault, Storage, Log Analytics,
  App Insights
- Diagnostic settings on OpenAI / KV / Storage → Log Analytics
- RBAC: workload MI → Cognitive Services OpenAI User, KV Secrets User

## Chat-model selection

- The original spec called for `gpt-5-chat` (GlobalStandard, 50 K TPM).
- This subscription has **0 TPM quota for all GlobalStandard chat SKUs**
  in `eastus2`, so the prior `az deployment sub validate` rejected the
  template (see `DEPLOY_FAILURE.md` for the original failure).
- Per user approval, `dev` swaps the primary chat model to **`gpt-4.1`
  (`2025-04-14`) on the `Standard` SKU at 50 K TPM** (the highest-quality
  generally-available chat model with TPM quota on this subscription).
- `gpt-5-chat` is intentionally retained in `main.test.bicepparam` and
  `main.prod.bicepparam`; those environments stay gated behind a separate
  quota request that the user will submit.

## Validation gates

| Gate                          | Result |
| ----------------------------- | ------ |
| `bicep build infra/main.bicep`| ✅ pass (warnings only) |
| `az deployment sub validate`  | ✅ `Succeeded`, `error: null` |
| `az deployment sub what-if`   | ✅ 17 Create / 4 Unsupported (informational) |
| `gitleaks detect --no-git`    | ✅ no leaks in working tree |
| Privacy grep (tenant/sub/emails) | ✅ 0 hits in tracked files |

`what-if` Create set:

- 1× resource group
- 1× UAMI, 1× Log Analytics, 1× App Insights
- 1× Key Vault (+ diag)
- 1× Storage account (+ diag)
- 1× Azure OpenAI account (+ diag) + 3× model deployments
- 1× Foundry hub + AzureOpenAI connection
- 1× Foundry project

`Unsupported` entries are RBAC / role-assignment short-circuits flagged by
what-if; they don't represent failures and are expected per the linter
warnings on `workload.bicep`.

## Resources provisioned

```
log-aio-dev-eus2         Log Analytics workspace
id-aio-dev-eus2          User-assigned managed identity
staiodeveus2npnga        Storage account
kv-aio-dev-eus2-npnga    Key Vault
appi-aio-dev-eus2        Application Insights
oai-aio-dev-eus2-npnga   Azure OpenAI account
hub-aio-dev-eus2         Foundry hub (Microsoft.MachineLearningServices/workspaces)
proj-aio-dev-eus2        Foundry project (workspaces, kind=Project)
```

Azure OpenAI deployments:

| Name                     | Model                  | Version    | SKU       | Capacity (K TPM) |
| ------------------------ | ---------------------- | ---------- | --------- | ---------------- |
| `gpt-4-1`                | `gpt-4.1`              | 2025-04-14 | Standard  | 50               |
| `gpt-4o`                 | `gpt-4o`               | 2024-11-20 | Standard  | 50               |
| `text-embedding-3-large` | `text-embedding-3-large` | 1        | Standard  | 120              |

## Code changes shipped with this deploy

1. **`infra/parameters/main.dev.bicepparam`**
   - Removed `gpt-5-chat` deployment entry (no quota).
   - Added `gpt-4.1 @ 2025-04-14, Standard / 50` as the primary chat model.
   - Set `enableAiSearch: false` for dev (see "Open follow-ups" below).

2. **`infra/shared/region-capabilities.bicep`**
   - Added `OpenAI:gpt-4.1` and `OpenAI:gpt-4.1-mini` to the `eastus2`
     supported set. (First-party Azure OpenAI; consumption-billed;
     Constitution VIII compliant.)

3. **`infra/modules/foundry-hub/main.bicep`**
   - `output principalId` now uses `contains(hub.identity, 'principalId')`
     instead of the `.?` safe-access on the SystemAssigned principalId.
     The hub uses UserAssigned identity only, so `identity.principalId`
     is absent at runtime and `?? ''` was throwing
     `DeploymentOutputEvaluationFailed`.

4. **`infra/workload.bicep`**
   - Added `@batchSize(1)` on the `oaiDeps` module loop. Parallel writes
     against the same `Microsoft.CognitiveServices/accounts` parent were
     triggering `RequestConflict` on the second/third model deployment.

`test`/`prod` paramfiles are unchanged.

## Open follow-ups

- **Azure AI Search** is disabled for `dev` until eastus2 Search capacity
  recovers. The two prior deploy attempts in this same session hit
  `InsufficientResourcesAvailable` from the regional Search SKU pool
  (not a quota issue — region-wide capacity exhaustion). `test`/`prod`
  paramfiles still request Search; flip the dev flag back when capacity
  returns or pin Search to an alternate region.
- **`gpt-5-chat` quota request** — submit Azure support ticket for
  `OpenAI.GlobalStandard.gpt-5-chat` ≥ 50 K TPM in `eastus2`. Once
  granted, restore `gpt-5-chat` to `main.dev.bicepparam` and remove the
  gpt-4.1 stopgap if desired.
- **Two preceding failed sub deployments** in this run
  (`aio-dev-20260510-231104`, `aio-dev-20260510-231505`,
  `aio-dev-20260510-231736`) are visible in the subscription deployment
  history; they left no orphan resources (the RG was created and reused;
  successful resources from earlier passes were idempotently reconciled
  in the final deploy).

## Privacy / compliance

- 0 tenant IDs, 0 subscription IDs, 0 personal emails in tracked files.
- gitleaks working-tree scan: clean. (Historic commits on this branch
  contain a redacted `whatif.json` artifact that was removed in `c5404f4`;
  that is acknowledged in `DEPLOY_FAILURE.md` and the branch will be
  squash-merged into `main`, so the leaks do not enter `main`.)
- Constitution v1.1.0 Principle VIII: zero Marketplace / partner SaaS
  resources. All deployed services are first-party Azure consumption
  resources.
