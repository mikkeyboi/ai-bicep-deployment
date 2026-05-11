# Feature Specification: AIO (All-In-One) AI Azure Foundation

**Feature Branch**: `001-aio-foundation`
**Created**: 2026-05-10
**Status**: Draft
**Input**: User description: "Scaffold a Bicep deployment for an all-in-one Azure AI foundation (AI Foundry hub + project, Azure OpenAI with frontier text + image models, Storage, Key Vault, dependencies). Must deploy via GitHub Actions (OIDC) and a local script. Nothing personal/private may live in source. Modular templates, central naming/tagging, and reusable functions. Billing must be compatible with Azure credits — no Azure Marketplace SaaS offers."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator deploys the full AIO foundation to a fresh environment from CI (Priority: P1)

As the repo owner, I push a change to `main` (or trigger a manual workflow run)
selecting `dev`. GitHub Actions authenticates to Azure with OIDC, runs `what-if`
against the target subscription, and on approval deploys the entire AIO stack
into a single resource group: AI Foundry hub + a default project, an Azure
OpenAI account with the configured model deployments, Storage, Key Vault, Log
Analytics, Application Insights, AI Search, and dependencies (managed identity,
RBAC role assignments, diagnostic settings). The workflow logs never reveal the
tenant ID, subscription ID, or any keys. Every provisioned resource bills as
Azure consumption — no Azure Marketplace SaaS offers are deployed.

**Why this priority**: This is the MVP. Without a working push-button deploy
of the full stack, every other story is blocked.

**Independent Test**: Configure GitHub OIDC + variables in a clean repo
clone, run the `Deploy` workflow targeting `dev`, observe a green run, then
confirm in the Azure portal that all expected resources exist in
`rg-aio-dev-eus2` and that the Foundry project lists the configured Azure
OpenAI model deployments.

**Acceptance Scenarios**:
1. **Given** a freshly created Azure subscription with no prior deployments
   and the GitHub repo configured with OIDC + variables for `dev`,
   **When** the operator runs the `Deploy (dev)` workflow,
   **Then** the workflow completes successfully, the resource group
   `rg-aio-dev-<region-short>` exists, and it contains an AI Foundry hub,
   one Foundry project, one Azure OpenAI account, one Storage account, one
   Key Vault, one Log Analytics workspace, one Application Insights
   instance, and one AI Search service — each tagged per the constitution.
   No Marketplace SaaS resources are present.
2. **Given** a successful prior deployment, **When** the workflow is re-run
   without source changes, **Then** the `what-if` step reports zero changes
   and the `create` step is a no-op.
3. **Given** any committed file, **When** `gitleaks` and a custom regex scan
   for tenant/subscription GUIDs run in CI, **Then** no findings are
   reported.

### User Story 2 — Developer deploys locally using `az login` without copying secrets (Priority: P2)

A developer cloned the repo and is signed into `az` against their own
subscription. They run `./scripts/deploy.ps1 -Environment dev -Subscription <id>
-Tenant <id>` (or its `.sh` twin) and get the same `what-if` → confirm →
`create` flow that CI uses. No tenant/subscription is ever read from a file
inside the repo.

**Why this priority**: Required for iteration, debugging, and onboarding
without burning CI minutes.

**Independent Test**: With `az login` complete, run the local script with
`-WhatIf`, verify the produced plan matches the CI-produced plan for the
same parameter file byte-for-byte (modulo timestamps).

**Acceptance Scenarios**:
1. **Given** a logged-in `az` session and required CLI args,
   **When** the script is invoked with `-WhatIf`,
   **Then** it prints a colored Bicep `what-if` diff and exits without
   creating resources.
2. **Given** the script invoked without `-Subscription` or `-Tenant`,
   **When** the script starts,
   **Then** it errors with a usage message and a non-zero exit code, and
   does not touch Azure.

