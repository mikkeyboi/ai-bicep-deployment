# Tasks: AIO Foundation

**Feature**: 001-aio-foundation
**Generated from**: spec.md, plan.md, research.md, data-model.md, contracts/

Conventions:
- `[P]` = can run in parallel with other `[P]` tasks in the same phase.
- Each task lists the **file(s)** it touches and a **done-when** check.
- Test-first: contract checks (Phase 3) precede implementation (Phase 4).

---

## Phase 1 — Repository skeleton & guardrails

- **T001** Create top-level files: `README.md` (links to spec + quickstart),
  `.gitignore` (Bicep + Node + VS Code + `.azure/`), `.editorconfig`,
  `LICENSE` (MIT, no real-name attribution — use GitHub handle).
  *Done when*: files exist; `git status` clean after stage.
- **T002** [P] Add `bicepconfig.json` enabling all `error`-level lint rules,
  declaring AVM registry alias `br/public`, and disabling `no-hardcoded-location`
  *only* inside `infra/parameters/**` (paramfiles legitimately set location).
  *Done when*: `bicep lint infra/main.bicep` runs (file may not exist yet — expect file-not-found, not config error).
- **T003** [P] Add `.gitleaks.toml` with custom rules:
  (a) Azure tenant/subscription GUID pattern outside `specs/**` and `*.md`,
  (b) the operator's personal email literal blocks (codified in `.gitleaks.toml`),
  (c) generic key/secret patterns from gitleaks defaults.
  *Done when*: `gitleaks detect --no-git -v` exits 0 on the empty repo.
- **T004** [P] Add `.github/copilot-instructions.md` mirroring the
  Constitution: "no IDs/keys in source; OIDC only; modular Bicep; CAF
  naming via `infra/shared/naming.bicep`; never echo `listKeys()` output;
  always run `what-if` before `create`."
  *Done when*: file present and references `.specify/memory/constitution.md`.

## Phase 2 — Shared infra (types, naming, tags, region map)

- **T005** Author `infra/shared/types.bicep` with `environmentConfig`,
  `openAiConfig`, `modelDeployment`, `connectionSpec`,
  `roleAssignmentSpec` (verbatim shapes from `data-model.md`).
  > **Amended 2026-05-10 (Constitution v1.1.0)**: `claudeConfig` removed;
  > `modelFormat` collapses to `'OpenAI'`; `connectionCategory` collapses
  > to `'AzureOpenAI'`. See research.md D11.
  *Done when*: `bicep build` on a stub consumer compiles cleanly.
- **T006** Author `infra/shared/naming.bicep`: user-defined functions
  `rg()`, `kv()`, `storage()`, `openai()`, `foundry()`, `project()`,
  `mi()`, `law()`, `ai()`. Pattern `<abbr>-<workload>-<env>-<regionShort>[-<inst>]`;
  storage strips hyphens; appends 5-char hash for global-unique names.
  Region-short map: `eastus2→eus2`, `swedencentral→sdc`, `canadacentral→cac`, …
  *Done when*: unit-style asserts in `infra/shared/_naming.tests.bicep` pass via `bicep build`.
- **T007** [P] Author `infra/shared/tags.bicep`: function `tags(env, owner, costCenter, deployedAt)` returning the standard map.
  *Done when*: `bicep build` of consumer module succeeds; assert keys exist.
- **T008** Author `infra/shared/region-capabilities.bicep`: const map
  `regionModels` populated from `research.md` D3/D4; function
  `assertModelInRegion(location, format, name)` that emits a clear error
  via `assert` when missing.
  *Done when*: a deliberate failing case fails `bicep build` with the expected message; happy paths build.

## Phase 3 — Module contract tests (test-first)

For every module under `infra/modules/<m>/`, add
`infra/modules/<m>/_contract.tests.bicep` that calls the module with a
known-bad input and expects a compile-time failure (asserts), and a
known-good input that compiles. Run `bicep build` on each test file in
CI as part of `validate.yml`.

- **T009** [P] openai-account contract test (rejects `disableLocalAuth=false` when env=prod).
- **T010** [P] openai-deployment contract test (rejects non-`OpenAI` format).
- **T011** ~~[P] foundry-claude-account contract test (rejects region not in `{eastus2, swedencentral}`).~~
  > **SUPERSEDED 2026-05-10**: module removed per Constitution VIII (no Marketplace SaaS).
