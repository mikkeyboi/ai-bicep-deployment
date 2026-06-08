# Tasks: 007 Azure ML Workspace + Compute

## Phase 0 — Spec (this directory)
- [x] spec.md
- [x] plan.md (Constitution Check + Complexity Tracking)
- [x] research.md
- [x] data-model.md
- [x] contracts/modules.contract.md
- [x] quickstart.md
- [x] tasks.md

## Phase 1 — Implement
- [x] `naming.bicep`: add `mlWorkspace`, `mlComputeInstance`, `mlComputeCluster`
- [x] `types.bicep`: add `computeProcessor`, `amlComputeScale`,
      `amlComputeInstanceConfig`, `amlComputeClusterConfig`,
      `machineLearningConfig`; extend `environmentConfig`
- [x] `role-assignment/main.bicep`: add Storage File Data Privileged
      Contributor GUID
- [x] `modules/machine-learning/main.bicep`: workspace + computes,
      keyless datastores (`systemDatastoresAuthMode=identity`),
      `2024-10-01-preview` API
- [x] `workload.bicep`: names, `ml` module, `raMlBlob`/`raMlFile`/`raMlKv`,
      `diagMl`, outputs
- [x] `main.bicep`: surface `ml*` in `workloadOutputs`
- [x] `main.dev.bicepparam`: `machineLearning` block (1 CPU instance, 1 CPU
      cluster) + GPU re-add stub

## Phase 2 — Validate (authoring env; no az login)
- [x] `bicep build infra/main.bicep` → exit 0, no ML-related warnings
- [x] `bicep lint infra/main.bicep` → no error-level
- [x] `bicep build-params` dev/test/prod → all exit 0 (optional field
      back-compat proven)
- [x] Compiled `main.json` grep: workspace + both compute types +
      `systemDatastoresAuthMode=identity` + File-Priv GUID present
- [x] **No NEW `listKeys()`**: functional count unchanged vs origin/main
      (2 pre-existing in matrix module; ML adds 0)
- [x] Names validated against AML regexes; GPU-add invariant proven
      (CPU names stable when a `gpu` entry is appended)
- [ ] gitleaks scan (CI)
- [ ] `az ml compute list-sizes` confirms `Standard_DS3_v2` in eastus2 (operator)
- [ ] `az deployment sub validate` + `what-if` (operator / CI)

## Phase 3 — Deploy
- [ ] Deploy dev (merge → deploy.yml, or local wrapper)
- [ ] Smoke: `az ml workspace show` (datastoreAuth=identity),
      `az ml compute list` shows ci + cc, cluster idle at 0 nodes

## Phase 4 — Wrap
- [ ] Sanitized DEPLOY_REPORT_007.md
- [ ] Squash-merge to main

## Open follow-ups (tracked, not blocking)
- [ ] GPU compute: obtain NC/ND quota in eastus2, append `processor:'gpu'`
      entry, redeploy.
- [ ] Optional hardening: dedicated ML Key Vault to scope the
      Secrets-Officer grant off the shared vault.
- [ ] Optional: managed-VNet / private-endpoint isolation before any prod
      promotion of ML.