### User Story 3 — Operator adds a new model deployment by editing one parameter file (Priority: P2)

The operator wants to add a new Azure OpenAI model deployment to `dev`.
They edit `infra/parameters/main.dev.bicepparam`, open a PR, and the PR
comment shows a `what-if` diff that adds exactly that model deployment.
After merge, CI deploys it.

**Why this priority**: Models are the primary axis of change for an AI
foundation; this must be friction-free.

**Independent Test**: Add `gpt-5-chat` to the `openAiModelDeployments`
array in the dev parameter file; the resulting `what-if` adds one
`Microsoft.CognitiveServices/accounts/deployments` resource and changes
nothing else.

**Acceptance Scenarios**:
1. **Given** a PR that appends one entry to the `openAiModelDeployments`
   array, **When** PR validation runs, **Then** the `what-if` summary
   posted to the PR shows exactly one resource added and zero modified or
   deleted.
2. **Given** a parameter referencing a model not available in the chosen
   region, **When** validation runs, **Then** it fails with a clear error
   identifying the model and region.

### User Story 4 — Operator promotes a configuration from `dev` to `prod` (Priority: P3)

After validating in `dev`, the operator merges a PR that bumps the `prod`
parameter file. The `Deploy (prod)` workflow requires a reviewer approval
(GitHub environment protection) before running.

**Why this priority**: Needed for safe operation but not part of the first
deploy.

**Acceptance Scenarios**:
1. **Given** the `prod` workflow run is queued, **When** no approver acts,
   **Then** the deployment does not start.
2. **Given** an approver approves, **When** the workflow runs, **Then** it
   uses a different OIDC federated subject (`environment:prod`) than `dev`
   and deploys against the same modules with `prod` parameters.

### Edge Cases

- The chosen region does not offer one of the requested models → validation
  must fail before any resource is created and tell the operator which
  model/region pair is the problem.
- A previous deployment left a soft-deleted Key Vault or Cognitive Services
  account with the same name → the deploy must surface this and offer a
  documented purge path; it must not silently recreate or fail opaquely.
- The OIDC federated credential is misconfigured (wrong `sub` claim) →
  the workflow must fail at the `azure/login` step with a message
  pointing to the README setup section.
- Quota for an OpenAI or Foundry model deployment is insufficient → the
  failure must identify the resource and the requested capacity vs the
  available quota.
- A secret value is accidentally introduced into a parameter file → the
  PR must be blocked by `gitleaks` before merge.

## Requirements *(mandatory)*

### Functional Requirements

**Repository & Configuration**
- **FR-001**: The repository MUST contain no tenant IDs, subscription IDs,
  object IDs, API keys, connection strings, or personal email addresses in
  any tracked file (current or historical from this point forward).
- **FR-002**: All environment-specific values MUST live in
  `infra/parameters/main.<env>.bicepparam`; module files MUST NOT contain
  literals for region, SKU, capacity, or model name.
- **FR-003**: The repository MUST provide a `dev` environment out of the
  box and MUST support adding `test` and `prod` by adding a parameter file
  and a GitHub environment, with no module changes.

**Templates & Layout**
- **FR-004**: A subscription-scope `infra/main.bicep` MUST be the single
  CI entry point; it creates/updates the resource group and invokes a
  workload module.
- **FR-005**: Reusable resource modules MUST live under
  `infra/modules/<family>/` with at least: `foundry-hub`,
  `foundry-project`, `foundry-connection`, `openai-account`,
  `openai-deployment`, `ai-search`, `storage`, `key-vault`,
  `log-analytics`, `app-insights`, `managed-identity`, `role-assignment`,
  `diagnostic-settings`.
- **FR-006**: A central `infra/shared/naming.bicep` MUST produce all
  resource names following the CAF abbreviation convention; modules MUST
  NOT construct resource names locally.
- **FR-007**: A central `infra/shared/tags.bicep` MUST produce the
  standard tag map; every taggable resource MUST consume it.