- **T012** ~~[P] foundry-claude-deployment contract test (rejects non-`Anthropic` format).~~
  > **SUPERSEDED 2026-05-10**: module removed per Constitution VIII.
- **T013** [P] foundry-hub contract test (requires KV + Storage + AI + LA inputs).
- **T014** [P] foundry-project contract test (requires `hubId`).
- **T015** [P] foundry-connection contract test (rejects `authType=ApiKey`).
- **T016** [P] key-vault contract test (rejects `enableRbacAuthorization=false`).
- **T017** [P] storage contract test (rejects `allowSharedKeyAccess=true` when env=prod).
- **T018** [P] role-assignment contract test (deterministic `name = guid(...)`).
- **T019** [P] log-analytics, app-insights, managed-identity, diagnostic-settings smoke build tests.

## Phase 4 — Module implementations

- **T020** `modules/managed-identity/main.bicep`
- **T021** [P] `modules/log-analytics/main.bicep`
- **T022** [P] `modules/app-insights/main.bicep` (depends on LA via input)
- **T023** [P] `modules/key-vault/main.bicep`
- **T024** [P] `modules/storage/main.bicep`
- **T025** `modules/openai-account/main.bicep`
- **T026** `modules/openai-deployment/main.bicep` (consumes account name)
- **T027** ~~`modules/foundry-claude-account/main.bicep`~~
  > **SUPERSEDED 2026-05-10**: removed per Constitution VIII (Azure Consumption Billing Only). Anthropic Claude in Foundry is a Marketplace SaaS offer.
- **T028** ~~`modules/foundry-claude-deployment/main.bicep`~~
  > **SUPERSEDED 2026-05-10**: removed alongside T027.
- **T029** `modules/foundry-hub/main.bicep`
- **T030** `modules/foundry-project/main.bicep`
- **T031** `modules/foundry-connection/main.bicep`
- **T032** `modules/role-assignment/main.bicep`
- **T033** `modules/diagnostic-settings/main.bicep`

*Done when*: each `bicep build` passes; contract tests from Phase 3 still pass.

## Phase 5 — Orchestration

- **T034** `infra/workload.bicep` orchestrating modules per
  `contracts/modules.contract.md` § workload, computing all names via
  `naming.bicep`, building tags via `tags.bicep`, and threading the MI
  through role assignments (no `listKeys` outputs).
- **T035** `infra/main.bicep` (sub scope), creating the RG and invoking
  `workload.bicep`. Calls `region-capabilities.assertModelInRegion(...)`
  for every model in `config.openAi.deployments`.
  > **Amended 2026-05-10**: no longer iterates `config.claude.deployments`
  > because `claudeConfig` has been removed (Constitution VIII).
- **T036** `infra/parameters/main.dev.bicepparam` matching the example
  in `data-model.md`.

## Phase 6 — Local scripts

- **T037** `scripts/deploy.ps1`:
  params `-Environment`, `-Subscription`, `-Tenant`, `-Location?`, `-WhatIf`.
  Refuses to run if missing required params or if `az account show` mismatches.
  Sequence: `az account set` → `az deployment sub validate` →
  `az deployment sub what-if` → on confirm `az deployment sub create`.
  Never prints raw GUIDs (mask middle 8 chars in stdout).
- **T038** [P] `scripts/deploy.sh`: thin wrapper that re-execs `pwsh -File ./scripts/deploy.ps1 "$@"`.
- **T039** `scripts/setup-oidc.ps1`:
  params `-SubscriptionId`, `-TenantId`, `-GitHubOrg`, `-GitHubRepo`, `-Environments` (CSV).
  Idempotent: creates app, SP, federated creds (one per env), assigns
  Contributor at sub scope, optional UAA. Prints values to set as
  GitHub Variables (no secrets).
- **T040** [P] `scripts/verify-deploy.ps1`: post-deploy assertions —
  expected RG exists; OpenAI account has expected deployments; Foundry
  hub + project exist; KV in RBAC mode; MI has expected role assignments.

## Phase 7 — CI workflows

