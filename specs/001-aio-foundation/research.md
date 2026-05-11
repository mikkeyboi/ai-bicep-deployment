# Phase 0 Research: AIO Foundation

**Feature**: 001-aio-foundation
**Date**: 2026-05-10

This document records the technology decisions, alternatives weighed, and
external constraints that shape `plan.md`. Anything marked
`NEEDS CLARIFICATION` in the spec is resolved here or escalated.

## Decisions

### D1. IaC: Bicep (subscription-scope entry, RG-scope workload)
**Decision**: Use Bicep with a subscription-scope `main.bicep` that creates
the resource group and invokes a resource-group-scope `workload.bicep`.
**Rationale**: Native Azure DSL; first-party tooling for `what-if`,
`lint`, and `build`; user-defined types & functions reduce repetition.
**Alternatives**:
- Terraform AzureRM/AzAPI — adds a state backend, providers, drift; the
  user already chose Bicep.
- Azure Verified Modules (Bicep) — we will *consume* AVM for individual
  resources (`br/public:avm/res/*`) where stable; the orchestration layer
  is ours.

### D2. Authentication: GitHub OIDC → Entra ID workload identity
**Decision**: One Entra app registration per repo with one federated
credential per environment (`subject = repo:mikkeyboi/ai-bicep-deployment:environment:<env>`).
Service principal granted `Contributor` at subscription scope and
`User Access Administrator` only when `roleAssignments` array is non-empty.
**Rationale**: Eliminates client secrets in GitHub; rotates automatically;
per-env subjects allow distinct approvers and isolation.
**Alternatives**:
- Service principal + client secret stored as GitHub secret — rejected by
  Constitution Principle III.
- Managed identity on a self-hosted runner — overkill for this repo.

### D3. Region default: `eastus2`
**Decision**: Default `location = eastus2` for `dev`. Allow override per
parameter file.
**Rationale**: As of 2026-05, **East US 2** offers the broadest set of
first-party Azure OpenAI capabilities consumed by this stack — the GPT-5
family, GPT-4o family, the latest text-embedding-3 models, and (with
limited-access approval) the GPT-image-1 / 1.5 image-generation models.
With partner Marketplace models removed per Constitution VIII (see D11),
the constraint reduces to “where is the GPT-5 family available with the
richest co-located OpenAI surface?” — and `eastus2` remains the best
answer. One region also keeps latency, networking, and quota simple for
a POC.
**Alternatives**:
- `swedencentral` — supports a smaller subset of OpenAI frontier text
  models; viable EU-residency secondary.