- **FR-008**: Shared user-defined types (e.g., `modelDeployment`) MUST
  live in `infra/shared/types.bicep` and be imported by modules.

**Deployment Pipelines**
- **FR-009**: The system MUST authenticate GitHub Actions to Azure via
  OIDC federated credentials with no client secret stored in GitHub.
- **FR-010**: A PR validation workflow MUST run `bicep lint`,
  `bicep build`, `az deployment sub validate`, `az deployment sub what-if`,
  and `gitleaks` on every PR that touches `infra/**` or `.github/**`.
- **FR-011**: The PR validation workflow MUST post the `what-if` summary
  as a PR comment.
- **FR-012**: A `Deploy (<env>)` workflow MUST run on push to `main`
  (for `dev`) or on `workflow_dispatch` (for any env) and MUST be gated by
  a GitHub environment whose required reviewers are configurable per env.
- **FR-013**: Deployment workflows MUST use named GitHub Environments so
  the OIDC `sub` claim differs per env (`environment:dev`,
  `environment:prod`, …).
- **FR-014**: Deployment workflows MUST NOT echo any secret value or
  GUID-shaped identifier to logs; the `azure/login` action and parameter
  passing MUST rely on env-injection only.

**Local Tooling**
- **FR-015**: `scripts/deploy.ps1` and `scripts/deploy.sh` MUST accept
  `-Subscription`/`--subscription`, `-Tenant`/`--tenant`,
  `-Environment`/`--environment`, optional `-Location`/`--location`, and a
  `-WhatIf`/`--what-if` switch. Missing required args MUST cause a
  non-zero exit before any Azure call.
- **FR-016**: Local scripts MUST execute the same `validate` →
  `what-if` → `create` sequence as CI against the same Bicep entry point.

**Resources Provisioned (default `dev` parameter file)**
- **FR-017**: The deployment MUST provision an Azure AI Foundry hub and
  one default project linked to it.
- **FR-018**: The deployment MUST provision one Azure OpenAI (Cognitive
  Services `OpenAI` kind) account and create the model deployments listed
  in the parameter file. The default list MUST include at least one chat
  model and one embedding model and MUST be region-validated at compile
  time using a region-capability map (see `research.md`).
- **FR-019**: The deployment MUST NOT provision any Azure Marketplace SaaS
  offering or any third-party model offering that bills outside Azure
  consumption / MCA-E credits (Constitution Principle VIII). Specifically,
  Anthropic Claude in Microsoft Foundry, Cohere Command/Embed, Mistral
  premium tiers, and any other partner SaaS plan in Foundry are out of
  scope. Re-introducing such an offering requires an amendment to the
  constitution.
- **FR-020**: Image-generation models that are gated (e.g., GPT-image-1
  family) MUST be expressible in parameters but MUST be disabled by
  default and MUST emit a clear validation error if requested in a region
  or subscription without access.
- **FR-021**: The deployment MUST provision one Storage account
  (LRS, HNS off by default), one Key Vault (RBAC mode, purge protection
  on for `prod`), one Log Analytics workspace, and one Application
  Insights instance wired to the workspace.
- **FR-022**: A user-assigned managed identity MUST be created and
  granted least-privilege RBAC on the Azure OpenAI account, the Storage
  account, the Key Vault, and (when enabled) the AI Search service.
- **FR-023**: Diagnostic settings MUST be created on every PaaS resource
  that supports them, routing to the Log Analytics workspace.

**Operational**
- **FR-024**: Every deployment MUST be tagged with `environment`,
  `workload=aio`, `owner` (parameterized), `costCenter` (parameterized,
  defaults to `poc`), `managedBy=bicep`, `repo`
  (= `mikkeyboi/ai-bicep-deployment`), and `deployedAt` (UTC timestamp).