- **T041** `.github/workflows/validate.yml`:
  Triggers on `pull_request` paths `infra/**`, `.github/**`, `scripts/**`.
  Steps: checkout → setup bicep → `bicep lint` → `bicep build` →
  `azure/login@v2` (OIDC, env=`dev`) → `az deployment sub validate` →
  `az deployment sub what-if` → comment what-if on PR →
  `gitleaks/gitleaks-action@v2`. Reads `AZURE_*` from GitHub Variables.
- **T042** `.github/workflows/deploy.yml`:
  Triggers: `workflow_dispatch` with `environment` input;
  `push` to `main` (auto-targets `dev`).
  Job uses `environment: ${{ inputs.environment || 'dev' }}` so the
  OIDC subject and approvers are correct per env.
  Steps: same prelude as validate → `az deployment sub create` →
  upload outputs as artifact (sanitized).

## Phase 8 — End-to-end verification

- **T043** Run `./scripts/deploy.ps1 -Environment dev -Subscription <id> -Tenant <id> -WhatIf` locally; capture diff; attach to PR.
- **T044** Open PR; confirm `validate.yml` runs and posts `what-if` comment within SC-004 budget.
- **T045** Merge to `main`; confirm `Deploy (dev)` runs green; run `verify-deploy.ps1`.
- **T046** Re-run `Deploy (dev)` with no source changes; confirm zero-change `what-if` ≤ 3 min (SC-002).
- **T047** Add one model to `main.dev.bicepparam`; PR what-if shows exactly one resource added (SC-003).

## Phase 9 — Documentation polish

- **T048** Expand `README.md`: 1-paragraph what/why, 3-step quickstart pointing at `specs/001-aio-foundation/quickstart.md`, link to constitution.
- **T049** Add `docs/architecture.md` with a Mermaid diagram of modules and dependencies (generated from `contracts/modules.contract.md`).
- **T050** Final pass: re-run gitleaks on full history; remove any stray TODOs; bump constitution to 1.0.0 PATCH if any wording fixed.

---

## Phase 10 — Constitution v1.1.0 amendment (Marketplace SaaS removal)

Added 2026-05-10 in response to the new repo constraint that all
resources MUST bill as Azure consumption. See research.md D11 and the
Constitution Principle VIII.

- **T051** Bump constitution to v1.1.0 with Principle VIII and Sync Impact Report.
  *Done when*: `.specify/memory/constitution.md` shows `Version: 1.1.0`.
- **T052** Update `specs/001-aio-foundation/spec.md`: remove Claude FRs/stories, add FR-019 (consumption-only), add Out of Scope, add SC-007.
  *Done when*: `git grep -i claude specs/001-aio-foundation/spec.md` returns 0 hits.
- **T053** Update `research.md` (D3 + D4 rewritten; D11 added).
- **T054** Update `plan.md` Constitution Check (re-run vs v1.1.0).
- **T055** Update `data-model.md` (remove `claudeConfig`).
- **T056** Update `contracts/modules.contract.md` (remove Claude/AIServices module contracts; constrain `connectionCategory` to `AzureOpenAI`).
- **T057** Update `quickstart.md` (remove Marketplace step; deploy is unattended).
- **T058** Delete `infra/modules/foundry-claude-account/` and `infra/modules/foundry-claude-deployment/`.
- **T059** Strip Claude wiring from `infra/workload.bicep` and `infra/main.bicep`; remove `claudeConfig` from `infra/shared/types.bicep`; remove `Anthropic:*` entries from `infra/shared/region-capabilities.bicep`.
- **T060** Remove `claude { ... }` blocks from `infra/parameters/main.{dev,test,prod}.bicepparam`.
- **T061** Remove Marketplace reminder from `scripts/preflight.ps1`; drop AIServices-specific check from `scripts/verify-deploy.ps1`; update `README.md`.
- **T062** Re-run validation chain: `bicep lint`, `bicep build`, `az deployment sub validate`, `az deployment sub what-if`, `gitleaks detect`, privacy grep.
  *Done when*: all six pass and what-if shows no Claude/AIServices resources.

### Parallelization map

- Phase 1: T002, T003, T004 in parallel after T001.
- Phase 3: all `[P]` contract tests in parallel.
- Phase 4: T021, T022, T023, T024 in parallel after T020; the OpenAI/Claude/Foundry chain is mostly sequential because of input dependencies.
- Phase 6: T038, T040 in parallel with T037 / T039.