- `canadacentral` (operator's locale) — does not host the GPT-5 family
  or the GPT-image program at this time. Not chosen for `dev`; could
  host paired regional resources later when GPT-5 lands.

### D4. Model deployment surface
**Decision**: Express model deployments as a typed array in the
parameter file, validated at compile time against a region-capability
map. Only first-party Azure OpenAI models are deployed (Constitution
VIII forbids Marketplace SaaS partner models).

Default `dev` set:
- **OpenAI account** (`Microsoft.CognitiveServices/accounts`, kind=`OpenAI`):
  - `gpt-5-chat` (Global Standard, capacity 50)
  - `gpt-4o` (Standard in eastus2, capacity 50) — fallback / cost-tier
  - `text-embedding-3-large` (Standard, capacity 120)
- **Disabled-by-default, parameter-only**:
  - `gpt-image-1`, `gpt-image-1.5` — gated; require Microsoft access
    approval per subscription. Parameter file documents how to enable.
    These bill as Azure consumption; they are first-party.

**Rationale**: Matches the user's request for GPT-5-class text and
image generation where available. Gated items are first-class but
opt-in to avoid deploy failures in fresh subscriptions. Partner /
Marketplace models (Anthropic, Cohere, Mistral premium) are excluded
per D11 / Constitution VIII.

### D5. Foundry resource shape
**Decision**: Provision a Foundry **hub** (`Microsoft.MachineLearningServices/workspaces`,
`kind=Hub`) plus one **project** (`kind=Project`) bound to the hub. The
Azure OpenAI account is created separately and “connected” to the hub
via a `connections` child resource so the deployed models appear inside
the Foundry experience.
**Rationale**: Clean separation between identity (the cognitive account)
and the user-facing AI workspace (the hub/project). The connection makes
the account discoverable in the Foundry portal without coupling
lifecycles. With partner Marketplace models removed (D11), no
additional `kind=AIServices` account is required.

### D6. Naming: CAF abbreviations + deterministic uniqueness
**Decision**: Pattern `<abbr>-<workload>-<env>-<regionShort>[-<instance>]`.
For globally-unique names (Storage, Key Vault), append a 5-char hash of
`subscription().subscriptionId` + resource group name. Implemented in
`infra/shared/naming.bicep` as a user-defined function `name()`.
**Examples**: `kv-aio-dev-eus2-7f3a1`, `stagaiodeveus27f3a1` (storage
strips hyphens).
**Rationale**: Consistent, predictable, collision-free across reruns.

### D7. Tags
**Decision**: Single tag map produced by `infra/shared/tags.bicep`:
```
environment, workload, owner, costCenter, managedBy, repo, deployedAt
```
`owner` and `costCenter` come from parameters; `deployedAt =
utcNow('yyyy-MM-ddTHH:mm:ssZ')` passed in from `main.bicep` so child
modules see a stable value within one deployment.

### D11. No Azure Marketplace SaaS offers (consumption-only)
**Decision**: Forbid every resource type whose billing flows through
Azure Marketplace SaaS rather than Azure consumption. This includes the
`Microsoft.SaaS/resources` provider in any form, and any partner model
offered in Microsoft Foundry that requires a Marketplace subscription
before deployment (Anthropic Claude, Cohere Command/Embed, Mistral
premium, etc.).
**Rationale**: Repository constraint — all spend must be redeemable
against Azure credits / MCA-E. Marketplace SaaS bills outside that
envelope even when the resource lives in the operator’s Azure tenant.
Codified as Constitution Principle VIII (v1.1.0, 2026-05-10).
**Consequence**:
- The `foundry-claude-account` and `foundry-claude-deployment` modules
  are removed; no `kind=AIServices` Cognitive Services account is
  provisioned (we used that kind only to host Claude).
- `claudeConfig` is removed from `environmentConfig`.
- `connectionCategory` collapses to `'AzureOpenAI'`.
- Region selection no longer needs to satisfy Claude availability.
- The quickstart no longer includes a Marketplace acceptance step; the
  deploy is fully unattended.
**Alternatives considered**:
1. Deploy Claude in Foundry anyway and accept separate billing —
   **REJECTED** per repo constraint (would consume operator’s credit
   card / MCA non-Azure invoice).
2. Self-host Claude-class open weights (e.g., Llama / Qwen) on AKS or
   Container Apps with GPUs — consumption-billable but **out of scope**
   for this AIO POC; requires its own spec / capacity story.
3. Wait for first-party Azure billing of partner Foundry models —
   speculative; will reassess if/when Microsoft offers a consumption
   SKU for these models.
**Audit hooks**: `git grep -nE "Microsoft\.SaaS|claude|Anthropic|Cohere|Mistral" -- infra scripts` MUST return zero hits in `infra/**` and `scripts/**`.

### D8. Secrets handling at deploy time
**Decision**: No secrets are passed to Bicep at deploy time. The
deployment **emits** outputs (resource IDs, endpoints) but never keys.
Applications retrieve runtime secrets from Key Vault using their managed
identity. The Storage and Cognitive Services accounts have
`disableLocalAuth: true` (Entra-only) where supported.

### D9. CI/CD layout
**Decision**: Two workflows.
- `.github/workflows/validate.yml` — on `pull_request` touching
  `infra/**` or `.github/**`. Runs lint, build, validate, what-if,
  gitleaks. Posts what-if as a PR comment.
- `.github/workflows/deploy.yml` — on `workflow_dispatch` with input
  `environment`, and on `push` to `main` (auto-targets `dev`). Uses the
  matching GitHub Environment for OIDC subject + reviewers.

### D10. Local script parity
**Decision**: `scripts/deploy.ps1` (cross-platform pwsh) is the canonical
implementation; `scripts/deploy.sh` is a thin wrapper that re-execs it
via `pwsh`. Both refuse to run if `--subscription` / `--tenant` are
missing or if `az account show` indicates a different active context
than was passed.

## Open Items Resolved

| Spec marker | Resolution |
|---|---|
| Region for frontier OpenAI surface | `eastus2` (D3) |
| GPT-image availability | Gated; param-only, disabled by default (D4) |
| Partner / Marketplace models (Claude, Cohere, Mistral premium) | Excluded; Constitution VIII / D11 |
| Secret material | None in repo; runtime via Key Vault + MI (D8) |
| CI auth | OIDC federated, per-env subject (D2) |

## External References (for plan & implementation)

- Azure OpenAI models & regions overview (Microsoft Learn).
- "How to use image generation models from OpenAI" (Microsoft Learn) —
  GPT-image-1 / 1.5 are limited-access (first-party / consumption-billed).
- Azure Verified Modules registry (`br/public:avm/res/*`) for
  battle-tested resource modules.
- CAF resource abbreviations table.
- GitHub OIDC + `azure/login@v2` documentation.