- **FR-025**: The system MUST be removable by deleting the resource
  group; no resources MUST be created outside the resource group except
  the resource group itself and required role assignments at RG scope.

### Key Entities *(include if feature involves data)*

- **Environment**: a named target (`dev`, `test`, `prod`) with its own
  parameter file, GitHub environment, OIDC federated subject, and
  required-reviewer policy.
- **Model Deployment**: a record with `name`, `model.format`,
  `model.name`, `model.version`, `sku.name`, `sku.capacity`, and
  `raiPolicyName`. Lives in the parameter file as an array element.
- **Workload Identity**: a user-assigned managed identity that
  applications inside the foundation use to call Foundry / OpenAI /
  Storage / Key Vault.
- **Federated Credential**: a per-environment OIDC trust binding
  GitHub `sub=repo:mikkeyboi/ai-bicep-deployment:environment:<env>` to
  an Azure AD app + service principal with subscription-scoped
  Contributor role.

## Out of Scope

The following are explicitly **out of scope** for this repository because
they violate Constitution Principle VIII (Azure Consumption Billing Only):

- **Anthropic Claude in Microsoft Foundry** — Marketplace SaaS, billed
  outside Azure consumption credits.
- **Cohere Command / Embed in Foundry** — Marketplace SaaS.
- **Mistral premium tiers in Foundry** — Marketplace SaaS.
- Any other partner / third-party model in Foundry sold through
  Marketplace.
- Self-hosted open-weight model serving (vLLM / TGI on AKS or VMs) —
  consumption-billable but out of scope for this POC; tracked separately.

These capabilities are not rejected on technical merit — they are simply
the wrong billing model for this repo. A separate spec + constitution
amendment can re-introduce them later.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time operator following only `README.md` can
  complete the OIDC setup, configure GitHub Variables, and reach a green
  `Deploy (dev)` run in **under 60 minutes** of active work.
- **SC-002**: A no-change re-deploy completes its `what-if` step in
  **under 3 minutes** and reports **zero** changes.
- **SC-003**: Adding one new Azure OpenAI model deployment requires
  editing **exactly one file** (`main.dev.bicepparam`) and **zero lines**
  of Bicep module code.
- **SC-004**: 100% of PRs that touch `infra/**` produce a `what-if` PR
  comment within **5 minutes** of the validation workflow starting.
- **SC-005**: A repository-wide `gitleaks` + GUID-pattern scan over the
  full git history reports **zero** findings on every default-branch
  commit.
- **SC-006**: A full clean deployment of the default `dev` parameter
  file finishes in **under 25 minutes** end-to-end.
- **SC-007**: A repository audit at any commit on the default branch
  reports **zero** references to Azure Marketplace SaaS offers (Claude in
  Foundry, Cohere, Mistral premium, etc.) in `infra/**`, parameter
  files, scripts, or tracked specs (Constitution VIII).

## Assumptions

- The target Azure subscription has the required resource providers
  registered (`Microsoft.CognitiveServices`, `Microsoft.MachineLearningServices`,
  `Microsoft.Storage`, `Microsoft.KeyVault`,
  `Microsoft.OperationalInsights`, `Microsoft.Insights`,
  `Microsoft.ManagedIdentity`, `Microsoft.Search`).
- The operator has Owner or `User Access Administrator` + `Contributor`
  on the target subscription long enough to perform the one-time OIDC
  app + role assignment setup. Steady-state CI uses only Contributor.
- GPT-image-1 / 1.5 require Microsoft-managed access approval; they are
  parameterized but NOT enabled by default.
- The default region for `dev` is `eastus2` because it currently hosts
  the broadest set of Azure OpenAI frontier text and embedding models
  (including the GPT-5 family). This is recorded and may be overridden
  per parameter file. The choice is no longer constrained by partner
  Marketplace model availability per Constitution VIII.
- The repository owner is the only human principal initially; future
  contributors are added via GitHub repo permissions, not Azure RBAC.
