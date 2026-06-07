# Tasks: 004 East US Image Foundry

## Phase A — Spec & Plan
- [x] T001 Branch `004-eastus-image-foundry` from main.
- [x] T002 Author `specs/004-eastus-image-foundry/{spec,plan,research,data-model,quickstart}.md`.
- [x] T003 Author `specs/004-eastus-image-foundry/contracts/modules.contract.md`.
- [x] T004 Log the API-key Security-section deviation in plan.md Complexity Tracking.

## Phase B — Implementation
- [x] T005 `types.bicep`: widen `modelFormat` to add `'Microsoft'`.
- [x] T006 `types.bicep`: add `location?` + `disableLocalAuth?` to `foundryAccountConfig`; add `secondaryFoundry?` to `environmentConfig`.
- [x] T007 `region-capabilities.bicep`: add `eastus` block (gpt-image-2, MAI-Image-2.5, + broadly-available text/embedding models).
- [x] T008 `workload.bicep`: add `foundry2` + `foundry2Proj` (guarded by `enableSecondaryFoundry`), in `secondaryLocation`.
- [x] T009 `workload.bicep`: add `raFoundry2` (Cognitive Services User) + `aif2Existing` + `diagFoundry2`.
- [x] T010 `workload.bicep`: add `secondaryFoundry*` outputs.
- [x] T011 `main.bicep`: extend capability gate to validate secondary models against `secondaryLocation`; surface `secondaryFoundry*` outputs.
- [x] T012 `main.dev.bicepparam`: add `secondaryFoundry` block (eastus, 2 image models, `disableLocalAuth: false`).

## Phase C — Validate
- [x] T013 `bicep build infra/main.bicep` clean (exit 0; warnings are pre-existing / mirror accepted patterns).
- [x] T014 `bicep lint infra/main.bicep` clean (exit 0, no error-level diagnostics).
- [x] T015 Compiled-ARM presence checks: secondary account, both image models, eastus map entry, no NEW listKeys().
- [x] T016 Privacy grep: 0 real GUIDs / emails / key-shapes introduced.
- [ ] T017 `az cognitiveservices model list --location eastus` — confirm gpt-image-2 version + MAI-Image-2.5 (2026-06-02) (operator/CI; az not in authoring env).
- [ ] T018 `az deployment sub validate` against dev paramfile (operator/CI).
- [ ] T019 `az deployment sub what-if` — confirm additive (creates only; eastus2 unchanged) (operator/CI).
- [ ] T020 gitleaks scan clean (CI).

## Phase D — Deploy
- [ ] T021 `az deployment sub create` (dev).
- [ ] T022 Smoke: account show (location=eastus), deployment list (2), project list (1), one image generation call.

## Phase E — Merge
- [ ] T023 Commit + push branch; open PR.
- [ ] T024 Squash-merge after approval + green CI.
- [ ] T025 Sanitized DEPLOY_REPORT_004.md committed to main.
