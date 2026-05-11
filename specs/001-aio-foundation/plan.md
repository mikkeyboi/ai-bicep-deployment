# Implementation Plan: AIO Foundation

**Branch**: `001-aio-foundation` | **Date**: 2026-05-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-aio-foundation/spec.md`

## Summary

Provision a complete Azure AI "all-in-one" foundation (Foundry hub +
project, Azure OpenAI with GPT-5/4o/embeddings, AI Search, Storage,
Key Vault, Log Analytics, App Insights, MI + RBAC) using a modular
Bicep tree. Two deployment paths share the same templates and parameter
files: GitHub Actions (OIDC, per-env reviewers) and a local pwsh
script. No tenant/subscription IDs, keys, or personal data live in the
repo. Per Constitution VIII (added in v1.1.0), every provisioned
resource bills as Azure consumption — no Azure Marketplace SaaS
offerings (e.g., Anthropic Claude in Foundry) are deployed.

## Technical Context

**Language/Version**: Bicep (latest CLI bundled with Azure CLI 2.86+),
PowerShell 7.4+ for scripts, GitHub Actions YAML.
**Primary Dependencies**: `azure/login@v2` (OIDC), `azure/arm-deploy@v2`
(or direct `az deployment sub`), `gitleaks/gitleaks-action@v2`,
`Azure/bicep` CLI, optional Azure Verified Modules
(`br/public:avm/res/*`).
**Storage**: N/A in repo (state-free); deployment outputs cached as
GitHub Action artifacts for the run only.
**Testing**:
- Static: `bicep lint`, `bicep build`, `gitleaks`.
- Semantic: `az deployment sub validate`, `az deployment sub what-if`.
- Smoke: post-deploy script asserts presence of expected resources, MI
  role assignments, and model deployments via `az resource list` /
  `az cognitiveservices account deployment list`.
**Target Platform**: Azure Commercial cloud, region default `eastus2`.
**Project Type**: Infrastructure-as-code mono-repo with CI.
**Performance Goals**: SC-002 ≤ 3 min no-op what-if; SC-006 ≤ 25 min
full clean deploy.
**Constraints**: Public repo (Constitution II); OIDC only (III); no
hardcoded identifiers (II, IV); CAF naming (V).
**Scale/Scope**: 1 subscription, 1–3 environments, ~20 resources per
env, ≤ 10 model deployments per env.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*
*Re-run 2026-05-10 against Constitution v1.1.0 (added Principle VIII).*

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Pure Bicep + `what-if`/`create`; scripts orchestrate only. |
| II. No Secrets / IDs / PII in Source | PASS | Identifiers via GitHub Variables + script args; gitleaks gate. |
| III. OIDC-First Auth | PASS | Federated credential per env; no client secret. |
| IV. Modular Templates / Single Entry | PASS | One `main.bicep` (sub scope); modules under `infra/modules/*`. |
| V. Naming & Tagging Discipline | PASS | `infra/shared/naming.bicep` + `tags.bicep`. |
| VI. Validation Gates | PASS | `validate.yml` runs lint/build/validate/what-if/gitleaks. |
| VII. Environment Parity | PASS | `main.<env>.bicepparam` is the only per-env diff. |
| VIII. Azure Consumption Billing Only | PASS | Claude/AIServices module + paramfile entries removed; only first-party RPs (`Microsoft.CognitiveServices` kind=`OpenAI`, `Microsoft.MachineLearningServices`, `Microsoft.Search`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.ManagedIdentity`, RBAC, diagnostic settings) remain. `git grep` for `Microsoft.SaaS` / `claude` / `Anthropic` / `Cohere` / `Mistral` over `infra/**` returns zero hits. |

**Result**: All gates pass. No entries required in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-aio-foundation/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions & rationale
├── data-model.md        # Phase 1 — entity & parameter model
├── quickstart.md        # Phase 1 — operator runbook (OIDC + first deploy)
├── contracts/           # Phase 1 — module input/output contracts
│   ├── main.contract.md
│   ├── foundry.contract.md
│   ├── openai.contract.md
│   ├── claude.contract.md
│   ├── storage.contract.md
│   ├── key-vault.contract.md
│   └── observability.contract.md
└── tasks.md             # Phase 2 — created by /speckit.tasks
```

### Source Code (repository root)

```text
ai-bicep-deployment/
├── .github/
│   ├── workflows/
│   │   ├── validate.yml        # PR gate (lint, build, validate, what-if, gitleaks)
│   │   └── deploy.yml          # OIDC deploy, env input, environment protection
│   └── copilot-instructions.md # Agent guidance, mirrors constitution
├── infra/
│   ├── main.bicep              # Subscription-scope entry
│   ├── workload.bicep          # RG-scope orchestrator (calls modules)
│   ├── parameters/
│   │   ├── main.dev.bicepparam
│   │   ├── main.test.bicepparam
│   │   └── main.prod.bicepparam
│   ├── shared/
│   │   ├── naming.bicep        # User-defined functions for resource names
│   │   ├── tags.bicep          # Standard tag map builder
│   │   ├── types.bicep         # User-defined types (modelDeployment, etc.)
│   │   └── region-capabilities.bicep  # Compile-time region/model validator
│   └── modules/
│       ├── foundry-hub/main.bicep
│       ├── foundry-project/main.bicep
│       ├── foundry-connection/main.bicep
│       ├── openai-account/main.bicep
│       ├── openai-deployment/main.bicep
│       ├── ai-search/main.bicep
│       ├── storage/main.bicep
│       ├── key-vault/main.bicep
│       ├── log-analytics/main.bicep
│       ├── app-insights/main.bicep
│       ├── managed-identity/main.bicep
│       ├── role-assignment/main.bicep
│       └── diagnostic-settings/main.bicep
├── scripts/
│   ├── deploy.ps1              # Canonical local deploy script
│   ├── deploy.sh               # pwsh wrapper
│   ├── setup-oidc.ps1          # One-time: create app + federated creds + role
│   └── verify-deploy.ps1       # Post-deploy smoke checks
├── specs/                      # Spec Kit artifacts
├── .specify/                   # Spec Kit templates & scripts
├── .gitignore
├── .gitleaks.toml              # Custom rules: tenant/sub GUID patterns
├── .editorconfig
├── bicepconfig.json            # lint rules, AVM registry alias
├── README.md                   # Top-level: what + 3-step quickstart link
└── LICENSE                     # MIT (or operator's choice — set in tasks)
```

**Structure Decision**: Single-repo IaC layout. `infra/` holds all
templates; `scripts/` holds operator tooling; `.github/workflows/` holds
CI. Per Constitution IV, `main.bicep` is the sole sub-scope entry; all
shared logic is in `infra/shared/`; every resource family has its own
module folder under `infra/modules/`.

## Phase 1 Outputs (planned)

- **`data-model.md`** — defines `modelDeployment`, `environmentConfig`,
  `connectionSpec`, `roleAssignmentSpec` types and their relationships.
- **`contracts/*.md`** — per-module inputs (typed), outputs, and
  invariants. These are the contract that `tasks.md` will turn into
  test-first work items (validate inputs reject bad shapes; outputs
  expose only IDs/endpoints, never keys).
- **`quickstart.md`** — 60-minute operator runbook (matches SC-001).

## Complexity Tracking

> Empty — Constitution Check passed without violations.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _none_    |            |                                     |
