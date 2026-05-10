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
**Rationale**: As of 2026-05, **East US 2** is the only region that
simultaneously offers (a) the latest Azure OpenAI frontier text models
including the GPT-5 family, (b) image-generation models gated under the
GPT-image program, and (c) Anthropic Claude models hosted in Microsoft
Foundry (alongside Sweden Central). One region = simpler latency,
networking, and quota story for a POC.
**Alternatives**:
- `swedencentral` — also supports Claude in Foundry; viable secondary.
- `canadacentral` (operator's locale) — does not yet host Claude in
  Foundry or the latest GPT-image models. Not chosen for `dev`; could
  host paired regional resources later.

### D4. Model deployment surface
**Decision**: Express model deployments as a typed array in the
parameter file, validated at compile time against a region-capability
map.

Default `dev` set:
- **OpenAI account** (`Microsoft.CognitiveServices/accounts`, kind=`OpenAI`):
  - `gpt-5-chat` (Global Standard, capacity 50)
  - `gpt-4o` (Global Standard, capacity 50) — fallback / cost-tier
  - `text-embedding-3-large` (Global Standard, capacity 120)
- **Foundry account hosting Claude** (`Microsoft.CognitiveServices/accounts`,
  kind=`AIServices` configured for partner models):
  - `claude-sonnet-4-5` (Global Standard)
  - `claude-haiku-4-5` (Global Standard)
- **Disabled-by-default, parameter-only**:
  - `gpt-image-1`, `gpt-image-1.5` — gated; require Microsoft access
    approval per subscription. Parameter file documents how to enable.
  - `claude-opus-4-7` — preview; uncomment after validating quota.

**Rationale**: Matches the user's request for GPT-5-class text, image
generation where available, and Claude. Gated items are first-class but
opt-in to avoid deploy failures in fresh subscriptions.

### D5. Foundry resource shape
**Decision**: Provision a Foundry **hub** (`Microsoft.MachineLearningServices/workspaces`,
`kind=Hub`) plus one **project** (`kind=Project`) bound to the hub. Both
the OpenAI account and the Claude-hosting Foundry account are created
separately and "connected" to the hub via `connections` child resources
so they appear inside the Foundry experience.
**Rationale**: Clean separation between identity (the cognitive accounts)
and the user-facing AI workspace (the hub/project). Connections make the
accounts discoverable in the Foundry portal without coupling lifecycles.

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
| Region for frontier + Claude co-residency | `eastus2` (D3) |
| GPT-image availability | Gated; param-only, disabled by default (D4) |
| Claude SKU/format | Global Standard via Foundry; Marketplace acceptance prerequisite (D4) |
| Secret material | None in repo; runtime via Key Vault + MI (D8) |
| CI auth | OIDC federated, per-env subject (D2) |

## External References (for plan & implementation)

- Azure OpenAI models & regions overview (Microsoft Learn).
- "Deploy and use Claude models in Microsoft Foundry" (Microsoft Learn) —
  region requirements: **East US 2** or **Sweden Central**; Marketplace
  subscription prerequisite.
- "How to use image generation models from OpenAI" (Microsoft Learn) —
  GPT-image-1 / 1.5 are limited-access.
- Azure Verified Modules registry (`br/public:avm/res/*`) for
  battle-tested resource modules.
- CAF resource abbreviations table.
- GitHub OIDC + `azure/login@v2` documentation.
