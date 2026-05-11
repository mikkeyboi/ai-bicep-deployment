# Tasks: 002 New Foundry

## Phase A — Spec & Constitution
- [x] T001 Branch `002-new-foundry` from main.
- [x] T002 Bump constitution to v1.2.0 with new Principle IV clarification.
- [x] T003 Author `specs/002-new-foundry/{spec,research,plan,data-model,quickstart}.md`.
- [x] T004 Author `specs/002-new-foundry/contracts/modules.contract.md`.

## Phase B — Implementation
- [x] T005 Create `infra/modules/foundry-account/main.bicep` (account + child deployments).
- [x] T006 Create `infra/modules/foundry-account/project.bicep`.
- [x] T007 Update `infra/shared/types.bicep`: drop `connectionSpec`/`connectionCategory`/`openAiConfig`; add `foundryAccountConfig`; swap field on `environmentConfig`.
- [x] T008 Update `infra/shared/naming.bicep`: confirm `foundry()` helper produces `aif-…`; mark hub/project helpers deprecated (kept exported for back-compat but unused).
- [x] T009 Rewrite `infra/workload.bicep` to call new module + drop OpenAI/Hub/Project/Connection wiring.
- [x] T010 Update `infra/main.bicep` outputs to surface `foundry*` instead of `foundryHub*`/`foundryProject*`/`openAi*`.
- [x] T011 Update `infra/parameters/main.dev.bicepparam`: rename `openAi` → `foundry` block; same model deployment list.
- [x] T012 Delete `infra/modules/foundry-hub/`, `infra/modules/foundry-project/`, `infra/modules/foundry-connection/`, `infra/modules/openai-account/`, `infra/modules/openai-deployment/`.
- [x] T013 Update RBAC: replace `raOpenAi` with `raFoundry` (Cognitive Services User on Foundry account).

## Phase C — Validate
- [x] T014 `bicep lint infra/main.bicep` clean.
- [x] T015 `bicep build infra/main.bicep` clean.
- [x] T016 `az deployment sub validate` passes against dev paramfile.
- [x] T017 `az deployment sub what-if` captured.
- [x] T018 gitleaks scan clean.
- [x] T019 Privacy grep returns 0 hits for forbidden tokens.

## Phase D — Tear down + redeploy
- [x] T020 Delete `proj-aio-dev-eus2`.
- [x] T021 Delete `hub-aio-dev-eus2`.
- [x] T022 Delete + purge `oai-aio-dev-eus2-npnga`.
- [x] T023 `az deployment sub create` succeeds.
- [x] T024 Smoke check: account show, deployment list, project list.

## Phase E — Merge
- [x] T025 Commit + push branch.
- [x] T026 Open PR + squash-merge.
- [x] T027 Sanitized `DEPLOY_REPORT_002.md` committed to main.
